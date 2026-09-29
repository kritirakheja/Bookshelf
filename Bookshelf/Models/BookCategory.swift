import Foundation
import SwiftData

/// Named `BookCategory` rather than `Category` to avoid clashing with the
/// Objective-C runtime's `Category` type, which Swift imports implicitly.
@Model
final class BookCategory {
    @Attribute(.unique) var name: String
    var books: [Book] = []

    init(name: String) {
        self.name = name
    }

    /// Returns the existing category with this name (ignoring case), or creates it.
    /// `@Attribute(.unique)` alone would silently merge an exact duplicate, but
    /// wouldn't stop "fantasy" and "Fantasy" becoming two separate categories.
    static func named(_ rawName: String, in context: ModelContext) -> BookCategory? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let all = (try? context.fetch(FetchDescriptor<BookCategory>())) ?? []
        if let existing = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let category = BookCategory(name: name)
        context.insert(category)
        return category
    }
}
