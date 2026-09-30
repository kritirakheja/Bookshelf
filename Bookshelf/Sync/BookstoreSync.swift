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
    var deleted: Bool = false
    /// Set by the server; never sent.
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, address, city, latitude, longitude, phone, website, note, deleted
        case dateSaved = "date_saved"
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
        try c.encode(deleted, forKey: .deleted)
    }
}

extension BookstoreRecord {
    init(store: Bookstore) {
        self.init(id: store.id, name: store.name, address: store.address, city: store.city,
                  latitude: store.latitude, longitude: store.longitude, phone: store.phone,
                  website: store.website, note: store.note, dateSaved: store.dateSaved)
    }
}

/// Two-way sync of saved bookstores, with the same rules as books (see `SyncEngine`):
/// pull first, applying online changes to stores not changed here; then push stores
/// changed here; removals travel as a `deleted` flag.
@MainActor
struct BookstoreSync {
    let context: ModelContext
    let remote: SyncRemote

    static func fingerprint(of store: Bookstore) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return SyncHash.of((try? encoder.encode(BookstoreRecord(store: store))) ?? Data())
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
            store.syncedFingerprint = Self.fingerprint(of: store)
        }

        let changed = stores.filter(hasLocalChanges)
        try await remote.upsertBookstores(changed.map(BookstoreRecord.init(store:)))
        changed.forEach { $0.syncedFingerprint = Self.fingerprint(of: $0) }
        try context.save()
        return newest
    }
}
