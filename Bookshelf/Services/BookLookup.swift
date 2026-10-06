import Foundation

/// Finds book details and covers using Open Library first, then Google Books for
/// whatever Open Library doesn't have. Google Books is skipped when there's no key.
struct BookLookup {
    var openLibrary = OpenLibraryClient()
    var google: GoogleBooksClient? = .fromBundle()
    var appleBooks = AppleBooksClient()

    // MARK: ISBN

    func lookup(isbn: String) async throws -> BookDraft {
        do {
            var draft = try await openLibrary.lookup(isbn: isbn)
            // Open Library knew the book; Google Books may add a cover and the description.
            let fromGoogle = try? await google?.lookup(isbn: isbn)
            if draft.coverImage == nil, let fromGoogle {
                draft.coverImage = await cover(for: fromGoogle)
            }
            draft.summary = await findDescription(title: draft.trimmedTitle, author: draft.authorList.first,
                                                  isbn: isbn, known: fromGoogle?.summary) ?? ""
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
        return Self.englishFirst(Self.merge(openLibraryResults, gb ?? []))
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

    /// English editions ahead of translations, otherwise keeping the order.
    static func englishFirst(_ candidates: [BookCandidate]) -> [BookCandidate] {
        candidates.filter(\.isEnglish) + candidates.filter { !$0.isEnglish }
    }

    /// A picked result as a draft, with its cover downloaded.
    func draft(for candidate: BookCandidate, isbn: String? = nil) async -> BookDraft {
        var draft = candidate.draft(isbn: isbn)
        async let coverData = cover(for: candidate)
        async let description = findDescription(title: candidate.title, author: candidate.authors.first,
                                                isbn: draft.normalizedISBN, known: candidate.summary)
        draft.coverImage = await coverData
        draft.summary = await description ?? ""
        return draft
    }

    // MARK: Descriptions

    /// The book's description: this edition's (by ISBN), else another English edition
    /// of the same book on Google Books, else Open Library's. A proper-length one wins
    /// in that order; otherwise the longest found. `known` is one already in hand.
    func findDescription(title: String, author: String?, isbn: String?, known: String? = nil) async -> String? {
        if let known, known.count >= BookDescription.goodLength { return known }
        var found: [String?] = [known]

        if let isbn, !isbn.isEmpty, known == nil, let google {
            found.append((try? await google.lookup(isbn: isbn))?.summary)
            if let best = BookDescription.best(found), best.count >= BookDescription.goodLength { return best }
        }

        let shortTitle = Self.shortTitle(title)
        // Searches ignore accents: Google lists "Ichiro Kishimi", not "Ichirō".
        let plainAuthor = author.map(Self.withoutAccents)
        let titleWords = BookMatcher.words(Self.withoutAccents(shortTitle))
        let authorWords = BookMatcher.words(plainAuthor ?? "")
        // Same book: every word of our title appears in the edition's (which may add a
        // subtitle, like "Tech Simplified for PMs and Entrepreneurs"), and the author matches.
        func isSameBook(_ edition: BookCandidate) -> Bool {
            let editionWords = BookMatcher.words(Self.withoutAccents(edition.title))
            let editionAuthors = BookMatcher.words(Self.withoutAccents(edition.authors.joined(separator: " ")))
            return edition.isEnglish && !titleWords.isEmpty && titleWords.isSubset(of: editionWords)
                && (authorWords.isEmpty || !authorWords.isDisjoint(with: editionAuthors))
        }
        if let google {
            var editions = (try? await google.search(title: shortTitle, author: plainAuthor)) ?? []
            if !editions.contains(where: isSameBook) {
                editions += (try? await google.search(shortTitle, limit: 10)) ?? []
            }
            found += editions.filter(isSameBook).map(\.summary)
            if let best = BookDescription.best(found), best.count >= BookDescription.goodLength { return best }
        }

        found.append(await openLibrary.workDescription(title: shortTitle, author: plainAuthor))
        return BookDescription.best(found)
    }

    /// Looks up a saved book's description if it has none. Returns whether it has one now.
    @MainActor
    @discardableResult
    func fillMissingDescription(of book: Book) async -> Bool {
        guard book.summary == nil else { return true }
        let found = await findDescription(title: book.title, author: book.authors.first, isbn: book.isbn)
        book.summaryLookupDate = .now
        if let found, book.summary == nil {
            book.summary = found
        }
        return book.summary != nil
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

    /// A sharper copy of the cover a book already has: its own edition first (by
    /// ISBN), then Apple Books, then other editions that happen to share the artwork.
    /// Nil if nothing online is both the same cover and clearly larger.
    func sharperCover(than current: Data, title: String, author: String?, isbn: String?) async -> Data? {
        func firstSharper(_ urls: [URL?]) async -> Data? {
            for url in urls.compactMap({ $0 }) {
                if let data = await openLibrary.downloadCover(from: [url]), CoverImage.isSharperCopy(data, of: current) {
                    return data
                }
            }
            return nil
        }
        if let isbn, !isbn.isEmpty {
            if let found = await firstSharper([OpenLibraryClient.isbnCoverURL(isbn)]) { return found }
        }
        if let found = await firstSharper(await appleBooks.coverURLs(title: Self.shortTitle(title), author: author)) {
            return found
        }
        if let isbn, !isbn.isEmpty {
            if let candidate = try? await google?.lookup(isbn: isbn), let found = await firstSharper([candidate.coverURL]) {
                return found
            }
        }
        let editions = await coverOptions(title: title, author: author, isbn: isbn)
        return await firstSharper(editions.prefix(6).map(\.coverURL))
    }

    /// Covers of other editions of the same book, English ones first, for choosing a
    /// different cover. Only results whose title and author match the book count.
    func coverOptions(title: String, author: String?, isbn: String?) async -> [BookCandidate] {
        let shortTitle = Self.shortTitle(title)
        async let byISBN = isbn.flatMap { $0.isEmpty ? nil : $0 }.asyncFlatMap { try? await google?.lookup(isbn: $0) }
        async let found = try? search([shortTitle, author].compactMap { $0 }.joined(separator: " "))

        let bookWords = BookMatcher.words(shortTitle)
        let authorWords = BookMatcher.words(author ?? "")
        let sameBook = ((await found) ?? []).filter { candidate in
            let words = BookMatcher.words(Self.shortTitle(candidate.title))
            guard !words.isEmpty, !bookWords.isEmpty else { return false }
            let titleOverlap = Double(words.intersection(bookWords).count) / Double(min(words.count, bookWords.count))
            let authorOK = authorWords.isEmpty
                || !BookMatcher.words(candidate.authors.joined(separator: " ")).isDisjoint(with: authorWords)
            return titleOverlap >= 0.6 && authorOK
        }

        var seen = Set<URL>()
        return Self.englishFirst([await byISBN].compactMap { $0 } + sameBook)
            .filter { $0.coverURL != nil && $0.thumbnailURL != nil }
            .filter { seen.insert($0.thumbnailURL!).inserted }
    }

    static func withoutAccents(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en"))
    }

    /// "Elon Musk: How the Billionaire… (Marathi)" → "Elon Musk"
    static func shortTitle(_ title: String) -> String {
        let cut = title.firstIndex { $0 == ":" || $0 == "(" } ?? title.endIndex
        let short = title[..<cut].trimmingCharacters(in: .whitespaces)
        return short.isEmpty ? title : short
    }

    /// Downloads a chosen cover option.
    func coverData(for candidate: BookCandidate) async -> Data? {
        await cover(for: candidate)
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

private extension Optional {
    func asyncFlatMap<T>(_ transform: (Wrapped) async -> T?) async -> T? {
        guard let self else { return nil }
        return await transform(self)
    }
}
