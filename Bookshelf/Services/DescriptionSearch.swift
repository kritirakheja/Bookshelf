import Foundation
import Observation

/// Looking a missing description up online at the reader's request, and how that's
/// going, for whichever screen shows the button.
@MainActor
@Observable
final class DescriptionSearch {
    private(set) var isSearching = false
    private(set) var notFound = false

    func run(for book: Book) {
        guard !isSearching else { return }
        isSearching = true
        Task {
            notFound = !(await BookLookup().fillMissingDescription(of: book))
            isSearching = false
        }
    }
}
