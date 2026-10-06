import SwiftUI
import UIKit

/// The app's one look: soft off-white behind every screen, white cards, a single
/// deep green accent, serif titles. Colours adapt to dark mode.
enum Theme {
    /// Behind every screen.
    static let paper = adaptive(light: (0.968, 0.970, 0.960), dark: (0.055, 0.062, 0.058))
    /// Cards and list rows (the system's own row colour, so custom cards and lists match).
    static let card = Color(.secondarySystemGroupedBackground)
    /// Hairlines and quiet fills.
    static let rule = adaptive(light: (0.85, 0.87, 0.85), dark: (0.25, 0.27, 0.26))
    /// The accent: buttons, links, labels. Same as the AccentColor asset.
    static let accent = adaptive(light: (0.10, 0.35, 0.26), dark: (0.46, 0.78, 0.62))

    static func serif(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    /// Serif titles in every navigation bar. Call once at launch.
    static func applyNavigationFonts() {
        func serif(_ style: UIFont.TextStyle, bold: Bool) -> UIFont {
            let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
            let design = base.withDesign(.serif) ?? base
            let descriptor = bold ? (design.withSymbolicTraits(.traitBold) ?? design) : design
            return UIFont(descriptor: descriptor, size: 0)
        }
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: serif(.title1, bold: true)]
        bar.titleTextAttributes = [.font: serif(.headline, bold: true)]
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
