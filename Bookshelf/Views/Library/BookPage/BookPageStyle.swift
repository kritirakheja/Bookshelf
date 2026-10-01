import SwiftUI
import UIKit

/// Look of a book's page: warm paper, cards, ink and a handwritten font, inspired by
/// a well-loved bookshop. Colours adapt to dark mode.
enum BookPageStyle {
    static let paper = adaptive(light: (0.980, 0.961, 0.922), dark: (0.110, 0.102, 0.094))
    static let card = adaptive(light: (1.0, 0.996, 0.984), dark: (0.169, 0.157, 0.141))
    static let rule = adaptive(light: (0.86, 0.80, 0.72), dark: (0.30, 0.27, 0.24))
    static let stickyNote = adaptive(light: (1.0, 0.945, 0.690), dark: (0.36, 0.32, 0.17))
    static let brown = Color(red: 0.55, green: 0.38, blue: 0.24)

    static func serif(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    /// Handwriting, for the staff-pick card and margin notes.
    static func handwriting(_ size: CGFloat) -> Font {
        .custom("Noteworthy-Bold", size: size, relativeTo: .body)
    }

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

/// A small-caps heading, like the labels on bookshop shelves.
struct ShelfHeading: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(2)
            .foregroundStyle(BookPageStyle.brown)
    }
}

/// A paper card the page's sections sit on.
struct PaperCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(BookPageStyle.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(BookPageStyle.rule.opacity(0.6), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
            .padding(.horizontal, 18)
    }
}

/// A rubber stamp, as on a library card ("LENT TO PRIYA").
struct RubberStamp: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.heavy))
            .tracking(1.2)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 1.6))
            .rotationEffect(.degrees(-3))
            .opacity(0.88)
    }
}

/// Lays views out in rows, wrapping like words on a line (for shelf labels).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX + (bounds.width - row.width) / 2   // centred rows
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].width += spacing + size.width
                rows[rows.count - 1].height = max(last.height, size.height)
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}
