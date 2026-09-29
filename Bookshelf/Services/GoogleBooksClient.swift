import Foundation

/// Google Books: the second source, for books Open Library doesn't have (often recent
/// or Indian editions). Needs an API key, from `GOOGLE_BOOKS_KEY` in Config/Local.xcconfig.
struct GoogleBooksClient {
    let apiKey: String
    var session: URLSession = .shared

    /// nil when this build has no key.
    static func fromBundle() -> GoogleBooksClient? {
        guard let key = Bundle.main.infoDictionary?["GoogleBooksKey"] as? String,
              !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return GoogleBooksClient(apiKey: key)
    }

    enum Failure: Error {
        case badResponse(Int)
    }

    /// The edition with this ISBN, if Google Books knows it.
    func lookup(isbn: String) async throws -> BookCandidate? {
        try await volumes(query: "isbn:\(isbn)", limit: 1).first
    }

    func search(_ text: String, limit: Int = 20) async throws -> [BookCandidate] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        return try await volumes(query: query, limit: limit)
    }

    private func volumes(query: String, limit: Int) async throws -> [BookCandidate] {
        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(min(limit, 40))),
            URLQueryItem(name: "printType", value: "books"),
            URLQueryItem(name: "key", value: apiKey),
        ]
        var request = URLRequest(url: components.url!)
        // The key is restricted to this app; Google checks this header.
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.badResponse(status) }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> [BookCandidate] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        return (response.items ?? []).compactMap { item in
            let info = item.volumeInfo
            guard let title = info.title, !title.isEmpty else { return nil }
            let identifiers = info.industryIdentifiers ?? []
            let isbn = identifiers.first { $0.type == "ISBN_13" }?.identifier
                ?? identifiers.first { $0.type == "ISBN_10" }?.identifier
            let thumbnail = info.imageLinks?.thumbnail ?? info.imageLinks?.smallThumbnail
            return BookCandidate(
                id: "gb-\(item.id)",
                source: .googleBooks,
                title: title,
                authors: info.authors ?? [],
                year: info.publishedDate.flatMap { Int($0.prefix(4)) },
                pageCount: info.pageCount.flatMap { $0 > 0 ? $0 : nil },
                subjects: info.categories ?? [],
                isbn: isbn,
                coverURL: thumbnail.flatMap { coverURL(fromThumbnail: $0, width: 800) },
                thumbnailURL: thumbnail.flatMap { coverURL(fromThumbnail: $0, width: 200) }
            )
        }
    }

    /// Google's thumbnail links are small, plain http, and sometimes add a page-curl
    /// effect. This asks for a clean, larger image over https.
    static func coverURL(fromThumbnail thumbnail: String, width: Int) -> URL? {
        guard var components = URLComponents(string: thumbnail) else { return nil }
        components.scheme = "https"
        var items = (components.queryItems ?? []).filter { $0.name != "edge" && $0.name != "fife" }
        items.append(URLQueryItem(name: "fife", value: "w\(width)"))
        components.queryItems = items
        return components.url
    }

    private struct Response: Decodable {
        let items: [Item]?
    }

    private struct Item: Decodable {
        let id: String
        let volumeInfo: VolumeInfo
    }

    private struct VolumeInfo: Decodable {
        struct Identifier: Decodable {
            let type: String
            let identifier: String
        }
        struct ImageLinks: Decodable {
            let smallThumbnail: String?
            let thumbnail: String?
        }

        let title: String?
        let authors: [String]?
        let publishedDate: String?
        let pageCount: Int?
        let categories: [String]?
        let industryIdentifiers: [Identifier]?
        let imageLinks: ImageLinks?
    }
}
