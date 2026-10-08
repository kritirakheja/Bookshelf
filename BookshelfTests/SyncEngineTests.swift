import XCTest
import SwiftData
@testable import Bookshelf

/// In-memory stand-in for Supabase: stamps `updated_at` on every write like the
/// server trigger does, and keeps uploaded files.
final class FakeRemote: SyncRemote {
    var rows: [UUID: BookRecord] = [:]
    var files: [String: Data] = [:]
    var profile: ProfileRecord?
    var uploads = 0
    var downloads = 0
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func tick() -> Date {
        clock = clock.addingTimeInterval(1)
        return clock
    }

    func fetchBooks(updatedAfter: Date?) async throws -> [BookRecord] {
        rows.values
            .filter { updatedAfter == nil || $0.updatedAt! > updatedAfter! }
            .sorted { $0.updatedAt! < $1.updatedAt! }
    }

    func upsertBooks(_ records: [BookRecord]) async throws {
        for var record in records {
            record.updatedAt = tick()
            rows[record.id] = record
        }
    }

    func markBooksDeleted(_ ids: [UUID]) async throws {
        for id in ids where rows[id] != nil {
            rows[id]!.deleted = true
            rows[id]!.updatedAt = tick()
        }
    }

    func fetchProfile() async throws -> ProfileRecord? { profile }
    func upsertProfile(_ profile: ProfileRecord) async throws { self.profile = profile }

    func uploadFile(_ data: Data, path: String) async throws {
        uploads += 1
        files[path] = data
    }

    func downloadFile(path: String) async throws -> Data {
        downloads += 1
        guard let data = files[path] else { throw URLError(.fileDoesNotExist) }
        return data
    }

    func removeFiles(paths: [String]) async throws {
        paths.forEach { files[$0] = nil }
    }

    var storeRows: [UUID: BookstoreRecord] = [:]

    func fetchBookstores(updatedAfter: Date?) async throws -> [BookstoreRecord] {
        storeRows.values
            .filter { updatedAfter == nil || $0.updatedAt! > updatedAfter! }
            .sorted { $0.updatedAt! < $1.updatedAt! }
    }

    func upsertBookstores(_ records: [BookstoreRecord]) async throws {
        for var record in records {
            record.updatedAt = tick()
            storeRows[record.id] = record
        }
    }

    func markBookstoresDeleted(_ ids: [UUID]) async throws {
        for id in ids where storeRows[id] != nil {
            storeRows[id]!.deleted = true
            storeRows[id]!.updatedAt = tick()
        }
    }
}

/// One phone: its own on-device library and its own "last pulled" marker.
@MainActor
final class Device {
    let container: ModelContainer
    let engine: SyncEngine
    var lastPulled: Date?

    init(remote: SyncRemote, userID: UUID) throws {
        container = try ModelContainer(
            for: Book.self, BookCategory.self, DeletedBook.self, Loan.self, ReadingEntry.self, Bookstore.self, DeletedBookstore.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        engine = SyncEngine(context: container.mainContext, remote: remote, userID: userID)
    }

    var context: ModelContext { container.mainContext }

    var books: [Book] {
        (try? context.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.title)]))) ?? []
    }

    func book(_ title: String) -> Book? { books.first { $0.title == title } }

    @discardableResult
    func add(_ title: String, author: String = "Author", isbn: String? = nil, cover: Data? = nil) -> Book {
        let book = Book(title: title, authors: [author], isbn: isbn, coverImage: cover)
        context.insert(book)
        return book
    }

    func delete(_ book: Book) {
        if let id = book.remoteID { context.insert(DeletedBook(remoteID: id)) }
        context.delete(book)
    }

    @discardableResult
    func sync() async throws -> SyncEngine.Result {
        let result = try await engine.syncBooks(lastPulledAt: lastPulled)
        lastPulled = result.lastPulledAt
        return result
    }
}

@MainActor
final class SyncEngineTests: XCTestCase {
    private let userID = UUID()
    private var remote: FakeRemote!
    private var phone: Device!
    private var ipad: Device!

    override func setUp() async throws {
        remote = FakeRemote()
        phone = try Device(remote: remote, userID: userID)
        ipad = try Device(remote: remote, userID: userID)
    }

    func testFirstSyncUploadsEverything() async throws {
        phone.add("Dune", cover: Data("cover".utf8))
        phone.add("Circe")

        let result = try await phone.sync()

        XCTAssertEqual(result.pushed, 2)
        XCTAssertEqual(Set(remote.rows.values.map(\.title)), ["Dune", "Circe"])
        XCTAssertEqual(remote.files.count, 1, "Only the book with a cover uploads a file")
        XCTAssertTrue(phone.books.allSatisfy { !phone.engine.hasLocalChanges($0) })
    }

    func testSecondDeviceGetsTheWholeLibrary() async throws {
        let dune = phone.add("Dune", cover: Data("cover".utf8))
        dune.setStatus(.read)
        dune.rating = 5
        dune.categories = [try XCTUnwrap(BookCategory.named("Sci-fi", in: phone.context))]
        try await phone.sync()

        try await ipad.sync()

        let copy = try XCTUnwrap(ipad.book("Dune"))
        XCTAssertEqual(copy.status, .read)
        XCTAssertEqual(copy.rating, 5)
        XCTAssertEqual(copy.categories.map(\.name), ["Sci-fi"])
        XCTAssertEqual(copy.coverImage, Data("cover".utf8))
        XCTAssertFalse(ipad.engine.hasLocalChanges(copy), "A freshly pulled book isn't pushed back")
    }

    func testNothingChangedMeansNothingSent() async throws {
        phone.add("Dune", cover: Data("cover".utf8))
        try await phone.sync()
        let uploads = remote.uploads

        let result = try await phone.sync()

        XCTAssertEqual(result.pushed, 0)
        XCTAssertEqual(remote.uploads, uploads, "Unchanged covers aren't uploaded again")
    }

    func testEditsTravelBetweenDevices() async throws {
        phone.add("Dune")
        try await phone.sync()
        try await ipad.sync()

        let onIpad = try XCTUnwrap(ipad.book("Dune"))
        onIpad.setStatus(.reading)
        onIpad.notes = "Slow start, great ending"
        try await ipad.sync()
        try await phone.sync()

        let onPhone = try XCTUnwrap(phone.book("Dune"))
        XCTAssertEqual(onPhone.status, .reading)
        XCTAssertEqual(onPhone.notes, "Slow start, great ending")
    }

    func testLendingSyncsBetweenDevices() async throws {
        let circe = phone.add("Circe")
        try await phone.sync()
        try await ipad.sync()

        circe.lend(to: "Priya", contactID: "phone-only-id")
        XCTAssertTrue(phone.engine.hasLocalChanges(circe), "Lending alone counts as a change")
        try await phone.sync()
        try await ipad.sync()
        XCTAssertEqual(ipad.book("Circe")?.currentLoan?.borrowerName, "Priya")

        // Returned on the iPad; the phone sees the history.
        ipad.book("Circe")?.markReturned()
        try await ipad.sync()
        try await phone.sync()
        XCTAssertFalse(circe.isLent)
        XCTAssertEqual(circe.pastLoans.map(\.borrowerName), ["Priya"])
        XCTAssertEqual(circe.loans.count, 1, "Same loan updated, not duplicated")

        // Removing a history entry syncs too.
        phone.context.delete(circe.pastLoans[0])
        try await phone.sync()
        try await ipad.sync()
        XCTAssertEqual(ipad.book("Circe")?.loans.count, 0)
        XCTAssertFalse(phone.engine.hasLocalChanges(try XCTUnwrap(ipad.book("Circe"))))
    }

    func testReadingProgressSyncsBetweenDevices() async throws {
        let dune = phone.add("Dune")
        dune.pageCount = 600
        dune.setStatus(.reading)
        dune.logProgress(page: 150)
        try await phone.sync()
        try await ipad.sync()

        let copy = try XCTUnwrap(ipad.book("Dune"))
        XCTAssertEqual(copy.currentPage, 150)
        XCTAssertEqual(copy.progressPercent, 25)

        // A later entry made on the other device comes back, without duplicating.
        copy.logProgress(page: 300)
        try await ipad.sync()
        try await phone.sync()
        XCTAssertEqual(dune.currentPage, 300)
        XCTAssertEqual(dune.progress.count, 1)
        XCTAssertFalse(phone.engine.hasLocalChanges(dune))
    }

    func testBorrowingSyncsBetweenDevices() async throws {
        let sapiens = phone.add("Sapiens")
        sapiens.borrow(from: "Meera")
        try await phone.sync()
        try await ipad.sync()

        let copy = try XCTUnwrap(ipad.book("Sapiens"))
        XCTAssertTrue(copy.isBorrowed)
        XCTAssertNil(copy.currentLoan, "Arrives as borrowed, not as lent")

        copy.giveBack()
        try await ipad.sync()
        try await phone.sync()
        XCTAssertTrue(sapiens.isGivenBack)
    }

    func testLoansSavedBeforeBorrowingExistedAreLends() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","borrower_name":"Priya","lent_at":"2026-09-01T10:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(LoanRecord.self, from: Data(json.utf8))
        XCTAssertNil(record.isBorrowed)   // treated as a lend when applied
    }

    func testYearOnlyFinishDateSyncs() async throws {
        let book = phone.add("Year-end read")
        book.isRead = true
        book.setFinishYear(2025)
        try await phone.sync()
        try await ipad.sync()
        XCTAssertEqual(ipad.book("Year-end read")?.dateReadYearOnly, true)
        XCTAssertEqual(ipad.book("Year-end read")?.finishDateText, "2025")
    }

    func testClearingAFieldSyncs() async throws {
        let dune = phone.add("Dune")
        dune.rating = 4
        try await phone.sync()
        try await ipad.sync()

        dune.rating = nil
        try await phone.sync()
        try await ipad.sync()

        XCTAssertNil(ipad.book("Dune")?.rating)
    }

    func testDeletionsTravelBetweenDevices() async throws {
        phone.add("Dune")
        phone.add("Circe")
        try await phone.sync()
        try await ipad.sync()

        phone.delete(try XCTUnwrap(phone.book("Dune")))
        try await phone.sync()
        try await ipad.sync()

        XCTAssertEqual(ipad.books.map(\.title), ["Circe"])
        XCTAssertTrue(try phone.context.fetch(FetchDescriptor<DeletedBook>()).isEmpty, "Deletion markers are cleared once sent")
    }

    func testDeletingABookFromTheAppRemovesItEverywhere() async throws {
        let dune = phone.add("Dune")
        let circe = phone.add("Circe")
        FavoritesShelf.add(dune, library: phone.books)
        FavoritesShelf.add(circe, library: phone.books)
        try await phone.sync()
        try await ipad.sync()

        phone.context.deleteBook(dune)

        XCTAssertEqual(phone.book("Circe")?.favoriteRank, 1, "The shelf closes the gap")
        XCTAssertEqual(try phone.context.fetch(FetchDescriptor<DeletedBook>()).count, 1)
        try await phone.sync()
        try await ipad.sync()
        XCTAssertEqual(ipad.books.map(\.title), ["Circe"])
        XCTAssertEqual(ipad.book("Circe")?.favoriteRank, 1)
    }

    func testDeletingANeverSyncedBookLeavesNoMarker() throws {
        let draft = phone.add("Just added")
        phone.context.deleteBook(draft)
        XCTAssertTrue(try phone.context.fetch(FetchDescriptor<DeletedBook>()).isEmpty)
        XCTAssertTrue(phone.books.isEmpty)
    }

    func testDeletedBookDoesNotComeBack() async throws {
        let dune = phone.add("Dune")
        try await phone.sync()

        phone.delete(dune)
        phone.lastPulled = nil   // even a full re-download mustn't resurrect it
        try await phone.sync()

        XCTAssertTrue(phone.books.isEmpty)
    }

    func testLocalEditWinsOverRemoteEditOfSameBook() async throws {
        phone.add("Dune")
        try await phone.sync()
        try await ipad.sync()

        ipad.book("Dune")?.notes = "from iPad"
        try await ipad.sync()
        phone.book("Dune")?.notes = "from phone"
        try await phone.sync()

        XCTAssertEqual(phone.book("Dune")?.notes, "from phone")
        try await ipad.sync()
        XCTAssertEqual(ipad.book("Dune")?.notes, "from phone", "The phone's version was pushed last")
    }

    func testFirstSyncLinksMatchingBooksInsteadOfDuplicating() async throws {
        phone.add("Dune", isbn: "9780441013593")
        phone.add("Circe", author: "Madeline Miller")
        try await phone.sync()

        // The iPad already had the same books, typed in separately.
        ipad.add("Dune", isbn: "9780441013593")
        ipad.add("circe", author: "madeline miller")
        ipad.add("Only on iPad")
        try await ipad.sync()

        XCTAssertEqual(ipad.books.count, 3)
        XCTAssertEqual(remote.rows.count, 3)
    }

    func testCoverChangesSyncAndRemovedCoversAreCleanedUp() async throws {
        let dune = phone.add("Dune", cover: Data("old".utf8))
        try await phone.sync()
        try await ipad.sync()

        dune.coverImage = Data("new".utf8)
        try await phone.sync()
        try await ipad.sync()
        XCTAssertEqual(ipad.book("Dune")?.coverImage, Data("new".utf8))

        dune.coverImage = nil
        try await phone.sync()
        try await ipad.sync()
        XCTAssertNil(ipad.book("Dune")?.coverImage)
        XCTAssertTrue(remote.files.isEmpty)
    }

    func testFavouriteRanksAreRepairedAfterMerging() async throws {
        let a = phone.add("A")
        FavoritesShelf.add(a, library: phone.books)
        try await phone.sync()

        // The iPad made its own #1 before ever syncing.
        let b = ipad.add("B")
        FavoritesShelf.add(b, library: ipad.books)
        try await ipad.sync()

        XCTAssertEqual(FavoritesShelf.ordered(ipad.books).compactMap(\.favoriteRank), [1, 2])
    }

    func testProfileSyncsBothWays() async throws {
        let first = try await phone.engine.syncProfile(
            local: .init(name: "Kriti", photo: Data("me".utf8)), lastSynced: nil)
        XCTAssertEqual(remote.profile?.name, "Kriti")

        // A new device with no profile yet takes the online one.
        let (onIpad, _) = try await ipad.engine.syncProfile(local: .init(name: "", photo: nil), lastSynced: nil)
        XCTAssertEqual(onIpad, .init(name: "Kriti", photo: Data("me".utf8)))

        // Unchanged locally: nothing is overwritten.
        let (again, _) = try await phone.engine.syncProfile(local: first.0, lastSynced: first.1)
        XCTAssertEqual(again, first.0)
    }
}
