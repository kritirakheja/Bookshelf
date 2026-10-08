import Foundation
import SwiftData

/// How far into a book you were at the end of one day's reading.
@Model
final class ReadingEntry {
    var id: UUID = UUID()
    /// The day, at midnight. One entry per book per day.
    var date: Date
    /// The page you stopped on.
    var page: Int
    var book: Book?

    init(date: Date, page: Int) {
        self.date = date
        self.page = page
    }
}

extension Book {
    /// The log, oldest day first.
    var sortedProgress: [ReadingEntry] { progress.sorted { $0.date < $1.date } }

    /// The page you're on, from the latest day logged; nil if nothing is logged yet.
    var currentPage: Int? { sortedProgress.last?.page }

    /// How much of the book is read, 0...1. Nil when the book's length isn't known.
    var progressFraction: Double? {
        guard let pageCount, pageCount > 0 else { return nil }
        return min(1, max(0, Double(currentPage ?? 0) / Double(pageCount)))
    }

    /// The same as a whole percentage, for showing.
    var progressPercent: Int? { progressFraction.map { Int(($0 * 100).rounded(.down)) } }

    var pagesToGo: Int? {
        guard let pageCount, pageCount > 0 else { return nil }
        return max(0, pageCount - (currentPage ?? 0))
    }

    /// Records the page you're on. Logging again on the same day replaces that day's
    /// entry, so a correction doesn't count twice.
    func logProgress(page: Int, on date: Date = .now, calendar: Calendar = .current) {
        var page = max(0, page)
        if let pageCount, pageCount > 0 { page = min(page, pageCount) }
        let day = calendar.startOfDay(for: date)
        if let today = progress.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
            today.page = page
        } else {
            progress.append(ReadingEntry(date: day, page: page))
        }
    }

    /// Pages read on a day: that day's page minus where you were before it. Zero for a
    /// day with no entry, and never negative (moving the page back is a correction).
    func pagesRead(on date: Date, calendar: Calendar = .current) -> Int {
        let entries = sortedProgress
        guard let index = entries.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: date) }) else { return 0 }
        let before = index > 0 ? entries[index - 1].page : 0
        return max(0, entries[index].page - before)
    }

    /// Pages read on each of the last `days` days, oldest first, ending today.
    func dailyPages(last days: Int, until now: Date = .now, calendar: Calendar = .current) -> [(day: Date, pages: Int)] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: today).map { ($0, pagesRead(on: $0, calendar: calendar)) }
        }
    }

    /// Forgets the log (the book went back to Unread).
    func clearProgress() {
        for entry in progress { modelContext?.delete(entry) }
        progress = []
    }
}
