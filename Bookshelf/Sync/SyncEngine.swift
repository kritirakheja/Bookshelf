import Foundation
import SwiftData

/// Two-way sync between the library on this phone and the online backup.
///
/// - A book has *local changes* when its fingerprint or cover differs from the last
///   sync (or it has never been synced), so edits don't need tracking where they happen.
/// - Pull runs first: online changes are applied to books without local changes. When
///   both sides changed, this phone's version wins and is pushed straight after.
/// - Deletions travel as a `deleted` flag so other devices remove the book too.
/// - On a first sync, local books matching an online one (same ISBN, or same title and
///   first author) are linked rather than duplicated.
@MainActor
struct SyncEngine {
    let context: ModelContext
    let remote: SyncRemote
    let userID: UUID

    struct Result: Equatable {
        var lastPulledAt: Date?
        var pulled: Int
        var pushed: Int
    }

    func syncBooks(lastPulledAt: Date?) async throws -> Result {
        // 1. Deletions made here go first, so the pull can't bring those books back.
        let tombstones = try context.fetch(FetchDescriptor<DeletedBook>())
        if !tombstones.isEmpty {
            let ids = tombstones.map(\.remoteID)
            try await remote.markBooksDeleted(ids)
            try? await remote.removeFiles(paths: ids.map(coverPath))
            tombstones.forEach(context.delete)
        }

        // 2. Pull.
        var books = try context.fetch(FetchDescriptor<Book>())
        var byID = Dictionary(books.compactMap { book in book.remoteID.map { ($0, book) } }, uniquingKeysWith: { first, _ in first })
        var newest = lastPulledAt
        var pulled = 0

        for row in try await remote.fetchBooks(updatedAfter: lastPulledAt) {
            if let updated = row.updatedAt, newest.map({ updated > $0 }) ?? true {
                newest = updated
            }
            if let local = byID[row.id] {
                guard !hasLocalChanges(local) else { continue }
                if row.deleted {
                    if local.isFavorite { FavoritesShelf.remove(local, library: books) }
                    books.removeAll { $0 === local }
                    byID[row.id] = nil
                    context.delete(local)
                } else {
                    try await apply(row, to: local, keepingLocalCover: false)
                }
                pulled += 1
            } else if !row.deleted {
                if let match = unsyncedMatch(for: row, in: books) {
                    match.remoteID = row.id
                    byID[row.id] = match
                    try await apply(row, to: match, keepingLocalCover: true)
                } else {
                    let book = Book(title: row.title)
                    context.insert(book)
                    book.remoteID = row.id
                    books.append(book)
                    byID[row.id] = book
                    try await apply(row, to: book, keepingLocalCover: false)
                }
                pulled += 1
            }
        }
        // Two devices may have ranked favourites independently.
        FavoritesShelf.normalize(books)

        // 3. Push everything with local changes.
        let changed = books.filter(hasLocalChanges)
        var records: [BookRecord] = []
        var staleCovers: [String] = []
        for book in changed {
            let id = book.remoteID ?? UUID()
            book.remoteID = id
            var record = BookRecord(book: book, id: id)
            if let data = book.coverImage, let hash = SyncHash.cover(of: book) {
                record.coverPath = coverPath(id)
                record.coverHash = hash
                if hash != book.syncedCoverHash {
                    try await remote.uploadFile(data, path: coverPath(id))
                }
            } else if book.syncedCoverHash != nil {
                staleCovers.append(coverPath(id))
            }
            records.append(record)
        }
        try await remote.upsertBooks(records)
        try? await remote.removeFiles(paths: staleCovers)
        for book in changed {
            book.syncedFingerprint = SyncHash.fingerprint(of: book)
            book.syncedCoverHash = SyncHash.cover(of: book)
        }

        try context.save()
        return Result(lastPulledAt: newest, pulled: pulled, pushed: changed.count)
    }

    func hasLocalChanges(_ book: Book) -> Bool {
        book.remoteID == nil
            || book.syncedFingerprint != SyncHash.fingerprint(of: book)
            || book.syncedCoverHash != SyncHash.cover(of: book)
    }

    private func apply(_ row: BookRecord, to book: Book, keepingLocalCover: Bool) async throws {
        book.title = row.title
        book.authors = row.authors
        book.isbn = row.isbn
        book.pageCount = row.pageCount
        book.publishedYear = row.publishedYear
        book.isRead = row.isRead
        book.isReading = row.isReading
        book.dateStarted = row.dateStarted
        book.dateRead = row.dateRead
        book.dateReadYearOnly = row.dateReadYearOnly ?? false
        book.dateAdded = row.dateAdded
        book.notes = row.notes
        book.summary = row.summary
        book.rating = row.rating
        book.favoriteRank = row.favoriteRank
        book.recommendationNote = row.recommendationNote
        book.categories = row.categories.compactMap { BookCategory.named($0, in: context) }
        applyLoans(row.loans ?? [], to: book)
        applyProgress(row.progress ?? [], to: book)

        if let hash = row.coverHash, let path = row.coverPath {
            if hash != SyncHash.cover(of: book) {
                book.coverImage = try await remote.downloadFile(path: path)
            }
            book.syncedCoverHash = hash
        } else if keepingLocalCover {
            book.syncedCoverHash = nil   // online copy has no cover: upload this phone's
        } else {
            book.coverImage = nil
            book.syncedCoverHash = nil
        }
        book.syncedFingerprint = SyncHash.fingerprint(of: book)
    }

    /// Makes the book's loans match the online row: update by id, add new, drop missing.
    private func applyLoans(_ records: [LoanRecord], to book: Book) {
        let existing = Dictionary(book.loans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let incomingIDs = Set(records.map(\.id))
        for loan in book.loans where !incomingIDs.contains(loan.id) {
            context.delete(loan)
        }
        book.loans = records.map { record in
            let loan = existing[record.id] ?? {
                let loan = Loan(borrowerName: record.borrowerName)
                loan.id = record.id
                context.insert(loan)
                return loan
            }()
            loan.borrowerName = record.borrowerName
            loan.contactID = record.contactID
            loan.lentAt = record.lentAt
            loan.returnedAt = record.returnedAt
            loan.isBorrowed = record.isBorrowed ?? false
            return loan
        }
    }

    /// Makes the book's reading log match the online row, the same way.
    private func applyProgress(_ records: [ProgressRecord], to book: Book) {
        let existing = Dictionary(book.progress.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let incomingIDs = Set(records.map(\.id))
        for entry in book.progress where !incomingIDs.contains(entry.id) {
            context.delete(entry)
        }
        book.progress = records.map { record in
            let entry = existing[record.id] ?? {
                let entry = ReadingEntry(date: record.date, page: record.page)
                entry.id = record.id
                context.insert(entry)
                return entry
            }()
            entry.date = record.date
            entry.page = record.page
            entry.loggedAt = record.loggedAt
            return entry
        }
    }

    private func unsyncedMatch(for row: BookRecord, in books: [Book]) -> Book? {
        let unsynced = books.filter { $0.remoteID == nil }
        if let isbn = row.isbn, let match = unsynced.first(where: { $0.isbn == isbn }) {
            return match
        }
        let key = Self.matchKey(title: row.title, author: row.authors.first)
        return unsynced.first { Self.matchKey(title: $0.title, author: $0.authors.first) == key }
    }

    private static func matchKey(title: String, author: String?) -> String {
        "\(title.lowercased())|\((author ?? "").lowercased())"
    }

    /// Files live under the account's own folder, which the storage rules require.
    func coverPath(_ bookID: UUID) -> String {
        "\(userID.uuidString.lowercased())/covers/\(bookID.uuidString.lowercased()).jpg"
    }

    // MARK: Profile

    struct Profile: Equatable {
        var name: String
        var photo: Data?
    }

    /// What the profile looked like at the last sync, to tell which side changed.
    struct ProfileFingerprint: Codable, Equatable {
        var name: String
        var photoHash: String?
    }

    /// Returns the profile to keep on this phone and the new fingerprint to store.
    func syncProfile(local: Profile, lastSynced: ProfileFingerprint?) async throws -> (Profile, ProfileFingerprint) {
        let localFingerprint = ProfileFingerprint(name: local.name, photoHash: local.photo.map(SyncHash.of))
        let online = try await remote.fetchProfile()

        let isFreshDevice = lastSynced == nil && local.name.isEmpty && local.photo == nil
        if localFingerprint != lastSynced && !isFreshDevice {
            // Changed here (or first sync from this phone): upload.
            let photoPath = "\(userID.uuidString.lowercased())/profile.jpg"
            if let photo = local.photo, localFingerprint.photoHash != online?.photoHash {
                try await remote.uploadFile(photo, path: photoPath)
            }
            try await remote.upsertProfile(ProfileRecord(
                userID: userID,
                name: local.name,
                photoPath: local.photo == nil ? nil : photoPath,
                photoHash: localFingerprint.photoHash
            ))
            return (local, localFingerprint)
        }

        guard let online else { return (local, localFingerprint) }
        let onlineFingerprint = ProfileFingerprint(name: online.name, photoHash: online.photoHash)
        guard onlineFingerprint != localFingerprint else { return (local, localFingerprint) }

        var updated = Profile(name: online.name, photo: local.photo)
        if online.photoHash != localFingerprint.photoHash {
            updated.photo = try await online.photoPath.asyncMap { try await remote.downloadFile(path: $0) }
        }
        return (updated, onlineFingerprint)
    }
}

private extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let self else { return nil }
        return try await transform(self)
    }
}
