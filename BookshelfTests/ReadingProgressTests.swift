import XCTest
import SwiftData
@testable import Bookshelf

@MainActor
final class ReadingProgressTests: XCTestCase {
    private var container: ModelContainer!
    private let calendar = Calendar.current

    override func setUp() async throws {
        container = try ModelContainer(
            for: Book.self, BookCategory.self, DeletedBook.self, Loan.self, ReadingEntry.self, Bookstore.self, DeletedBookstore.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func book(pages: Int? = 300) -> Book {
        let book = Book(title: "Circe", pageCount: pages)
        container.mainContext.insert(book)
        book.setStatus(.reading)
        return book
    }

    private func day(_ back: Int) -> Date {
        calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: .now))!
    }

    func testPercentageAndPagesToGo() {
        let book = book()
        XCTAssertEqual(book.progressPercent, 0)
        book.logProgress(page: 110)
        XCTAssertEqual(book.currentPage, 110)
        XCTAssertEqual(book.progressPercent, 36)
        XCTAssertEqual(book.pagesToGo, 190)
        XCTAssertEqual(book.progressSummary, "36% · page 110 of 300")
    }

    func testPagesPerDayComeFromTheDifference() {
        let book = book()
        book.logProgress(page: 50, on: day(2))
        book.logProgress(page: 110, on: day(0))
        XCTAssertEqual(book.pagesRead(on: day(2)), 50)
        XCTAssertEqual(book.pagesRead(on: day(1)), 0, "Nothing logged that day")
        XCTAssertEqual(book.pagesRead(on: day(0)), 60)
        XCTAssertEqual(book.dailyPages(last: 4).map(\.pages), [0, 50, 0, 60])
    }

    func testLoggingAgainTheSameDayReplacesTheEntry() {
        let book = book()
        book.logProgress(page: 50, on: day(1))
        book.logProgress(page: 80)
        book.logProgress(page: 95)
        XCTAssertEqual(book.progress.count, 2)
        XCTAssertEqual(book.pagesRead(on: .now), 45)
    }

    func testMovingThePageBackIsACorrectionNotNegativeReading() {
        let book = book()
        book.logProgress(page: 100, on: day(1))
        book.logProgress(page: 90)
        XCTAssertEqual(book.pagesRead(on: .now), 0)
        XCTAssertEqual(book.currentPage, 90)
    }

    func testThePageStaysWithinTheBook() {
        let book = book()
        book.logProgress(page: 999)
        XCTAssertEqual(book.currentPage, 300)
        XCTAssertEqual(book.progressPercent, 100)
    }

    func testNoPageCountMeansNoPercentage() {
        let book = book(pages: nil)
        book.logProgress(page: 40)
        XCTAssertNil(book.progressPercent)
        XCTAssertEqual(book.progressSummary, "Page 40")
    }

    func testUnreadClearsTheLogAndReadKeepsIt() {
        let finished = book()
        finished.logProgress(page: 300)
        finished.setStatus(.read)
        XCTAssertEqual(finished.progress.count, 1)

        let abandoned = book()
        abandoned.logProgress(page: 20)
        abandoned.setStatus(.unread)
        XCTAssertTrue(abandoned.progress.isEmpty)
    }

    func testProgressIsPartOfWhatSyncs() throws {
        let book = book()
        let before = SyncHash.fingerprint(of: book)
        book.logProgress(page: 10)
        XCTAssertNotEqual(SyncHash.fingerprint(of: book), before, "Logging progress marks the book as changed")
        XCTAssertEqual(BookRecord(book: book, id: UUID()).progress?.map(\.page), [10])

        // A row saved before progress existed still decodes.
        let old = #"{"id":"00000000-0000-0000-0000-000000000001","title":"Old","authors":[],"is_read":false,"is_reading":true,"date_added":0,"notes":"","categories":[],"deleted":false}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        XCTAssertNil(try decoder.decode(BookRecord.self, from: Data(old.utf8)).progress)
    }
}
