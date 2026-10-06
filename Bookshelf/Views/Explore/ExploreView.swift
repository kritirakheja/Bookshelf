import SwiftUI
import SwiftData

/// Browse your unread books by category: a list of categories, each with a few
/// covers, opening to a grid of that category's books.
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
                    List {
                        ForEach(categories) { category in
                            Section {
                                NavigationLink(value: ShelfRoute(id: category.id)) {
                                    CategoryRow(category: category)
                                }
                            }
                        }
                    }
                    .listSectionSpacing(14)
                }
            }
            .confirmDeletingBook($bookToDelete)
            .paperScreen()
            // No heading: the search box, always showing, says what the page is for.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Book.self) { BookDetailView(book: $0) }
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

// MARK: - Category row

/// A category's name, with its newest six covers underneath.
private struct CategoryRow: View {
    let category: ExploreShelves.Shelf

    private static let slots = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(category.title)
                .font(Theme.serif(.headline, .semibold))
            // Six equal slots that share the row's width, so the covers reach the edge.
            HStack(spacing: 8) {
                ForEach(0..<Self.slots, id: \.self) { slot in
                    Color.clear
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .overlay {
                            if slot < category.books.count {
                                GeometryReader { proxy in
                                    CoverView(book: category.books[slot], width: proxy.size.width)
                                }
                            }
                        }
                }
            }
        }
        .padding(.vertical, 6)
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
                NavigationLink(value: book) {
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
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            Text(book.authorLine)
                .font(.caption2)
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
