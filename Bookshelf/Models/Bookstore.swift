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
}

/// Left behind when a synced bookstore is removed, so the removal reaches the backup.
@Model
final class DeletedBookstore {
    var remoteID: UUID

    init(remoteID: UUID) {
        self.remoteID = remoteID
    }
}
