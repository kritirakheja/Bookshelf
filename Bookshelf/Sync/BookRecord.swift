import Foundation
import CryptoKit

/// A book as stored online (one row of the `books` table).
struct BookRecord: Codable, Equatable {
    var id: UUID
    var title: String
    var authors: [String]
    var isbn: String?
    var pageCount: Int?
    var publishedYear: Int?
    var isRead: Bool
    var isReading: Bool
    var dateStarted: Date?
    var dateRead: Date?
    var dateAdded: Date
    var notes: String
    var rating: Int?
    var categories: [String]
    var favoriteRank: Int?
    var recommendationNote: String?
    var coverPath: String?
    var coverHash: String?
    /// Lending history, stored as a JSON array in the row. Optional so rows from
    /// before lending existed still decode.
    var loans: [LoanRecord]?
    var deleted: Bool = false
    /// Set by the server; never sent.
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, authors, isbn, notes, rating, categories, loans, deleted
        case pageCount = "page_count"
        case publishedYear = "published_year"
        case isRead = "is_read"
        case isReading = "is_reading"
        case dateStarted = "date_started"
        case dateRead = "date_read"
        case dateAdded = "date_added"
        case favoriteRank = "favorite_rank"
        case recommendationNote = "recommendation_note"
        case coverPath = "cover_path"
        case coverHash = "cover_hash"
        case updatedAt = "updated_at"
    }

    /// Writes nil values as explicit nulls, so clearing a field (e.g. removing a rating)
    /// reaches the server. The synthesized encoder would leave them out, and the old
    /// value would stay online. `updated_at` is left out: the server sets it.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(authors, forKey: .authors)
        try c.encode(isbn, forKey: .isbn)
        try c.encode(pageCount, forKey: .pageCount)
        try c.encode(publishedYear, forKey: .publishedYear)
        try c.encode(isRead, forKey: .isRead)
        try c.encode(isReading, forKey: .isReading)
        try c.encode(dateStarted, forKey: .dateStarted)
        try c.encode(dateRead, forKey: .dateRead)
        try c.encode(dateAdded, forKey: .dateAdded)
        try c.encode(notes, forKey: .notes)
        try c.encode(rating, forKey: .rating)
        try c.encode(categories, forKey: .categories)
        try c.encode(favoriteRank, forKey: .favoriteRank)
        try c.encode(recommendationNote, forKey: .recommendationNote)
        try c.encode(coverPath, forKey: .coverPath)
        try c.encode(coverHash, forKey: .coverHash)
        try c.encode(loans ?? [], forKey: .loans)
        try c.encode(deleted, forKey: .deleted)
    }
}

/// One loan inside a book's row.
struct LoanRecord: Codable, Equatable {
    var id: UUID
    var borrowerName: String
    var contactID: String?
    var lentAt: Date
    var returnedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case borrowerName = "borrower_name"
        case contactID = "contact_id"
        case lentAt = "lent_at"
        case returnedAt = "returned_at"
    }

    init(loan: Loan) {
        id = loan.id
        borrowerName = loan.borrowerName
        contactID = loan.contactID
        lentAt = loan.lentAt
        returnedAt = loan.returnedAt
    }
}

extension BookRecord {
    /// The book's syncable details, without the cover (tracked separately by hash).
    init(book: Book, id: UUID) {
        self.init(
            id: id,
            title: book.title,
            authors: book.authors,
            isbn: book.isbn,
            pageCount: book.pageCount,
            publishedYear: book.publishedYear,
            isRead: book.isRead,
            isReading: book.isReading,
            dateStarted: book.dateStarted,
            dateRead: book.dateRead,
            dateAdded: book.dateAdded,
            notes: book.notes,
            rating: book.rating,
            categories: book.sortedCategories.map(\.name),
            favoriteRank: book.favoriteRank,
            recommendationNote: book.recommendationNote
        )
        // Sorted so the fingerprint doesn't depend on the database's ordering.
        loans = book.loans
            .sorted { ($0.lentAt, $0.id.uuidString) < ($1.lentAt, $1.id.uuidString) }
            .map(LoanRecord.init(loan:))
    }
}

enum SyncHash {
    static func of(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Fingerprint of a book's details. It changes whenever anything that syncs is
    /// edited, so edits never have to be tracked at each place the app changes a book.
    static func fingerprint(of book: Book) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let record = BookRecord(book: book, id: UUID(uuid: UUID_NULL))
        return of((try? encoder.encode(record)) ?? Data())
    }

    static func cover(of book: Book) -> String? {
        book.coverImage.map(of)
    }
}
