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

    private static let searchFields = "key,title,author_name,cover_i,first_publish_year,number_of_pages_median,subject"

    // MARK: Lookup by ISBN

    /// Fetches the book's details and its cover image, if one can be found.
    func lookup(isbn: String) async throws -> BookDraft {
        let data = try await get(Self.searchURL([URLQueryItem(name: "isbn", value: isbn)]))
        guard let result = try Self.parse(data, isbn: isbn) else {
            throw LookupError.notFound
        }
        var draft = result.draft
        draft.coverImage = await downloadCover(from: [result.coverURL, Self.isbnCoverURL(isbn)])
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
        draft.coverImage = await downloadCover(from: [result.coverURL])
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
        let docs = try await coverCandidates(for: prominent)
        guard let doc = Self.bestMatch(in: docs, coverText: prominent),
              let result = Self.draft(from: doc, isbn: isbn) else { return nil }
        var draft = result.draft
        draft.coverImage = await downloadCover(from: [result.coverURL])
        return draft
    }

    /// Search results for the text read off a cover. Tries the most specific query first
    /// (all the big text), then the top two lines, then the biggest line, and stops once
    /// a result matches both title and author (a title-only match might be a different
    /// book with the same name, so it keeps looking).
    func coverCandidates(for prominent: [String]) async throws -> [SearchDoc] {
        guard !prominent.isEmpty else { return [] }
        var queries: [String] = []
        for query in [prominent.joined(separator: " "), prominent.prefix(2).joined(separator: " "), prominent[0]]
        where !queries.contains(query) {
            queries.append(query)
        }
        var candidates: [SearchDoc] = []
        for query in queries {
            let data = try await get(Self.searchURL([URLQueryItem(name: "q", value: query)], limit: 8))
            candidates += try JSONDecoder().decode(SearchResponse.self, from: data).docs
            if Self.rankedMatch(in: candidates, coverText: prominent)?.authorMatched == true { break }
        }
        return candidates
    }

    static func bestMatch(in docs: [SearchDoc], coverText: [String]) -> SearchDoc? {
        rankedMatch(in: docs, coverText: coverText)?.doc
    }

    static func rankedMatch(in docs: [SearchDoc], coverText: [String]) -> (doc: SearchDoc, authorMatched: Bool)? {
        BookMatcher.rankedMatch(in: docs, coverText: coverText, title: { $0.title ?? "" }, authors: { $0.authorName ?? [] })
            .map { ($0.item, $0.authorMatched) }
    }

    static func words(_ text: String) -> Set<String> { BookMatcher.words(text) }

    // MARK: Covers

    /// Finds a cover for a book that doesn't have one: first by ISBN, then by
    /// searching for the title and author. Returns nil if nothing turns up.
    func findCover(title: String, author: String?, isbn: String?) async -> Data? {
        if let isbn, let data = await downloadCover(from: [Self.isbnCoverURL(isbn)]) {
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
        return await downloadCover(from: Array(candidates))
    }

    /// Downloads each URL in turn and returns the first real image.
    func downloadCover(from urls: [URL?]) async -> Data? {
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
        var key: String? = nil

        enum CodingKeys: String, CodingKey {
            case title, subject, key
            case authorName = "author_name"
            case coverID = "cover_i"
            case firstPublishYear = "first_publish_year"
            case numberOfPagesMedian = "number_of_pages_median"
        }
    }
}
