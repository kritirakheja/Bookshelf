import Foundation
import NaturalLanguage

/// An ebook in Apple Books: enough to tell whether it's the same book, and its cover.
struct AppleBook: Equatable {
    var title: String
    var author: String
    /// The cover at a large size.
    var coverURL: URL
    /// The store's blurb. Apple doesn't say what language an edition is in; this does.
    var blurb = ""

    /// An English edition, as far as can be told: the blurb reads as English and the
    /// title isn't marked as a translation ("Grey (En espanol)").
    var isEnglish: Bool {
        let lower = title.lowercased()
        if BookCandidate.isTranslationTitle(title) || Self.translationMarks.contains(where: lower.contains) { return false }
        let text = blurb.replacing(#/<[^>]+>/#, with: " ")
        guard text.count >= 40 else { return true }
        return NLLanguageRecognizer.dominantLanguage(for: text) == .english
    }

    private static let translationMarks = ["español", "espanol", "edição", "versione italiana", "édition française", "ausgabe"]

    /// Who wrote it, beyond the names that match `author`: an illustrator or adapter
    /// here means a different kind of edition (a graphic novel, say).
    func hasOtherAuthors(than author: String) -> Bool {
        !Self.names(self.author).subtracting(Self.names(author)).isEmpty
    }

    /// Whether this is the same book as `title` by `author`: the same title (ignoring
    /// subtitles, punctuation and words like "the") and an author name in common.
    /// Title alone isn't enough: unrelated novels share titles.
    func isSameBook(title: String, author: String) -> Bool {
        let wanted = BookMatcher.words(BookLookup.withoutAccents(BookLookup.shortTitle(title)))
        let mine = BookMatcher.words(BookLookup.withoutAccents(BookLookup.shortTitle(self.title)))
        guard !wanted.isEmpty, wanted == mine else { return false }
        let wantedNames = Self.names(author), myNames = Self.names(self.author)
        return !wantedNames.isDisjoint(with: myNames)
    }

    /// The parts of a name worth comparing: no initials.
    private static func names(_ author: String) -> Set<String> {
        Set(BookLookup.withoutAccents(author).lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 3 })
    }
}

/// Apple Books (the iTunes Search API): a source of large, clean cover images.
/// No key needed, but Apple allows only about 20 searches a minute.
struct AppleBooksClient {
    var session: URLSession = .shared
    /// Stores to search, in order. India's ebook store is thin, so it isn't used.
    var countries = ["us", "gb"]

    /// English ebooks that are this title by this author, those by the author alone
    /// first. The second store is only asked when the first has none.
    func editions(title: String, author: String, limit: Int = 8) async -> [AppleBook] {
        for country in countries {
            var components = URLComponents(string: "https://itunes.apple.com/search")!
            components.queryItems = [
                URLQueryItem(name: "term", value: "\(BookLookup.shortTitle(title)) \(author)"),
                URLQueryItem(name: "media", value: "ebook"),
                URLQueryItem(name: "entity", value: "ebook"),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "country", value: country),
            ]
            await Self.pace.wait()
            guard let url = components.url, let (data, _) = try? await session.data(from: url) else { continue }
            var seen = Set<URL>()
            let matches = Self.parse(data)
                .filter { $0.isSameBook(title: title, author: author) && $0.isEnglish }
                .filter { seen.insert($0.coverURL).inserted }
            let alone = matches.filter { !$0.hasOtherAuthors(than: author) }
            if !alone.isEmpty { return alone }
            if !matches.isEmpty { return matches }
        }
        return []
    }

    /// Apple's results carry a 100-pixel thumbnail; the same address with a larger
    /// size in it returns the cover at that size.
    static func parse(_ data: Data, size: Int = 1200) -> [AppleBook] {
        struct Response: Decodable {
            struct Result: Decodable {
                let trackName: String?
                let artistName: String?
                let artworkUrl100: String?
                let description: String?
            }
            let results: [Result]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return response.results.compactMap { result in
            guard let thumbnail = result.artworkUrl100,
                  let url = URL(string: thumbnail.replacingOccurrences(of: "100x100bb", with: "\(size)x\(size)bb")) else { return nil }
            return AppleBook(title: result.trackName ?? "", author: result.artistName ?? "", coverURL: url,
                             blurb: result.description ?? "")
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
