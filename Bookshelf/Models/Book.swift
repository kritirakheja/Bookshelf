import Foundation
import SwiftData

@Model
final class Book {
    var title: String
    var authors: [String]
    /// Digits only (hyphens stripped). Used to spot duplicates when adding.
    var isbn: String?
    @Attribute(.externalStorage) var coverImage: Data?
    var pageCount: Int?
    var publishedYear: Int?
    // Status is stored as two flags (rather than one enum) so that libraries saved
    // before "Reading" existed keep their read/unread state. Use `status` instead.
    var isRead: Bool = false
    var isReading: Bool = false
    var dateStarted: Date?
    var dateRead: Date?
    /// Only the year of `dateRead` is known (it's stored as 1 January of that year).
    var dateReadYearOnly: Bool = false
    var dateAdded: Date = Date.now
    var notes: String = ""
    /// 1–5 stars, nil = not rated.
    var rating: Int?
    @Relationship(inverse: \BookCategory.books) var categories: [BookCategory] = []
    /// nil = not on the favourites shelf; 1...N = position on the shelf.
    var favoriteRank: Int?
    var recommendationNote: String?
    /// Every time this book was lent out, including the current loan (if any).
    @Relationship(deleteRule: .cascade, inverse: \Loan.book) var loans: [Loan] = []

    // Backup & sync bookkeeping (see SyncEngine).
    /// The book's id in the online library; nil until first synced.
    var remoteID: UUID?
    /// Fingerprint of the book's details at the last sync; differs once edited.
    var syncedFingerprint: String?
    /// Hash of the cover at the last sync.
    var syncedCoverHash: String?

    init(
        title: String,
        authors: [String] = [],
        isbn: String? = nil,
        pageCount: Int? = nil,
        publishedYear: Int? = nil,
        coverImage: Data? = nil
    ) {
        self.title = title
        self.authors = authors
        self.isbn = isbn
        self.pageCount = pageCount
        self.publishedYear = publishedYear
        self.coverImage = coverImage
    }

    var authorLine: String {
        authors.isEmpty ? "Unknown author" : authors.formatted(.list(type: .and))
    }

    var isFavorite: Bool { favoriteRank != nil }

    /// "14 Mar 2026", or "2025" when only the year is known.
    var finishDateText: String? {
        guard let dateRead else { return nil }
        return dateReadYearOnly
            ? String(Calendar.current.component(.year, from: dateRead))
            : dateRead.formatted(date: .abbreviated, time: .omitted)
    }

    /// Records the year a book was finished when the exact day isn't known.
    func setFinishYear(_ year: Int, calendar: Calendar = .current) {
        dateRead = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
        dateReadYearOnly = true
    }

    var sortedCategories: [BookCategory] {
        categories.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Lending (my books, out with friends)

    /// Who has the book right now, if anyone.
    var currentLoan: Loan? { loans.first { !$0.isBorrowed && $0.returnedAt == nil } }

    var isLent: Bool { currentLoan != nil }

    /// Returned loans, most recent first.
    var pastLoans: [Loan] {
        loans.filter { !$0.isBorrowed && $0.returnedAt != nil }.sorted { $0.lentAt > $1.lentAt }
    }

    /// Records the book as lent. Does nothing if it's already out (return it first),
    /// or if it isn't mine to lend.
    func lend(to name: String, contactID: String? = nil, on date: Date = .now) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isLent, isOwned else { return }
        loans.append(Loan(borrowerName: name, contactID: contactID, lentAt: date))
    }

    func markReturned(on date: Date = .now) {
        currentLoan?.returnedAt = date
    }

    // MARK: Borrowing (someone else's book)

    /// The most recent time I borrowed this book, whether or not I've given it back.
    var borrowing: Loan? {
        loans.filter(\.isBorrowed).max { $0.lentAt < $1.lentAt }
    }

    /// Borrowed and still with me.
    var isBorrowed: Bool { borrowing.map { $0.returnedAt == nil } ?? false }

    /// Borrowed, and already given back to its owner.
    var isGivenBack: Bool { borrowing?.returnedAt != nil }

    /// My own copy: never borrowed from anyone.
    var isOwned: Bool { borrowing == nil }

    /// Marks the book as someone else's. Not while it's lent out (it would be mine then).
    func borrow(from name: String, contactID: String? = nil, on date: Date = .now) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isBorrowed, !isLent else { return }
        loans.append(Loan(borrowerName: name, contactID: contactID, lentAt: date, isBorrowed: true))
    }

    /// Gave the borrowed book back to its owner.
    func giveBack(on date: Date = .now) {
        guard isBorrowed else { return }
        borrowing?.returnedAt = date
    }

    var status: ReadingStatus {
        if isRead { return .read }
        if isReading { return .reading }
        return .unread
    }

    /// The one place the app changes reading status (Reading tab swipes and
    /// the picker on the book's page), keeping the dates consistent.
    func setStatus(_ newStatus: ReadingStatus) {
        guard newStatus != status else { return }
        switch newStatus {
        case .unread:
            isRead = false
            isReading = false
            dateStarted = nil
            dateRead = nil
            dateReadYearOnly = false
        case .reading:
            isRead = false
            isReading = true
            dateStarted = .now
            dateRead = nil
            dateReadYearOnly = false
        case .read:
            isRead = true
            isReading = false
            dateRead = .now
            dateReadYearOnly = false
        }
    }
}

enum ReadingStatus: String, CaseIterable, Identifiable {
    case unread = "Unread"
    case reading = "Reading"
    case read = "Read"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .unread: "book.closed"
        case .reading: "book"
        case .read: "checkmark.circle.fill"
        }
    }

    /// Label for a button that moves a book *to* this status.
    var actionTitle: String {
        switch self {
        case .unread: "Unread"
        case .reading: "Start reading"
        case .read: "Finished"
        }
    }
}
