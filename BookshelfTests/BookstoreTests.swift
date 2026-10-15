import XCTest
import SwiftData
import CoreLocation
import UIKit
@testable import Bookshelf

@MainActor
final class BookstoreTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: Book.self, BookCategory.self, DeletedBook.self, Loan.self, ReadingEntry.self, Bookstore.self, DeletedBookstore.self, BookstorePhoto.self,
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

    func testRatingsAndPhotosSyncBetweenDevices() async throws {
        let remote = FakeRemote()
        let user = UUID()
        let phone = try container(), ipad = try container()
        let phoneSync = BookstoreSync(context: phone.mainContext, remote: remote, userID: user)
        let ipadSync = BookstoreSync(context: ipad.mainContext, remote: remote, userID: user)

        let store = BookstoreSearch.save(blossom, in: phone.mainContext, existing: [])
        store.readingRating = 4
        store.coffeeRating = 2
        let photo = BookstorePhoto(data: Data("shelves".utf8))
        phone.mainContext.insert(photo)
        photo.store = store
        var phonePulled = try await phoneSync.sync(lastPulledAt: nil)
        XCTAssertEqual(remote.uploads, 1, "The new photo is uploaded")
        XCTAssertEqual(photo.remotePath, BookstoreSync.photoPath(user: user, store: store.id, photo: photo.id))

        var ipadPulled = try await ipadSync.sync(lastPulledAt: nil)
        let copy = try XCTUnwrap(try ipad.mainContext.fetch(FetchDescriptor<Bookstore>()).first)
        XCTAssertEqual(copy.readingRating, 4)
        XCTAssertEqual(copy.coffeeRating, 2)
        XCTAssertEqual(copy.sortedPhotos.map(\.data), [Data("shelves".utf8)])
        XCTAssertEqual(copy.sortedPhotos.first?.id, photo.id)

        // Nothing changed: syncing again uploads nothing.
        phonePulled = try await phoneSync.sync(lastPulledAt: phonePulled)
        XCTAssertEqual(remote.uploads, 1)

        // Deleting the photo and clearing a rating on the iPad reaches the phone.
        ipad.mainContext.delete(try XCTUnwrap(copy.sortedPhotos.first))
        copy.coffeeRating = nil
        ipadPulled = try await ipadSync.sync(lastPulledAt: ipadPulled)
        _ = try await phoneSync.sync(lastPulledAt: phonePulled)
        XCTAssertNil(store.coffeeRating)
        XCTAssertTrue(store.sortedPhotos.isEmpty)
    }

    func testAPhotoWaitingToUploadCountsAsAChange() throws {
        let container = try container()   // kept alive for the whole test
        let context = container.mainContext
        let store = BookstoreSearch.save(blossom, in: context, existing: [])
        store.syncedFingerprint = BookstoreSync.fingerprint(of: store)
        let sync = BookstoreSync(context: context, remote: FakeRemote())
        XCTAssertFalse(sync.hasLocalChanges(store))

        let photo = BookstorePhoto(data: Data([1]))
        context.insert(photo)
        photo.store = store
        XCTAssertTrue(sync.hasLocalChanges(store))
        XCTAssertTrue(BookstoreRecord(store: store).photoIDs.isEmpty, "Not listed until it's uploaded")

        store.syncedFingerprint = BookstoreSync.fingerprint(of: store)
        store.readingRating = 5
        XCTAssertTrue(sync.hasLocalChanges(store), "A rating is a change too")
    }

    func testOlderRowsWithoutTheNewColumnsStillDecode() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Atta Galatta","address":"","city":"","latitude":1,"longitude":2,
         "note":"","date_saved":"2026-10-01T10:00:00Z","deleted":false}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(BookstoreRecord.self, from: Data(json.utf8))
        XCTAssertNil(record.readingRating)
        XCTAssertEqual(record.photoIDs, [])
    }

    // MARK: Google photos

    func testGooglePlaceMustBeTheSameShopNearby() throws {
        let json = """
        {"places":[
          {"id":"cafe","displayName":{"text":"Matteo Coffea"},"location":{"latitude":12.97561,"longitude":77.60502}},
          {"id":"far","displayName":{"text":"Blossom Book House"},"location":{"latitude":12.99,"longitude":77.62}},
          {"id":"right","displayName":{"text":"Blossom Book House"},"location":{"latitude":12.97565,"longitude":77.60508}}
        ]}
        """
        let places = try GooglePlacesClient.parsePlaces(Data(json.utf8))
        let here = CLLocationCoordinate2D(latitude: 12.9756, longitude: 77.6050)
        XCTAssertEqual(GooglePlacesClient.match(places, name: "Blossom Book House", near: here)?.id, "right",
                       "Not the café next door, not a branch across town")
        XCTAssertNil(GooglePlacesClient.match(Array(places.prefix(2)), name: "Blossom Book House", near: here))
    }

    func testGooglePhotoCreditsAreRead() throws {
        let json = """
        {"photos":[{"name":"places/x/photos/1","authorAttributions":[{"displayName":"Priya S."}]},{"name":"places/x/photos/2"}]}
        """
        let refs = try GooglePlacesClient.parsePhotos(Data(json.utf8))
        XCTAssertEqual(refs.map(\.name), ["places/x/photos/1", "places/x/photos/2"])
        XCTAssertEqual(refs.first?.authorAttributions?.first?.displayName, "Priya S.")
    }

    func testWithoutAFinderThereAreNoGooglePhotos() async throws {
        let container = try container()
        let store = BookstoreSearch.save(blossom, in: container.mainContext, existing: [])
        let photos = await PlacePhotoCache.photos(for: store, finder: nil)
        XCTAssertTrue(photos.isEmpty)
        XCTAssertNil(store.googlePlaceID)
    }

    func testThePlaceIsLookedUpOnceAndRemembered() async throws {
        final class Finder: PlacePhotoFinding {
            var searches = 0
            func placeID(name: String, address: String, near coordinate: CLLocationCoordinate2D) async -> String? {
                searches += 1
                return "place-1"
            }
            func photos(placeID: String, limit: Int) async -> [PlacePhoto] {
                [PlacePhoto(image: UIImage(), credit: "Priya S.")]
            }
        }
        let finder = Finder()
        let container = try container()
        let store = BookstoreSearch.save(blossom, in: container.mainContext, existing: [])
        let photos = await PlacePhotoCache.photos(for: store, finder: finder)
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(store.googlePlaceID, "place-1")
        _ = await PlacePhotoCache.photos(for: store, finder: finder)
        XCTAssertEqual(finder.searches, 1)
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
