import Foundation
import SwiftData

/// A saved bookstore as stored online (one row of the `bookstores` table).
struct BookstoreRecord: Codable, Equatable {
    var id: UUID
    var name: String
    var address: String
    var city: String
    var latitude: Double
    var longitude: Double
    var phone: String?
    var website: String?
    var note: String
    var dateSaved: Date
    var readingRating: Int?
    var coffeeRating: Int?
    var googlePlaceID: String?
    /// Your photos, by id; each is a file at `BookstoreSync.photoPath`.
    var photoIDs: [UUID] = []
    var deleted: Bool = false
    /// Set by the server; never sent.
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, address, city, latitude, longitude, phone, website, note, deleted
        case dateSaved = "date_saved"
        case readingRating = "reading_rating"
        case coffeeRating = "coffee_rating"
        case googlePlaceID = "google_place_id"
        case photoIDs = "photo_ids"
        case updatedAt = "updated_at"
    }

    /// Explicit nulls, so clearing a field reaches the server; `updated_at` is the server's.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(address, forKey: .address)
        try c.encode(city, forKey: .city)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(phone, forKey: .phone)
        try c.encode(website, forKey: .website)
        try c.encode(note, forKey: .note)
        try c.encode(dateSaved, forKey: .dateSaved)
        try c.encode(readingRating, forKey: .readingRating)
        try c.encode(coffeeRating, forKey: .coffeeRating)
        try c.encode(googlePlaceID, forKey: .googlePlaceID)
        try c.encode(photoIDs, forKey: .photoIDs)
        try c.encode(deleted, forKey: .deleted)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        address = try c.decode(String.self, forKey: .address)
        city = try c.decode(String.self, forKey: .city)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        website = try c.decodeIfPresent(String.self, forKey: .website)
        note = try c.decode(String.self, forKey: .note)
        dateSaved = try c.decode(Date.self, forKey: .dateSaved)
        readingRating = try c.decodeIfPresent(Int.self, forKey: .readingRating)
        coffeeRating = try c.decodeIfPresent(Int.self, forKey: .coffeeRating)
        googlePlaceID = try c.decodeIfPresent(String.self, forKey: .googlePlaceID)
        photoIDs = try c.decodeIfPresent([UUID].self, forKey: .photoIDs) ?? []
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    init(id: UUID, name: String, address: String, city: String, latitude: Double, longitude: Double,
         phone: String?, website: String?, note: String, dateSaved: Date, readingRating: Int? = nil,
         coffeeRating: Int? = nil, googlePlaceID: String? = nil, photoIDs: [UUID] = [],
         deleted: Bool = false, updatedAt: Date? = nil) {
        self.id = id; self.name = name; self.address = address; self.city = city
        self.latitude = latitude; self.longitude = longitude; self.phone = phone; self.website = website
        self.note = note; self.dateSaved = dateSaved; self.readingRating = readingRating
        self.coffeeRating = coffeeRating; self.googlePlaceID = googlePlaceID; self.photoIDs = photoIDs
        self.deleted = deleted; self.updatedAt = updatedAt
    }
}

extension BookstoreRecord {
    init(store: Bookstore) {
        self.init(id: store.id, name: store.name, address: store.address, city: store.city,
                  latitude: store.latitude, longitude: store.longitude, phone: store.phone,
                  website: store.website, note: store.note, dateSaved: store.dateSaved,
                  readingRating: store.readingRating, coffeeRating: store.coffeeRating,
                  googlePlaceID: store.googlePlaceID,
                  // Only photos already uploaded, so another device never looks for a missing file.
                  photoIDs: store.sortedPhotos.filter { $0.remotePath != nil }.map(\.id))
    }
}

/// Two-way sync of saved bookstores, with the same rules as books (see `SyncEngine`):
/// pull first, applying online changes to stores not changed here; then push stores
/// changed here; removals travel as a `deleted` flag.
@MainActor
struct BookstoreSync {
    let context: ModelContext
    let remote: SyncRemote
    /// Whose backup: photo files live in this user's folder. Without it, photos stay on this phone.
    var userID: UUID?

    static func photoPath(user: UUID, store: UUID, photo: UUID) -> String {
        "\(user.uuidString.lowercased())/bookstores/\(store.uuidString.lowercased())/\(photo.uuidString.lowercased()).jpg"
    }

    static func fingerprint(of store: Bookstore) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let record = (try? encoder.encode(BookstoreRecord(store: store))) ?? Data()
        // A photo waiting to upload counts as a change, so the next sync tries again.
        let waiting = (store.photos ?? []).filter { $0.remotePath == nil }.count
        return SyncHash.of(record + Data("|\(waiting)".utf8))
    }

    func hasLocalChanges(_ store: Bookstore) -> Bool {
        store.syncedFingerprint != Self.fingerprint(of: store)
    }

    /// Returns the newest server time seen, to pull from next time.
    func sync(lastPulledAt: Date?) async throws -> Date? {
        let tombstones = try context.fetch(FetchDescriptor<DeletedBookstore>())
        if !tombstones.isEmpty {
            try await remote.markBookstoresDeleted(tombstones.map(\.remoteID))
            tombstones.forEach(context.delete)
        }

        var stores = try context.fetch(FetchDescriptor<Bookstore>())
        var newest = lastPulledAt
        for row in try await remote.fetchBookstores(updatedAfter: lastPulledAt) {
            if let updated = row.updatedAt, newest.map({ updated > $0 }) ?? true { newest = updated }
            let local = stores.first { $0.id == row.id }
            if let local, hasLocalChanges(local) { continue }   // changed here: ours wins, pushed below
            if row.deleted {
                if let local {
                    stores.removeAll { $0 === local }
                    context.delete(local)
                }
                continue
            }
            let store = local ?? {
                let created = Bookstore(name: row.name, latitude: row.latitude, longitude: row.longitude)
                created.id = row.id
                context.insert(created)
                stores.append(created)
                return created
            }()
            store.name = row.name
            store.address = row.address
            store.city = row.city
            store.latitude = row.latitude
            store.longitude = row.longitude
            store.phone = row.phone
            store.website = row.website
            store.note = row.note
            store.dateSaved = row.dateSaved
            store.readingRating = row.readingRating
            store.coffeeRating = row.coffeeRating
            store.googlePlaceID = row.googlePlaceID
            await pullPhotos(row.photoIDs, into: store)
            store.syncedFingerprint = Self.fingerprint(of: store)
        }

        let changed = stores.filter(hasLocalChanges)
        for store in changed { await pushPhotos(of: store) }
        try await remote.upsertBookstores(changed.map(BookstoreRecord.init(store:)))
        changed.forEach { $0.syncedFingerprint = Self.fingerprint(of: $0) }
        try context.save()
        return newest
    }

    /// Makes this store's photos match the backup's list: downloads new ones, and drops
    /// ones removed on another device. Photos not uploaded yet are kept.
    private func pullPhotos(_ ids: [UUID], into store: Bookstore) async {
        guard let userID else { return }
        for photo in store.photos ?? [] where photo.remotePath != nil && !ids.contains(photo.id) {
            context.delete(photo)
        }
        let have = Set((store.photos ?? []).map(\.id))
        for id in ids where !have.contains(id) {
            let path = Self.photoPath(user: userID, store: store.id, photo: id)
            guard let data = try? await remote.downloadFile(path: path) else { continue }
            let photo = BookstorePhoto(data: data)
            photo.id = id
            photo.remotePath = path
            context.insert(photo)
            photo.store = store
        }
    }

    /// Uploads photos added on this phone.
    private func pushPhotos(of store: Bookstore) async {
        guard let userID else { return }
        for photo in store.photos ?? [] where photo.remotePath == nil {
            let path = Self.photoPath(user: userID, store: store.id, photo: photo.id)
            if (try? await remote.uploadFile(photo.data, path: path)) != nil {
                photo.remotePath = path
            }
        }
    }
}
