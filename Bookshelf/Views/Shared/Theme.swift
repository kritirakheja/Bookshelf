import SwiftUI
import UIKit

/// The app's one look: soft off-white behind every screen, white cards, a single
/// deep green accent, and Inter for all text. Colours adapt to dark mode.
enum Theme {
    /// Behind every screen.
    static let paper = adaptive(light: (0.968, 0.970, 0.960), dark: (0.055, 0.062, 0.058))
    /// Cards and list rows (the system's own row colour, so custom cards and lists match).
    static let card = Color(.secondarySystemGroupedBackground)
    /// Hairlines and quiet fills.
    static let rule = adaptive(light: (0.85, 0.87, 0.85), dark: (0.25, 0.27, 0.26))
    /// The accent: buttons, links, labels. Same as the AccentColor asset.
    static let accent = adaptive(light: (0.10, 0.35, 0.26), dark: (0.46, 0.78, 0.62))

    /// Inter in every navigation bar, tab label and search box (the parts SwiftUI's
    /// fonts don't reach). Call once at launch.
    static func applyBarFonts() {
        func inter(_ face: String, _ size: CGFloat, _ style: UIFont.TextStyle) -> UIFont {
            let font = UIFont(name: face, size: size) ?? .systemFont(ofSize: size)
            return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
        }
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: inter("Inter-Bold", 28, .title1)]
        bar.titleTextAttributes = [.font: inter("Inter-SemiBold", 17, .headline)]
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: inter("Inter-Medium", 17, .body)], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: inter("Inter-Medium", 10, .caption2)], for: .normal)
        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).font = inter("Inter-Regular", 17, .body)
    }

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

extension View {
    /// Puts a screen on paper. On a List or Form it replaces the grey backdrop.
    func paperScreen() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
    }
}

extension Font {
    /// The app's typeface, Inter, at a text style's size (it grows with the reader's
    /// text-size setting). Every screen uses this instead of the system font.
    static func inter(_ style: TextStyle, _ weight: Weight? = nil) -> Font {
        let size: CGFloat = switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
        let face = switch weight ?? (style == .headline ? .semibold : .regular) {
        case .medium: "Inter-Medium"
        case .semibold: "Inter-SemiBold"
        case .bold, .heavy, .black: "Inter-Bold"
        default: "Inter-Regular"
        }
        return .custom(face, size: size, relativeTo: style)
    }
}
