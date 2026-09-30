import XCTest
import SwiftData
@testable import Bookshelf

@MainActor
final class LibrarySectionsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(
            for: Book.self, BookCategory.self, DeletedBook.self, Loan.self, Bookstore.self, DeletedBookstore.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func book(_ title: String, _ categories: [String]) -> Book {
        let book = Book(title: title)
        context.insert(book)
        book.categories = categories.compactMap { BookCategory.named($0, in: context) }
        return book
    }

    func testSides() {
        XCTAssertEqual(LibrarySections.side(of: book("Circe", ["Mythology"])), .fiction)
        XCTAssertEqual(LibrarySections.side(of: book("Book Thief", ["Historical Fiction", "Young Adult"])), .fiction)
        XCTAssertEqual(LibrarySections.side(of: book("Zero to One", ["Business"])), .nonFiction)
        XCTAssertEqual(LibrarySections.side(of: book("White Nights", ["Classics"])), .fiction, "A classic with nothing else is a novel/play")
        XCTAssertEqual(LibrarySections.side(of: book("Beyond Good and Evil", ["Philosophy", "Classics"])), .nonFiction)
        XCTAssertEqual(LibrarySections.side(of: book("Pride and Prejudice", ["Classics", "Romance"])), .fiction)
        XCTAssertEqual(LibrarySections.side(of: book("Unsure", ["Did Not Finish"])), .unsorted)
        XCTAssertEqual(LibrarySections.side(of: book("New", [])), .unsorted)
    }

    func testSplitKeepsOrderAndDropsEmptySections() {
        let a = book("A", ["Romance"]), b = book("B", ["Business"]), c = book("C", ["Fantasy"])
        let sections = LibrarySections.split([a, b, c])
        XCTAssertEqual(sections.map(\.title), ["Fiction", "Non-fiction"])
        XCTAssertEqual(sections[0].books.map(\.title), ["A", "C"])
        XCTAssertEqual(LibrarySections.split([b]).map(\.title), ["Non-fiction"])
    }
}
