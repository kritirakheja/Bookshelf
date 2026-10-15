import Foundation
import SwiftData
import CoreLocation

/// A bookstore saved on the Bookstores map.
@Model
final class Bookstore {
    /// Also the store's id in the online backup.
    var id: UUID = UUID()
    var name: String
    var address: String = ""
    var city: String = ""
    var latitude: Double
    var longitude: Double
    var phone: String?
    var website: String?
    /// Kriti's own words ("great second-hand section").
    var note: String = ""
    /// 1–5: a place to sit and read a book (seats, quiet, can you stay a while).
    var readingRating: Int?
    /// 1–5: a good coffee shop nearby.
    var coffeeRating: Int?
    /// The shop on Google Maps, found once, for showing its photos.
    var googlePlaceID: String?
    /// Photos you took or picked (Google's are shown, never stored).
    @Relationship(deleteRule: .cascade, inverse: \BookstorePhoto.store)
    var photos: [BookstorePhoto]? = []
    var dateSaved: Date = Date.now
    /// Fingerprint of the store at the last sync; differs once edited.
    var syncedFingerprint: String?

    init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    /// Your photos, oldest first.
    var sortedPhotos: [BookstorePhoto] {
        (photos ?? []).sorted { $0.addedAt < $1.addedAt }
    }
}

/// A photo of a bookstore that you took or picked.
@Model
final class BookstorePhoto {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var data: Data
    var addedAt: Date = Date.now
    /// Where it's kept in the online backup, once uploaded.
    var remotePath: String?
    var store: Bookstore?

    init(data: Data) {
        self.data = data
    }
}

/// Left behind when a synced bookstore is removed, so the removal reaches the backup.
@Model
final class DeletedBookstore {
    var remoteID: UUID

    init(remoteID: UUID) {
        self.remoteID = remoteID
    }
}
