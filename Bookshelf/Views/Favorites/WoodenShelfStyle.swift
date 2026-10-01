import SwiftUI
import UIKit

/// A light wooden bookcase: grained wood behind everything, cream buttons, and
/// thin shelves running wall to wall. Adapts to dark mode with a darker wood.
enum WoodenShelfStyle {
    static let wood = adaptive(light: (0.82, 0.67, 0.47), dark: (0.25, 0.18, 0.12))
    static let grain = adaptive(light: (0.55, 0.38, 0.22), dark: (0.10, 0.06, 0.03))
    static let cream = adaptive(light: (0.97, 0.91, 0.79), dark: (0.36, 0.28, 0.20))
    static let ink = adaptive(light: (0.13, 0.09, 0.06), dark: (0.97, 0.94, 0.89))
    static let faded = adaptive(light: (0.42, 0.31, 0.21), dark: (0.78, 0.70, 0.60))
    static let tag = adaptive(light: (0.50, 0.35, 0.22), dark: (0.62, 0.47, 0.32))

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

/// Wood grain: long, slightly wavy vertical lines of varying weight. The same
/// pattern every time (no randomness), so it doesn't flicker when redrawn.
struct WoodGrain: View {
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 0
            var index = 0
            while x < size.width {
                let seed = Double(index)
                let wobble = 3 + 4 * abs(sin(seed * 1.7))
                let phase = seed * 2.3
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                var y: CGFloat = 0
                while y <= size.height {
                    y += 24
                    path.addLine(to: CGPoint(x: x + wobble * sin(y / 140 + phase), y: y))
                }
                let opacity = 0.10 + 0.14 * abs(sin(seed * 0.9))
                let width = 0.6 + 1.2 * abs(cos(seed * 1.3))
                context.stroke(path, with: .color(WoodenShelfStyle.grain.opacity(opacity)), lineWidth: width)
                x += 9 + 14 * abs(sin(seed * 2.9))
                index += 1
            }
        }
        .background(WoodenShelfStyle.wood)
        .ignoresSafeArea()
    }
}

/// A thin shelf running the full width of the bookcase.
struct WallShelf: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color(red: 0.86, green: 0.72, blue: 0.53), Color(red: 0.76, green: 0.60, blue: 0.40)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 7)
            LinearGradient(colors: [Color(red: 0.62, green: 0.46, blue: 0.29), Color(red: 0.52, green: 0.37, blue: 0.22)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 9)
        }
        .shadow(color: .black.opacity(0.28), radius: 5, y: 5)
    }
}

/// A cream pill or round button, like the controls at the top of the bookcase.
struct CreamButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(WoodenShelfStyle.ink)
            .background(WoodenShelfStyle.cream, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}
