import Foundation
import SwiftData
import Observation
import Supabase

/// Sign-up / log-in state and backup & sync. The library always lives on the phone;
/// signing in adds an online copy that's kept in sync.
@MainActor
@Observable
final class AccountStore {
    enum Status: Equatable {
        case idle
        case syncing
        case failed(String)
    }

    private(set) var email: String?
    private(set) var userID: UUID?
    private(set) var status: Status = .idle
    private(set) var lastSynced: Date?

    /// nil when this build has no Supabase settings (e.g. a fresh clone without Config/Local.xcconfig).
    @ObservationIgnored let client: SupabaseClient?
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let defaults = UserDefaults.standard

    var isConfigured: Bool { client != nil }
    var isSignedIn: Bool { userID != nil }

    init(container: ModelContainer) {
        self.container = container
        client = Self.makeClient()
        if let user = client?.auth.currentUser {
            setUser(user)
        }
    }

    /// A client for the project in this build's settings, or nil if there isn't one.
    /// - Parameter authStorage: where the login is kept (the keychain unless given).
    static func makeClient(authStorage: (any AuthLocalStorage)? = nil) -> SupabaseClient? {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let host = info["SupabaseHost"] as? String, !host.isEmpty, !host.hasPrefix("$("),
              let key = info["SupabaseKey"] as? String, !key.isEmpty, !key.hasPrefix("$("),
              let url = URL(string: "https://\(host)") else { return nil }

        // No HTTP cache: iOS's cache doesn't tell accounts apart, so after switching
        // accounts on one phone, a cached cover could otherwise be served to the wrong one.
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(storage: authStorage ?? AuthClient.Configuration.defaultLocalStorage),
                global: .init(session: URLSession(configuration: configuration))
            )
        )
    }

    private func setUser(_ user: User?) {
        userID = user?.id
        email = user?.email
        lastSynced = user.flatMap { defaults.object(forKey: key("lastSynced", $0.id)) as? Date }
    }

    // MARK: Sign up / log in

    enum SignUpResult {
        case signedIn
        case needsEmailConfirmation
    }

    func signUp(email: String, password: String) async throws -> SignUpResult {
        guard let client else { return .needsEmailConfirmation }
        switch try await client.auth.signUp(email: email, password: password) {
        case .session(let session):
            setUser(session.user)
            await sync()
            return .signedIn
        case .user:
            return .needsEmailConfirmation
        }
    }

    func logIn(email: String, password: String) async throws {
        guard let client else { return }
        let session = try await client.auth.signIn(email: email, password: password)
        setUser(session.user)
        await sync()
    }

    /// Stops syncing. The library stays on this phone.
    func logOut() async {
        try? await client?.auth.signOut()
        setUser(nil)
        status = .idle
    }

    // MARK: Sync

    func sync() async {
        guard let client, let userID, status != .syncing else { return }
        status = .syncing
        do {
            let context = container.mainContext
            prepareLibrary(for: userID, in: context)

            let engine = SyncEngine(context: context, remote: SupabaseRemote(client: client), userID: userID)
            let lastPulled = defaults.object(forKey: key("lastPulled", userID)) as? Date
            let result = try await engine.syncBooks(lastPulledAt: lastPulled)
            defaults.set(result.lastPulledAt, forKey: key("lastPulled", userID))

            try await syncProfile(engine: engine, userID: userID)

            lastSynced = .now
            defaults.set(lastSynced, forKey: key("lastSynced", userID))
            status = .idle
        } catch {
            status = .failed(Self.describe(error))
        }
    }

    /// If this phone's library was last synced with a *different* account, treat it as
    /// new to this one, so books aren't pushed under the other account's ids.
    private func prepareLibrary(for userID: UUID, in context: ModelContext) {
        let owner = defaults.string(forKey: "syncAccountID")
        guard owner != userID.uuidString else { return }
        if owner != nil {
            for book in (try? context.fetch(FetchDescriptor<Book>())) ?? [] {
                book.remoteID = nil
                book.syncedFingerprint = nil
                book.syncedCoverHash = nil
            }
            for tombstone in (try? context.fetch(FetchDescriptor<DeletedBook>())) ?? [] {
                context.delete(tombstone)
            }
        }
        defaults.set(userID.uuidString, forKey: "syncAccountID")
    }

    private func syncProfile(engine: SyncEngine, userID: UUID) async throws {
        let fingerprintKey = key("profileFingerprint", userID)
        let lastSynced = defaults.data(forKey: fingerprintKey)
            .flatMap { try? JSONDecoder().decode(SyncEngine.ProfileFingerprint.self, from: $0) }
        let local = SyncEngine.Profile(name: defaults.string(forKey: "profileName") ?? "", photo: ProfilePhotoStore.data())

        let (profile, fingerprint) = try await engine.syncProfile(local: local, lastSynced: lastSynced)
        if profile.name != local.name {
            defaults.set(profile.name, forKey: "profileName")
        }
        if profile.photo != local.photo {
            if let photo = profile.photo {
                ProfilePhotoStore.saveExact(photo)
            } else {
                ProfilePhotoStore.remove()
            }
            NotificationCenter.default.post(name: .profilePhotoChanged, object: nil)
        }
        defaults.set(try JSONEncoder().encode(fingerprint), forKey: fingerprintKey)
    }

    private func key(_ name: String, _ userID: UUID) -> String {
        "\(name).\(userID.uuidString)"
    }

    private static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            return "You're offline. Changes will sync when you're back online."
        }
        return error.localizedDescription
    }
}

extension Notification.Name {
    static let profilePhotoChanged = Notification.Name("profilePhotoChanged")
}
