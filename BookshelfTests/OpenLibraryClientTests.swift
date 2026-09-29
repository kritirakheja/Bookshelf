import XCTest
@testable import Bookshelf

final class OpenLibraryClientTests: XCTestCase {
    /// Real `/search.json?isbn=9780753559178` response (the book from the phone test),
    /// with `number_of_pages_median` added so that field is covered too.
    private let materialWorld = """
    {"numFound":1,"start":0,"numFoundExact":true,"docs":[{
      "author_name":["Ed Conway"],
      "cover_i":14591884,
      "first_publish_year":2023,
      "number_of_pages_median":512,
      "title":"Material World",
      "subject":["Science","Economics","History","World politics","Business","Environmental policy","Long Now Manual for Civilization"]
    }]}
    """

    func testParsesBookDetails() throws {
        let result = try XCTUnwrap(OpenLibraryClient.parse(Data(materialWorld.utf8), isbn: "9780753559178"))
        XCTAssertEqual(result.draft.title, "Material World")
        XCTAssertEqual(result.draft.authors, "Ed Conway")
        XCTAssertEqual(result.draft.isbn, "9780753559178")
        XCTAssertEqual(result.draft.pageCount, "512")
        XCTAssertEqual(result.draft.publishedYear, "2023")
        XCTAssertEqual(result.coverURL?.absoluteString, "https://covers.openlibrary.org/b/id/14591884-L.jpg")
    }

    func testMapsSubjectsToCategories() throws {
        let result = try XCTUnwrap(OpenLibraryClient.parse(Data(materialWorld.utf8), isbn: "9780753559178"))
        XCTAssertEqual(result.draft.categoryNames, ["History", "Science", "Business"])
    }

    func testUnknownISBNReturnsNil() throws {
        let json = #"{"numFound":0,"start":0,"docs":[]}"#
        XCTAssertNil(try OpenLibraryClient.parse(Data(json.utf8), isbn: "9781234000003"))
    }

    func testMinimalEntryParses() throws {
        let json = #"{"numFound":1,"docs":[{"title":"Just a Title"}]}"#
        let result = try XCTUnwrap(OpenLibraryClient.parse(Data(json.utf8), isbn: "123"))
        XCTAssertEqual(result.draft.title, "Just a Title")
        XCTAssertEqual(result.draft.authors, "")
        XCTAssertNil(result.coverURL)
        XCTAssertEqual(result.draft.categoryNames, [])
    }

    func testCoverURLs() {
        XCTAssertEqual(OpenLibraryClient.coverURL(id: 14591884).absoluteString, "https://covers.openlibrary.org/b/id/14591884-L.jpg")
        XCTAssertEqual(OpenLibraryClient.isbnCoverURL("9780753559178").absoluteString, "https://covers.openlibrary.org/b/isbn/9780753559178-L.jpg?default=false")
    }

    /// Hits the real API, since that's what broke before (`/api/books` started returning 404).
    /// Run with: TEST_RUNNER_LIVE_TESTS=1 xcodebuild test ...
    func testLiveLookupAndCovers() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE_TESTS"] == "1", "Set LIVE_TESTS=1 to call Open Library")
        let client = OpenLibraryClient()

        let draft = try await client.lookup(isbn: "9780753559178")
        XCTAssertEqual(draft.title, "Material World")
        XCTAssertEqual(draft.authors, "Ed Conway")
        XCTAssertNotNil(draft.coverImage, "ISBN lookup should bring a cover")

        let byTitle = await client.findCover(title: "Circe", author: "Madeline Miller", isbn: nil)
        XCTAssertNotNil(byTitle, "Title + author search should find a cover")

        do {
            _ = try await client.lookup(isbn: "9781234000003")
            XCTFail("Unknown ISBN should throw")
        } catch OpenLibraryClient.LookupError.notFound {
            // expected
        }
    }

    @MainActor
    func testSearchResultsMatchOwnedBooksLoosely() {
        XCTAssertEqual(
            BookSearchView.key(title: "The Housemaid", author: "Freida McFadden"),
            BookSearchView.key(title: "HOUSEMAID", author: "freida mcfadden")
        )
        XCTAssertNotEqual(
            BookSearchView.key(title: "The Housemaid", author: "Freida McFadden"),
            BookSearchView.key(title: "The Housemaid's Secret", author: "Freida McFadden")
        )
    }

    func testLiveSearchAndAdd() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE_TESTS"] == "1", "Set LIVE_TESTS=1 to call Open Library")
        let client = OpenLibraryClient()

        let results = try await client.search("circe madeline miller")
        let circe = try XCTUnwrap(results.first { $0.title == "Circe" && $0.authorName?.contains("Madeline Miller") == true })
        let draft = await client.draft(for: circe)
        XCTAssertEqual(draft.title, "Circe")
        XCTAssertEqual(draft.authors, "Madeline Miller")
        XCTAssertNotNil(draft.coverImage)
        XCTAssertEqual(draft.isbn, "", "A search doesn't know which edition you own")

        let empty = try await client.search("c")
        XCTAssertTrue(empty.isEmpty, "Too short to search")
    }

    func testCategorySuggestionsAvoidFalseMatches() {
        XCTAssertEqual(CategorySuggestions.categories(forSubjects: ["Science fiction", "Space warfare"]), ["Science Fiction"])
        XCTAssertEqual(CategorySuggestions.categories(forSubjects: ["Historical fiction"]), ["Historical Fiction"])
        XCTAssertEqual(CategorySuggestions.categories(forSubjects: ["World history", "Civilization"]), ["History"])
        XCTAssertEqual(CategorySuggestions.categories(forSubjects: ["Accessible book", "Protected DAISY"]), [])
    }
}
