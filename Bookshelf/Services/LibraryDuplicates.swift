import Foundation

/// Spotting a book that's already in the library, before adding it again.
enum LibraryDuplicates {
    /// A book with this ISBN, other than `excluded` (the one being edited).
    static func book(withISBN isbn: String?, in library: [Book], excluding excluded: Book? = nil) -> Book? {
        guard let isbn, !isbn.isEmpty else { return nil }
        return library.first { $0.isbn == isbn && $0 !== excluded }
    }

    /// A book with the same title and first author, ignoring case, accents and punctuation.
    static func book(title: String, author: String?, in library: [Book]) -> Book? {
        guard !title.isEmpty else { return nil }
        let key = BookMatcher.key(title: title, author: author)
        return library.first { BookMatcher.key(title: $0.title, author: $0.authors.first) == key }
    }
}
