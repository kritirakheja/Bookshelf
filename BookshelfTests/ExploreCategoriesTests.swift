import XCTest
import SwiftData
@testable import Bookshelf

@MainActor
final class ExploreCategoriesTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(
            for: Book.self, BookCategory.self, DeletedBook.self, Loan.self, ReadingEntry.self, Bookstore.self, DeletedBookstore.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func book(_ title: String, author: String = "A", pages: Int? = nil, category: String? = nil,
                      status: ReadingStatus = .unread, rating: Int? = nil, addedDaysAgo: Double = 0) -> Book {
        let book = Book(title: title, authors: [author], pageCount: pages)
        context.insert(book)
        book.setStatus(status)
        book.rating = rating
        book.dateAdded = Date.now.addingTimeInterval(-addedDaysAgo * 86_400)
        if let category { book.categories = [BookCategory.named(category, in: context)!] }
        return book
    }

    private func titles(in id: String, of explore: ExploreCategories) -> [String]? {
        explore.categories.first { $0.id == id }?.books.map(\.title)
    }

    func testCategories() {
        let books = [
            book("Reading now", category: "Fantasy", status: .reading),
            book("Short one", pages: 180, category: "Fantasy", addedDaysAgo: 1),
            book("Long one", pages: 600, category: "Fantasy", addedDaysAgo: 2),
            book("Work", category: "Business", addedDaysAgo: 3),
            book("Finished", category: "Fantasy", status: .read),
        ]
        let explore = ExploreCategories(books: books)

        XCTAssertEqual(titles(in: "category-Fantasy", of: explore), ["Short one", "Long one"], "Only unread books, newest first")
        XCTAssertEqual(explore.categories.map(\.id), ["category-Fantasy", "category-Business"], "Fullest category first")
    }

    func testBooksWithoutACategoryComeLast() {
        let explore = ExploreCategories(books: [book("Loose"), book("Sorted", category: "Fantasy")])
        XCTAssertEqual(explore.categories.map(\.title), ["Fantasy", "Not sorted yet"])
        XCTAssertEqual(titles(in: ExploreCategories.unsortedID, of: explore), ["Loose"])
    }

    func testNothingUnreadMeansNoCategories() {
        let explore = ExploreCategories(books: [book("Done", category: "Fantasy", status: .read)])
        XCTAssertTrue(explore.categories.isEmpty)
    }
}
