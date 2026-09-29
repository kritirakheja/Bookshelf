import Foundation

/// A book found online, from either source, before it becomes a draft to review.
struct BookCandidate: Identifiable {
    enum Source {
        case openLibrary
        case googleBooks
    }

    let id: String
    let source: Source
    var title: String
    var authors: [String]
    var year: Int?
    var pageCount: Int?
    /// Open Library subjects or Google Books categories, for suggesting categories.
    var subjects: [String] = []
    /// The edition's ISBN when the source knows it (Google Books usually does).
    var isbn: String?
    /// Every ISBN the source lists for this edition (10- and 13-digit).
    var isbns: [String] = []
    var coverURL: URL?
    var thumbnailURL: URL?

    /// The candidate as a form draft. An ISBN from a scanned barcode wins over the source's.
    func draft(isbn scannedISBN: String? = nil) -> BookDraft {
        var draft = BookDraft()
        draft.title = title
        draft.authors = authors.joined(separator: ", ")
        draft.isbn = scannedISBN.flatMap { $0.isEmpty ? nil : $0 } ?? isbn ?? ""
        draft.publishedYear = year.map(String.init) ?? ""
        draft.pageCount = pageCount.map(String.init) ?? ""
        draft.categoryNames = CategorySuggestions.categories(forSubjects: subjects)
        return draft
    }
}

extension BookCandidate {
    init(openLibrary doc: OpenLibraryClient.SearchDoc, index: Int) {
        self.init(
            id: "ol-\(doc.key ?? String(index))",
            source: .openLibrary,
            title: doc.title ?? "",
            authors: doc.authorName ?? [],
            year: doc.firstPublishYear,
            pageCount: doc.numberOfPagesMedian,
            subjects: doc.subject ?? [],
            coverURL: doc.coverID.map(OpenLibraryClient.coverURL(id:)),
            thumbnailURL: doc.coverID.map(OpenLibraryClient.thumbnailURL(id:))
        )
    }
}

/// Decides which search result is the book whose cover text we read.
enum BookMatcher {
    /// Most title words must appear on the cover (so "The Housemaid's Secret" loses to
    /// "The Housemaid" when the cover only says HOUSEMAID); a matching author name and
    /// covering more of the cover's words break ties.
    static func rankedMatch<Item>(
        in items: [Item],
        coverText: [String],
        title: (Item) -> String,
        authors: (Item) -> [String]
    ) -> (item: Item, authorMatched: Bool)? {
        let coverWords = words(coverText.joined(separator: " "))
        guard !coverWords.isEmpty else { return nil }

        var best: (item: Item, score: Double, authorMatched: Bool)?
        for item in items {
            let titleWords = words(title(item))
            guard !titleWords.isEmpty else { continue }
            let shared = Double(titleWords.intersection(coverWords).count)
            let precision = shared / Double(titleWords.count)
            guard precision >= 0.6 else { continue }
            let authorWords = words(authors(item).joined(separator: " "))
            let authorMatched = authorWords.contains { name in
                coverWords.contains { roughlyEqual(name, $0) }
            }
            let recall = shared / Double(coverWords.count)
            let score = 2 * precision + (authorMatched ? 1 : 0) + recall
            if score > (best?.score ?? 0) {
                best = (item, score, authorMatched)
            }
        }
        return best.map { ($0.item, $0.authorMatched) }
    }

    static func rankedMatch(in candidates: [BookCandidate], coverText: [String]) -> (item: BookCandidate, authorMatched: Bool)? {
        rankedMatch(in: candidates, coverText: coverText, title: \.title, authors: \.authors)
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

    /// Title + first author, loosely, for spotting the same book twice.
    static func key(title: String, author: String?) -> String {
        "\(words(title).sorted())|\(words(author ?? "").sorted())"
    }
}
