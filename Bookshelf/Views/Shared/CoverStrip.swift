import SwiftUI

/// A row of covers that scrolls sideways, sized so a set number fit across with a
/// sliver of the next showing. Each cover is a link to `value(book)`.
struct CoverStrip<Value: Hashable, Menu: View>: View {
    let books: [Book]
    /// How many covers fit across; a fraction leaves the next one peeking in.
    var coversInView: CGFloat = 4.3
    var spacing: CGFloat = 10
    let value: (Book) -> Value
    @ViewBuilder let menu: (Book) -> Menu

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: spacing) {
                ForEach(books) { book in
                    NavigationLink(value: value(book)) {
                        Color.clear
                            .aspectRatio(2 / 3, contentMode: .fit)
                            .containerRelativeFrame(.horizontal) { width, _ in
                                (width - spacing * coversInView.rounded(.down)) / coversInView
                            }
                            .overlay {
                                GeometryReader { proxy in
                                    CoverView(book: book, width: proxy.size.width)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menu(book) }
                }
            }
            .padding(.vertical, 4)   // room for the covers' shadows
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }
}

/// Books as a grid of covers with their titles, each a link to `value(book)`.
struct BookGrid<Value: Hashable, Menu: View>: View {
    let books: [Book]
    let value: (Book) -> Value
    @ViewBuilder let menu: (Book) -> Menu

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 16, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(books) { book in
                NavigationLink(value: value(book)) {
                    BookTile(book: book, width: 100)
                }
                .buttonStyle(.plain)
                .contextMenu { menu(book) }
            }
        }
        .padding()
    }
}

/// A cover with its title and author underneath.
struct BookTile: View {
    let book: Book
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverView(book: book, width: width)
            Text(book.title)
                .font(.inter(.caption, .semibold))
                .lineLimit(2)
            Text(book.authorLine)
                .font(.inter(.caption2))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
    }
}
