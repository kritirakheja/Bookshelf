import SwiftUI
import SwiftData

/// Browse your unread books by category: a card per category with its covers
/// scrolling sideways, opening to a grid of that category's books.
struct ExploreView: View {
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]
    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var bookToDelete: Book?

    /// A category's page.
    private struct ShelfRoute: Hashable {
        let id: String
    }

    private var shelves: ExploreShelves { ExploreShelves(books: books) }

    /// Unread books matching the search, for the results grid.
    private var searchResults: [Book] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return books.filter { book in
            book.status == .unread && !book.isGivenBack
                && (book.title.localizedStandardContains(query)
                    || book.authors.contains { $0.localizedStandardContains(query) })
        }
    }

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        let categories = shelves.categories
        NavigationStack {
            Group {
                if isSearching {
                    ScrollView { BookGrid(books: searchResults, menu: bookMenu) }
                } else {
                    // One card per category.
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(categories) { category in
                                CategoryCard(category: category, route: ShelfRoute(id: category.id), menu: bookMenu)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .confirmDeletingBook($bookToDelete)
            .paperScreen()
            // No heading: the search box, always showing, says what the page is for.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Book.self) { BookDetailView(book: $0) }
            .navigationDestination(for: PickedUp.self) { BackCoverView(book: $0.book) }
            .navigationDestination(for: ShelfRoute.self) { route in
                if let category = categories.first(where: { $0.id == route.id }) {
                    ScrollView { BookGrid(books: category.books, menu: bookMenu) }
                        .paperScreen()
                        .navigationTitle(category.title)
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find your next read")
            .toolbar {
                Button("Add book", systemImage: "plus") { showingAdd = true }
            }
            .sheet(isPresented: $showingAdd) {
                AddBookSheet()
            }
            .overlay {
                if categories.isEmpty {
                    ContentUnavailableView(
                        "Nothing unread",
                        systemImage: "books.vertical",
                        description: Text("Books you haven't read yet show up here. Tap + to add one.")
                    )
                } else if isSearching && searchResults.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    /// Long-press actions on any cover.
    @ViewBuilder
    private func bookMenu(_ book: Book) -> some View {
        if book.status != .reading {
            Button("Start reading", systemImage: ReadingStatus.reading.systemImage) {
                withAnimation { book.setStatus(.reading) }
            }
        }
        Button("Mark as read", systemImage: ReadingStatus.read.systemImage) {
            withAnimation { book.setStatus(.read) }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            bookToDelete = book
        }
    }
}

/// A book taken off the shelf here: opens to its back cover rather than its full page.
private struct PickedUp: Hashable {
    let book: Book
}

// MARK: - Category card

/// A category's name (tap for the full grid) over its covers, which scroll sideways.
private struct CategoryCard<Route: Hashable, Menu: View>: View {
    let category: ExploreShelves.Shelf
    let route: Route
    @ViewBuilder let menu: (Book) -> Menu

    private let spacing: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: route) {
                HStack {
                    Text(category.title)
                        .font(Font.inter(.headline, .semibold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.inter(.footnote, .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: spacing) {
                    ForEach(category.books) { book in
                        NavigationLink(value: PickedUp(book: book)) {
                            // Four covers and a sliver of the fifth, to show there's more.
                            Color.clear
                                .aspectRatio(2 / 3, contentMode: .fit)
                                .containerRelativeFrame(.horizontal) { width, _ in
                                    (width - spacing * 4) / 4.3
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
        .padding(.vertical, 16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

/// All of a category's books (or search results) as a grid.
private struct BookGrid<Menu: View>: View {
    let books: [Book]
    @ViewBuilder let menu: (Book) -> Menu

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 16, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(books) { book in
                NavigationLink(value: PickedUp(book: book)) {
                    BookTile(book: book, width: 100)
                }
                .buttonStyle(.plain)
                .contextMenu { menu(book) }
            }
        }
        .padding()
    }
}

private struct BookTile: View {
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

#Preview {
    ExploreView()
        .modelContainer(SampleData.previewContainer)
        .environment(AccountStore(container: SampleData.previewContainer))
}
