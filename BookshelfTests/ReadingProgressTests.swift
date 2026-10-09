import XCTest
import SwiftData
@testable import Bookshelf

@MainActor
final class ReadingProgressTests: XCTestCase {
    private var container: ModelContainer!
    private let calendar = Calendar.current

    override func setUp() async throws {
        container = try ModelContainer(
            for: Book.self, BookCategory.self, DeletedBook.self, Loan.self, ReadingEntry.self, Bookstore.self, DeletedBookstore.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func book(pages: Int? = 300) -> Book {
        let book = Book(title: "Circe", pageCount: pages)
        container.mainContext.insert(book)
        book.setStatus(.reading)
        return book
    }

    private func day(_ back: Int) -> Date {
        calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: .now))!
    }

    func testPercentageAndPagesToGo() {
        let book = book()
        XCTAssertEqual(book.progressPercent, 0)
        book.logProgress(page: 110)
        XCTAssertEqual(book.currentPage, 110)
        XCTAssertEqual(book.progressPercent, 36)
        XCTAssertEqual(book.pagesToGo, 190)
        XCTAssertEqual(book.progressSummary, "36% · page 110 of 300")
    }

    func testPagesPerDayComeFromTheDifference() {
        let book = book()
        book.logProgress(page: 50, on: day(2))
        book.logProgress(page: 110, on: day(0))
        XCTAssertEqual(book.pagesRead(on: day(2)), 50)
        XCTAssertEqual(book.pagesRead(on: day(1)), 0, "Nothing logged that day")
        XCTAssertEqual(book.pagesRead(on: day(0)), 60)
        XCTAssertEqual(book.dailyPages(last: 4).map(\.pages), [0, 50, 0, 60])
    }

    func testLoggingAgainTheSameDayReplacesTheEntry() {
        let book = book()
        book.logProgress(page: 50, on: day(1))
        book.logProgress(page: 80)
        book.logProgress(page: 95)
        XCTAssertEqual(book.progress.count, 2)
        XCTAssertEqual(book.pagesRead(on: .now), 45)
    }

    func testMovingThePageBackIsACorrectionNotNegativeReading() {
        let book = book()
        book.logProgress(page: 100, on: day(1))
        book.logProgress(page: 90)
        XCTAssertEqual(book.pagesRead(on: .now), 0)
        XCTAssertEqual(book.currentPage, 90)
    }

    func testThePageStaysWithinTheBook() {
        let book = book()
        book.logProgress(page: 999)
        XCTAssertEqual(book.currentPage, 300)
        XCTAssertEqual(book.progressPercent, 100)
    }

    func testNoPageCountMeansNoPercentage() {
        let book = book(pages: nil)
        book.logProgress(page: 40)
        XCTAssertNil(book.progressPercent)
        XCTAssertEqual(book.progressSummary, "Page 40")
    }

    func testUnreadClearsTheLogAndReadKeepsIt() {
        let finished = book()
        finished.logProgress(page: 300)
        finished.setStatus(.read)
        XCTAssertEqual(finished.progress.count, 1)

        let abandoned = book()
        abandoned.logProgress(page: 20)
        abandoned.setStatus(.unread)
        XCTAssertTrue(abandoned.progress.isEmpty)
    }

    func testProgressIsPartOfWhatSyncs() throws {
        let book = book()
        let before = SyncHash.fingerprint(of: book)
        book.logProgress(page: 10)
        XCTAssertNotEqual(SyncHash.fingerprint(of: book), before, "Logging progress marks the book as changed")
        XCTAssertEqual(BookRecord(book: book, id: UUID()).progress?.map(\.page), [10])

        // A row saved before progress existed still decodes.
        let old = #"{"id":"00000000-0000-0000-0000-000000000001","title":"Old","authors":[],"is_read":false,"is_reading":true,"date_added":0,"notes":"","categories":[],"deleted":false}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        XCTAssertNil(try decoder.decode(BookRecord.self, from: Data(old.utf8)).progress)
    }

    func testPageCountComesFromEditionsOfTheSameBook() {
        func edition(_ title: String, _ author: String, _ pages: Int?) -> BookCandidate {
            BookCandidate(id: UUID().uuidString, source: .openLibrary, title: title, authors: [author], pageCount: pages)
        }
        let editions = [
            edition("Blue Sisters", "Coco Mellors", 352),
            edition("Blue Sisters: A Novel", "Coco Mellors", 368),
            edition("Blue Sisters", "Coco Mellors", 400),
            edition("Blue Sisters", "Coco Mellors", 12),          // a sample
            edition("Blue Sisters", "Someone Else", 900),         // another book
            edition("Summary of Blue Sisters", "Coco Mellors", 60),
            edition("Blue Sisters", "Coco Mellors", nil),
        ]
        XCTAssertEqual(BookLookup.pageCount(title: "Blue Sisters", author: "Coco Mellors", among: editions), 368, "The middle of the real editions")
        XCTAssertNil(BookLookup.pageCount(title: "Dr. Cuterus", author: "Tanaya Narendra", among: editions))
    }

    func testTheMostRecentlyUpdatedBookComesFirst() {
        let morning = book(), evening = book(), justStarted = book(), lastWeek = book()
        let today = calendar.startOfDay(for: .now)
        morning.title = "Morning"; evening.title = "Evening"; justStarted.title = "Just started"; lastWeek.title = "Last week"
        for old in [morning, evening, lastWeek] { old.dateStarted = day(30) }
        lastWeek.logProgress(page: 40, on: day(7))
        morning.logProgress(page: 10, on: today.addingTimeInterval(8 * 3600))
        evening.logProgress(page: 10, on: today.addingTimeInterval(20 * 3600))
        justStarted.dateStarted = today.addingTimeInterval(3600)

        let order = CurrentlyReadingView.ordered([lastWeek, justStarted, morning, evening]).map(\.title)
        XCTAssertEqual(order, ["Evening", "Morning", "Just started", "Last week"])

        // An entry from before the time was recorded counts as its day.
        lastWeek.progress[0].loggedAt = nil
        XCTAssertEqual(lastWeek.lastActivity, day(7))
    }

    func testTheLoggedTimeSyncsAndOldEntriesStillDecode() throws {
        let book = book()
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        book.logProgress(page: 10, on: moment)
        XCTAssertEqual(BookRecord(book: book, id: UUID()).progress?.first?.loggedAt, moment)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let old = #"{"id":"00000000-0000-0000-0000-000000000001","date":0,"page":12}"#
        XCTAssertNil(try decoder.decode(ProgressRecord.self, from: Data(old.utf8)).loggedAt)
    }
}
