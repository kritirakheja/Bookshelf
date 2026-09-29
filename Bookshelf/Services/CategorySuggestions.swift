import Foundation

/// Open Library "subjects" are noisy ("Accessible book", "Fiction, general",
/// "nyt:hardcover-fiction=2010-01-01"...). Rather than importing them as-is,
/// map them onto a small set of familiar shelf categories.
enum CategorySuggestions {
    static let maxSuggestions = 3

    private struct Rule {
        let category: String
        let keywords: [String]
        var excluding: [String] = []

        func matches(_ subject: String) -> Bool {
            keywords.contains(where: subject.contains) && !excluding.contains(where: subject.contains)
        }
    }

    /// Checked in order, so more specific rules come first.
    private static let rules: [Rule] = [
        Rule(category: "Science Fiction", keywords: ["science fiction", "sci-fi", "dystopia"]),
        Rule(category: "Fantasy", keywords: ["fantasy", "magic", "dragons", "wizards"]),
        Rule(category: "Historical Fiction", keywords: ["historical fiction"]),
        Rule(category: "Mystery", keywords: ["mystery", "detective"]),
        Rule(category: "Thriller", keywords: ["thriller", "suspense"]),
        Rule(category: "Horror", keywords: ["horror", "ghost stories"]),
        Rule(category: "Romance", keywords: ["romance", "love stories", "courtship"]),
        Rule(category: "Young Adult", keywords: ["young adult"]),
        Rule(category: "Children's", keywords: ["juvenile", "children's"], excluding: ["young adult"]),
        Rule(category: "Graphic Novels", keywords: ["graphic novel", "comic"]),
        Rule(category: "Poetry", keywords: ["poetry", "poems"]),
        Rule(category: "Short Stories", keywords: ["short stories"]),
        Rule(category: "Classics", keywords: ["classic"]),
        Rule(category: "Biography & Memoir", keywords: ["biography", "autobiography", "memoir"]),
        Rule(category: "History", keywords: ["history"], excluding: ["fiction", "natural history"]),
        Rule(category: "Philosophy", keywords: ["philosophy"]),
        Rule(category: "Psychology", keywords: ["psychology"]),
        Rule(category: "Science", keywords: ["science", "physics", "biology", "evolution"], excluding: ["fiction"]),
        Rule(category: "Business", keywords: ["business", "economics", "management"]),
        Rule(category: "Self-help", keywords: ["self-help", "self-actualization"]),
        Rule(category: "Cooking", keywords: ["cooking", "cookery", "recipes"]),
        Rule(category: "Travel", keywords: ["travel"]),
    ]

    static func categories(forSubjects subjects: [String]) -> [String] {
        let lowered = subjects.map { $0.lowercased() }
        let matched = rules
            .filter { rule in lowered.contains(where: rule.matches) }
            .map(\.category)
        return Array(matched.prefix(maxSuggestions))
    }
}
