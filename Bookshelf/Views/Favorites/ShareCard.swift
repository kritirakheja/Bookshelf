import SwiftUI

/// The two shapes the share image comes in.
enum ShareFormat: String, CaseIterable, Identifiable {
    case story = "Story"
    case square = "Square"

    var id: String { rawValue }

    /// In points; rendered at 3× (1080 pixels wide).
    var size: CGSize {
        switch self {
        case .story: CGSize(width: 360, height: 640)
        case .square: CGSize(width: 360, height: 360)
        }
    }
}

/// Your favourites as an image to send: the books standing as spines on a shelf, on
/// warm paper, with the list underneath. Fixed colours (not the app's adaptive
/// ones), so it looks the same whichever mode the phone is in.
struct FavouritesShareCard: View {
    let books: [Book]
    let name: String
    let format: ShareFormat

    static let paper = Color(red: 0.957, green: 0.937, blue: 0.902)
    static let ink = Color(red: 0.118, green: 0.114, blue: 0.102)
    static let green = Color(red: 0.10, green: 0.35, blue: 0.26)
    static let paperRGB = CoverColor.RGB(r: 0.957, g: 0.937, b: 0.902)

    private var isStory: Bool { format == .story }
    private var scale: CGFloat { isStory ? 1 : 0.62 }
    private var padding: CGFloat { isStory ? 28 : 22 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: isStory ? 20 : 10)
            shelf
            Spacer(minLength: isStory ? 26 : 12)
            list
            Spacer(minLength: isStory ? 18 : 10)
            footer
        }
        .padding(padding)
        .frame(width: format.size.width, height: format.size.height, alignment: .topLeading)
        .background {
            ZStack {
                Self.paper
                // A soft darker edge, like light falling on paper.
                RadialGradient(colors: [.clear, Self.ink.opacity(0.07)], center: .center,
                               startRadius: format.size.width * 0.35, endRadius: format.size.height * 0.75)
            }
        }
        .environment(\.colorScheme, .light)
    }

    // MARK: Header and footer

    private var header: some View {
        VStack(alignment: .leading, spacing: isStory ? 6 : 4) {
            Text(Self.owner(name))
                .font(.inter(size: isStory ? 12 : 10, .semibold))
                .tracking(isStory ? 3.5 : 3)
                .foregroundStyle(Self.green)
            Text("Favourite Books")
                .font(.inter(size: isStory ? 36 : 26, .bold))
                .tracking(-0.6)
                .foregroundStyle(Self.ink)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Self.ink.opacity(0.35)).frame(width: 18, height: 1)
            Text(Self.footer(count: books.count))
                .font(.inter(size: isStory ? 10 : 8.5, .semibold))
                .tracking(isStory ? 3 : 2.5)
                .foregroundStyle(Self.ink.opacity(0.6))
        }
    }

    /// "KRITI'S", from the first name on the profile; "MY" without one.
    static func owner(_ name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespaces).split(separator: " ").first else { return "MY" }
        let upper = first.uppercased()
        return upper.hasSuffix("S") ? upper + "’" : upper + "’S"
    }

    static func footer(count: Int) -> String {
        "TOP \(count) FAVOURITE BOOK\(count == 1 ? "" : "S")"
    }

    // MARK: Shelf

    private var shelfWidth: CGFloat { format.size.width - padding * 2 }

    private var shelf: some View {
        let widths = SpineMetrics.widths(pages: books.map(\.pageCount), fitting: shelfWidth, scale: scale)
        return VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: SpineMetrics.spacing * scale) {
                ForEach(Array(books.enumerated()), id: \.element.persistentModelID) { index, book in
                    let leaning = index == books.count - 1 && books.count > 2
                    Spine(book: book, rank: index + 1, width: widths[index],
                          height: SpineMetrics.height(for: book.title) * scale, scale: scale)
                        // The last book leans on its neighbour.
                        .rotationEffect(.degrees(leaning ? -SpineMetrics.leanDegrees : 0), anchor: .bottomTrailing)
                        .padding(.leading, leaning ? SpineMetrics.leanGap * scale : 0)
                }
            }
            .padding(.horizontal, 6 * scale)
            .frame(maxWidth: .infinity)

            // The shelf: a dark plank with a soft shadow under it.
            Rectangle()
                .fill(Self.ink.opacity(0.88))
                .frame(height: 5 * max(scale, 0.8))
            LinearGradient(colors: [Self.ink.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 12 * scale)
        }
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        if isStory {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(books.enumerated()), id: \.element.persistentModelID) { index, book in
                    row(index + 1, book)
                }
            }
        } else {
            let half = (books.count + 1) / 2
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(books.prefix(half).enumerated()), id: \.element.persistentModelID) { index, book in
                        row(index + 1, book)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(books.dropFirst(half).enumerated()), id: \.element.persistentModelID) { index, book in
                        row(half + index + 1, book)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row(_ rank: Int, _ book: Book) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: isStory ? 12 : 7) {
            Text(String(format: "%02d", rank))
                .font(.inter(size: isStory ? 11 : 8.5, .semibold))
                .monospacedDigit()
                .foregroundStyle(Self.green)
            if isStory {
                (Text(book.title).font(.inter(size: 13.5, .semibold)).foregroundColor(Self.ink)
                 + Text(book.authors.first.map { "  ·  \($0)" } ?? "").font(.inter(size: 12.5)).foregroundColor(Self.ink.opacity(0.5)))
                    .lineLimit(1)
            } else {
                Text(book.title)
                    .font(.inter(size: 10, .semibold))
                    .foregroundStyle(Self.ink)
                    .lineLimit(1)
            }
        }
    }
}

/// How big each spine is: thicker for longer books, and a height of its own (fixed
/// per title) so the row looks like real books rather than a bar chart.
enum SpineMetrics {
    static let spacing: CGFloat = 2.5
    static let leanDegrees: Double = 8
    /// Room for the leaning book's top to tip into.
    static let leanGap: CGFloat = 18
    static let thinnest: CGFloat = 18
    static let thickest: CGFloat = 34

    static func width(pages: Int?) -> CGFloat {
        guard let pages, pages > 0 else { return 24 }
        let t = (CGFloat(pages) - 150) / 650
        return min(thickest, max(thinnest, thinnest + t * (thickest - thinnest)))
    }

    /// 150–190 points, the same every time for the same title.
    static func height(for title: String) -> CGFloat {
        var hash: UInt32 = 2_166_136_261
        for byte in title.lowercased().utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return 150 + CGFloat(hash % 41)
    }

    /// The fullest a spine gets when books are widened to fill the shelf.
    static let widest: CGFloat = 46

    /// Every spine's width, scaled evenly so the books fill the shelf: shrunk if
    /// they'd overflow, widened (up to `widest`) if they'd leave a gap.
    static func widths(pages: [Int?], fitting shelf: CGFloat, scale: CGFloat) -> [CGFloat] {
        let natural = pages.map { width(pages: $0) * scale }
        let sum = natural.reduce(0, +)
        guard sum > 0 else { return natural }
        let extras = (spacing * CGFloat(max(pages.count - 1, 0)) + (pages.count > 2 ? leanGap : 0) + 12) * scale
        let fill = max(0, shelf - extras) / sum
        let cap = widest * scale / (natural.max() ?? 1)
        return natural.map { $0 * min(fill, cap) }
    }
}

/// One book standing on the shelf: its cover's colour, its title running down it.
private struct Spine: View {
    let book: Book
    let rank: Int
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat

    var body: some View {
        let colour = CoverColor.accent(of: book.coverImage) ?? CoverColor.average(of: book.coverImage)
        let light = CoverColor.prefersLightText(on: colour)
        let text = light ? Color.white : FavouritesShareCard.ink
        let pale = CoverColor.contrast(colour, FavouritesShareCard.paperRGB) < 1.35
        let inset = 14 * scale

        RoundedRectangle(cornerRadius: 2 * scale)
            .fill(Color(red: colour.r, green: colour.g, blue: colour.b))
            .overlay {
                // Rounded-spine shading: darker edges, a faint highlight left of centre.
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.22), location: 0),
                    .init(color: .clear, location: 0.18),
                    .init(color: .white.opacity(0.10), location: 0.35),
                    .init(color: .clear, location: 0.6),
                    .init(color: .black.opacity(0.25), location: 1),
                ], startPoint: .leading, endPoint: .trailing)
                .clipShape(RoundedRectangle(cornerRadius: 2 * scale))
            }
            .overlay(alignment: .top) {
                VStack(spacing: 4 * scale) {
                    Text("\(rank)")
                        .font(.inter(size: 8 * max(scale, 0.75), .semibold))
                        .foregroundStyle(text.opacity(0.8))
                        .padding(.top, 5 * scale)
                    band(text)
                }
            }
            .overlay(alignment: .bottom) {
                band(text).padding(.bottom, inset)
            }
            .overlay {
                Text(book.title)
                    .font(.inter(size: min(11 * scale, width * 0.42), .semibold))
                    .foregroundStyle(text)
                    .lineLimit(1)
                    .frame(width: height - (34 + 26) * scale)
                    .rotationEffect(.degrees(90))
                    .offset(y: 4 * scale)
            }
            .overlay {
                if pale {
                    RoundedRectangle(cornerRadius: 2 * scale).stroke(FavouritesShareCard.ink.opacity(0.18), lineWidth: 0.6)
                }
            }
            .frame(width: width, height: height)
    }

    /// The thin printed lines near a spine's ends.
    private func band(_ colour: Color) -> some View {
        Rectangle()
            .fill(colour.opacity(0.35))
            .frame(height: 1.2 * max(scale, 0.7))
            .padding(.horizontal, 3 * scale)
    }
}
