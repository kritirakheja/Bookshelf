import XCTest
@testable import Bookshelf

final class EditionPreferenceTests: XCTestCase {
    private func candidate(_ id: String, _ title: String, author: String = "Ashlee Vance", language: String? = nil) -> BookCandidate {
        BookCandidate(id: id, source: .googleBooks, title: title, authors: [author],
                      coverURL: URL(string: "https://example.com/\(id)-L.jpg"),
                      thumbnailURL: URL(string: "https://example.com/\(id).jpg"),
                      language: language)
    }

    func testSpotsTranslations() {
        XCTAssertFalse(candidate("a", "Elon Musk: How the Billionaire CEO of SpaceX and Tesla is Shaping our Future (Marathi)").isEnglish)
        XCTAssertFalse(candidate("b", "Sapiens (Hindi Edition)").isEnglish)
        XCTAssertFalse(candidate("c", "Elon Musk", language: "mr").isEnglish)
        XCTAssertTrue(candidate("d", "Elon Musk", language: "en").isEnglish)
        XCTAssertTrue(candidate("e", "Elon Musk").isEnglish, "Unknown language counts as English")
        XCTAssertTrue(candidate("f", "A Suitable Boy").isEnglish)
    }

    func testOpenLibraryLanguages() {
        let english = OpenLibraryClient.SearchDoc(title: "Elon Musk", authorName: nil, coverID: nil, firstPublishYear: nil,
                                                  numberOfPagesMedian: nil, subject: nil, language: ["eng", "mar"])
        let marathi = OpenLibraryClient.SearchDoc(title: "Elon Musk", authorName: nil, coverID: nil, firstPublishYear: nil,
                                                  numberOfPagesMedian: nil, subject: nil, language: ["mar"])
        XCTAssertTrue(BookCandidate(openLibrary: english, index: 0).isEnglish, "Available in English")
        XCTAssertFalse(BookCandidate(openLibrary: marathi, index: 0).isEnglish)
    }

    func testEnglishFirstKeepsOrderOtherwise() {
        let list = [candidate("mr", "Elon Musk (Marathi)"), candidate("en1", "Elon Musk"), candidate("hi", "Elon Musk", language: "hi"), candidate("en2", "Elon Musk: Tesla")]
        XCTAssertEqual(BookLookup.englishFirst(list).map(\.id), ["en1", "en2", "mr", "hi"])
    }

    func testCoverScanPrefersTheEnglishEditionOfTheSameBook() {
        let matches = [candidate("mr", "Elon Musk (Marathi)"), candidate("en", "Elon Musk")]
        let best = BookMatcher.rankedMatch(in: matches, coverText: ["ELON MUSK", "ASHLEE VANCE"])
        XCTAssertEqual(best?.item.id, "en")
    }

    func testShortTitle() {
        XCTAssertEqual(BookLookup.shortTitle("Elon Musk: How the Billionaire CEO… (Marathi)"), "Elon Musk")
        XCTAssertEqual(BookLookup.shortTitle("Sapiens (Hindi Edition)"), "Sapiens")
        XCTAssertEqual(BookLookup.shortTitle("Circe"), "Circe")
    }

    /// Kriti's book: the Marathi edition's ISBN. English covers should come first.
    func testLiveCoverOptionsForElonMusk() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE_TESTS"] == "1", "Set LIVE_TESTS=1")
        let options = await BookLookup().coverOptions(
            title: "Elon Musk: How the Billionaire CEO of SpaceX and Tesla is Shaping our Future (Marathi)",
            author: "Ashlee Vance",
            isbn: "9789390085231"
        )
        print("MUSK options: " + options.map { "\($0.title) [\($0.isEnglish ? "en" : $0.language ?? "?")]" }.joined(separator: " | "))
        XCTAssertGreaterThan(options.count, 1)
        XCTAssertTrue(try XCTUnwrap(options.first).isEnglish, "English cover offered first")
        XCTAssertTrue(options.contains { !$0.isEnglish }, "The Marathi edition's cover is still there to pick")
    }
}
