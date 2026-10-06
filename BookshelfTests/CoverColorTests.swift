import XCTest
import UIKit
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

    func testBarcodeIsDrawnForAnISBN() {
        XCTAssertNotNil(BookArt.barcode(for: "9780141439518"))
    }
}
