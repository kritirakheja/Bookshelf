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
