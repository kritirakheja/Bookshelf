import SwiftUI

/// Books as rows of face-out covers, in titled sections (Fiction, Non-fiction).
struct CoverRows<Menu: View>: View {
    let sections: [LibrarySections.Section]
    @ViewBuilder let menu: (Book) -> Menu

    private let coverWidth: CGFloat = 100
    private let spacing: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let perRow = Self.booksPerRow(width: proxy.size.width, coverWidth: coverWidth, spacing: spacing)
            // Headings line up with the left edge of the covers below them.
            let inset = (proxy.size.width - CGFloat(perRow) * coverWidth - CGFloat(perRow - 1) * spacing) / 2
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(sections) { section in
                        SectionHeader(title: section.title, count: section.books.count)
                            .padding(.horizontal, max(inset, 16))
                            .padding(.top, section.id == sections.first?.id ? 0 : 16)
                        ForEach(section.books.chunked(into: perRow), id: \.first!.persistentModelID) { row in
                            CoverRow(books: row, perRow: perRow, coverWidth: coverWidth, spacing: spacing, menu: menu)
                        }
                    }
                }
                .padding(.vertical, 24)
            }
            .background(Theme.background.ignoresSafeArea())
        }
    }

    /// As many covers as fit across the screen: 3 on an iPhone, more on wider screens.
    static func booksPerRow(width: CGFloat, coverWidth: CGFloat, spacing: CGFloat) -> Int {
        max(2, Int((width - 44 + spacing) / (coverWidth + spacing)))
    }
}

/// A section's title and how many books it holds.
struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.inter(.title3, .bold))
            Text("\(count)")
                .font(.inter(.subheadline))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One row of face-out covers.
struct CoverRow<Menu: View>: View {
    let books: [Book]
    let perRow: Int
    let coverWidth: CGFloat
    let spacing: CGFloat
    @ViewBuilder let menu: (Book) -> Menu

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(books) { book in
                    NavigationLink(value: book) {
                        CoverView(book: book, width: coverWidth)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menu(book) }
                }
                // Keep a part-filled last row aligned to the left.
                if books.count < perRow {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 22)
        }
    }
}
