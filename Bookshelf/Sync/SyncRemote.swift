import Foundation
import Supabase

/// The online side of sync. `SupabaseRemote` is the real one; tests use a fake.
protocol SyncRemote {
    /// Rows changed after the given server time (all rows when nil), oldest first.
    func fetchBooks(updatedAfter: Date?) async throws -> [BookRecord]
    func upsertBooks(_ records: [BookRecord]) async throws
    func markBooksDeleted(_ ids: [UUID]) async throws
    func fetchProfile() async throws -> ProfileRecord?
    func upsertProfile(_ profile: ProfileRecord) async throws
    func uploadFile(_ data: Data, path: String) async throws
    func downloadFile(path: String) async throws -> Data
    func removeFiles(paths: [String]) async throws
}

struct ProfileRecord: Codable, Equatable {
    var userID: UUID?
    var name: String
    var photoPath: String?
    var photoHash: String?

    enum CodingKeys: String, CodingKey {
        case name
        case userID = "user_id"
        case photoPath = "photo_path"
        case photoHash = "photo_hash"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(userID, forKey: .userID)
        try c.encode(name, forKey: .name)
        try c.encode(photoPath, forKey: .photoPath)
        try c.encode(photoHash, forKey: .photoHash)
    }
}

struct SupabaseRemote: SyncRemote {
    let client: SupabaseClient
    private static let bucket = "library"

    /// Millisecond precision: rounding down means the newest row may be fetched again
    /// (harmless), but never skipped.
    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded(.down) / 1000))
    }
    private static let pageSize = 500

    func fetchBooks(updatedAfter: Date?) async throws -> [BookRecord] {
        var all: [BookRecord] = []
        var from = 0
        while true {
            var query = client.from("books").select()
            if let updatedAfter {
                query = query.gt("updated_at", value: Self.timestamp(updatedAfter))
            }
            let page: [BookRecord] = try await query
                .order("updated_at")
                .order("id")
                .range(from: from, to: from + Self.pageSize - 1)
                .execute()
                .value
            all += page
            if page.count < Self.pageSize { return all }
            from += Self.pageSize
        }
    }

    func upsertBooks(_ records: [BookRecord]) async throws {
        guard !records.isEmpty else { return }
        for batch in records.chunked(into: Self.pageSize) {
            try await client.from("books").upsert(batch, returning: .minimal).execute()
        }
    }

    func markBooksDeleted(_ ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try await client.from("books")
            .update(["deleted": true])
            .in("id", values: ids.map { $0.uuidString.lowercased() })
            .execute()
    }

    func fetchProfile() async throws -> ProfileRecord? {
        let rows: [ProfileRecord] = try await client.from("profiles").select().limit(1).execute().value
        return rows.first
    }

    func upsertProfile(_ profile: ProfileRecord) async throws {
        try await client.from("profiles").upsert(profile, returning: .minimal).execute()
    }

    func uploadFile(_ data: Data, path: String) async throws {
        try await client.storage.from(Self.bucket)
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
    }

    func downloadFile(path: String) async throws -> Data {
        try await client.storage.from(Self.bucket).download(path: path)
    }

    func removeFiles(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        _ = try await client.storage.from(Self.bucket).remove(paths: paths)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
