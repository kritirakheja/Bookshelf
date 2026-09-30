import XCTest
import SwiftData
@testable import Bookshelf

@MainActor
final class LibraryStatsTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int = 6) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 15))!
    }

    private func book(_ title: String, author: String = "A", pages: Int? = nil, status: ReadingStatus = .unread,
                      finished: Date? = nil, rating: Int? = nil) -> Book {
        let book = Book(title: title, authors: [author], pageCount: pages)
        book.setStatus(status)
        if status == .read { book.dateRead = finished }
        book.rating = rating
        return book
    }

    func testCountsAndPages() {
        let books = [
            book("A", pages: 300, status: .read, finished: date(2026), rating: 5),
            book("B", pages: 200, status: .read, finished: nil, rating: 3),
            book("C", pages: 999, status: .reading),
            book("D", status: .unread, rating: 4),
        ]
        let stats = LibraryStats(books: books)
        XCTAssertEqual(stats.total, 4)
        XCTAssertEqual(stats.readCount, 2)
        XCTAssertEqual(stats.readingCount, 1)
        XCTAssertEqual(stats.unreadCount, 1)
    }

    func testEmptyLibrary() {
        let stats = LibraryStats(books: [])
        XCTAssertEqual(stats.total, 0)
        XCTAssertEqual(stats.lentCount, 0)
    }
}
