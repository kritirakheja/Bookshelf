import XCTest
import SwiftData
@testable import Bookshelf

@MainActor
final class ReadingActivityTests: XCTestCase {
    private var container: ModelContainer!
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()

    override func setUp() async throws {
        container = try ModelContainer(
            for: Book.self, BookCategory.self, DeletedBook.self, Loan.self, ReadingEntry.self, Bookstore.self, DeletedBookstore.self, BookstorePhoto.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func book(_ title: String, pages: Int? = 500, log: [(Date, Int)] = []) -> Book {
        let book = Book(title: title, pageCount: pages)
        container.mainContext.insert(book)
        book.setStatus(.reading)
        for (day, page) in log { book.logProgress(page: page, on: day, calendar: calendar) }
        return book
    }

    func testPagesAreSummedAcrossBooksPerDay() {
        let a = book("Sapiens", log: [(date(2026, 10, 8), 40), (date(2026, 10, 9), 100)])
        let b = book("Circe", log: [(date(2026, 10, 9), 25)])
        let activity = ReadingActivity(books: [a, b], calendar: calendar)

        XCTAssertEqual(activity.pages(on: date(2026, 10, 8)), 40)
        XCTAssertEqual(activity.pages(on: date(2026, 10, 9)), 85)
        XCTAssertEqual(activity.days[date(2026, 10, 9)]?.books.map(\.title), ["Sapiens", "Circe"], "Most pages first")
        XCTAssertEqual(activity.pages(on: date(2026, 10, 10)), 0)
    }

    func testACorrectionDownwardsAddsNothing() {
        let a = book("Sapiens", log: [(date(2026, 10, 8), 100), (date(2026, 10, 9), 90), (date(2026, 10, 10), 120)])
        let activity = ReadingActivity(books: [a], calendar: calendar)
        XCTAssertEqual(activity.pages(on: date(2026, 10, 9)), 0)
        XCTAssertEqual(activity.pages(on: date(2026, 10, 10)), 30)
        XCTAssertEqual(activity.daysRead(in: 2026), 2)
    }

    func testYearsTotalsAndStreaks() {
        let a = book("Sapiens", log: [
            (date(2025, 12, 30), 10), (date(2025, 12, 31), 30),
            (date(2026, 1, 1), 60), (date(2026, 3, 4), 80), (date(2026, 3, 5), 90), (date(2026, 3, 6), 100), (date(2026, 3, 8), 130),
        ])
        let activity = ReadingActivity(books: [a], calendar: calendar)
        XCTAssertEqual(activity.years, [2026, 2025])
        XCTAssertEqual(activity.totalPages(in: 2025), 30)
        XCTAssertEqual(activity.totalPages(in: 2026), 100)
        XCTAssertEqual(activity.daysRead(in: 2026), 5)
        XCTAssertEqual(activity.longestStreak(in: 2026), 3)
        XCTAssertEqual(activity.longestStreak(in: 2025), 2)

        XCTAssertEqual(activity.currentStreak(asOf: date(2026, 3, 6)), 3, "Read today")
        XCTAssertEqual(activity.currentStreak(asOf: date(2026, 3, 7)), 3, "Nothing yet today: yesterday's run still stands")
        XCTAssertEqual(activity.currentStreak(asOf: date(2026, 3, 10)), 0, "Broken two days ago")
        XCTAssertEqual(activity.currentStreak(asOf: date(2026, 1, 1)), 3, "Runs across the new year")
    }

    func testLevelsComeFromYourOwnReading() {
        let one = ReadingActivity(books: [book("One", log: [(date(2026, 5, 1), 12)])], calendar: calendar)
        XCTAssertEqual(one.level(on: date(2026, 5, 1)), 4, "Your only day is your best day")
        XCTAssertEqual(one.level(on: date(2026, 5, 2)), 0)

        let spread = book("Spread", log: [(date(2026, 5, 1), 10), (date(2026, 5, 2), 30), (date(2026, 5, 3), 60), (date(2026, 5, 4), 100)])
        let activity = ReadingActivity(books: [spread], calendar: calendar)   // 10, 20, 30, 40 pages
        XCTAssertEqual((1...4).map { activity.level(on: date(2026, 5, $0)) }, [1, 2, 3, 4])
    }

    func testTheGridIsMondayFirstAndStopsToday() {
        let activity = ReadingActivity(books: [], calendar: calendar)
        // 1 Jan 2026 is a Thursday; 9 Oct 2026 is a Friday.
        let grid = activity.grid(for: 2026, now: date(2026, 10, 9))
        XCTAssertEqual(grid.weeks.first, [nil, nil, nil, date(2026, 1, 1), date(2026, 1, 2), date(2026, 1, 3), date(2026, 1, 4)])
        XCTAssertEqual(grid.weeks.last, [date(2026, 10, 5), date(2026, 10, 6), date(2026, 10, 7), date(2026, 10, 8), date(2026, 10, 9), nil, nil])
        XCTAssertEqual(grid.monthStarts.first?.week, 0)
        XCTAssertEqual(grid.monthStarts.map(\.name).prefix(3), ["Jan", "Feb", "Mar"])
        XCTAssertEqual(grid.monthStarts.count, 10)

        let past = activity.grid(for: 2025, now: date(2026, 10, 9))
        XCTAssertEqual(past.weeks.flatMap { $0 }.compactMap { $0 }.count, 365, "A finished year is shown whole")
    }

    func testFinishingABookCountsItsLastPagesToday() {
        let reading = book("Sapiens", pages: 300, log: [(Calendar.current.date(byAdding: .day, value: -1, to: .now)!, 250)])
        reading.setStatus(.read)
        XCTAssertEqual(ReadingActivity(books: [reading]).pages(on: .now), 50)

        // Marked read without having been in progress (an old book): no square.
        let old = Book(title: "Old", pageCount: 200)
        container.mainContext.insert(old)
        old.setStatus(.read)
        XCTAssertTrue(old.progress.isEmpty)

        // No page count: nothing to log, and nothing breaks.
        let unknown = book("Unknown", pages: nil)
        unknown.setStatus(.read)
        XCTAssertTrue(unknown.progress.isEmpty)
    }
}
