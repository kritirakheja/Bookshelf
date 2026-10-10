import Foundation

/// Every day you read, and how much: the data behind the Profile's reading calendar.
/// Built from the pages logged on each book's progress.
struct ReadingActivity {
    struct Day {
        var pages = 0
        /// Which books, and how many pages of each, most pages first.
        var books: [(title: String, pages: Int)] = []
    }

    /// A year laid out like a wall calendar turned on its side: one column per week,
    /// Monday at the top. Days outside the year (or still to come) are nil.
    struct Grid {
        var weeks: [[Date?]]
        /// Month names, by the index of the week column each one starts in.
        var monthStarts: [(week: Int, name: String)]
    }

    let calendar: Calendar
    /// Keyed by the start of each day with reading.
    private(set) var days: [Date: Day] = [:]

    init(books: [Book], calendar: Calendar = .current) {
        self.calendar = calendar
        for book in books {
            var before = 0
            for entry in book.sortedProgress {
                // Moving the page back is a correction, not reading.
                let pages = max(0, entry.page - before)
                before = entry.page
                guard pages > 0 else { continue }
                let day = calendar.startOfDay(for: entry.date)
                days[day, default: Day()].pages += pages
                days[day]?.books.append((book.title, pages))
            }
        }
        for day in days.keys {
            days[day]?.books.sort { ($0.pages, $1.title) > ($1.pages, $0.title) }
        }
    }

    func pages(on date: Date) -> Int { days[calendar.startOfDay(for: date)]?.pages ?? 0 }

    /// Years with any reading, newest first.
    var years: [Int] {
        Set(days.keys.map { calendar.component(.year, from: $0) }).sorted(by: >)
    }

    private func days(in year: Int) -> [(day: Date, pages: Int)] {
        days.filter { calendar.component(.year, from: $0.key) == year }
            .map { ($0.key, $0.value.pages) }
            .sorted { $0.day < $1.day }
    }

    func totalPages(in year: Int) -> Int { days(in: year).reduce(0) { $0 + $1.pages } }
    func daysRead(in year: Int) -> Int { days(in: year).count }

    /// How bright a day's square is: 0 for no reading, then 1...4. The steps come from
    /// your own reading that year (its quartiles), so the grid has contrast whether
    /// you read 20 pages a day or 200.
    func level(on date: Date) -> Int {
        let pages = pages(on: date)
        guard pages > 0 else { return 0 }
        let all = days(in: calendar.component(.year, from: date)).map(\.pages).sorted()
        func quantile(_ share: Double) -> Int { all[min(all.count - 1, Int(Double(all.count) * share))] }
        if pages >= quantile(0.75) { return 4 }
        if pages >= quantile(0.5) { return 3 }
        if pages >= quantile(0.25) { return 2 }
        return 1
    }

    /// Days in a row with reading, ending today (or yesterday, if today isn't logged yet).
    func currentStreak(asOf now: Date = .now) -> Int {
        var day = calendar.startOfDay(for: now)
        if days[day] == nil, let yesterday = calendar.date(byAdding: .day, value: -1, to: day) { day = yesterday }
        var streak = 0
        while days[day] != nil, let previous = calendar.date(byAdding: .day, value: -1, to: day) {
            streak += 1
            day = previous
        }
        return streak
    }

    /// The longest run of consecutive days with reading in a year.
    func longestStreak(in year: Int) -> Int {
        var longest = 0, run = 0
        var last: Date?
        for (day, _) in days(in: year) {
            if let last, calendar.date(byAdding: .day, value: 1, to: last) == day { run += 1 } else { run = 1 }
            longest = max(longest, run)
            last = day
        }
        return longest
    }

    /// The year's days in week columns, up to today for the current year.
    func grid(for year: Int, now: Date = .now) -> Grid {
        guard let first = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) else { return Grid(weeks: [], monthStarts: []) }
        let last = min(end, calendar.startOfDay(for: now))
        var weeks: [[Date?]] = []
        var months: [(week: Int, name: String)] = []
        var day = first
        while day <= last {
            // Monday = row 0 … Sunday = row 6.
            let row = (calendar.component(.weekday, from: day) + 5) % 7
            if weeks.isEmpty || row == 0 { weeks.append(Array(repeating: nil, count: 7)) }
            weeks[weeks.count - 1][row] = day
            if calendar.component(.day, from: day) == 1 {
                months.append((weeks.count - 1, calendar.shortMonthSymbols[calendar.component(.month, from: day) - 1]))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return Grid(weeks: weeks, monthStarts: months)
    }
}
