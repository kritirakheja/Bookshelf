import XCTest
@testable import Bookshelf

final class ReadingStatusTests: XCTestCase {
    func testNewBookIsUnread() {
        let book = Book(title: "New")
        XCTAssertEqual(book.status, .unread)
        XCTAssertNil(book.dateStarted)
        XCTAssertNil(book.dateRead)
    }

    func testStartThenFinish() {
        let book = Book(title: "Book")
        book.setStatus(.reading)
        XCTAssertEqual(book.status, .reading)
        XCTAssertNotNil(book.dateStarted)
        XCTAssertNil(book.dateRead)

        let started = book.dateStarted
        book.setStatus(.read)
        XCTAssertEqual(book.status, .read)
        XCTAssertNotNil(book.dateRead)
        XCTAssertEqual(book.dateStarted, started, "Finishing keeps the start date")
    }

    func testBackToUnreadClearsDates() {
        let book = Book(title: "Book")
        book.setStatus(.reading)
        book.setStatus(.read)
        book.setStatus(.unread)
        XCTAssertEqual(book.status, .unread)
        XCTAssertNil(book.dateStarted)
        XCTAssertNil(book.dateRead)
    }

    func testRereadingClearsFinishDate() {
        let book = Book(title: "Book")
        book.setStatus(.read)
        book.setStatus(.reading)
        XCTAssertEqual(book.status, .reading)
        XCTAssertNil(book.dateRead)
        XCTAssertNotNil(book.dateStarted)
    }

    func testSettingSameStatusKeepsDates() {
        let book = Book(title: "Book")
        book.setStatus(.reading)
        let started = book.dateStarted
        book.setStatus(.reading)
        XCTAssertEqual(book.dateStarted, started)
    }

    /// Books saved before "Reading" existed only have `isRead`.
    func testOldReadFlagStillCounts() {
        let book = Book(title: "Old")
        book.isRead = true
        XCTAssertEqual(book.status, .read)
    }
}
