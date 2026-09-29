import Foundation
import SwiftData

/// The rows on the Explore page, Netflix-style: a few featured books, then shelves of
/// unread books to browse sideways.
struct ExploreShelves {
    struct Shelf: Identifiable {
        let id: String
        let title: String
        let books: [Book]
    }

    /// Unread books to feature at the top: a different handful each day.
    let featured: [Book]
    let shelves: [Shelf]

    static let quickReadPages = 250

    init(books: [Book], today: Date = .now, calendar: Calendar = .current) {
        // Unread and still here (not already given back to a friend), newest first.
        let unread = books
            .filter { $0.status == .unread && !$0.isGivenBack }
            .sorted { $0.dateAdded > $1.dateAdded }

        featured = Self.dailyPick(from: unread, count: 5, today: today, calendar: calendar)

        var shelves: [Shelf] = []
        let reading = books.filter { $0.status == .reading }
            .sorted { ($0.dateStarted ?? .distantPast) > ($1.dateStarted ?? .distantPast) }
        shelves.append(Shelf(id: "reading", title: "Continue reading", books: reading))
        shelves.append(Shelf(id: "recent", title: "Recently added", books: Array(unread.prefix(20))))
        shelves.append(Shelf(id: "quick", title: "Quick reads",
                             books: unread.filter { ($0.pageCount ?? .max) < Self.quickReadPages }))

        // Authors of books rated 4★ or more.
        let lovedAuthors = Set(books.filter { ($0.rating ?? 0) >= 4 }.compactMap { $0.authors.first?.lowercased() })
        shelves.append(Shelf(id: "authors", title: "More from authors you love",
                             books: unread.filter { lovedAuthors.contains($0.authors.first?.lowercased() ?? "") }))

        // One shelf per category, fullest first.
        var byCategory: [String: [Book]] = [:]
        for book in unread {
            for category in book.categories {
                byCategory[category.name, default: []].append(book)
            }
        }
        let fullestFirst = byCategory.keys.sorted { a, b in
            let countA = byCategory[a]!.count, countB = byCategory[b]!.count
            return countA != countB ? countA > countB : a < b
        }
        for name in fullestFirst {
            shelves.append(Shelf(id: "category-\(name)", title: name, books: byCategory[name]!))
        }

        self.shelves = shelves.filter { !$0.books.isEmpty }
    }

    /// The same picks all day, new ones tomorrow.
    static func dailyPick(from books: [Book], count: Int, today: Date, calendar: Calendar) -> [Book] {
        guard books.count > count else { return books }
        let day = calendar.ordinality(of: .day, in: .era, for: today) ?? 0
        var generator = SeededGenerator(seed: UInt64(day))
        return Array(books.shuffled(using: &generator).prefix(count))
    }
}

/// Small repeatable random generator (SplitMix64), so a day's picks don't change
/// every time the page redraws.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
