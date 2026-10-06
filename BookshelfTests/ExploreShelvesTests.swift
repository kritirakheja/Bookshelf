import XCTest
import SwiftData
@testable import Bookshelf

@MainActor
final class ExploreShelvesTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(
            for: Book.self, BookCategory.self, DeletedBook.self, Loan.self, Bookstore.self, DeletedBookstore.self,
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

    private func shelf(_ id: String, in shelves: ExploreShelves) -> [String]? {
        shelves.categories.first { $0.id == id }?.books.map(\.title)
    }

    func testCategories() {
        let books = [
            book("Reading now", category: "Fantasy", status: .reading),
            book("Short one", pages: 180, category: "Fantasy", addedDaysAgo: 1),
            book("Long one", pages: 600, category: "Fantasy", addedDaysAgo: 2),
            book("Work", category: "Business", addedDaysAgo: 3),
            book("Finished", category: "Fantasy", status: .read),
        ]
        let shelves = ExploreShelves(books: books)

        XCTAssertEqual(shelf("category-Fantasy", in: shelves), ["Short one", "Long one"], "Only unread books, newest first")
        XCTAssertEqual(shelves.categories.map(\.id), ["category-Fantasy", "category-Business"], "Fullest category first")
    }

    func testBooksWithoutACategoryComeLast() {
        let shelves = ExploreShelves(books: [book("Loose"), book("Sorted", category: "Fantasy")])
        XCTAssertEqual(shelves.categories.map(\.title), ["Fantasy", "Not sorted yet"])
        XCTAssertEqual(shelf(ExploreShelves.unsortedID, in: shelves), ["Loose"])
    }

    func testNothingUnreadMeansNoCategories() {
        let shelves = ExploreShelves(books: [book("Done", category: "Fantasy", status: .read)])
        XCTAssertTrue(shelves.categories.isEmpty)
    }
}
