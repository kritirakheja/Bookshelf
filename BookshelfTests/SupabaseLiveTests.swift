import XCTest
import SwiftData
import Supabase
@testable import Bookshelf

/// End-to-end sync against the real Supabase project in Config/Local.xcconfig.
/// Creates throwaway accounts, then deletes their data (the accounts themselves can be
/// removed under Authentication → Users). Run with TEST_RUNNER_LIVE_TESTS=1.
@MainActor
final class SupabaseLiveTests: XCTestCase {
    /// Built exactly like the app's client, except the login isn't kept in the keychain.
    private func makeClient() throws -> SupabaseClient {
        try XCTUnwrap(AccountStore.makeClient(authStorage: InMemoryAuthStorage()), "No Supabase settings in this build")
    }

    private func signUpThrowaway(_ client: SupabaseClient) async throws -> UUID {
        let email = "bookshelf-test-\(UUID().uuidString.prefix(8).lowercased())@example.com"
        guard case .session(let session) = try await client.auth.signUp(email: email, password: "Test-\(UUID().uuidString)") else {
            throw XCTSkip("Sign-up needs email confirmation; turn off Confirm email to run this test")
        }
        return session.user.id
    }

    private func cleanUp(_ client: SupabaseClient, userID: UUID) async throws {
        let folder = userID.uuidString.lowercased()
        let covers = try await client.storage.from("library").list(path: "\(folder)/covers").map { "\(folder)/covers/\($0.name)" }
        _ = try? await client.storage.from("library").remove(paths: covers + ["\(folder)/profile.jpg"])
        try await client.from("books").delete().neq("id", value: UUID(uuid: UUID_NULL).uuidString).execute()
        try await client.from("profiles").delete().eq("user_id", value: folder).execute()
        try? await client.from("bookstores").delete().neq("id", value: UUID(uuid: UUID_NULL).uuidString).execute()
        try? await client.auth.signOut()
    }

    func testLiveSyncRoundTrip() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE_TESTS"] == "1", "Set LIVE_TESTS=1 to call Supabase")
        let client = try makeClient()
        let userID = try await signUpThrowaway(client)
        let remote = SupabaseRemote(client: client)
        let phone = try Device(remote: remote, userID: userID)
        let ipad = try Device(remote: remote, userID: userID)
        let cover = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }.jpegData(compressionQuality: 0.9))

        do {
            // Phone backs up two books, one with a cover and categories.
            let dune = phone.add("Dune", author: "Frank Herbert", isbn: "9780441013593", cover: cover)
            dune.setStatus(.read)
            dune.rating = 5
            dune.categories = [try XCTUnwrap(BookCategory.named("Science Fiction", in: phone.context))]
            FavoritesShelf.add(dune, library: phone.books)
            phone.add("Circe", author: "Madeline Miller")
            let firstSync = try await phone.sync()
            XCTAssertEqual(firstSync.pushed, 2)

            // A second device gets everything, cover included.
            try await ipad.sync()
            let copy = try XCTUnwrap(ipad.book("Dune"))
            XCTAssertEqual(copy.status, .read)
            XCTAssertEqual(copy.rating, 5)
            XCTAssertEqual(copy.favoriteRank, 1)
            XCTAssertEqual(copy.categories.map(\.name), ["Science Fiction"])
            XCTAssertEqual(copy.coverImage, cover)
            XCTAssertEqual(ipad.books.count, 2)

            // An edit on the second device comes back, including clearing a field.
            copy.rating = nil
            copy.notes = "Read it twice"
            try await ipad.sync()
            try await phone.sync()
            XCTAssertNil(phone.book("Dune")?.rating)
            XCTAssertEqual(phone.book("Dune")?.notes, "Read it twice")

            // Lending and returning, with history, both ways.
            phone.book("Dune")?.lend(to: "Priya Sharma", contactID: "local-only")
            try await phone.sync()
            try await ipad.sync()
            XCTAssertEqual(ipad.book("Dune")?.currentLoan?.borrowerName, "Priya Sharma")
            ipad.book("Dune")?.markReturned()
            try await ipad.sync()
            try await phone.sync()
            XCTAssertEqual(phone.book("Dune")?.isLent, false)
            XCTAssertEqual(phone.book("Dune")?.pastLoans.map(\.borrowerName), ["Priya Sharma"])

            // A deletion on the phone reaches the second device.
            phone.delete(try XCTUnwrap(phone.book("Circe")))
            try await phone.sync()
            try await ipad.sync()
            XCTAssertEqual(ipad.books.map(\.title), ["Dune"])

            // Profile name and photo.
            _ = try await phone.engine.syncProfile(local: .init(name: "Test Reader", photo: cover), lastSynced: nil)
            let (profile, _) = try await ipad.engine.syncProfile(local: .init(name: "", photo: nil), lastSynced: nil)
            XCTAssertEqual(profile, .init(name: "Test Reader", photo: cover))

            // A saved bookstore reaches the second device, then its removal does too.
            let storeSync = BookstoreSync(context: phone.context, remote: remote)
            let ipadStoreSync = BookstoreSync(context: ipad.context, remote: remote)
            let store = Bookstore(name: "Blossom Book House", latitude: 12.9756, longitude: 77.6050)
            store.note = "Three floors"
            phone.context.insert(store)
            let pulled = try await storeSync.sync(lastPulledAt: nil)
            var ipadPulled = try await ipadStoreSync.sync(lastPulledAt: nil)
            XCTAssertEqual(try ipad.context.fetch(FetchDescriptor<Bookstore>()).map(\.note), ["Three floors"])
            phone.context.deleteBookstore(store)
            _ = try await storeSync.sync(lastPulledAt: pulled)
            ipadPulled = try await ipadStoreSync.sync(lastPulledAt: ipadPulled)
            XCTAssertEqual(try ipad.context.fetchCount(FetchDescriptor<Bookstore>()), 0)

            // Privacy: another account sees none of it.
            let stranger = try makeClient()
            let strangerID = try await signUpThrowaway(stranger)
            let seen = try await SupabaseRemote(client: stranger).fetchBooks(updatedAfter: nil)
            XCTAssertTrue(seen.isEmpty, "Another account must not see these books")
            let peek = try? await SupabaseRemote(client: stranger).downloadFile(path: phone.engine.coverPath(try XCTUnwrap(dune.remoteID)))
            XCTAssertNil(peek, "Another account must not download these covers")
            try await cleanUp(stranger, userID: strangerID)
        } catch {
            try? await cleanUp(client, userID: userID)
            throw error
        }
        try await cleanUp(client, userID: userID)
    }
}

/// Keeps test sessions out of the keychain, so the simulator app isn't left logged in.
final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private var items: [String: Data] = [:]
    func store(key: String, value: Data) throws { items[key] = value }
    func retrieve(key: String) throws -> Data? { items[key] }
    func remove(key: String) throws { items[key] = nil }
}
