import XCTest
@testable import Bookshelf

final class GoogleBooksTests: XCTestCase {
    /// Shaped like a real Google Books response for the book from Kriti's bug report.
    private let storiesOfWords = """
    {"kind":"books#volumes","totalItems":1,"items":[{"id":"SbWP0QEACAAJ","volumeInfo":{
      "title":"Stories of Words and Phrases",
      "subtitle":"Discover the fascinating stories behind everyday expressions",
      "authors":["Sumanto Chattopadhyay"],
      "publisher":"Rupa Publications India",
      "publishedDate":"2025-07-19",
      "industryIdentifiers":[{"type":"ISBN_10","identifier":"9370034188"},{"type":"ISBN_13","identifier":"9789370034181"}],
      "pageCount":296,
      "categories":["Language Arts & Disciplines"],
      "imageLinks":{"smallThumbnail":"http://books.google.com/books/content?id=SbWP0QEACAAJ&printsec=frontcover&img=1&zoom=5&source=gbs_api",
                    "thumbnail":"http://books.google.com/books/content?id=SbWP0QEACAAJ&printsec=frontcover&img=1&zoom=1&edge=curl&source=gbs_api"}
    }}]}
    """

    func testParsesAVolume() throws {
        let book = try XCTUnwrap(GoogleBooksClient.parse(Data(storiesOfWords.utf8)).first)
        XCTAssertEqual(book.title, "Stories of Words and Phrases")
        XCTAssertEqual(book.authors, ["Sumanto Chattopadhyay"])
        XCTAssertEqual(book.isbn, "9789370034181", "Prefers the 13-digit ISBN")
        XCTAssertEqual(book.year, 2025)
        XCTAssertEqual(book.pageCount, 296)
        XCTAssertEqual(book.source, .googleBooks)

        let draft = book.draft()
        XCTAssertEqual(draft.categoryNames, ["Language"])
        XCTAssertEqual(draft.isbn, "9789370034181")
    }

    func testCoverLinksAreHTTPSLargerAndWithoutPageCurl() throws {
        let book = try XCTUnwrap(GoogleBooksClient.parse(Data(storiesOfWords.utf8)).first)
        let cover = try XCTUnwrap(book.coverURL?.absoluteString)
        XCTAssertTrue(cover.hasPrefix("https://"))
        XCTAssertFalse(cover.contains("edge=curl"))
        XCTAssertTrue(cover.contains("fife=w800"))
    }

    func testNoResults() throws {
        XCTAssertTrue(try GoogleBooksClient.parse(Data(#"{"kind":"books#volumes","totalItems":0}"#.utf8)).isEmpty)
    }

    func testScannedISBNWinsOverTheSources() {
        let candidate = BookCandidate(id: "x", source: .googleBooks, title: "T", authors: [], isbn: "111")
        XCTAssertEqual(candidate.draft(isbn: "999").isbn, "999")
        XCTAssertEqual(candidate.draft(isbn: "").isbn, "111")
        XCTAssertEqual(candidate.draft().isbn, "111")
    }

    func testMergedSearchAlternatesAndDropsDuplicates() {
        func c(_ id: String, _ title: String, _ author: String, _ source: BookCandidate.Source) -> BookCandidate {
            BookCandidate(id: id, source: source, title: title, authors: [author])
        }
        let ol = [c("o1", "Circe", "Madeline Miller", .openLibrary), c("o2", "The Song of Achilles", "Madeline Miller", .openLibrary)]
        let gb = [c("g1", "CIRCE", "madeline miller", .googleBooks), c("g2", "Galatea", "Madeline Miller", .googleBooks)]
        XCTAssertEqual(BookLookup.merge(ol, gb).map(\.id), ["o1", "o2", "g2"])
    }

    /// Needs GOOGLE_BOOKS_KEY in Config/Local.xcconfig. Run with TEST_RUNNER_LIVE_TESTS=1.
    func testLiveFindsTheBookOpenLibraryMissed() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE_TESTS"] == "1", "Set LIVE_TESTS=1")
        try XCTSkipIf(GoogleBooksClient.fromBundle() == nil, "No Google Books key in this build")
        let lookup = BookLookup()

        let draft = try await lookup.lookup(isbn: "9789370034181")
        XCTAssertEqual(draft.title, "Stories of Words and Phrases")
        XCTAssertEqual(draft.authors, "Sumanto Chattopadhyay")
        print("GOOGLE cover bytes: \(draft.coverImage?.count ?? 0)")

        let results = try await lookup.search("stories of words and phrases")
        XCTAssertTrue(results.contains { $0.title == "Stories of Words and Phrases" })

        // What a cover scan reads (title in two lines, author name).
        let identified = await lookup.identify(coverLines: ["STORIES OF WORDS", "AND PHRASES", "SUMANTO CHATTOPADHYAY"], isbn: "")
        XCTAssertEqual(identified?.title, "Stories of Words and Phrases")
    }
}
