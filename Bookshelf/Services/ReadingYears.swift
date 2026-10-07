import Foundation
import Observation

/// The books you've finished, grouped by the year you finished them.
struct ReadingYears {
    struct Year: Identifiable {
        let year: Int
        /// Most recently finished first.
        let books: [Book]
        var id: Int { year }
    }

    /// Newest first. The current year is always there, even with nothing read yet,
    /// so there's somewhere to set this year's goal.
    let years: [Year]
    /// Read, but with no finish date to place them in a year.
    let undated: [Book]

    init(books: [Book], now: Date = .now, calendar: Calendar = .current) {
        let read = books.filter { $0.status == .read }
        undated = read.filter { $0.dateRead == nil }.sorted { $0.dateAdded > $1.dateAdded }

        var byYear: [Int: [Book]] = [calendar.component(.year, from: now): []]
        for book in read {
            guard let finished = book.dateRead else { continue }
            byYear[calendar.component(.year, from: finished), default: []].append(book)
        }
        years = byYear.keys.sorted(by: >).map { year in
            Year(year: year, books: byYear[year]!.sorted {
                ($0.dateRead ?? .distantPast, $0.dateAdded) > ($1.dateRead ?? .distantPast, $1.dateAdded)
            })
        }
    }
}

/// How many books you aim to read each year. Kept on this phone.
@MainActor
@Observable
final class ReadingGoals {
    static let shared = ReadingGoals()
    static let range = 1...200

    private static let key = "readingGoals"
    private let defaults: UserDefaults
    private var goals: [Int: Int]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
        goals = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in Int(key).map { ($0, value) } })
    }

    func goal(for year: Int) -> Int? { goals[year] }

    /// Sets the year's goal; nil removes it.
    func set(_ goal: Int?, for year: Int) {
        goals[year] = goal.map { min(max($0, Self.range.lowerBound), Self.range.upperBound) }
        defaults.set(Dictionary(uniqueKeysWithValues: goals.map { (String($0), $1) }), forKey: Self.key)
    }
}
