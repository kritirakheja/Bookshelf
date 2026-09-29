import Foundation

/// Numbers for the Profile tab, computed from the whole library.
struct LibraryStats {
    struct YearCount: Identifiable, Equatable {
        let year: Int
        let count: Int
        var id: Int { year }
    }

    struct NameCount: Identifiable, Equatable {
        let name: String
        let count: Int
        var id: String { name }
    }

    let total: Int
    let readCount: Int
    let readingCount: Int
    let unreadCount: Int
    let pagesRead: Int
    let lentCount: Int
    let averageRating: Double?
    let readThisYear: Int
    /// Only books with a finish date count here.
    let finishedPerYear: [YearCount]
    let datedReadCount: Int
    /// Index 0 = 1 star ... index 4 = 5 stars.
    let ratingCounts: [Int]
    let topAuthors: [NameCount]
    let topCategories: [NameCount]

    init(books: [Book], now: Date = .now, calendar: Calendar = .current) {
        let read = books.filter { $0.status == .read }
        total = books.count
        readCount = read.count
        readingCount = books.filter { $0.status == .reading }.count
        unreadCount = books.filter { $0.status == .unread }.count
        pagesRead = read.compactMap(\.pageCount).reduce(0, +)
        lentCount = books.filter(\.isLent).count

        let ratings = books.compactMap(\.rating)
        averageRating = ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count)
        ratingCounts = (1...5).map { star in ratings.filter { $0 == star }.count }

        let finishYears = read.compactMap(\.dateRead).map { calendar.component(.year, from: $0) }
        datedReadCount = finishYears.count
        readThisYear = finishYears.filter { $0 == calendar.component(.year, from: now) }.count
        finishedPerYear = Dictionary(grouping: finishYears, by: { $0 })
            .map { YearCount(year: $0.key, count: $0.value.count) }
            .sorted { $0.year < $1.year }

        topAuthors = Self.top(read.compactMap(\.authors.first), limit: 3, minimum: 2)
        topCategories = Self.top(books.flatMap { $0.categories.map(\.name) }, limit: 3, minimum: 1)
    }

    /// Most frequent names, ties broken alphabetically.
    private static func top(_ names: [String], limit: Int, minimum: Int) -> [NameCount] {
        Dictionary(grouping: names, by: { $0 })
            .map { NameCount(name: $0.key, count: $0.value.count) }
            .filter { $0.count >= minimum }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
            .prefix(limit)
            .map { $0 }
    }
}
