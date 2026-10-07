import XCTest
import UIKit
import SwiftUI
@testable import Bookshelf

final class CoverColorTests: XCTestCase {
    private func solidImage(_ color: UIColor) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }.pngData()!
    }

    func testAverageOfASolidCoverIsThatColour() {
        let average = CoverColor.average(of: solidImage(UIColor(red: 0.8, green: 0.2, blue: 0.4, alpha: 1)))
        XCTAssertEqual(average.r, 0.8, accuracy: 0.03)
        XCTAssertEqual(average.g, 0.2, accuracy: 0.03)
        XCTAssertEqual(average.b, 0.4, accuracy: 0.03)
    }

    func testNoCoverUsesTheFallback() {
        XCTAssertEqual(CoverColor.average(of: nil), CoverColor.fallback)
        XCTAssertEqual(CoverColor.average(of: Data("not an image".utf8)), CoverColor.fallback)
    }

    func testTextColourContrastsWithTheCover() {
        XCTAssertTrue(CoverColor.prefersLightText(on: .init(r: 0.1, g: 0.1, b: 0.3)), "Dark cover, white text")
        XCTAssertTrue(CoverColor.prefersLightText(on: CoverColor.fallback))
        XCTAssertFalse(CoverColor.prefersLightText(on: .init(r: 1, g: 0.95, b: 0.7)), "Pale cover, black text")
        XCTAssertFalse(CoverColor.prefersLightText(on: .init(r: 1, g: 1, b: 1)))
    }

    /// A cover that is `background` with a band of `band` across the middle third.
    private func cover(background: UIColor, band: UIColor) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 60, height: 90), format: format).image { context in
            background.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 90))
            band.setFill()
            context.fill(CGRect(x: 0, y: 30, width: 60, height: 30))
        }.pngData()!
    }

    func testAccentIsTheVividColourNotTheBackground() throws {
        let red = try XCTUnwrap(CoverColor.accent(of: cover(background: .white, band: UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))))
        XCTAssertGreaterThan(red.r, 0.8)
        XCTAssertLessThan(red.g, 0.2)

        let blue = try XCTUnwrap(CoverColor.accent(of: cover(background: .gray, band: UIColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1))))
        XCTAssertGreaterThan(blue.b, 0.8)
        XCTAssertLessThan(blue.r, 0.2)
    }

    func testACoverWithoutColourHasNoAccent() {
        XCTAssertNil(CoverColor.accent(of: cover(background: .white, band: .black)))
        XCTAssertNil(CoverColor.accent(of: solidImage(.darkGray)))
        XCTAssertNil(CoverColor.accent(of: nil))
        XCTAssertNil(CoverColor.accent(of: Data("not an image".utf8)))
    }

    func testAccentIsMadeReadableOnThePage() {
        let lightPage = CoverColor.RGB(r: 0.97, g: 0.97, b: 0.96)
        let darkPage = CoverColor.RGB(r: 0.06, g: 0.06, b: 0.06)

        let paleYellow = CoverColor.RGB(r: 1, g: 0.9, b: 0.3)
        let darkened = CoverColor.legible(paleYellow, on: lightPage)
        XCTAssertGreaterThanOrEqual(CoverColor.contrast(darkened, lightPage), CoverColor.readableContrast)
        XCTAssertLessThan(darkened.r, paleYellow.r)
        XCTAssertGreaterThan(darkened.r, darkened.b, "Still a yellow, only darker")

        let navy = CoverColor.RGB(r: 0.05, g: 0.1, b: 0.4)
        let lightened = CoverColor.legible(navy, on: darkPage)
        XCTAssertGreaterThanOrEqual(CoverColor.contrast(lightened, darkPage), CoverColor.readableContrast)
        XCTAssertGreaterThan(lightened.b, lightened.r, "Still a blue, only lighter")

        XCTAssertEqual(CoverColor.legible(navy, on: lightPage), navy, "Already readable: left alone")
    }

    func testContrastRunsFromOneToTwentyOne() {
        let black = CoverColor.RGB(r: 0, g: 0, b: 0), white = CoverColor.RGB(r: 1, g: 1, b: 1)
        XCTAssertEqual(CoverColor.contrast(black, white), 21, accuracy: 0.01)
        XCTAssertEqual(CoverColor.contrast(white, white), 1, accuracy: 0.01)
    }

    @MainActor
    func testABookWithoutAColourfulCoverUsesTheAppGreen() {
        XCTAssertEqual(Book(title: "No cover").accentColor(for: .light), Theme.accent)
        XCTAssertEqual(Book(title: "Grey", coverImage: solidImage(.darkGray)).accentColor(for: .light), Theme.accent)
        let red = Book(title: "Red", coverImage: solidImage(UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)))
        XCTAssertNotEqual(red.accentColor(for: .light), Theme.accent)
    }

    func testBarcodeIsDrawnForAnISBN() {
        XCTAssertNotNil(BookArt.barcode(for: "9780141439518"))
    }
}
