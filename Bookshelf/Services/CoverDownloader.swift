import UIKit

/// Downloads cover images from any source, keeping them to a sensible size.
struct CoverDownloader {
    var session: URLSession = .shared

    /// Tries each address in turn and returns the first real image.
    func download(from urls: [URL?]) async -> Data? {
        for url in urls.compactMap({ $0 }) {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data),
                  image.size.width > 10 else { continue }  // skip 1×1 "no cover" placeholders
            return CoverImage.capped(data)
        }
        return nil
    }
}
