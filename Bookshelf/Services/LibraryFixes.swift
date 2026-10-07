import Foundation
import SwiftData

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

    /// Two books ended up with the wrong cover before covers were matched by title,
    /// author and language: a Spanish edition, and a "summary and workbook". Each
    /// gets its proper English cover (the old one is kept, as with any swap).
    /// Retried on later launches until both are done or gone.
    static let wrongCovers = [("Mile High", "Liz Tomforde"), ("$100M Offers", "Alex Hormozi")]

    @MainActor
    static func replaceWrongCovers(in context: ModelContext, lookup: BookLookup = BookLookup(), defaults: UserDefaults = .standard) async {
        let key = "fix.wrongCovers.2026-10-07"
        guard !defaults.bool(forKey: key) else { return }
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        var allDone = true
        for (title, author) in wrongCovers {
            guard let book = books.first(where: { $0.title == title && $0.authors.first == author }),
                  !book.coverIsCustom else { continue }
            if let cover = await lookup.editionCover(title: title, author: author) {
                book.previousCoverImage = book.coverImage
                book.coverImage = cover
            } else {
                allDone = false
            }
        }
        try? context.save()
        if allDone { defaults.set(true, forKey: key) }
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
