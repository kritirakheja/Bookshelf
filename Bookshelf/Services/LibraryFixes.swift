import Foundation
import SwiftData

/// Fills in descriptions for books that have none, one at a time in the background.
/// Books with nothing online are tried again after a month, not on every launch.
enum DescriptionBackfill {
    static let retryAfter: TimeInterval = 30 * 86_400

    @MainActor
    static func run(in context: ModelContext, lookup: BookLookup = BookLookup()) async {
        // Not while tests run the app: it would spend the day's free lookups each time.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let waiting = books.filter { book in
            book.summary == nil && (book.summaryLookupDate.map { Date.now.timeIntervalSince($0) > retryAfter } ?? true)
        }
        for (index, book) in waiting.enumerated() {
            guard !Task.isCancelled else { break }
            await lookup.fillMissingDescription(of: book)
            if index % 10 == 9 { try? context.save() }
        }
        try? context.save()
    }
}

/// One-off corrections to existing libraries. Each runs once per device.
enum LibraryFixes {
    @MainActor
    static func runPending(in context: ModelContext, defaults: UserDefaults = .standard) {
        let key = "fix.goodreadsYearEndFinishYears"
        guard !defaults.bool(forKey: key) else { return }
        markYearEndImportsAsFinishedThatYear(in: context)
        try? context.save()
        defaults.set(true, forKey: key)
    }

    /// Goodreads had no finish date for many imported books. Those added on 31 December
    /// were the year's reading, logged in one go, so they get "finished in <that year>".
    /// Only touches read books that have no finish date at all.
    @MainActor
    @discardableResult
    static func markYearEndImportsAsFinishedThatYear(in context: ModelContext, calendar: Calendar = .current) -> Int {
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        var changed = 0
        for book in books where book.status == .read && book.dateRead == nil {
            let added = calendar.dateComponents([.year, .month, .day], from: book.dateAdded)
            guard added.month == 12, added.day == 31, added.year == 2025, let year = added.year else { continue }
            book.setFinishYear(year, calendar: calendar)
            changed += 1
        }
        return changed
    }
}
