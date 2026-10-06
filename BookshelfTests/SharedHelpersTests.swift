import XCTest
import UIKit
@testable import Bookshelf

@MainActor
final class SharedHelpersTests: XCTestCase {
    func testChunkedKeepsOrderAndLeavesAShortLastRow() {
        XCTAssertEqual([1, 2, 3, 4, 5, 6, 7].chunked(into: 3), [[1, 2, 3], [4, 5, 6], [7]])
        XCTAssertEqual([Int]().chunked(into: 3), [])
    }

    func testBookMatchesTitleOrAnyAuthorIgnoringCaseAndAccents() {
        let book = Book(title: "Gödel, Escher, Bach", authors: ["Douglas R. Hofstadter", "Someone Else"])
        XCTAssertTrue(book.matches(search: "godel"))
        XCTAssertTrue(book.matches(search: "HOFSTADTER"))
        XCTAssertTrue(book.matches(search: "else"))
        XCTAssertFalse(book.matches(search: "tolkien"))
    }

    func testEmptyRecommendationTextClearsTheNote() {
        let book = Book(title: "Circe", authors: ["Madeline Miller"])
        XCTAssertEqual(book.recommendationNoteText, "")
        book.recommendationNoteText = "Read it twice"
        XCTAssertEqual(book.recommendationNote, "Read it twice")
        book.recommendationNoteText = ""
        XCTAssertNil(book.recommendationNote)
    }

    func testDuplicatesByISBN() {
        let circe = Book(title: "Circe", authors: ["Madeline Miller"], isbn: "9781408890042")
        let dune = Book(title: "Dune", authors: ["Frank Herbert"])
        XCTAssertTrue(LibraryDuplicates.book(withISBN: "9781408890042", in: [dune, circe]) === circe)
        XCTAssertNil(LibraryDuplicates.book(withISBN: "9781408890042", in: [dune, circe], excluding: circe), "Editing a book isn't a duplicate of itself")
        XCTAssertNil(LibraryDuplicates.book(withISBN: nil, in: [dune, circe]))
        XCTAssertNil(LibraryDuplicates.book(withISBN: "", in: [dune, circe]))
    }

    func testDuplicatesByTitleAndAuthor() {
        let circe = Book(title: "Circe", authors: ["Madeline Miller"])
        XCTAssertTrue(LibraryDuplicates.book(title: "CIRCE", author: "madeline miller", in: [circe]) === circe)
        XCTAssertNil(LibraryDuplicates.book(title: "Circe", author: "Someone Else", in: [circe]))
        XCTAssertNil(LibraryDuplicates.book(title: "", author: nil, in: [circe]))
    }

    func testFittedShrinksOnlyLargeImages() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1000), format: format).image { _ in }
        XCTAssertEqual(big.fitted(maxSide: 500).size, CGSize(width: 500, height: 250))
        XCTAssertEqual(big.fitted(maxSide: 4000).size, CGSize(width: 2000, height: 1000))
    }

    func testInterFaceFollowsTheWeight() {
        XCTAssertEqual(InterFace(.semibold), .semibold)
        XCTAssertEqual(InterFace(.heavy), .bold)
        XCTAssertEqual(InterFace(.light), .regular)
        XCTAssertNotNil(UIFont(name: InterFace.medium.rawValue, size: 12), "The font file is bundled and registered")
    }
}
