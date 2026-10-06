import Foundation
import SwiftData

/// Replaces small, blurry covers with sharper copies of the same artwork, one book at
/// a time in the background. Each book is looked up once per device; covers that
/// can't be matched (your own photos, other editions) are left alone.
enum CoverUpgrade {
    /// Covers at least this wide are already sharp enough.
    static let sharpEnough = 700
    static let checkedKey = "coverUpgrade.checked.v2"   // v2: Apple Books added as a source

    @MainActor
    static func run(in context: ModelContext, lookup: BookLookup = BookLookup(), defaults: UserDefaults = .standard) async {
        // Not while tests run the app: it would spend the day's free lookups each time.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        var checked = Set(defaults.stringArray(forKey: checkedKey) ?? [])
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        for book in books {
            guard !Task.isCancelled else { break }
            let key = Self.key(for: book)
            guard !checked.contains(key), let current = book.coverImage,
                  let width = CoverImage.pixelWidth(of: current), width < sharpEnough else { continue }
            let sharper = await lookup.sharperCover(than: current, title: book.title, author: book.authors.first, isbn: book.isbn)
            // Only if the cover hasn't been changed by hand in the meantime.
            if let sharper, book.coverImage == current {
                book.coverImage = sharper
                try? context.save()
            }
            checked.insert(key)
            defaults.set(Array(checked), forKey: checkedKey)
        }
    }

    static func key(for book: Book) -> String {
        "\(book.title.lowercased())|\(book.authors.first?.lowercased() ?? "")|\(book.isbn ?? "")"
    }
}
