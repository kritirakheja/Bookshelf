import Foundation

/// Finds book details and covers using Open Library first, then Google Books for
/// whatever Open Library doesn't have. Google Books is skipped when there's no key.
struct BookLookup {
    var openLibrary = OpenLibraryClient()
    var google: GoogleBooksClient? = .fromBundle()

    // MARK: ISBN

    func lookup(isbn: String) async throws -> BookDraft {
        do {
            var draft = try await openLibrary.lookup(isbn: isbn)
            // Open Library knew the book but had no cover: Google Books may have one.
            if draft.coverImage == nil, let candidate = try? await google?.lookup(isbn: isbn) {
                draft.coverImage = await cover(for: candidate)
            }
            return draft
        } catch OpenLibraryClient.LookupError.notFound {
            guard let google else { throw OpenLibraryClient.LookupError.notFound }
            guard let candidate = try await google.lookup(isbn: isbn) else {
                throw OpenLibraryClient.LookupError.notFound
            }
            return await draft(for: candidate, isbn: isbn)
        }
    }

    // MARK: Search

    /// Results from both sources, alternating so neither buries the other, with the
    /// same book (same title and author) listed once.
    func search(_ text: String) async throws -> [BookCandidate] {
        async let fromOpenLibrary = try? openLibrary.search(text)
        async let fromGoogle = try? google?.search(text)
        let (ol, gb) = await (fromOpenLibrary, fromGoogle)
        if ol == nil && gb == nil && text.trimmingCharacters(in: .whitespaces).count >= 2 {
            throw OpenLibraryClient.LookupError.badResponse(0)
        }
        let openLibraryResults = (ol ?? []).enumerated().map { BookCandidate(openLibrary: $1, index: $0) }
        return Self.merge(openLibraryResults, gb ?? [])
    }

    static func merge(_ first: [BookCandidate], _ second: [BookCandidate]) -> [BookCandidate] {
        var seen = Set<String>()
        var merged: [BookCandidate] = []
        for index in 0..<max(first.count, second.count) {
            for list in [first, second] where index < list.count {
                let candidate = list[index]
                if seen.insert(BookMatcher.key(title: candidate.title, author: candidate.authors.first)).inserted {
                    merged.append(candidate)
                }
            }
        }
        return merged
    }

    /// A picked result as a draft, with its cover downloaded.
    func draft(for candidate: BookCandidate, isbn: String? = nil) async -> BookDraft {
        var draft = candidate.draft(isbn: isbn)
        draft.coverImage = await cover(for: candidate)
        return draft
    }

    // MARK: Cover text

    /// The book whose title and author best match the text read off its cover, from
    /// either source. A result matching the author as well as the title wins.
    /// - Parameter queries: searches to try, most specific first (see
    ///   `CoverTextReader.searchQueries`); defaults to ones built from `prominent`.
    func identify(coverLines prominent: [String], queries: [String]? = nil, isbn: String) async -> BookDraft? {
        guard !prominent.isEmpty else { return nil }
        let queries = queries ?? [prominent.joined(separator: " ")]
        async let olDocs = try? openLibrary.coverCandidates(for: prominent, queries: queries)
        async let gbCandidates = googleCandidates(for: queries)
        let candidates = ((await olDocs) ?? []).enumerated().map { BookCandidate(openLibrary: $1, index: $0) }
            + (await gbCandidates)
        guard let match = BookMatcher.rankedMatch(in: candidates, coverText: prominent) else { return nil }
        return await draft(for: match.item, isbn: isbn)
    }

    private func googleCandidates(for queries: [String]) async -> [BookCandidate] {
        guard let google, !queries.isEmpty else { return [] }
        async let first = try? google.search(queries[0], limit: 10)
        async let second = queries.count > 1 ? try? google.search(queries[1], limit: 10) : nil
        return ((await first) ?? []) + ((await second) ?? [])
    }

    // MARK: Covers

    /// A cover for a book that has none: Open Library (by ISBN, then title and
    /// author), then Google Books.
    func findCover(title: String, author: String?, isbn: String?) async -> Data? {
        if let data = await openLibrary.findCover(title: title, author: author, isbn: isbn) {
            return data
        }
        guard let google else { return nil }
        if let isbn, let candidate = try? await google.lookup(isbn: isbn), let data = await cover(for: candidate) {
            return data
        }
        let query = [title, author].compactMap { $0 }.joined(separator: " ")
        guard let results = try? await google.search(query, limit: 5),
              let match = BookMatcher.rankedMatch(in: results, coverText: [title, author ?? ""]) else { return nil }
        return await cover(for: match.item)
    }

    /// Fills in the cover of a saved book if it has none. Returns whether it has one now.
    @MainActor
    @discardableResult
    func fillMissingCover(of book: Book) async -> Bool {
        guard book.coverImage == nil else { return true }
        let data = await findCover(title: book.title, author: book.authors.first, isbn: book.isbn)
        if let data, book.coverImage == nil {
            book.coverImage = data
        }
        return book.coverImage != nil
    }

    private func cover(for candidate: BookCandidate) async -> Data? {
        await openLibrary.downloadCover(from: [candidate.coverURL, candidate.thumbnailURL])
    }
}
