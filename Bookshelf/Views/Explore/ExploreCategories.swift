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

    /// One entry per category that has unread books (plus "Not sorted yet" for books
    /// with none), the one you added to most recently first, so a book you just added
    /// is in the top card.
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
        var categories = byCategory.keys.map { Category(id: "category-\($0)", title: $0, books: byCategory[$0]!) }

        let unsorted = unread.filter { $0.categories.isEmpty }
        if !unsorted.isEmpty {
            categories.append(Category(id: Self.unsortedID, title: "Not sorted yet", books: unsorted))
        }
        self.categories = categories.sorted(by: Self.newestFirst)
    }

    /// Each category's books are newest first, so its first book says when it was
    /// last added to.
    private static func newestFirst(_ a: Category, _ b: Category) -> Bool {
        let newestA = a.books[0].dateAdded, newestB = b.books[0].dateAdded
        if newestA != newestB { return newestA > newestB }
        if a.books.count != b.books.count { return a.books.count > b.books.count }
        return a.title < b.title
    }
}
