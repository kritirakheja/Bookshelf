import Foundation

/// Numbers for the Profile tab, computed from the whole library.
struct LibraryStats {
    /// Books I own (borrowed ones still count towards reading stats below).
    let total: Int
    /// Borrowed from friends and still with me.
    let borrowedCount: Int
    let readCount: Int
    let readingCount: Int
    let unreadCount: Int
    let pagesRead: Int
    let lentCount: Int

    init(books: [Book]) {
        let read = books.filter { $0.status == .read }
        total = books.filter(\.isOwned).count
        borrowedCount = books.filter(\.isBorrowed).count
        readCount = read.count
        readingCount = books.filter { $0.status == .reading }.count
        unreadCount = books.filter { $0.status == .unread && !$0.isGivenBack }.count
        pagesRead = read.compactMap(\.pageCount).reduce(0, +)
        lentCount = books.filter(\.isLent).count
    }
}
