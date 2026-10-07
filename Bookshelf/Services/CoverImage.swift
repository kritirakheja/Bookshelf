import UIKit
import ImageIO
import CoreImage

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
        return image.resized(to: size).jpegData(compressionQuality: 0.85) ?? data
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

    /// Of several covers of the same book, the sharp one that looks most like
    /// `current` (the same artwork if it's among them). Nil if none is sharp.
    static func closestSharp(to current: Data, among candidates: [Data], minimumWidth: Int = CoverUpgrade.sharpEnough) -> Data? {
        let currentSignature = signature(of: current)
        let sharp = candidates.filter { (pixelWidth(of: $0) ?? 0) >= minimumWidth }
        func distance(_ candidate: Data) -> Double {
            guard let currentSignature, let other = signature(of: candidate) else { return 1 }
            return difference(currentSignature, other)
        }
        return sharp.min { distance($0) < distance($1) }
    }

    /// Whether `candidate` is the same cover as `current`, only clearly sharper.
    static func isSharperCopy(_ candidate: Data, of current: Data) -> Bool {
        guard let currentWidth = pixelWidth(of: current), let newWidth = pixelWidth(of: candidate),
              Double(newWidth) >= Double(currentWidth) * 1.4,
              let a = signature(of: current), let b = signature(of: candidate) else { return false }
        return difference(a, b) < sameArtworkLimit
    }
}
