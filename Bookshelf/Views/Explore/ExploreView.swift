import SwiftUI
import SwiftData

/// Browse your unread books Netflix-style: featured picks up top, then shelves you
/// swipe through sideways (continue reading, recently added, quick reads, categories…).
struct ExploreView: View {
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]
    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var bookToDelete: Book?

    /// A shelf's "See all" page.
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
        let shelves = shelves
        NavigationStack {
            ScrollView {
                if isSearching {
                    BookGrid(books: searchResults, menu: bookMenu)
                } else {
                    VStack(alignment: .leading, spacing: 28) {
                        if !shelves.featured.isEmpty {
                            FeaturedCarousel(books: shelves.featured)
                        }
                        ForEach(shelves.shelves) { shelf in
                            ShelfRow(shelf: shelf, route: ShelfRoute(id: shelf.id), menu: bookMenu)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .confirmDeletingBook($bookToDelete)
            .navigationTitle("Explore")
            .navigationDestination(for: Book.self) { BookDetailView(book: $0) }
            .navigationDestination(for: ShelfRoute.self) { route in
                if let shelf = shelves.shelves.first(where: { $0.id == route.id }) {
                    ScrollView { BookGrid(books: shelf.books, menu: bookMenu) }
                        .navigationTitle(shelf.title)
                }
            }
            .searchable(text: $searchText, prompt: "Search unread books")
            .toolbar {
                Button("Add book", systemImage: "plus") { showingAdd = true }
            }
            .sheet(isPresented: $showingAdd) {
                AddBookSheet()
            }
            .overlay {
                if shelves.shelves.isEmpty && shelves.featured.isEmpty {
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

// MARK: - Featured

/// Big, swipeable picks at the top, on a blurred wash of the cover.
private struct FeaturedCarousel: View {
    let books: [Book]
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                FeaturedCard(book: book).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: books.count > 1 ? .always : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .frame(height: 440)
    }
}

private struct FeaturedCard: View {
    let book: Book

    var body: some View {
        ZStack(alignment: .bottom) {
            backdrop
            VStack(spacing: 14) {
                NavigationLink(value: book) {
                    CoverView(book: book, width: 150)
                        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                }
                .buttonStyle(.plain)

                VStack(spacing: 4) {
                    Text(book.title)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(book.authorLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !book.categories.isEmpty {
                        Text(book.sortedCategories.map(\.name).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                HStack(spacing: 12) {
                    Button {
                        withAnimation { book.setStatus(.reading) }
                    } label: {
                        Label("Start reading", systemImage: "book.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(minWidth: 130)
                    }
                    .buttonStyle(.borderedProminent)

                    NavigationLink(value: book) {
                        Label("Details", systemImage: "info.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding(.bottom, 40)
        }
    }

    /// The cover, blown up and blurred, fading into the page.
    private var backdrop: some View {
        GeometryReader { proxy in
            ZStack {
                if let data = book.coverImage, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: 40)
                        .opacity(0.55)
                        .clipped()
                }
                LinearGradient(
                    colors: [.clear, Color(.systemBackground).opacity(0.6), Color(.systemBackground)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
    }
}

// MARK: - Shelves

/// A titled row of covers that scrolls sideways, with "See all".
private struct ShelfRow<Route: Hashable, Menu: View>: View {
    let shelf: ExploreShelves.Shelf
    let route: Route
    @ViewBuilder let menu: (Book) -> Menu

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(shelf.title)
                    .font(.title3.weight(.bold))
                Text("\(shelf.books.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if shelf.books.count > 3 {
                    NavigationLink(value: route) {
                        Text("See all").font(.subheadline)
                    }
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(shelf.books) { book in
                        NavigationLink(value: book) {
                            BookTile(book: book, width: 110)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { menu(book) }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// All of a shelf's books (or search results) as a grid.
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
