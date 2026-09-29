import Foundation

/// Editable, unsaved copy of a book's details. The add/edit form works on a
/// draft so that "Cancel" never leaves a half-edited `Book` in the database.
/// Numbers are kept as text because that's what the text fields bind to.
struct BookDraft {
    var title = ""
    var authors = ""
    var isbn = ""
    var publishedYear = ""
    var pageCount = ""
    var coverImage: Data?
    var summary = ""
    /// Categories to attach when a new book is saved (edit them on the book's page afterwards).
    var categoryNames: [String] = []

    init() {}

    init(book: Book) {
        title = book.title
        authors = book.authors.joined(separator: ", ")
        isbn = book.isbn ?? ""
        publishedYear = book.publishedYear.map(String.init) ?? ""
        pageCount = book.pageCount.map(String.init) ?? ""
        coverImage = book.coverImage
        summary = book.summary ?? ""
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var authorList: [String] {
        authors.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// ISBN with hyphens and spaces removed, or nil if empty.
    var normalizedISBN: String? {
        let digits = isbn.filter { $0.isNumber || $0 == "X" || $0 == "x" }.uppercased()
        return digits.isEmpty ? nil : digits
    }

    var isValid: Bool { !trimmedTitle.isEmpty }

    func apply(to book: Book) {
        book.title = trimmedTitle
        book.authors = authorList
        book.isbn = normalizedISBN
        book.publishedYear = Int(publishedYear)
        book.pageCount = Int(pageCount)
        book.coverImage = coverImage
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        book.summary = trimmedSummary.isEmpty ? nil : trimmedSummary
    }

    func makeBook() -> Book {
        let book = Book(title: trimmedTitle)
        apply(to: book)
        return book
    }
}
