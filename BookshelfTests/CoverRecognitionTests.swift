import XCTest
@testable import Bookshelf

final class CoverRecognitionTests: XCTestCase {
    private func line(_ text: String, _ size: CGFloat, at position: CGFloat = 0) -> CoverTextReader.Line {
        .init(text: text, size: size, position: position)
    }

    private func doc(_ title: String, _ author: String) -> OpenLibraryClient.SearchDoc {
        .init(title: title, authorName: [author], coverID: nil, firstPublishYear: nil, numberOfPagesMedian: nil, subject: nil)
    }

    /// Exactly what text recognition read off the real cover of "Stories of Words and
    /// Phrases" (top to bottom), including its misreads.
    private var storiesOfWordsCover: [CoverTextReader.Line] {
        [("SHASHI THARDOR", 0.030), ("Sumanto", 0.046), ("Chattopadhyay", 0.052), ("Newese of \"The Engies Nuts", 0.026),
         ("STORIES", 0.098), ("OF", 0.060), ("WORDS", 0.099), ("AND", 0.052), ("PHRASES", 0.110),
         ("Discover the", 0.030), ("fascinating stories", 0.043), ("behind everyday", 0.043), ("expressions", 0.037)]
            .enumerated().map { line($1.0, $1.1, at: CGFloat($0) / 13) }
    }

    func testProminentLinesSkipBlurbsAndKeepReadingOrder() {
        let lines = [
            line("#1 NEW YORK TIMES BESTSELLER", 0.03, at: 0.05),
            line("THE HOUSEMAID", 0.12, at: 0.3),
            line("FREIDA McFADDEN", 0.06, at: 0.8),
            line("A Novel", 0.04, at: 0.5),
            line("“Twisty and addictive” — Someone", 0.02, at: 0.9),
            line("7", 0.2, at: 0.95),
        ]
        XCTAssertEqual(CoverTextReader.prominentLines(lines), ["THE HOUSEMAID", "FREIDA McFADDEN"])
    }

    func testStoriesOfWordsCoverKeepsTitleAndAuthor() {
        XCTAssertEqual(
            CoverTextReader.prominentLines(storiesOfWordsCover),
            ["Sumanto", "Chattopadhyay", "STORIES", "OF", "WORDS", "AND", "PHRASES"],
            "Every title word (including STORIES, OF, AND) and the author, top to bottom"
        )
    }

    func testSearchQueriesStartWithAllTextThenTheBiggest() {
        let housemaid = [
            line("From behind closed doors,", 0.05, at: 0.05),
            line("she sees everything.", 0.05, at: 0.1),
            line("THE", 0.08, at: 0.3),
            line("HOUSEMAID", 0.14, at: 0.4),
            line("FREIDA McFADDEN", 0.07, at: 0.8),
        ]
        XCTAssertEqual(CoverTextReader.searchQueries(housemaid), [
            "she sees everything. THE HOUSEMAID FREIDA McFADDEN",
            "HOUSEMAID FREIDA McFADDEN",
            "HOUSEMAID",
        ], "The tagline ending in a comma is dropped; size decides the shorter searches")
    }

    func testGuessFromStoriesOfWordsCover() {
        let guess = CoverTextReader.guess(from: storiesOfWordsCover)
        XCTAssertEqual(guess.title, "Stories Of Words And Phrases")
        XCTAssertEqual(guess.author, "Sumanto Chattopadhyay", "Name split over two lines is joined")
    }

    func testGuessNeedsANameLikeAuthor() {
        let guess = CoverTextReader.guess(from: [line("THE HOUSEMAID", 0.12, at: 0.3), line("FREIDA McFADDEN", 0.06, at: 0.8)])
        XCTAssertEqual(guess.title, "The Housemaid")
        XCTAssertEqual(guess.author, "Freida Mcfadden")

        let noAuthor = CoverTextReader.guess(from: [line("Sapiens", 0.12, at: 0.2), line("a brief history of humankind", 0.04, at: 0.4)])
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
        XCTAssertEqual(BookMatcher.words("The Housemaid’s Secret"), ["housemaid", "secret"])
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
        let lookup = BookLookup()   // exactly what the app uses
        var results: [String] = []
        for (expected, coverID) in books {
            let (data, _) = try await URLSession.shared.data(from: OpenLibraryClient.coverURL(id: coverID))
            let image = try XCTUnwrap(UIImage(data: data), "cover \(coverID)")
            let lines = try await CoverTextReader.read(image)
            let prominent = CoverTextReader.prominentLines(lines)
            let draft = await lookup.identify(coverLines: prominent, queries: CoverTextReader.searchQueries(lines), isbn: "")
            results.append("\(expected): read \(prominent) → \(draft.map { "\($0.title) / \($0.authors)" } ?? "no match")")
            XCTAssertEqual(draft.map { BookMatcher.words($0.title) }, BookMatcher.words(expected), results.last!)
        }
        print("COVER_RESULTS\n" + results.joined(separator: "\n"))
    }
}
