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

/// Fills in page counts for books that have none, so reading progress can show a
/// percentage. Each book is looked up once per device; the ones nothing is found
/// for are asked about when you first log progress.
enum PageCountBackfill {
    static let checkedKey = "pageCountBackfill.checked.v1"

    @MainActor
    static func run(in context: ModelContext, lookup: BookLookup = BookLookup(), defaults: UserDefaults = .standard) async {
        var checked = Set(defaults.stringArray(forKey: checkedKey) ?? [])
        let books = ((try? context.fetch(FetchDescriptor<Book>())) ?? [])
            .filter { ($0.pageCount ?? 0) <= 0 && !checked.contains(CoverUpgrade.key(for: $0)) }
            // Books being read first: those are the ones waiting for a percentage.
            .sorted { $0.isReading && !$1.isReading }
        for book in books {
            guard !Task.isCancelled else { break }
            await lookup.fillMissingPageCount(of: book)
            checked.insert(CoverUpgrade.key(for: book))
            defaults.set(Array(checked), forKey: checkedKey)
        }
        try? context.save()
    }
}
