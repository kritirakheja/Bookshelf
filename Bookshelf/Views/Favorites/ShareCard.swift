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

/// Your favourites as an image to send: the real covers standing face-out on two
/// glass shelves of five, numbered, on a soft blur of their own colours.
struct FavouritesShareCard: View {
    let books: [Book]
    let name: String
    let format: ShareFormat

    static let perShelf = 5
    /// The app's name, small, where a repeat of the title used to be.
    static let footer = "BOOKSHELF"

    private var isStory: Bool { format == .story }
    private var coverWidth: CGFloat { isStory ? 54 : 46 }
    private var padding: CGFloat { isStory ? 28 : 22 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Self.owner(name))
                .font(.inter(size: isStory ? 12 : 10, .semibold))
                .tracking(isStory ? 3.5 : 3)
                .foregroundStyle(.white.opacity(0.75))
            Text("Favourite Books")
                .font(.inter(size: isStory ? 36 : 26, .bold))
                .tracking(-0.6)
                .foregroundStyle(.white)
                .padding(.top, isStory ? 6 : 4)
            Spacer(minLength: 12)
            shelf(Array(books.prefix(Self.perShelf)), startRank: 1)
            if books.count > Self.perShelf {
                Spacer().frame(height: isStory ? 34 : 18)
                shelf(Array(books.dropFirst(Self.perShelf).prefix(Self.perShelf)), startRank: Self.perShelf + 1)
            }
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                Rectangle().fill(.white.opacity(0.5)).frame(width: 18, height: 1)
                Text(Self.footer)
                    .font(.inter(size: isStory ? 10 : 8.5, .semibold))
                    .tracking(isStory ? 3 : 2.5)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(padding)
        .frame(width: format.size.width, height: format.size.height, alignment: .topLeading)
        .background(CoverWash(books: books))
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    /// "KRITI'S", from the first name on the profile; "MY" without one.
    static func owner(_ name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespaces).split(separator: " ").first else { return "MY" }
        let upper = first.uppercased()
        return upper.hasSuffix("S") ? upper + "’" : upper + "’S"
    }

    /// One glass shelf with up to five covers standing on it, each with its rank.
    private func shelf(_ row: [Book], startRank: Int) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(row.enumerated()), id: \.offset) { index, book in
                    ShareCover(book: book, width: coverWidth)
                        .shadow(color: .black.opacity(0.45), radius: 6, x: 2, y: 4)
                        .overlay(alignment: .topLeading) {
                            Text("\(startRank + index)")
                                .font(.inter(size: isStory ? 8 : 7, .bold))
                                .foregroundStyle(.black)
                                .frame(width: isStory ? 15 : 13, height: isStory ? 15 : 13)
                                .background(.white, in: Circle())
                                .offset(x: -5, y: -5)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.3))
                .frame(height: isStory ? 6 : 5)
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.6)).frame(height: 1) }
                .shadow(color: .black.opacity(0.35), radius: 8, y: 6)
        }
    }
}

/// A plain cover for the share image (no lent/borrowed badges, unlike `CoverView`).
private struct ShareCover: View {
    let book: Book
    let width: CGFloat

    var body: some View {
        Group {
            if let data = book.coverImage, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color(white: 0.88)
                    Text(book.title)
                        .font(.inter(size: width * 0.13, .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.black.opacity(0.7))
                        .padding(width * 0.1)
                }
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

/// The covers blown up and blurred until only their colours are left: drawn tiny,
/// then stretched smoothly to fill (so the edges don't go dark the way a blur does).
private struct CoverWash: View {
    let books: [Book]

    var body: some View {
        ZStack {
            Color(white: 0.12)
            if let tiny = Self.tinyGrid(of: books) {
                Image(uiImage: tiny)
                    .resizable()
                    .interpolation(.high)
                    .saturation(1.25)
                    .blur(radius: 30)
                    .scaleEffect(1.3)
            }
            Color.black.opacity(0.4)
        }
        .clipped()
    }

    /// Up to six covers in two columns, shrunk to a few pixels.
    static func tinyGrid(of books: [Book]) -> UIImage? {
        let covers = books.prefix(6).compactMap { $0.coverImage.flatMap(UIImage.init(data:)) }
        guard !covers.isEmpty else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let grid = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 105), format: format).image { _ in
            for (index, cover) in covers.enumerated() {
                cover.draw(in: CGRect(x: CGFloat(index % 2) * 30, y: CGFloat(index / 2) * 35, width: 30, height: 35))
            }
        }
        return grid.resized(to: CGSize(width: 4, height: 7))
    }
}
