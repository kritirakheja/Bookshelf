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
        shelves.shelves.first { $0.id == id }?.books.map(\.title)
    }

    func testShelves() {
        let books = [
            book("Reading now", status: .reading),
            book("Short one", pages: 180, category: "Fantasy", addedDaysAgo: 1),
            book("Long one", pages: 600, category: "Fantasy", addedDaysAgo: 2),
            book("By a favourite", author: "Loved", category: "Business", addedDaysAgo: 3),
            book("Loved before", author: "Loved", status: .read, rating: 5),
            book("Finished", category: "Fantasy", status: .read),
        ]
        let shelves = ExploreShelves(books: books)

        XCTAssertEqual(shelf("reading", in: shelves), ["Reading now"])
        XCTAssertEqual(shelf("recent", in: shelves), ["Short one", "Long one", "By a favourite"], "Unread, newest first")
        XCTAssertEqual(shelf("quick", in: shelves), ["Short one"])
        XCTAssertEqual(shelf("authors", in: shelves), ["By a favourite"])
        XCTAssertEqual(shelf("category-Fantasy", in: shelves), ["Short one", "Long one"], "Only unread books")
        XCTAssertEqual(shelves.shelves.map(\.id).suffix(2), ["category-Fantasy", "category-Business"], "Fullest category first")
    }

    func testEmptyShelvesAreLeftOut() {
        let shelves = ExploreShelves(books: [book("Only", pages: 400)])
        XCTAssertEqual(shelves.shelves.map(\.id), ["recent"])
    }

    func testFeaturedIsStableForADayAndChangesAfter() {
        let books = (1...20).map { book("Book \($0)") }
        let monday = Date(timeIntervalSince1970: 1_790_000_000)
        let first = ExploreShelves(books: books, today: monday).featured.map(\.title)
        let again = ExploreShelves(books: books, today: monday.addingTimeInterval(3600)).featured.map(\.title)
        let tomorrow = ExploreShelves(books: books, today: monday.addingTimeInterval(86_400)).featured.map(\.title)
        XCTAssertEqual(first.count, 5)
        XCTAssertEqual(first, again)
        XCTAssertNotEqual(first, tomorrow)
    }
}
