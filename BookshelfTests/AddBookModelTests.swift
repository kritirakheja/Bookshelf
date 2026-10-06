import XCTest
@testable import Bookshelf

@MainActor
final class AddBookModelTests: XCTestCase {
    /// Answers lookups from a script instead of the network, and counts them.
    private final class FakeFinder: BookFinding {
        var result: Result<BookDraft, Error> = .failure(OpenLibraryClient.LookupError.notFound)
        private(set) var lookups: [String] = []

        func lookup(isbn: String) async throws -> BookDraft {
            lookups.append(isbn)
            return try result.get()
        }

        func draft(for candidate: BookCandidate, isbn: String?) async -> BookDraft {
            var draft = BookDraft()
            draft.title = candidate.title
            draft.authors = candidate.authors.joined(separator: ", ")
            return draft
        }

        func identify(coverLines prominent: [String], queries: [String]?, isbn: String) async -> BookDraft? { nil }
    }

    private func draft(_ title: String, author: String = "Madeline Miller", isbn: String = "") -> BookDraft {
        var draft = BookDraft()
        draft.title = title
        draft.authors = author
        draft.isbn = isbn
        return draft
    }

    func testISBNsAreNormalised() {
        XCTAssertEqual(AddBookModel.normalizedISBN("978-1-4088-9004-2"), "9781408890042")
        XCTAssertEqual(AddBookModel.normalizedISBN("014143951x"), "014143951X")
        XCTAssertNil(AddBookModel.normalizedISBN("12345"))
        XCTAssertNil(AddBookModel.normalizedISBN(""))
    }

    func testAFoundBookOpensTheForm() async {
        let finder = FakeFinder()
        finder.result = .success(draft("Circe", isbn: "9781408890042"))
        let model = AddBookModel(finder: finder)
        await model.lookUp("978-1408890042", library: [])
        XCTAssertEqual(finder.lookups, ["9781408890042"])
        XCTAssertEqual(model.form?.draft.title, "Circe")
        XCTAssertNil(model.duplicate)
        XCTAssertNil(model.progress)
    }

    func testAnUnknownBarcodeOffersTheCoverScan() async {
        let model = AddBookModel(finder: FakeFinder())
        await model.lookUp("9781408890042", library: [])
        XCTAssertEqual(model.unknownISBN, "9781408890042")
        XCTAssertNil(model.form)
    }

    func testANetworkFailureStillOpensTheFormWithTheISBN() async {
        let finder = FakeFinder()
        finder.result = .failure(URLError(.notConnectedToInternet))
        let model = AddBookModel(finder: finder)
        await model.lookUp("9781408890042", library: [])
        XCTAssertEqual(model.form?.draft.isbn, "9781408890042")
        XCTAssertNotNil(model.form?.notice)
    }

    func testAnOwnedISBNIsCaughtWithoutLookingItUp() async {
        let finder = FakeFinder()
        let owned = Book(title: "Circe", authors: ["Madeline Miller"], isbn: "9781408890042")
        let model = AddBookModel(finder: finder)
        await model.lookUp("9781408890042", library: [owned])
        XCTAssertTrue(model.duplicate?.book === owned)
        XCTAssertNil(model.duplicate?.pending, "Same edition: nothing to add")
        XCTAssertTrue(finder.lookups.isEmpty)
        XCTAssertNil(model.form)
    }

    func testTheSameTitleInAnotherEditionAsksFirst() async {
        let finder = FakeFinder()
        finder.result = .success(draft("Circe", isbn: "9780316556347"))
        let owned = Book(title: "Circe", authors: ["Madeline Miller"], isbn: "9781408890042")
        let model = AddBookModel(finder: finder)
        await model.lookUp("9780316556347", library: [owned])
        XCTAssertTrue(model.duplicate?.book === owned)
        XCTAssertEqual(model.duplicate?.pending?.draft.isbn, "9780316556347", "Can still be added as a second edition")
        XCTAssertNil(model.form)
    }

    func testInvalidTextDoesNothing() async {
        let finder = FakeFinder()
        let model = AddBookModel(finder: finder)
        await model.lookUp("not an isbn", library: [])
        XCTAssertTrue(finder.lookups.isEmpty)
        XCTAssertNil(model.form)
        XCTAssertNil(model.unknownISBN)
    }

    func testAPickedSearchResultOpensTheForm() async {
        let model = AddBookModel(finder: FakeFinder())
        let candidate = BookCandidate(id: "1", source: .googleBooks, title: "Dune", authors: ["Frank Herbert"])
        await model.add(candidate, library: [])
        XCTAssertEqual(model.form?.draft.title, "Dune")
    }

    func testEnteringManuallyKeepsAnUnknownISBN() {
        let model = AddBookModel(finder: FakeFinder())
        model.enterManually(isbn: "9781408890042")
        XCTAssertEqual(model.form?.draft.isbn, "9781408890042")
        model.enterManually()
        XCTAssertEqual(model.form?.draft.isbn, "")
    }
}
