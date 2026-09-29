import XCTest
import SwiftData
@testable import Bookshelf

@MainActor
final class FavoritesShelfTests: XCTestCase {
    private var container: ModelContainer!
    private var library: [Book] = []

    override func setUp() async throws {
        container = try ModelContainer(
            for: Book.self, BookCategory.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        library = (1...12).map { Book(title: "Book \($0)") }
        library.forEach(container.mainContext.insert)
    }

    private func shelfTitles() -> [String] {
        FavoritesShelf.ordered(library).map(\.title)
    }

    private func ranks() -> [Int] {
        FavoritesShelf.ordered(library).compactMap(\.favoriteRank)
    }

    func testAddAppendsToEnd() {
        XCTAssertEqual(FavoritesShelf.add(library[0], library: library), .added)
        XCTAssertEqual(FavoritesShelf.add(library[1], library: library), .added)
        XCTAssertEqual(shelfTitles(), ["Book 1", "Book 2"])
        XCTAssertEqual(ranks(), [1, 2])
    }

    func testAddTwiceIsRejected() {
        FavoritesShelf.add(library[0], library: library)
        XCTAssertEqual(FavoritesShelf.add(library[0], library: library), .alreadyOnShelf)
        XCTAssertEqual(ranks(), [1])
    }

    func testShelfIsCappedAtCapacity() {
        for book in library.prefix(FavoritesShelf.capacity) {
            XCTAssertEqual(FavoritesShelf.add(book, library: library), .added)
        }
        XCTAssertEqual(FavoritesShelf.add(library[10], library: library), .shelfFull)
        XCTAssertNil(library[10].favoriteRank)
        XCTAssertEqual(ranks(), Array(1...FavoritesShelf.capacity))
    }

    func testRemoveClosesTheGap() {
        library.prefix(3).forEach { FavoritesShelf.add($0, library: library) }
        FavoritesShelf.remove(library[1], library: library)
        XCTAssertNil(library[1].favoriteRank)
        XCTAssertEqual(shelfTitles(), ["Book 1", "Book 3"])
        XCTAssertEqual(ranks(), [1, 2])
    }

    func testMoveDown() {
        library.prefix(4).forEach { FavoritesShelf.add($0, library: library) }
        // List-style offsets: move the first item to just before index 3.
        FavoritesShelf.move(library: library, fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(shelfTitles(), ["Book 2", "Book 3", "Book 1", "Book 4"])
        XCTAssertEqual(ranks(), [1, 2, 3, 4])
    }

    func testMoveUp() {
        library.prefix(4).forEach { FavoritesShelf.add($0, library: library) }
        FavoritesShelf.move(library: library, fromOffsets: [3], toOffset: 0)
        XCTAssertEqual(shelfTitles(), ["Book 4", "Book 1", "Book 2", "Book 3"])
    }

    func testMoveToEnd() {
        library.prefix(3).forEach { FavoritesShelf.add($0, library: library) }
        FavoritesShelf.move(library: library, fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(shelfTitles(), ["Book 2", "Book 3", "Book 1"])
    }
}
