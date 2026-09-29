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
        guard let doc = response.docs.first, let title = doc.title else { return nil }

        var draft = BookDraft()
        draft.title = title
        draft.authors = (doc.authorName ?? []).joined(separator: ", ")
        draft.isbn = isbn
        draft.publishedYear = doc.firstPublishYear.map(String.init) ?? ""
        draft.pageCount = doc.numberOfPagesMedian.map(String.init) ?? ""
        draft.categoryNames = CategorySuggestions.categories(forSubjects: doc.subject ?? [])
        return LookupResult(draft: draft, coverURL: doc.coverID.map(coverURL(id:)))
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

    private static func searchURL(_ query: [URLQueryItem]) -> URL {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = query + [
            URLQueryItem(name: "fields", value: searchFields),
            URLQueryItem(name: "limit", value: "3"),
        ]
        return components.url!
    }

    private func get(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw LookupError.badResponse(status) }
        return data
    }

    private struct SearchResponse: Decodable {
        let docs: [Doc]
    }

    private struct Doc: Decodable {
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
