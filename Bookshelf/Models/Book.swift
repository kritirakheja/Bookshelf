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
    var dateAdded: Date = Date.now
    var notes: String = ""
    /// 1–5 stars, nil = not rated.
    var rating: Int?
    @Relationship(inverse: \BookCategory.books) var categories: [BookCategory] = []
    /// nil = not on the favourites shelf; 1...N = position on the shelf.
    var favoriteRank: Int?
    var recommendationNote: String?

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

    var sortedCategories: [BookCategory] {
        categories.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
        case .reading:
            isRead = false
            isReading = true
            dateStarted = .now
            dateRead = nil
        case .read:
            isRead = true
            isReading = false
            dateRead = .now
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
