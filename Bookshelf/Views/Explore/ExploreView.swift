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
    private struct CategoryRoute: Hashable {
        let id: String
    }

    private var explore: ExploreCategories { ExploreCategories(books: books) }

    /// Unread books matching the search, for the results grid.
    private var searchResults: [Book] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return books.filter { $0.status == .unread && !$0.isGivenBack && $0.matches(search: query) }
    }

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        let categories = explore.categories
        NavigationStack {
            Group {
                if isSearching {
                    ScrollView { BookGrid(books: searchResults, value: { PickedUp(book: $0) }, menu: bookMenu) }
                } else {
                    // One card per category.
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(categories) { category in
                                CategoryCard(category: category, route: CategoryRoute(id: category.id), menu: bookMenu)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .confirmDeletingBook($bookToDelete)
            .themedScreen()
            // No heading: the search box, always showing, says what the page is for.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Book.self) { BookDetailView(book: $0) }
            .navigationDestination(for: PickedUp.self) { BackCoverView(book: $0.book) }
            .navigationDestination(for: CategoryRoute.self) { route in
                if let category = categories.first(where: { $0.id == route.id }) {
                    ScrollView { BookGrid(books: category.books, value: { PickedUp(book: $0) }, menu: bookMenu) }
                        .themedScreen()
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
    let category: ExploreCategories.Category
    let route: Route
    @ViewBuilder let menu: (Book) -> Menu

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: route) {
                HStack {
                    Text(category.title)
                        .font(.inter(.headline, .semibold))
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

            CoverStrip(books: category.books, value: { PickedUp(book: $0) }, menu: menu)
        }
        .padding(.vertical, 16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

#Preview {
    ExploreView()
        .modelContainer(SampleData.previewContainer)
        .environment(AccountStore(container: SampleData.previewContainer))
}
