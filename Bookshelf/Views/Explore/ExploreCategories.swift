import Foundation
import SwiftData

/// The Explore page's contents: your unread books grouped by category.
struct ExploreCategories {
    struct Category: Identifiable {
        let id: String
        let title: String
        let books: [Book]
    }

    static let unsortedID = "unsorted"

    /// One entry per category that has unread books, fullest first, then the unread
    /// books with no category at all.
    let categories: [Category]

    init(books: [Book]) {
        // Unread and still here (not already given back to a friend), newest first.
        let unread = books
            .filter { $0.status == .unread && !$0.isGivenBack }
            .sorted { $0.dateAdded > $1.dateAdded }

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
        var categories = fullestFirst.map { Category(id: "category-\($0)", title: $0, books: byCategory[$0]!) }

        let unsorted = unread.filter { $0.categories.isEmpty }
        if !unsorted.isEmpty {
            categories.append(Category(id: Self.unsortedID, title: "Not sorted yet", books: unsorted))
        }
        self.categories = categories
    }
}
