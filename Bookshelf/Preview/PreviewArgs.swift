#if DEBUG
import Foundation

/// Launch arguments for taking simulator screenshots of screens that can't be
/// reached without tapping, e.g. `simctl launch … -previewBook "Quiet"`.
enum PreviewArgs {
    /// `-previewBook "<title>"`: open that book's full details page.
    static var book: String? { UserDefaults.standard.string(forKey: "previewBook") }
    /// `-previewBackCover "<title>"`: open that book as the 3D book Explore shows.
    static var backCover: String? { UserDefaults.standard.string(forKey: "previewBackCover") }
    /// `-previewFlipAngle 60`: hold the 3D book at this angle (degrees) instead of turning it.
    static var flipAngle: Float? { UserDefaults.standard.string(forKey: "previewFlipAngle").flatMap(Float.init) }
    /// `-previewScanner YES`: open the barcode scanner (with a stand-in for the camera).
    static var scanner: Bool { UserDefaults.standard.bool(forKey: "previewScanner") }
    /// `-previewScanFound YES`: have the scanner "catch" a barcode after a moment.
    static var scanFound: Bool { UserDefaults.standard.bool(forKey: "previewScanFound") }
}
#endif
