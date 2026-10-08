import XCTest
import UIKit
import SwiftData
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

    func testSmallCoversAreEnlargedForShowingBig() {
        XCTAssertEqual(CoverImage.enlarged(cover(width: 300), toWidth: 900)?.cgImage?.width, 900)
        XCTAssertEqual(CoverImage.enlarged(cover(width: 800), toWidth: 900)?.cgImage?.width, 800, "Near enough: left alone")
    }

    func testAppleBooksResultsCarryTitleAuthorAndALargeCover() {
        let json = #"{"results":[{"trackName":"Circe","artistName":"Madeline Miller","artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/a/b/cover.jpg/100x100bb.jpg"},{"trackName":"No art"}]}"#
        XCTAssertEqual(AppleBooksClient.parse(Data(json.utf8)), [
            AppleBook(title: "Circe", author: "Madeline Miller",
                      coverURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/a/b/cover.jpg/1200x1200bb.jpg")!),
        ])
        XCTAssertTrue(AppleBooksClient.parse(Data("oops".utf8)).isEmpty)
    }

    func testAnotherEditionMustBeTheSameTitleAndAuthor() {
        func edition(_ title: String, _ author: String) -> AppleBook {
            AppleBook(title: title, author: author, coverURL: URL(string: "https://example.com/c.jpg")!)
        }
        XCTAssertTrue(edition("The Housemaid", "Freida McFadden").isSameBook(title: "The Housemaid", author: "Freida McFadden"))
        XCTAssertFalse(edition("The Housemaid", "Sarah A. Denzil").isSameBook(title: "The Housemaid", author: "Freida McFadden"),
                       "Same title, different novel")
        XCTAssertFalse(edition("Perfect Fit", "Clare Gilmore").isSameBook(title: "Perfect", author: "Cecelia Ahern"))
        XCTAssertTrue(edition("The 12-Week MBA", "Bjorn Billhardt & Nathan Kracklauer").isSameBook(title: "12 Week MBA", author: "Bjorn Billhardt"))
        XCTAssertTrue(edition("Who Moved My Cheese?", "Spencer Johnson").isSameBook(title: "Who Moved My Cheese", author: "Dr Spencer Johnson"))
        XCTAssertTrue(edition("Quiet: The Power of Introverts", "Susan Cain").isSameBook(title: "Quiet", author: "Susan Cain"))
        XCTAssertFalse(edition("Circe", "Madeline Miller").isSameBook(title: "Circe", author: ""))
    }

    func testForeignEditionsAndAdaptationsAreSpotted() {
        func edition(_ title: String, author: String = "E L James", blurb: String = "") -> AppleBook {
            AppleBook(title: title, author: author, coverURL: URL(string: "https://example.com/c.jpg")!, blurb: blurb)
        }
        let english = "<b>E L James revisits the world of Fifty Shades with a deeper and darker take on the love story.</b>"
        XCTAssertTrue(edition("Grey", blurb: english).isEnglish)
        XCTAssertFalse(edition("Grey (En espanol)").isEnglish)
        XCTAssertFalse(edition("Grey", blurb: "Ve el mundo de Cincuenta sombras de Grey a través de los ojos de Christian Grey, en sus propias palabras.").isEnglish)
        XCTAssertFalse(edition("The Go-giver", blurb: "गो-गिवर आमतौर पर बड़े लाभ अर्जित करते हैं; क्योंकि वे देने में विश्वास रखते हैं।").isEnglish)
        XCTAssertTrue(edition("Grey").isEnglish, "No blurb to judge by: given the benefit of the doubt")

        XCTAssertTrue(edition("The Midnight Library", author: "Matt Haig & Fred Fordham").hasOtherAuthors(than: "Matt Haig"))
        XCTAssertFalse(edition("The Midnight Library", author: "Matt Haig").hasOtherAuthors(than: "Matt Haig"))
    }

    func testTheClosestSharpEditionIsChosen() {
        let current = cover(width: 300)
        let sameArt = cover(width: 900)
        let otherArt = cover(width: 1200, background: .systemBlue, band: .white)
        XCTAssertEqual(CoverImage.closestSharp(to: current, among: [otherArt, sameArt]), sameArt, "The same artwork wins")
        XCTAssertEqual(CoverImage.closestSharp(to: current, among: [otherArt]), otherArt, "Another edition is better than blurry")
        XCTAssertNil(CoverImage.closestSharp(to: current, among: [cover(width: 400)]), "Not sharp enough to bother")
        XCTAssertNil(CoverImage.closestSharp(to: current, among: []))
    }
}

@MainActor
final class CoverUpgradePassTests: XCTestCase {
    private struct FakeFinder: SharperCoverFinding {
        let sharp: Data?
        func sharperCover(than current: Data, title: String, author: String?, isbn: String?) async -> Data? { sharp }
    }

    private var container: ModelContainer!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        container = try ModelContainer(
            for: Book.self, BookCategory.self, DeletedBook.self, Loan.self, ReadingEntry.self, Bookstore.self, DeletedBookstore.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        defaults = UserDefaults(suiteName: "CoverUpgradePassTests")
        defaults.removePersistentDomain(forName: "CoverUpgradePassTests")
    }

    private func cover(width: CGFloat, color: UIColor = .systemRed) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: width, height: width * 1.5)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.9)!
    }

    private func book(_ title: String, cover: Data?, custom: Bool = false) -> Book {
        let book = Book(title: title, authors: ["A. Writer"], coverImage: cover)
        book.coverIsCustom = custom
        container.mainContext.insert(book)
        return book
    }

    func testBlurryCoversAreSwappedAndTheOldOneKept() async {
        let small = cover(width: 300), sharp = cover(width: 900, color: .systemBlue)
        let blurry = book("Blurry", cover: small)
        let fine = book("Fine", cover: cover(width: 800))
        let mine = book("Mine", cover: small, custom: true)
        let bare = book("Bare", cover: nil)

        await CoverUpgrade().run(in: container.mainContext, finder: FakeFinder(sharp: sharp), defaults: defaults)

        XCTAssertEqual(blurry.coverImage, sharp)
        XCTAssertEqual(blurry.previousCoverImage, small, "Kept so it can be put back")
        XCTAssertEqual(fine.previousCoverImage, nil, "Already sharp: untouched")
        XCTAssertEqual(mine.coverImage, small, "A cover set by hand is never swapped")
        XCTAssertNil(bare.coverImage)
    }

    func testABookWithNothingFoundIsNotTriedAgainUnlessAsked() async {
        let small = cover(width: 300)
        let blurry = book("Blurry", cover: small)
        let upgrade = CoverUpgrade()
        await upgrade.run(in: container.mainContext, finder: FakeFinder(sharp: nil), defaults: defaults)
        XCTAssertEqual(blurry.coverImage, small)

        let sharp = cover(width: 900)
        await upgrade.run(in: container.mainContext, finder: FakeFinder(sharp: sharp), defaults: defaults)
        XCTAssertEqual(blurry.coverImage, small, "Already checked on this device")

        await upgrade.run(in: container.mainContext, finder: FakeFinder(sharp: sharp), defaults: defaults, retryingChecked: true)
        XCTAssertEqual(blurry.coverImage, sharp, "Sharpen covers tries everything again")
        XCTAssertFalse(upgrade.isRunning)
    }
}
