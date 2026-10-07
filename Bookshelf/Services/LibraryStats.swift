import Foundation

/// Numbers for the Profile tab, computed from the whole library.
struct LibraryStats {
    /// Every book in the library, as listed under All books (including friends'
    /// books I've borrowed).
    let total: Int
    /// Borrowed from friends and still with me.
    let borrowedCount: Int
    let readCount: Int
    let readingCount: Int
    let unreadCount: Int
    let lentCount: Int

    init(books: [Book]) {
        let read = books.filter { $0.status == .read }
        total = books.count
        borrowedCount = books.filter(\.isBorrowed).count
        readCount = read.count
        readingCount = books.filter { $0.status == .reading }.count
        unreadCount = books.filter { $0.status == .unread && !$0.isGivenBack }.count
        lentCount = books.filter(\.isLent).count
    }
}
