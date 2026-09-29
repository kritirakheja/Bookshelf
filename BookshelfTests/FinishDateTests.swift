import XCTest
import SwiftData
@testable import Bookshelf

@MainActor
final class FinishDateTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let calendar = Calendar.current

    override func setUp() async throws {
        container = try ModelContainer(
            for: Book.self, BookCategory.self, DeletedBook.self, Loan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func readBook(_ title: String, added: Date, finished: Date? = nil) -> Book {
        let book = Book(title: title)
        context.insert(book)
        book.isRead = true
        book.dateRead = finished
        book.dateAdded = added
        return book
    }

    func testYearEndImportsGetTheirYear() {
        let yearEnd = readBook("Year-end", added: date(2025, 12, 31))
        let joined = readBook("Joined", added: date(2024, 3, 6))
        let dated = readBook("Dated", added: date(2025, 12, 31), finished: date(2025, 5, 2))
        let unread = Book(title: "Unread")
        context.insert(unread)
        unread.dateAdded = date(2025, 12, 31)

        XCTAssertEqual(LibraryFixes.markYearEndImportsAsFinishedThatYear(in: context), 1)

        XCTAssertTrue(yearEnd.dateReadYearOnly)
        XCTAssertEqual(yearEnd.finishDateText, "2025")
        XCTAssertNil(joined.dateRead, "Other days aren't guessed")
        XCTAssertEqual(dated.dateRead, date(2025, 5, 2), "Real dates are never touched")
        XCTAssertFalse(dated.dateReadYearOnly)
        XCTAssertNil(unread.dateRead)
    }

    func testFixRunsOnlyOnce() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FinishDateTests-\(UUID())"))
        let book = readBook("Year-end", added: date(2025, 12, 31))
        LibraryFixes.runPending(in: context, defaults: defaults)
        XCTAssertTrue(book.dateReadYearOnly)

        // Cleared by hand afterwards: the fix mustn't bring it back.
        book.dateRead = nil
        book.dateReadYearOnly = false
        LibraryFixes.runPending(in: context, defaults: defaults)
        XCTAssertNil(book.dateRead)
    }

    func testYearOnlyCountsInThatYearAndSortsAfterExactDates() {
        let exact = readBook("Exact", added: .now, finished: date(2025, 3, 10))
        let yearOnly = readBook("Year only", added: .now)
        yearOnly.setFinishYear(2025)

        let stats = LibraryStats(books: [exact, yearOnly], now: date(2026, 9, 1))
        XCTAssertEqual(stats.finishedPerYear, [.init(year: 2025, count: 2)])
        XCTAssertLessThan(yearOnly.dateRead!, exact.dateRead!, "1 Jan sorts after dated books in the Read list")
    }

    func testMarkingReadAgainGivesAnExactDate() {
        let book = readBook("Book", added: .now)
        book.setFinishYear(2025)
        book.setStatus(.reading)
        book.setStatus(.read)
        XCTAssertFalse(book.dateReadYearOnly)
        XCTAssertEqual(calendar.component(.year, from: book.dateRead!), calendar.component(.year, from: .now))
    }
}
