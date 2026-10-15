import UIKit
import SwiftData
import Observation

/// Finds a sharper cover for a book. `BookLookup` does it online; tests use a fake.
protocol SharperCoverFinding {
    func sharperCover(than current: Data, title: String, author: String?, isbn: String?) async -> Data?
}

extension BookLookup: SharperCoverFinding {}

/// Replaces small, blurry covers with sharp ones, one book at a time: the same
/// artwork when a sharp copy exists, otherwise another edition of the same book.
/// The cover it replaces is kept on the book, and covers you set yourself are left
/// alone. Each book is tried once, then again about once a month (new editions and
/// sharper scans turn up online over time).
@MainActor
@Observable
final class CoverUpgrade {
    static let shared = CoverUpgrade()

    /// Covers at least this wide are already sharp enough.
    nonisolated static let sharpEnough = 700
    nonisolated static let checkedKey = "coverUpgrade.checked.v3"   // v3: other editions allowed
    /// When books that found nothing were last tried again.
    nonisolated static let lastRetryKey = "coverUpgrade.lastRetry"
    nonisolated static let retryEvery: TimeInterval = 30 * 86_400

    private(set) var isRunning = false
    /// Progress through this run's books.
    private(set) var done = 0
    private(set) var total = 0

    /// Whether this cover is one the pass would try to improve.
    static func isBlurry(_ book: Book) -> Bool {
        guard !book.coverIsCustom, let cover = book.coverImage, let width = CoverImage.pixelWidth(of: cover) else { return false }
        return width < sharpEnough
    }

    /// Runs at every launch: tries books not tried yet, and once a month all the
    /// blurry ones again.
    func run(in context: ModelContext, finder: any SharperCoverFinding = BookLookup(),
             defaults: UserDefaults = .standard, now: Date = .now) async {
        guard !isRunning else { return }
        var checked = Set(defaults.stringArray(forKey: Self.checkedKey) ?? [])
        if let last = defaults.object(forKey: Self.lastRetryKey) as? Date {
            if now.timeIntervalSince(last) >= Self.retryEvery {
                checked = []
                defaults.set(Array(checked), forKey: Self.checkedKey)
                defaults.set(now, forKey: Self.lastRetryKey)
            }
        } else {
            // The month starts now; this run already tries everything not yet tried.
            defaults.set(now, forKey: Self.lastRetryKey)
        }
        let books = ((try? context.fetch(FetchDescriptor<Book>())) ?? [])
            .filter { Self.isBlurry($0) && !checked.contains(Self.key(for: $0)) }
        guard !books.isEmpty else { return }

        isRunning = true
        done = 0
        total = books.count
        // Keep going for a little while if the app is left mid-run.
        var background = UIBackgroundTaskIdentifier.invalid
        background = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(background) }
        defer {
            isRunning = false
            UIApplication.shared.endBackgroundTask(background)
        }

        for book in books {
            guard !Task.isCancelled else { break }
            guard let current = book.coverImage else { continue }
            let sharper = await finder.sharperCover(than: current, title: book.title, author: book.authors.first, isbn: book.isbn)
            // Only if the cover hasn't been changed by hand in the meantime.
            if let sharper, book.coverImage == current, !book.coverIsCustom {
                book.previousCoverImage = current
                book.coverImage = sharper
                try? context.save()
            }
            checked.insert(Self.key(for: book))
            defaults.set(Array(checked), forKey: Self.checkedKey)
            done += 1
        }
    }

    nonisolated static func key(for book: Book) -> String {
        "\(book.title.lowercased())|\(book.authors.first?.lowercased() ?? "")|\(book.isbn ?? "")"
    }
}
