import Foundation
import UIKit

/// Looks up books and covers using the free Open Library APIs (no key needed).
///
/// Uses the search API (`/search.json`): the older `/api/books` endpoint now
/// answers 404 for every ISBN.
struct OpenLibraryClient {
    enum LookupError: LocalizedError {
        case notFound
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .notFound:
                "Open Library doesn't know this ISBN. You can fill in the details yourself."
            case .badResponse:
                "Open Library isn't responding right now. You can fill in the details yourself."
            }
        }
    }

    struct LookupResult {
        var draft: BookDraft
        var coverURL: URL?
    }

    var session: URLSession = .shared

    private static let searchFields = "title,author_name,cover_i,first_publish_year,number_of_pages_median,subject"

    // MARK: Lookup by ISBN

    /// Fetches the book's details and its cover image, if one can be found.
    func lookup(isbn: String) async throws -> BookDraft {
        let data = try await get(Self.searchURL([URLQueryItem(name: "isbn", value: isbn)]))
        guard let result = try Self.parse(data, isbn: isbn) else {
            throw LookupError.notFound
        }
        var draft = result.draft
        draft.coverImage = await firstCover(from: [result.coverURL, Self.isbnCoverURL(isbn)])
        return draft
    }

    /// Turns a search response into a draft, or nil when nothing matched.
    static func parse(_ data: Data, isbn: String) throws -> LookupResult? {
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return response.docs.first.flatMap { draft(from: $0, isbn: isbn) }
    }

    static func draft(from doc: SearchDoc, isbn: String) -> LookupResult? {
        guard let title = doc.title else { return nil }
        var draft = BookDraft()
        draft.title = title
        draft.authors = (doc.authorName ?? []).joined(separator: ", ")
        draft.isbn = isbn
        draft.publishedYear = doc.firstPublishYear.map(String.init) ?? ""
        draft.pageCount = doc.numberOfPagesMedian.map(String.init) ?? ""
        draft.categoryNames = CategorySuggestions.categories(forSubjects: doc.subject ?? [])
        return LookupResult(draft: draft, coverURL: doc.coverID.map(coverURL(id:)))
    }

    // MARK: Search by title or author

    /// Books matching free text such as "circe" or "madeline miller", best matches first.
    func search(_ text: String) async throws -> [SearchDoc] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        let data = try await get(Self.searchURL([URLQueryItem(name: "q", value: query)], limit: 20))
        return try JSONDecoder().decode(SearchResponse.self, from: data).docs.filter { $0.title != nil }
    }

    /// A search result as a draft, with its cover downloaded. The edition (and so the
    /// ISBN) isn't known from a search, so the ISBN is left for the user.
    func draft(for doc: SearchDoc) async -> BookDraft {
        guard let result = Self.draft(from: doc, isbn: "") else { return BookDraft() }
        var draft = result.draft
        draft.coverImage = await firstCover(from: [result.coverURL])
        return draft
    }

    /// Small cover image for search results.
    static func thumbnailURL(id: Int) -> URL {
        URL(string: "https://covers.openlibrary.org/b/id/\(id)-M.jpg")!
    }

    // MARK: Identify from the front cover

    /// Searches Open Library for the book whose title and author best match the text
    /// read off its cover. Returns nil when nothing matches well enough.
    func identify(coverLines prominent: [String], isbn: String) async throws -> BookDraft? {
        guard !prominent.isEmpty else { return nil }
        // Most specific first: all the big text, then the top two lines, then the biggest.
        var queries: [String] = []
        for query in [prominent.joined(separator: " "), prominent.prefix(2).joined(separator: " "), prominent[0]]
        where !queries.contains(query) {
            queries.append(query)
        }
        var candidates: [SearchDoc] = []
        for query in queries {
            let data = try await get(Self.searchURL([URLQueryItem(name: "q", value: query)], limit: 8))
            candidates += try JSONDecoder().decode(SearchResponse.self, from: data).docs
            // Stop once a result matches both title and author; a title-only match might
            // be a different book with the same name, so keep looking.
            if Self.rankedMatch(in: candidates, coverText: prominent)?.authorMatched == true { break }
        }
        guard let doc = Self.bestMatch(in: candidates, coverText: prominent),
              let result = Self.draft(from: doc, isbn: isbn) else { return nil }
        var draft = result.draft
        draft.coverImage = await firstCover(from: [result.coverURL])
        return draft
    }

    /// Picks the result whose title is best supported by the words on the cover.
    /// Most title words must appear on the cover (so "The Housemaid's Secret" loses to
    /// "The Housemaid" when the cover only says HOUSEMAID); a matching author surname
    /// and covering more of the cover's words break ties.
    static func bestMatch(in docs: [SearchDoc], coverText: [String]) -> SearchDoc? {
        rankedMatch(in: docs, coverText: coverText)?.doc
    }

    static func rankedMatch(in docs: [SearchDoc], coverText: [String]) -> (doc: SearchDoc, authorMatched: Bool)? {
        let coverWords = words(coverText.joined(separator: " "))
        guard !coverWords.isEmpty else { return nil }

        var best: (doc: SearchDoc, score: Double, authorMatched: Bool)?
        for doc in docs {
            let titleWords = words(doc.title ?? "")
            guard !titleWords.isEmpty else { continue }
            let shared = Double(titleWords.intersection(coverWords).count)
            let precision = shared / Double(titleWords.count)
            guard precision >= 0.6 else { continue }
            let authorWords = words((doc.authorName ?? []).joined(separator: " "))
            let authorMatched = authorWords.contains { name in
                coverWords.contains { roughlyEqual(name, $0) }
            }
            let recall = shared / Double(coverWords.count)
            let score = 2 * precision + (authorMatched ? 1 : 0) + recall
            if score > (best?.score ?? 0) {
                best = (doc, score, authorMatched)
            }
        }
        return best.map { ($0.doc, $0.authorMatched) }
    }

    /// Same word, allowing for text-recognition slips in longer words
    /// ("CONWAY" read as "INWAY").
    static func roughlyEqual(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard min(a.count, b.count) >= 5 else { return false }
        return editDistance(a, b) <= 2
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = a[i - 1] == b[j - 1]
                    ? previous[j - 1]
                    : 1 + min(previous[j - 1], previous[j], current[j - 1])
            }
            previous = current
        }
        return previous[b.count]
    }

    private static let stopWords: Set<String> = ["the", "a", "an", "of", "and", "to", "in", "on", "for", "by", "with"]

    /// Lowercased words without possessives or punctuation ("Housemaid's" → "housemaid").
    static func words(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .replacing(#/['\u{2019}]s\b/#, with: "")
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 2 && !stopWords.contains($0) }
        )
    }

    // MARK: Covers

    /// Finds a cover for a book that doesn't have one: first by ISBN, then by
    /// searching for the title and author. Returns nil if nothing turns up.
    func findCover(title: String, author: String?, isbn: String?) async -> Data? {
        if let isbn, let data = await firstCover(from: [Self.isbnCoverURL(isbn)]) {
            return data
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        var query = [URLQueryItem(name: "title", value: trimmedTitle)]
        if let author, !author.isEmpty {
            query.append(URLQueryItem(name: "author", value: author))
        }
        guard let data = try? await get(Self.searchURL(query)),
              let response = try? JSONDecoder().decode(SearchResponse.self, from: data) else {
            return nil
        }
        let candidates = response.docs.compactMap(\.coverID).prefix(3).map(Self.coverURL(id:))
        return await firstCover(from: Array(candidates))
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

    /// Downloads each URL in turn and returns the first real image.
    private func firstCover(from urls: [URL?]) async -> Data? {
        for url in urls.compactMap({ $0 }) {
            guard let data = try? await get(url),
                  let image = UIImage(data: data),
                  image.size.width > 10 else { continue }  // skip 1×1 "no cover" placeholders
            return data
        }
        return nil
    }

    static func coverURL(id: Int) -> URL {
        URL(string: "https://covers.openlibrary.org/b/id/\(id)-L.jpg")!
    }

    /// `default=false` makes Open Library answer 404 instead of a blank image when there's no cover.
    static func isbnCoverURL(_ isbn: String) -> URL {
        URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg?default=false")!
    }

    // MARK: Networking

    private static func searchURL(_ query: [URLQueryItem], limit: Int = 3) -> URL {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = query + [
            URLQueryItem(name: "fields", value: searchFields),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return components.url!
    }

    private func get(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw LookupError.badResponse(status) }
        return data
    }

    struct SearchResponse: Decodable {
        let docs: [SearchDoc]
    }

    struct SearchDoc: Decodable {
        let title: String?
        let authorName: [String]?
        let coverID: Int?
        let firstPublishYear: Int?
        let numberOfPagesMedian: Int?
        let subject: [String]?

        enum CodingKeys: String, CodingKey {
            case title, subject
            case authorName = "author_name"
            case coverID = "cover_i"
            case firstPublishYear = "first_publish_year"
            case numberOfPagesMedian = "number_of_pages_median"
        }
    }
}
