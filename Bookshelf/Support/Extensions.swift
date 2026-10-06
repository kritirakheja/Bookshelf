import UIKit

extension Array {
    /// Consecutive slices of at most `size` elements: rows of covers, pages of uploads.
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

extension UIImage {
    /// Redrawn at exactly `size` pixels (one pixel per point).
    func resized(to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Scaled down, if need be, so its longer side is at most `maxSide` pixels.
    func fitted(maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        return resized(to: CGSize(width: size.width * scale, height: size.height * scale))
    }
}
