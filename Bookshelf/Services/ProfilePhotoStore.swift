import UIKit

/// Keeps the profile picture as a small JPEG in the app's private storage.
/// (A single image doesn't need the database.)
enum ProfilePhotoStore {
    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "profile-photo.jpg")
    }

    static func load() -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Shrinks the photo (a phone photo can be 5+ MB) before saving.
    @discardableResult
    static func save(_ data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let resized = image.fitted(maxSide: 600)
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return nil }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? jpeg.write(to: url, options: .atomic)
        return resized
    }

    /// The stored JPEG exactly as saved (for sync, so its hash stays stable).
    static func data() -> Data? {
        try? Data(contentsOf: url)
    }

    /// Stores already-prepared JPEG bytes as they are (a photo synced from another device).
    static func saveExact(_ data: Data) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
