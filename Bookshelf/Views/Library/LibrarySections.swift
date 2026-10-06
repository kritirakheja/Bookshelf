import Foundation

/// Splits the library into Fiction and Non-fiction.
enum LibrarySections {
    struct Section: Identifiable {
        let title: String
        let books: [Book]
        var id: String { title }
    }

    /// Categories that make a book fiction. "Classics" isn't here: it covers
    /// Dostoevsky and Nietzsche alike, so it's decided by the book's other categories.
    static let fictionCategories: Set<String> = [
        "Literary Fiction", "Romance", "Fantasy", "Science Fiction", "Thriller & Mystery",
        "Historical Fiction", "Young Adult", "Short Stories", "Mythology",
    ]

    static let classics = "Classics"
    /// Not a subject, so it doesn't decide which side a book is on.
    static let ignored: Set<String> = ["Did Not Finish"]

    enum Side {
        case fiction, nonFiction, unsorted
    }

    static func side(of book: Book) -> Side {
        let names = Set(book.categories.map(\.name)).subtracting(ignored)
        if names.isEmpty { return .unsorted }
        if !names.isDisjoint(with: fictionCategories) { return .fiction }
        let others = names.subtracting([classics])
        // A classic with nothing else to go on (a novel, a play) is fiction.
        return others.isEmpty ? .fiction : .nonFiction
    }

    /// Fiction, then Non-fiction, then anything not categorised yet; empty ones left out.
    /// Books keep the order they're given in (the chosen sort).
    static func split(_ books: [Book]) -> [Section] {
        let sides = books.map { ($0, side(of: $0)) }
        return [
            Section(title: "Fiction", books: sides.filter { $0.1 == .fiction }.map(\.0)),
            Section(title: "Non-fiction", books: sides.filter { $0.1 == .nonFiction }.map(\.0)),
            Section(title: "Not sorted yet", books: sides.filter { $0.1 == .unsorted }.map(\.0)),
        ].filter { !$0.books.isEmpty }
    }
}
