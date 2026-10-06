import UIKit
import ImageIO
import CoreImage
import SwiftData

/// Measuring and comparing cover images.
enum CoverImage {
    /// Covers are kept no wider than this: sharp at full screen, without storing
    /// (and syncing) multi-megabyte scans.
    static let maxWidth: CGFloat = 1200

    /// The image's width in pixels, read from its header without decoding it.
    static func pixelWidth(of data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        return properties[kCGImagePropertyPixelWidth] as? Int
    }

    /// The same image, scaled down if it's wider than `maxWidth`.
    static func capped(_ data: Data) -> Data {
        guard let width = pixelWidth(of: data), CGFloat(width) > maxWidth, let image = UIImage(data: data) else { return data }
        let scale = maxWidth / image.size.width
        let size = CGSize(width: maxWidth, height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let smaller = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return smaller.jpegData(compressionQuality: 0.85) ?? data
    }

    /// A tiny 16×24 colour thumbnail, as bytes, for telling whether two files show
    /// the same artwork.
    static func signature(of data: Data) -> [UInt8]? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        let width = 16, height = 24
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    /// A small cover enlarged for showing big: scaled up with a sharp (Lanczos)
    /// filter and lightly sharpened, which looks crisper than plain stretching.
    /// Covers already near `width` pixels wide are returned as they are.
    static func enlarged(_ data: Data, toWidth width: CGFloat) -> UIImage? {
        guard let image = UIImage(data: data), let source = CIImage(data: data) else { return nil }
        let scale = width / source.extent.width
        guard scale > 1.25 else { return image }
        let scaled = source.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
        let sharpened = scaled.applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: 2.0 * min(scale, 3), kCIInputIntensityKey: 0.6])
        guard let rendered = renderer.createCGImage(sharpened, from: scaled.extent) else { return image }
        return UIImage(cgImage: rendered)
    }

    private static let renderer = CIContext()

    /// How different two covers look, from 0 (identical) to 1.
    static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        var total = 0
        for index in a.indices where index % 4 != 3 {
            total += abs(Int(a[index]) - Int(b[index]))
        }
        return Double(total) / Double(a.count / 4 * 3 * 255)
    }

    /// The same file at another size scores under about 0.03 here, the same artwork
    /// cropped or tinted a little differently up to about 0.07, and different covers
    /// over 0.08 (measured on this library). Candidates are already the same title,
    /// so the limit sits at the top of the "same artwork" range.
    static let sameArtworkLimit = 0.075

    /// Whether `candidate` is the same cover as `current`, only clearly sharper.
    static func isSharperCopy(_ candidate: Data, of current: Data) -> Bool {
        guard let currentWidth = pixelWidth(of: current), let newWidth = pixelWidth(of: candidate),
              Double(newWidth) >= Double(currentWidth) * 1.4,
              let a = signature(of: current), let b = signature(of: candidate) else { return false }
        return difference(a, b) < sameArtworkLimit
    }
}

/// Replaces small, blurry covers with sharper copies of the same artwork, one book at
/// a time in the background. Each book is looked up once per device; covers that
/// can't be matched (your own photos, other editions) are left alone.
enum CoverUpgrade {
    /// Covers at least this wide are already sharp enough.
    static let sharpEnough = 700
    static let checkedKey = "coverUpgrade.checked.v2"   // v2: Apple Books added as a source

    @MainActor
    static func run(in context: ModelContext, lookup: BookLookup = BookLookup(), defaults: UserDefaults = .standard) async {
        // Not while tests run the app: it would spend the day's free lookups each time.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        var checked = Set(defaults.stringArray(forKey: checkedKey) ?? [])
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        for book in books {
            guard !Task.isCancelled else { break }
            let key = Self.key(for: book)
            guard !checked.contains(key), let current = book.coverImage,
                  let width = CoverImage.pixelWidth(of: current), width < sharpEnough else { continue }
            let sharper = await lookup.sharperCover(than: current, title: book.title, author: book.authors.first, isbn: book.isbn)
            // Only if the cover hasn't been changed by hand in the meantime.
            if let sharper, book.coverImage == current {
                book.coverImage = sharper
                try? context.save()
            }
            checked.insert(key)
            defaults.set(Array(checked), forKey: checkedKey)
        }
    }

    static func key(for book: Book) -> String {
        "\(book.title.lowercased())|\(book.authors.first?.lowercased() ?? "")|\(book.isbn ?? "")"
    }
}
