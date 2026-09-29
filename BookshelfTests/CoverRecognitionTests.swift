import XCTest
@testable import Bookshelf

final class CoverRecognitionTests: XCTestCase {
    private func line(_ text: String, _ size: CGFloat) -> CoverTextReader.Line {
        .init(text: text, size: size)
    }

    private func doc(_ title: String, _ author: String) -> OpenLibraryClient.SearchDoc {
        .init(title: title, authorName: [author], coverID: nil, firstPublishYear: nil, numberOfPagesMedian: nil, subject: nil)
    }

    func testProminentLinesSkipBlurbsAndPreferBigText() {
        let lines = [
            line("#1 NEW YORK TIMES BESTSELLER", 0.03),
            line("FREIDA McFADDEN", 0.06),
            line("THE HOUSEMAID", 0.12),
            line("A Novel", 0.04),
            line("“Twisty and addictive” — Someone", 0.02),
            line("7", 0.2),
        ]
        XCTAssertEqual(CoverTextReader.prominentLines(lines), ["THE HOUSEMAID", "FREIDA McFADDEN"])
    }

    func testGuessNeedsANameLikeAuthor() {
        let guess = CoverTextReader.guess(from: ["THE HOUSEMAID", "FREIDA McFADDEN"])
        XCTAssertEqual(guess.title, "The Housemaid")
        XCTAssertEqual(guess.author, "Freida Mcfadden")

        let noAuthor = CoverTextReader.guess(from: ["Sapiens", "a brief history of humankind"])
        XCTAssertEqual(noAuthor.title, "Sapiens")
        XCTAssertNil(noAuthor.author)
    }

    func testBestMatchPrefersTheTitleOnTheCover() {
        let docs = [doc("The Housemaid's Secret", "Freida McFadden"), doc("The Housemaid", "Freida McFadden")]
        let match = OpenLibraryClient.bestMatch(in: docs, coverText: ["THE HOUSEMAID", "FREIDA McFADDEN"])
        XCTAssertEqual(match?.title, "The Housemaid")
    }

    func testBestMatchUsesAuthorToBreakTies() {
        let docs = [doc("Circe", "Somebody Else"), doc("Circe", "Madeline Miller")]
        let match = OpenLibraryClient.bestMatch(in: docs, coverText: ["CIRCE", "MADELINE MILLER"])
        XCTAssertEqual(match?.authorName, ["Madeline Miller"])
    }

    func testBestMatchRejectsUnrelatedResults() {
        let docs = [doc("A Completely Different Book", "Someone")]
        XCTAssertNil(OpenLibraryClient.bestMatch(in: docs, coverText: ["THE HOUSEMAID"]))
    }

    func testWordsDropPossessivesAndStopWords() {
        XCTAssertEqual(OpenLibraryClient.words("The Housemaid’s Secret"), ["housemaid", "secret"])
    }

    /// Real covers from Open Library, read with the same on-device text recognition the
    /// phone uses, then identified online. Run with TEST_RUNNER_LIVE_TESTS=1.
    func testLiveIdentifyRealCovers() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE_TESTS"] == "1", "Set LIVE_TESTS=1 to call Open Library")
        let books = [
            ("Material World", 14591884),
            ("The Housemaid", 15105883),
            ("Born a Crime", 8294078),
        ]
        let client = OpenLibraryClient()
        var results: [String] = []
        for (expected, coverID) in books {
            let (data, _) = try await URLSession.shared.data(from: OpenLibraryClient.coverURL(id: coverID))
            let image = try XCTUnwrap(UIImage(data: data), "cover \(coverID)")
            let prominent = CoverTextReader.prominentLines(try await CoverTextReader.read(image))
            let draft = try await client.identify(coverLines: prominent, isbn: "")
            results.append("\(expected): read \(prominent) → \(draft.map { "\($0.title) / \($0.authors)" } ?? "no match")")
            XCTAssertEqual(draft.map { OpenLibraryClient.words($0.title) }, OpenLibraryClient.words(expected), results.last!)
        }
        print("COVER_RESULTS\n" + results.joined(separator: "\n"))
    }
}
