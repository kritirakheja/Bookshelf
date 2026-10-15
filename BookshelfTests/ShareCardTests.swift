import XCTest
import SwiftData
@testable import Bookshelf

@MainActor
final class ShareCardTests: XCTestCase {
    func testLongerBooksHaveThickerSpines() {
        XCTAssertEqual(SpineMetrics.width(pages: nil), 24, "Unknown length: a middling spine")
        XCTAssertLessThan(SpineMetrics.width(pages: 180), SpineMetrics.width(pages: 600))
        XCTAssertEqual(SpineMetrics.width(pages: 40), SpineMetrics.thinnest)
        XCTAssertEqual(SpineMetrics.width(pages: 2_000), SpineMetrics.thickest)
    }

    func testEachTitleKeepsItsHeight() {
        XCTAssertEqual(SpineMetrics.height(for: "Siddhartha"), SpineMetrics.height(for: "Siddhartha"))
        let heights = ["Dune", "Circe", "Siddhartha", "Bird by Bird", "Born a Crime"].map(SpineMetrics.height(for:))
        XCTAssertTrue(heights.allSatisfy { (150...190).contains($0) })
        XCTAssertGreaterThan(Set(heights).count, 1, "Not all the same height")
    }

    func testTenThickBooksFitTheShelfAndAFewFillIt() {
        let shelf: CGFloat = 304
        let thick = SpineMetrics.widths(pages: Array(repeating: 1_200, count: 10), fitting: shelf, scale: 1)
        let used = thick.reduce(0, +) + SpineMetrics.spacing * 9 + SpineMetrics.leanGap + 12
        XCTAssertLessThanOrEqual(used, shelf + 0.5)

        let few = SpineMetrics.widths(pages: [200, 300], fitting: shelf, scale: 1)
        XCTAssertTrue(few.allSatisfy { $0 <= SpineMetrics.widest + 0.001 }, "Widened, but not into slabs")
    }

    func testTitleWording() {
        XCTAssertEqual(FavouritesShareCard.owner("Kriti"), "KRITI’S")
        XCTAssertEqual(FavouritesShareCard.owner("  Kriti Rakheja "), "KRITI’S")
        XCTAssertEqual(FavouritesShareCard.owner("James"), "JAMES’")
        XCTAssertEqual(FavouritesShareCard.owner(""), "MY")
        XCTAssertEqual(FavouritesShareCard.footer(count: 10), "TOP 10 FAVOURITE BOOKS")
        XCTAssertEqual(FavouritesShareCard.footer(count: 1), "TOP 1 FAVOURITE BOOK")
    }

    func testTheImageIs1080PixelsWide() throws {
        let books = (1...10).map { Book(title: "Book \($0)", authors: ["A. Writer"]) }
        let story = try XCTUnwrap(ShareFavouritesSheet.render(books: books, name: "Kriti", format: .story))
        XCTAssertEqual(story.size.width * story.scale, 1080)
        XCTAssertEqual(story.size.height * story.scale, 1920)
        let square = try XCTUnwrap(ShareFavouritesSheet.render(books: books, name: "Kriti", format: .square))
        XCTAssertEqual(square.size.height * square.scale, 1080)
    }
}
