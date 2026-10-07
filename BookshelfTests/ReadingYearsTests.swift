import XCTest
@testable import Bookshelf

@MainActor
final class ReadingYearsTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int = 6, _ day: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func read(_ title: String, finished: Date?) -> Book {
        let book = Book(title: title)
        book.setStatus(.read)
        book.dateRead = finished
        return book
    }

    func testBooksAreGroupedByFinishYearNewestFirst() {
        let yearOnly = read("Year only", finished: nil)
        yearOnly.setFinishYear(2025, calendar: calendar)
        let unread = Book(title: "Unread")
        let reading = Book(title: "Reading")
        reading.setStatus(.reading)
        let books = [
            read("March", finished: date(2026, 3)), read("August", finished: date(2026, 8)),
            read("Old", finished: date(2023)), yearOnly, unread, reading, read("No date", finished: nil),
        ]
        let years = ReadingYears(books: books, now: date(2026, 10), calendar: calendar)

        XCTAssertEqual(years.years.map(\.year), [2026, 2025, 2023])
        XCTAssertEqual(years.years[0].books.map(\.title), ["August", "March"], "Most recently finished first")
        XCTAssertEqual(years.years[1].books.map(\.title), ["Year only"])
        XCTAssertEqual(years.undated.map(\.title), ["No date"])
    }

    func testTheCurrentYearIsThereEvenWithNothingRead() {
        let years = ReadingYears(books: [read("Old", finished: date(2024))], now: date(2026), calendar: calendar)
        XCTAssertEqual(years.years.map(\.year), [2026, 2024])
        XCTAssertTrue(years.years[0].books.isEmpty)
    }

    func testGoalsAreKeptPerYear() {
        let defaults = UserDefaults(suiteName: "ReadingGoalsTests")!
        defaults.removePersistentDomain(forName: "ReadingGoalsTests")
        let goals = ReadingGoals(defaults: defaults)
        XCTAssertNil(goals.goal(for: 2026))
        goals.set(24, for: 2026)
        goals.set(500, for: 2025)
        XCTAssertEqual(goals.goal(for: 2026), 24)
        XCTAssertEqual(goals.goal(for: 2025), 200, "Kept within a sensible range")

        XCTAssertEqual(ReadingGoals(defaults: defaults).goal(for: 2026), 24, "Still there after a restart")
        goals.set(nil, for: 2026)
        XCTAssertNil(ReadingGoals(defaults: defaults).goal(for: 2026))
    }
}
