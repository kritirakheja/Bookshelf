import UIKit
import Vision

/// Reads the text on a photo of a book's front cover (on-device, via Vision) and
/// picks out the lines most likely to be the title and author.
enum CoverTextReader {
    struct Line: Equatable {
        let text: String
        /// Height of the text relative to the photo: bigger text is more likely the title.
        let size: CGFloat
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
                return Line(text: candidate.string, size: observation.boundingBox.height)
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
    private static let blurbLines: Set<String> = ["a novel", "novel", "a memoir", "memoir", "stories", "a thriller"]

    /// The biggest lines on the cover, largest first, minus blurbs and stray characters.
    static func prominentLines(_ lines: [Line], limit: Int = 4) -> [String] {
        lines
            .filter { line in
                let lower = line.text.lowercased().trimmingCharacters(in: .whitespaces)
                let letters = lower.filter(\.isLetter).count
                return letters >= 2
                    && !blurbLines.contains(lower)
                    && !blurbPhrases.contains(where: lower.contains)
            }
            .sorted { $0.size > $1.size }
            .prefix(limit)
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
    }

    /// Best guess at title and author from the cover text alone (used when the book
    /// can't be found online). The author guess needs to look like a name.
    static func guess(from prominent: [String]) -> (title: String, author: String?) {
        guard let first = prominent.first else { return ("", nil) }
        let author = prominent.dropFirst().first { line in
            let words = line.split(separator: " ")
            return (2...4).contains(words.count)
                && !line.contains(where: \.isNumber)
                && words.allSatisfy { $0.first?.isUppercase == true }
        }
        return (tidyCase(first), author.map(tidyCase))
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
