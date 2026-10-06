import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Colours taken from a book's cover, for drawing its back and spine.
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
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
        return luminance < 0.4
    }
}
