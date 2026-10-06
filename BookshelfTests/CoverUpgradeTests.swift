import XCTest
import UIKit
@testable import Bookshelf

final class CoverUpgradeTests: XCTestCase {
    /// A made-up cover: a coloured background with a contrasting band, at any size.
    private func cover(width: CGFloat, background: UIColor = .systemRed, band: UIColor = .yellow) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: width, height: width * 1.5)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            band.setFill()
            context.fill(CGRect(x: 0, y: size.height * 0.3, width: size.width, height: size.height * 0.2))
        }.jpegData(compressionQuality: 0.9)!
    }

    func testPixelWidth() {
        XCTAssertEqual(CoverImage.pixelWidth(of: cover(width: 300)), 300)
        XCTAssertNil(CoverImage.pixelWidth(of: Data("nope".utf8)))
    }

    func testWideCoversAreScaledDownAndSmallOnesLeftAlone() {
        let small = cover(width: 600)
        XCTAssertEqual(CoverImage.capped(small), small)
        XCTAssertEqual(CoverImage.pixelWidth(of: CoverImage.capped(cover(width: 2000))), 1200)
    }

    func testASharperCopyOfTheSameCoverIsAccepted() {
        XCTAssertTrue(CoverImage.isSharperCopy(cover(width: 1200), of: cover(width: 300)))
    }

    func testADifferentCoverIsRejectedHoweverSharp() {
        let other = cover(width: 1200, background: .systemBlue, band: .white)
        XCTAssertFalse(CoverImage.isSharperCopy(other, of: cover(width: 300)))
    }

    func testTheSameCoverBarelyLargerIsNotWorthSwapping() {
        XCTAssertFalse(CoverImage.isSharperCopy(cover(width: 330), of: cover(width: 300)))
    }
}
