import SwiftUI
import UIKit

/// The app's one look: warm paper behind every screen, white cards, a single brown
/// accent, serif titles. Colours adapt to dark mode.
enum Theme {
    /// Behind every screen.
    static let paper = adaptive(light: (0.980, 0.961, 0.922), dark: (0.065, 0.058, 0.052))
    /// Cards and list rows (the system's own row colour, so custom cards and lists match).
    static let card = Color(.secondarySystemGroupedBackground)
    /// Hairlines and quiet fills.
    static let rule = adaptive(light: (0.86, 0.80, 0.72), dark: (0.30, 0.27, 0.24))
    /// The accent: buttons, links, labels. Same as the AccentColor asset.
    static let brown = adaptive(light: (0.55, 0.38, 0.24), dark: (0.82, 0.64, 0.46))
    static let stickyNote = adaptive(light: (1.0, 0.945, 0.690), dark: (0.36, 0.32, 0.17))

    static func serif(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    /// Handwriting, for recommendation notes and margin notes.
    static func handwriting(_ size: CGFloat) -> Font {
        .custom("Noteworthy-Bold", size: size, relativeTo: .body)
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
        bar.largeTitleTextAttributes = [.font: serif(.largeTitle, bold: true)]
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
