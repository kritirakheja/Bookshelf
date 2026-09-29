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
        let stats = LibraryStats(books: books, now: date(2026, 9), calendar: calendar)
        XCTAssertEqual(stats.total, 4)
        XCTAssertEqual(stats.readCount, 2)
        XCTAssertEqual(stats.readingCount, 1)
        XCTAssertEqual(stats.unreadCount, 1)
        XCTAssertEqual(stats.pagesRead, 500, "Only read books count towards pages read")
        XCTAssertEqual(stats.averageRating, 4.0)
        XCTAssertEqual(stats.ratingCounts, [0, 0, 1, 1, 1])
    }

    func testFinishedPerYearOnlyUsesDatedBooks() {
        let books = [
            book("A", status: .read, finished: date(2024)),
            book("B", status: .read, finished: date(2026, 1)),
            book("C", status: .read, finished: date(2026, 8)),
            book("D", status: .read, finished: nil),
        ]
        let stats = LibraryStats(books: books, now: date(2026, 9), calendar: calendar)
        XCTAssertEqual(stats.finishedPerYear, [.init(year: 2024, count: 1), .init(year: 2026, count: 2)])
        XCTAssertEqual(stats.datedReadCount, 3)
        XCTAssertEqual(stats.readThisYear, 2)
    }

    func testTopAuthorsNeedTwoReadBooks() {
        let books = [
            book("A", author: "Austen", status: .read),
            book("B", author: "Austen", status: .read),
            book("C", author: "Herbert", status: .read),
            book("D", author: "Herbert", status: .unread),
        ]
        let stats = LibraryStats(books: books, calendar: calendar)
        XCTAssertEqual(stats.topAuthors, [.init(name: "Austen", count: 2)])
    }

    func testEmptyLibrary() {
        let stats = LibraryStats(books: [], calendar: calendar)
        XCTAssertEqual(stats.total, 0)
        XCTAssertNil(stats.averageRating)
        XCTAssertEqual(stats.finishedPerYear, [])
    }
}
