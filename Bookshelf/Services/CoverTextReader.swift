import UIKit
import Vision

/// Reads the text on a photo of a book's front cover (on-device, via Vision) and
/// picks out the lines most likely to be the title and author.
enum CoverTextReader {
    struct Line: Equatable {
        let text: String
        /// Height of the text relative to the photo: bigger text is more likely the title.
        let size: CGFloat
        /// How far down the cover the line is (0 = top, 1 = bottom), for reading order.
        var position: CGFloat = 0
    }

    static func read(_ image: UIImage) async throws -> [Line] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
            return (request.results ?? []).compactMap { observation -> Line? in
                guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.3 else { return nil }
                // Vision measures from the bottom; flip so 0 is the top of the cover.
                return Line(text: candidate.string, size: observation.boundingBox.height,
                            position: 1 - observation.boundingBox.maxY)
            }
        }.value
    }

    /// Cover text that is never the title or author.
    private static let blurbPhrases = [
        "bestsell", "best-sell", "best sell", "new york times", "sunday times", "usa today",
        "author of", "winner", "prize", "award", "million copies", "now a major", "netflix",
        "book club", "'s pick", "\u{2019}s pick", "praise", "foreword", "introduction by", "translated", "edition",
        "www.", ".com", "copyright", "\u{201C}", "\u{201D}", "\"",
    ]
    /// Whole lines that are genre labels, never titles. (Single words like "Stories"
    /// aren't here: they're often part of the title itself.)
    private static let blurbLines: Set<String> = ["a novel", "a memoir", "a thriller", "a novel.", "short stories"]

    private static func isBlurb(_ line: Line) -> Bool {
        let lower = line.text.lowercased().trimmingCharacters(in: .whitespaces)
        return lower.filter(\.isLetter).count < 2
            || blurbLines.contains(lower)
            || blurbPhrases.contains(where: lower.contains)
            // Taglines read like sentences: long, or broken off mid-sentence with a comma.
            || lower.split(separator: " ").count >= 7
            || lower.hasSuffix(",")
    }

    /// Lines like "OF" or "AND": part of a title set in big type, but not worth one of
    /// the few places kept for meaningful lines.
    private static func isOnlySmallWords(_ line: Line) -> Bool {
        BookMatcher.words(line.text).isEmpty
    }

    /// The most prominent text on the cover, in reading order (top to bottom): the
    /// biggest `limit` meaningful lines, plus any small-word lines ("OF", "AND") set at
    /// least as big as those, minus blurbs.
    static func prominentLines(_ lines: [Line], limit: Int = 5) -> [String] {
        prominent(lines, limit: limit).map { $0.text.trimmingCharacters(in: .whitespaces) }
    }

    private static func prominent(_ lines: [Line], limit: Int = 5) -> [Line] {
        let candidates = lines.filter { !isBlurb($0) }
        let meaningful = candidates.filter { !isOnlySmallWords($0) }.sorted { $0.size > $1.size }.prefix(limit)
        guard let smallest = meaningful.last?.size else { return [] }
        let kept = candidates.filter { line in
            meaningful.contains(line) || (isOnlySmallWords(line) && line.size >= smallest)
        }
        return readingOrder(kept)
    }

    /// Searches to try, most specific first: all the prominent text (in reading order),
    /// then just the two biggest lines (usually title and author), then the biggest.
    /// Size decides, not position, so a tagline printed above the title can't take over.
    static func searchQueries(_ lines: [Line]) -> [String] {
        let kept = prominent(lines)
        let bySize = kept.filter { !isOnlySmallWords($0) }.sorted { $0.size > $1.size }
        let queries = [
            kept.map(\.text).joined(separator: " "),
            readingOrder(Array(bySize.prefix(2))).map(\.text).joined(separator: " "),
            bySize.first?.text ?? "",
        ]
        var unique: [String] = []
        for query in queries where !query.isEmpty && !unique.contains(query) {
            unique.append(query)
        }
        return unique
    }

    private static func readingOrder(_ lines: [Line]) -> [Line] {
        lines.enumerated()
            .sorted { ($0.element.position, $0.offset) < ($1.element.position, $1.offset) }
            .map(\.element)
    }

    /// Best guess at title and author from the cover text alone (used when the book
    /// can't be found online). The title is the biggest type, read top to bottom
    /// (including small words like "OF" between big lines); the author is the first
    /// other text that looks like a name, joining a name split over two lines.
    static func guess(from lines: [Line]) -> (title: String, author: String?) {
        let candidates = readingOrder(lines.filter { !isBlurb($0) })
        guard let biggest = candidates.map(\.size).max() else { return ("", nil) }

        let bigIndices = candidates.indices.filter { candidates[$0].size >= biggest * 0.6 && !isOnlySmallWords(candidates[$0]) }
        guard let first = bigIndices.first, let last = bigIndices.last else { return ("", nil) }
        let titleRange = first...last
        let title = candidates[titleRange].map(\.text).joined(separator: " ")

        // Other lines, with neighbouring similar-sized lines joined ("Sumanto" + "Chattopadhyay").
        var blocks: [(text: String, size: CGFloat)] = []
        var previous: Line?
        for (index, line) in candidates.enumerated() where !titleRange.contains(index) {
            if let previous, !blocks.isEmpty, line.size / previous.size > 0.75, line.size / previous.size < 1.33 {
                blocks[blocks.count - 1].text += " " + line.text
                blocks[blocks.count - 1].size = max(blocks[blocks.count - 1].size, line.size)
            } else {
                blocks.append((line.text, line.size))
            }
            previous = line
        }
        // The author's name is usually the biggest name-like text after the title; a
        // "Foreword by …" credit is smaller.
        let author = blocks
            .filter { block in
                let words = block.text.split(separator: " ")
                return (2...4).contains(words.count)
                    && !block.text.contains(where: \.isNumber)
                    && words.allSatisfy { $0.first?.isUppercase == true }
            }
            .max { $0.size < $1.size }?
            .text
        return (tidyCase(title), author.map(tidyCase))
    }

    /// "THE HOUSEMAID" → "The Housemaid", word by word, so "FREIDA McFADDEN" works too.
    /// Words that aren't mostly capitals are left alone.
    static func tidyCase(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false).map { word in
            let letters = word.filter(\.isLetter)
            let capitals = letters.filter(\.isUppercase).count
            return letters.count >= 2 && Double(capitals) / Double(letters.count) >= 0.75
                ? word.capitalized
                : String(word)
        }
        .joined(separator: " ")
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
