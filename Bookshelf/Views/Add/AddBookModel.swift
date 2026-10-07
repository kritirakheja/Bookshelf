import UIKit
import Observation

/// The lookups behind "Add a Book", so the screen only has to draw them.
protocol BookFinding {
    func lookup(isbn: String) async throws -> BookDraft
    func draft(for candidate: BookCandidate, isbn: String?) async -> BookDraft
    func identify(coverLines prominent: [String], queries: [String]?, isbn: String) async -> BookDraft?
}

extension BookLookup: BookFinding {}

/// What "Add a Book" is doing and what it found: a lookup in progress, a draft ready
/// for the form, a book that's already in the library, or a barcode nobody knows.
@MainActor
@Observable
final class AddBookModel {
    /// Once set, the sheet switches to the form for reviewing and saving.
    struct FormState {
        var draft: BookDraft
        var notice: String?
    }

    /// A book that's already in the library. `pending` is the form to continue to if
    /// it's only a title match (possibly a different edition); nil for the same ISBN.
    struct Duplicate {
        let book: Book
        let pending: FormState?
    }

    var form: FormState?
    var duplicate: Duplicate?
    /// A scanned ISBN no source knew; offers the cover scan instead.
    var unknownISBN: String?
    /// Carried into a cover scan so the saved book keeps the edition's ISBN.
    var coverISBN = ""
    /// What's being looked up right now, in words; nil when idle.
    private(set) var progress: String?

    private let finder: any BookFinding

    init(finder: any BookFinding = BookLookup()) {
        self.finder = finder
    }

    /// A 10- or 13-digit ISBN from what was typed or scanned, or nil.
    static func normalizedISBN(_ text: String) -> String? {
        var draft = BookDraft()
        draft.isbn = text
        guard let isbn = draft.normalizedISBN, isbn.count == 10 || isbn.count == 13 else { return nil }
        return isbn
    }

    /// Starts an empty form, optionally keeping an ISBN that couldn't be looked up.
    func enterManually(isbn: String? = nil) {
        var draft = BookDraft()
        if let isbn { draft.isbn = isbn }
        form = FormState(draft: draft)
    }

    /// Opens the form, unless the book turns out to be in the library already.
    func show(_ state: FormState, library: [Book]) {
        if let owned = LibraryDuplicates.book(withISBN: state.draft.normalizedISBN, in: library) {
            duplicate = Duplicate(book: owned, pending: nil)
        } else if let owned = LibraryDuplicates.book(title: state.draft.trimmedTitle, author: state.draft.authorList.first, in: library) {
            duplicate = Duplicate(book: owned, pending: state)
        } else {
            form = state
        }
    }

    // MARK: Lookups

    func lookUp(_ text: String, library: [Book]) async {
        guard let isbn = Self.normalizedISBN(text), progress == nil else { return }
        // Same barcode as a book already here: say so straight away, no lookup needed.
        if let owned = LibraryDuplicates.book(withISBN: isbn, in: library) {
            duplicate = Duplicate(book: owned, pending: nil)
            return
        }
        progress = "Looking up book…"
        defer { progress = nil }
        do {
            show(FormState(draft: try await finder.lookup(isbn: isbn)), library: library)
        } catch OpenLibraryClient.LookupError.notFound {
            unknownISBN = isbn
        } catch {
            var draft = BookDraft()
            draft.isbn = isbn
            form = FormState(draft: draft, notice: "Couldn't look this book up right now. You can fill in the details yourself.")
        }
    }

    /// A search result picked: fetch its cover, then review it in the form.
    func add(_ candidate: BookCandidate, library: [Book]) async {
        guard progress == nil else { return }
        progress = "Getting book details…"
        defer { progress = nil }
        show(FormState(draft: await finder.draft(for: candidate, isbn: nil)), library: library)
    }

    /// Reads the cover scan, then looks the book up from its title and author.
    func identify(_ photo: UIImage, library: [Book]) async {
        let isbn = coverISBN
        progress = "Reading the cover…"
        defer { progress = nil }
        let lines = (try? await CoverTextReader.read(photo)) ?? []
        let prominent = CoverTextReader.prominentLines(lines)

        progress = "Finding the book…"
        let queries = CoverTextReader.searchQueries(lines)
        if var draft = await finder.identify(coverLines: prominent, queries: queries, isbn: isbn) {
            if draft.coverImage == nil {
                draft.coverImage = photo.coverJPEG()
                draft.coverIsCustom = true
            }
            show(FormState(draft: draft, notice: "Recognised from the cover. Check the details before saving."), library: library)
            return
        }

        // Not found online: keep what the cover says, and the scan as the cover.
        var draft = BookDraft()
        let guess = CoverTextReader.guess(from: lines)
        draft.title = guess.title
        draft.authors = guess.author ?? ""
        draft.isbn = isbn
        draft.coverImage = photo.coverJPEG()
        draft.coverIsCustom = true
        let notice = prominent.isEmpty
            ? "Couldn't read the cover. Try again in better light, or fill in the details."
            : "Couldn't find this book online, so the details below were read from the cover. Please check them."
        show(FormState(draft: draft, notice: notice), library: library)
    }
}
