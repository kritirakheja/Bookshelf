import XCTest
@testable import Bookshelf

final class BookDescriptionTests: XCTestCase {
    func testCleansHTMLAndEntities() {
        let raw = "<p><b>THE BESTSELLER</b></p><p>A story of love &amp; loss.<br>It&#39;s &quot;wonderful&quot;.</p>"
        XCTAssertEqual(BookDescription.clean(raw), "THE BESTSELLER\n\nA story of love & loss.\n\nIt's \"wonderful\".")
    }

    func testCollapsesExtraSpaceAndBlankLines() {
        XCTAssertEqual(BookDescription.clean("  One   two\n\n\n\nThree  "), "One two\n\nThree")
    }

    func testBestPrefersTheFirstProperLengthOne() {
        let short = String(repeating: "a", count: 103)
        let longer = String(repeating: "b", count: 900)
        let first = String(repeating: "c", count: 250)
        XCTAssertEqual(BookDescription.best([short, first, longer]), first, "In order of preference, once long enough")
        XCTAssertEqual(BookDescription.best([short, nil, String(repeating: "d", count: 150)])?.count, 150, "Otherwise the longest")
        XCTAssertNil(BookDescription.best([nil, "Too short"]))
    }

    func testOpenLibraryWorkDescriptionEitherShape() {
        XCTAssertEqual(OpenLibraryClient.parseWorkDescription(Data(#"{"description":"Plain text."}"#.utf8)), "Plain text.")
        XCTAssertEqual(OpenLibraryClient.parseWorkDescription(Data(#"{"description":{"type":"/type/text","value":"Wrapped text."}}"#.utf8)), "Wrapped text.")
        XCTAssertNil(OpenLibraryClient.parseWorkDescription(Data(#"{"title":"No description"}"#.utf8)))
    }

    func testGoogleDescriptionReachesTheDraft() throws {
        let json = #"{"items":[{"id":"x","volumeInfo":{"title":"T","description":"<p>About the book.</p>"}}]}"#
        let candidate = try XCTUnwrap(GoogleBooksClient.parse(Data(json.utf8)).first)
        XCTAssertEqual(candidate.draft().summary, "About the book.")
    }

    /// Three of Kriti's books, each needing a different source. Run with TEST_RUNNER_LIVE_TESTS=1.
    func testLiveFindsDescriptions() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE_TESTS"] == "1", "Set LIVE_TESTS=1")
        try XCTSkipIf(GoogleBooksClient.fromBundle() == nil, "No Google Books key in this build")
        let lookup = BookLookup()
        let cases: [(String, String, String?)] = [
            ("Stories of Words and Phrases", "Sumanto Chattopadhyay", "9789370034181"),  // this edition
            ("How to Win Friends and Influence People", "Dale Carnegie", "9780091906351"),  // another edition
            ("A Thousand Splendid Suns", "Khaled Hosseini", "9781408844441"),  // Open Library's is fuller
        ]
        for (title, author, isbn) in cases {
            let found = await lookup.findDescription(title: title, author: author, isbn: isbn)
            print("DESC \(title): \(found?.count ?? 0) chars — \(found?.prefix(80) ?? "none")")
            XCTAssertGreaterThanOrEqual(found?.count ?? 0, BookDescription.goodLength, title)
            XCTAssertFalse(found?.contains("<") ?? false, "No HTML left in \(title)")
        }
    }
}
