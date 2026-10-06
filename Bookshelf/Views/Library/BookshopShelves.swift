import SwiftUI

/// Books displayed like a bookshop: covers face-out, a row per wooden shelf,
/// against a warm backdrop, in signed sections (Fiction, Non-fiction).
struct BookshopShelves<Menu: View>: View {
    let sections: [LibrarySections.Section]
    @ViewBuilder let menu: (Book) -> Menu

    private let coverWidth: CGFloat = 100
    private let spacing: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let perShelf = Self.booksPerShelf(width: proxy.size.width, coverWidth: coverWidth, spacing: spacing)
            ScrollView {
                LazyVStack(spacing: 30) {
                    ForEach(sections) { section in
                        SectionSign(title: section.title, count: section.books.count)
                            .padding(.top, section.id == sections.first?.id ? 0 : 20)
                        ForEach(Self.shelves(section.books, perShelf: perShelf), id: \.first!.persistentModelID) { shelf in
                            BookshopShelf(books: shelf, perShelf: perShelf, coverWidth: coverWidth, spacing: spacing, menu: menu)
                        }
                    }
                }
                .padding(.vertical, 24)
            }
            .background(BookshopWall())
        }
    }

    /// As many covers as fit across the screen: 3 on an iPhone, more on wider screens.
    static func booksPerShelf(width: CGFloat, coverWidth: CGFloat, spacing: CGFloat) -> Int {
        max(2, Int((width - 44 + spacing) / (coverWidth + spacing)))
    }

    static func shelves(_ books: [Book], perShelf: Int) -> [[Book]] {
        stride(from: 0, to: books.count, by: perShelf).map { Array(books[$0..<min($0 + perShelf, books.count)]) }
    }
}

/// The sign over a section, like the boards above a bookshop's aisles.
struct SectionSign: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .font(.system(.title3, design: .serif, weight: .bold))
                .tracking(2)
            Text("\(count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().stroke(Theme.rule, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
    }
}

/// One shelf of face-out covers.
struct BookshopShelf<Menu: View>: View {
    let books: [Book]
    let perShelf: Int
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
                // Keep a part-filled last shelf aligned to the left.
                if books.count < perShelf {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 22)
            Plank()
        }
    }
}

/// A wooden shelf (also under the cover on a book's page): a lighter top surface over a darker front edge, casting a shadow.
struct Plank: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color(red: 0.72, green: 0.52, blue: 0.34), Color(red: 0.62, green: 0.43, blue: 0.27)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 8)
            LinearGradient(colors: [Color(red: 0.50, green: 0.33, blue: 0.20), Color(red: 0.40, green: 0.26, blue: 0.15)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 5)
        .padding(.horizontal, 10)
    }
}

/// The wall behind the shelves: the app's paper.
struct BookshopWall: View {
    var body: some View {
        Theme.paper.ignoresSafeArea()
    }
}
