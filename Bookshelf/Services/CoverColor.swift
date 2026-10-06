import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Colours taken from a book's cover: for drawing its back and spine, and for
/// tinting its details page.
enum CoverColor {
    struct RGB: Equatable {
        var r: Double
        var g: Double
        var b: Double
    }

    /// Used when a book has no cover image.
    static let fallback = RGB(r: 0.20, g: 0.27, b: 0.24)

    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// The cover's average colour.
    static func average(of data: Data?) -> RGB {
        guard let data, let image = CIImage(data: data), !image.extent.isEmpty else { return fallback }
        return average(of: image, in: image.extent) ?? fallback
    }

    private static func average(of image: CIImage, in rect: CGRect) -> RGB? {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = rect
        guard let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        return RGB(r: Double(pixel[0]) / 255, g: Double(pixel[1]) / 255, b: Double(pixel[2]) / 255)
    }

    /// Whether white text reads better than black on this colour (by relative luminance).
    static func prefersLightText(on color: RGB) -> Bool {
        luminance(of: color) < 0.4
    }

    private static func luminance(of color: RGB) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
    }

    // MARK: - Accent

    /// The cover's most prominent vivid colour, for tinting the book's page. White,
    /// black and grey areas don't count, so a white cover with an orange dot gives
    /// orange. Nil when the cover has no real colour (or there's no cover).
    static func accent(of data: Data?) -> RGB? {
        guard let data else { return nil }
        let key = "\(data.count)-\(data.prefix(64).hashValue)-\(data.suffix(64).hashValue)" as NSString
        if let cached = accentCache.object(forKey: key) { return cached.value }
        let found = findAccent(in: data)
        accentCache.setObject(CachedAccent(found), forKey: key)
        return found
    }

    /// Covers are decoded once per launch; the page asks for its colour on every redraw.
    private static let accentCache = NSCache<NSString, CachedAccent>()

    private final class CachedAccent {
        let value: RGB?
        init(_ value: RGB?) { self.value = value }
    }

    private static let hueBuckets = 12
    /// Pixels greyer or darker than this are background, not colour.
    private static let minimumSaturation = 0.35
    private static let minimumBrightness = 0.25
    /// The share of the cover that must be vivid for it to have a colour at all.
    private static let minimumVividShare = 0.02

    private static func findAccent(in data: Data) -> RGB? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        let width = 32, height = 48
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Sort the vivid pixels by hue, each counting for more the more vivid it is.
        var weight = [Double](repeating: 0, count: hueBuckets)
        var sum = [RGB](repeating: RGB(r: 0, g: 0, b: 0), count: hueBuckets)
        var vivid = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index]) / 255, g = Double(pixels[index + 1]) / 255, b = Double(pixels[index + 2]) / 255
            let (hue, saturation, high) = hsb(RGB(r: r, g: g, b: b))
            guard saturation >= minimumSaturation, high >= minimumBrightness else { continue }
            let bucket = min(Int(hue * Double(hueBuckets)), hueBuckets - 1)
            let pixelWeight = saturation * high
            weight[bucket] += pixelWeight
            sum[bucket].r += r * pixelWeight
            sum[bucket].g += g * pixelWeight
            sum[bucket].b += b * pixelWeight
            vivid += 1
        }
        guard Double(vivid) >= Double(width * height) * minimumVividShare,
              let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0 else { return nil }
        return RGB(r: sum[best].r / weight[best], g: sum[best].g / weight[best], b: sum[best].b / weight[best])
    }

    /// How strongly two colours contrast, from 1 (identical) to 21 (black on white).
    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let first = luminance(of: a), second = luminance(of: b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// Enough contrast for semibold labels and for white text on a filled button.
    /// (Body-text contrast, 4.5, would turn every orange and yellow into brown.)
    static let readableContrast = 3.2

    /// `color` made readable against `page`: kept vivid, and darkened (or on a dark
    /// page, lightened) only as far as it takes. A colour that already reads well
    /// comes back unchanged.
    static func legible(_ color: RGB, on page: RGB) -> RGB {
        guard contrast(color, page) < readableContrast else { return color }
        let pageIsDark = luminance(of: page) < 0.5
        var (hue, saturation, brightness) = hsb(color)
        // Full colour first: a darker shade of a washed-out colour is a muddy one.
        saturation = max(saturation, 0.85)
        var result = rgb(hue: hue, saturation: saturation, brightness: brightness)
        for _ in 0..<60 where contrast(result, page) < readableContrast {
            if pageIsDark {
                // Brighter, then paler once it can't get brighter.
                if brightness < 1 { brightness = min(1, brightness + 0.04) } else { saturation = max(0, saturation - 0.05) }
            } else {
                brightness = max(0, brightness - 0.03)
            }
            result = rgb(hue: hue, saturation: saturation, brightness: brightness)
        }
        return result
    }

    private static func hsb(_ color: RGB) -> (hue: Double, saturation: Double, brightness: Double) {
        let high = max(color.r, color.g, color.b), low = min(color.r, color.g, color.b)
        let span = high - low
        guard span > 0 else { return (0, 0, high) }
        var hue: Double
        if high == color.r { hue = (color.g - color.b) / span } else if high == color.g { hue = 2 + (color.b - color.r) / span } else { hue = 4 + (color.r - color.g) / span }
        hue = (hue / 6).truncatingRemainder(dividingBy: 1)
        if hue < 0 { hue += 1 }
        return (hue, span / high, high)
    }

    private static func rgb(hue: Double, saturation: Double, brightness: Double) -> RGB {
        let sector = hue * 6
        let index = Int(sector) % 6
        let fraction = sector - floor(sector)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))
        switch index {
        case 0: return RGB(r: brightness, g: t, b: p)
        case 1: return RGB(r: q, g: brightness, b: p)
        case 2: return RGB(r: p, g: brightness, b: t)
        case 3: return RGB(r: p, g: q, b: brightness)
        case 4: return RGB(r: t, g: p, b: brightness)
        default: return RGB(r: brightness, g: p, b: q)
        }
    }
}
