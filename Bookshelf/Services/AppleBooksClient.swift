import Foundation

/// Apple Books (the iTunes Search API): a source of large, clean cover images.
/// No key needed, but Apple allows only about 20 searches a minute.
struct AppleBooksClient {
    var session: URLSession = .shared
    /// Stores to search, in order. India's ebook store is thin, so it isn't used.
    var countries = ["us", "gb"]

    /// Large covers of ebooks matching the title and author, best matches first.
    func coverURLs(title: String, author: String?, limit: Int = 5) async -> [URL] {
        var found: [URL] = []
        for country in countries {
            var components = URLComponents(string: "https://itunes.apple.com/search")!
            components.queryItems = [
                URLQueryItem(name: "term", value: [title, author].compactMap { $0 }.joined(separator: " ")),
                URLQueryItem(name: "media", value: "ebook"),
                URLQueryItem(name: "entity", value: "ebook"),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "country", value: country),
            ]
            await Self.pace.wait()
            guard let url = components.url, let (data, _) = try? await session.data(from: url) else { continue }
            found += Self.parse(data)
        }
        var seen = Set<URL>()
        return found.filter { seen.insert($0).inserted }
    }

    /// Apple's results carry a 100-pixel thumbnail; the same address with a larger
    /// size in it returns the cover at that size.
    static func parse(_ data: Data, size: Int = 1200) -> [URL] {
        struct Response: Decodable {
            struct Result: Decodable { let artworkUrl100: String? }
            let results: [Result]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return response.results.compactMap(\.artworkUrl100).compactMap { thumbnail in
            URL(string: thumbnail.replacingOccurrences(of: "100x100bb", with: "\(size)x\(size)bb"))
        }
    }

    /// Keeps searches about three seconds apart, under Apple's limit.
    private static let pace = Pace(interval: 3.2)

    private actor Pace {
        let interval: TimeInterval
        private var next = Date.distantPast

        init(interval: TimeInterval) { self.interval = interval }

        func wait() async {
            let now = Date.now
            let start = max(now, next)
            next = start.addingTimeInterval(interval)
            if start > now {
                try? await Task.sleep(for: .seconds(start.timeIntervalSince(now)))
            }
        }
    }
}
