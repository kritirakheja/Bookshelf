import Foundation

/// Rules for the ranked favourites shelf. Ranks are always 1...N with no gaps,
/// so every change renumbers the whole shelf.
enum FavoritesShelf {
    static let capacity = 10

    enum AddResult: Equatable {
        case added
        case alreadyOnShelf
        case shelfFull
    }

    /// Books on the shelf, best first. `books` can be the whole library.
    static func ordered(_ books: [Book]) -> [Book] {
        books
            .filter(\.isFavorite)
            .sorted { ($0.favoriteRank ?? .max) < ($1.favoriteRank ?? .max) }
    }

    /// Puts the book at the end of the shelf, unless the shelf is full.
    @discardableResult
    static func add(_ book: Book, library: [Book]) -> AddResult {
        if book.isFavorite { return .alreadyOnShelf }
        let shelf = ordered(library)
        guard shelf.count < capacity else { return .shelfFull }
        renumber(shelf + [book])
        return .added
    }

    /// Takes the book off the shelf and closes the gap it leaves.
    static func remove(_ book: Book, library: [Book]) {
        let remaining = ordered(library).filter { $0 !== book }
        book.favoriteRank = nil
        renumber(remaining)
    }

    /// Reorders the shelf using List-style offsets (as given by `.onMove`).
    static func move(library: [Book], fromOffsets source: IndexSet, toOffset destination: Int) {
        var shelf = ordered(library)
        let moving = source.map { shelf[$0] }
        let insertAt = destination - source.filter { $0 < destination }.count
        shelf.remove(atOffsets: source)
        shelf.insert(contentsOf: moving, at: insertAt)
        renumber(shelf)
    }

    /// Repairs ranks after merging changes from another device: closes gaps, settles
    /// ties, and drops anything beyond capacity. Leaves an already-tidy shelf untouched.
    static func normalize(_ library: [Book]) {
        let shelf = ordered(library)
        let kept = Array(shelf.prefix(capacity))
        shelf.dropFirst(capacity).forEach { $0.favoriteRank = nil }
        if kept.map(\.favoriteRank) != kept.indices.map({ $0 + 1 }) {
            renumber(kept)
        }
    }

    private static func renumber(_ shelf: [Book]) {
        for (index, book) in shelf.enumerated() {
            book.favoriteRank = index + 1
        }
    }
}

private extension Array {
    mutating func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            remove(at: index)
        }
    }
}
