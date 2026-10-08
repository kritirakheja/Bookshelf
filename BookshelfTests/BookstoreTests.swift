import XCTest
import SwiftData
import CoreLocation
@testable import Bookshelf

@MainActor
final class BookstoreTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: Book.self, BookCategory.self, DeletedBook.self, Loan.self, ReadingEntry.self, Bookstore.self, DeletedBookstore.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private let blossom = BookstoreResult(name: "Blossom Book House", address: "Church Street, Bengaluru", city: "Bengaluru",
                                          latitude: 12.9756, longitude: 77.6050, phone: "+91 80 4127 1234", website: "https://blossombookhouse.com")

    func testSavingAResultCopiesItsDetails() throws {
        let container = try container()
        let store = BookstoreSearch.save(blossom, in: container.mainContext, existing: [])
        XCTAssertEqual(store.name, "Blossom Book House")
        XCTAssertEqual(store.address, "Church Street, Bengaluru")
        XCTAssertEqual(store.city, "Bengaluru")
        XCTAssertEqual(store.phone, "+91 80 4127 1234")
        XCTAssertEqual(store.latitude, 12.9756, accuracy: 0.00001)
    }

    func testTheSameShopIsntSavedTwice() throws {
        let container = try container()
        let context = container.mainContext
        let first = BookstoreSearch.save(blossom, in: context, existing: [])
        var nearlyTheSame = blossom
        nearlyTheSame.latitude += 0.0003   // ~35 m away: same shop, slightly different pin
        let second = BookstoreSearch.save(nearlyTheSame, in: context, existing: [first])
        XCTAssertTrue(first === second)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Bookstore>()), 1)

        var branch = blossom
        branch.latitude += 0.05   // ~5 km away: a different branch
        XCTAssertNil(BookstoreSearch.saved(branch, in: [first]))
    }

    func testDistanceText() {
        XCTAssertEqual(BookstoreSearch.distanceText(347), "350 m")
        XCTAssertEqual(BookstoreSearch.distanceText(2_430), "2.4 km")
    }

    func testGoogleMapsLink() {
        let url = BookstoreSearch.googleMapsURL(name: "Blossom Book House", address: "Church Street", latitude: 0, longitude: 0)
        XCTAssertEqual(url.absoluteString, "https://www.google.com/maps/search/?api=1&query=Blossom%20Book%20House,%20Church%20Street")
    }

    func testBookstoresSyncBetweenDevices() async throws {
        let remote = FakeRemote()
        let phone = try container(), ipad = try container()
        let phoneSync = BookstoreSync(context: phone.mainContext, remote: remote)
        let ipadSync = BookstoreSync(context: ipad.mainContext, remote: remote)

        let store = BookstoreSearch.save(blossom, in: phone.mainContext, existing: [])
        var phonePulled = try await phoneSync.sync(lastPulledAt: nil)
        var ipadPulled = try await ipadSync.sync(lastPulledAt: nil)
        let copy = try XCTUnwrap(try ipad.mainContext.fetch(FetchDescriptor<Bookstore>()).first)
        XCTAssertEqual(copy.name, "Blossom Book House")
        XCTAssertEqual(copy.id, store.id)

        // A note added on the iPad reaches the phone.
        copy.note = "Three floors of second-hand books"
        ipadPulled = try await ipadSync.sync(lastPulledAt: ipadPulled)
        phonePulled = try await phoneSync.sync(lastPulledAt: phonePulled)
        XCTAssertEqual(store.note, "Three floors of second-hand books")

        // Removing it on the phone removes it on the iPad.
        phone.mainContext.deleteBookstore(store)
        _ = try await phoneSync.sync(lastPulledAt: phonePulled)
        _ = try await ipadSync.sync(lastPulledAt: ipadPulled)
        XCTAssertEqual(try ipad.mainContext.fetchCount(FetchDescriptor<Bookstore>()), 0)
    }

    /// Real Apple Maps search. Run with TEST_RUNNER_LIVE_TESTS=1.
    func testLiveFindsBookstoresInBangalore() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE_TESTS"] == "1", "Set LIVE_TESTS=1")
        let churchStreet = CLLocationCoordinate2D(latitude: 12.9756, longitude: 77.6050)
        let found = try await BookstoreSearch.nearby(center: churchStreet)
        print("STORES near Church Street: " + found.prefix(8).map { "\($0.name) (\($0.address))" }.joined(separator: " | "))
        XCTAssertFalse(found.isEmpty)
        let byName = try await BookstoreSearch.named("Blossom Book House", near: churchStreet)
        print("STORES named: " + byName.prefix(3).map(\.name).joined(separator: " | "))
        XCTAssertTrue(byName.contains { $0.name.localizedCaseInsensitiveContains("Blossom") })
    }
}
