import Foundation

/// Finds and tidies a book's description (the publisher's blurb, usually the
/// back-cover text). Amazon's page isn't used: Amazon has no public way to read it,
/// but Google Books carries the same publisher descriptions.
enum BookDescription {
    /// Long enough to be a proper description rather than a one-liner.
    static let goodLength = 200

    /// Descriptions arrive with HTML tags (<p>, <br>, <b>) and entities; make them plain text.
    static func clean(_ raw: String) -> String {
        var text = raw
            .replacing(#/<br\s*/?>|</p>\s*<p[^>]*>|</p>/#.ignoresCase(), with: "\n\n")
            .replacing(#/<[^>]+>/#, with: "")
        for (entity, character) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
                                    "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–"] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text
            .replacing(#/[ \t]+/#, with: " ")
            .replacing(#/\n\s*\n(\s*\n)+/#, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first description that's a proper length, in order of preference; failing
    /// that, the longest one found.
    static func best(_ candidates: [String?]) -> String? {
        let found = candidates.compactMap { $0 }.filter { $0.count >= 40 }
        return found.first { $0.count >= goodLength } ?? found.max { $0.count < $1.count }
    }
}
