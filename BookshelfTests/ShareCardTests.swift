import XCTest
import SwiftData
@testable import Bookshelf

@MainActor
final class ShareCardTests: XCTestCase {
    func testTitleWording() {
        XCTAssertEqual(FavouritesShareCard.owner("Kriti"), "KRITI’S")
        XCTAssertEqual(FavouritesShareCard.owner("  Kriti Rakheja "), "KRITI’S")
        XCTAssertEqual(FavouritesShareCard.owner("James"), "JAMES’")
        XCTAssertEqual(FavouritesShareCard.owner(""), "MY")
        XCTAssertEqual(FavouritesShareCard.footer, "TOP 10 FAVOURITE BOOKS", "Always Top 10, as she asked")
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
