import SwiftUI
import SwiftData

/// The Favourites tab: the shelf of books you'd recommend most, then everything
/// you've read, year by year, against each year's goal.
struct FavoritesShelfView: View {
    @Query(filter: #Predicate<Book> { $0.favoriteRank != nil }, sort: \Book.favoriteRank)
    private var shelf: [Book]
    @Query private var books: [Book]
    @State private var editing = false

    var body: some View {
        let reading = ReadingYears(books: books)
        NavigationStack {
            Group {
                if editing {
                    editList
                } else {
                    showcase(reading)
                }
            }
            .themedScreen()
            .navigationTitle(editing ? "Rearrange" : "Favourites")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Book.self) { BookDetailView(book: $0) }
            .navigationDestination(for: YearRoute.self) { route in
                let yearBooks = route.year.map { year in reading.years.first { $0.year == year }?.books ?? [] } ?? reading.undated
                ScrollView { BookGrid(books: yearBooks, value: { $0 }, menu: { _ in EmptyView() }) }
                    .themedScreen()
                    .navigationTitle(route.year.map { "Read in \(String($0))" } ?? "Year not set")
            }
            .toolbar {
                if editing {
                    Button("Done") {
                        withAnimation { editing = false }
                    }
                    .fontWeight(.semibold)
                } else if !shelf.isEmpty {
                    Button("Rearrange", systemImage: "arrow.up.arrow.down") {
                        withAnimation { editing = true }
                    }
                }
            }
        }
    }

    // MARK: Showcase

    private func showcase(_ reading: ReadingYears) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                topFavourites
                Text("Read by year")
                    .font(.inter(.title3, .bold))
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                ForEach(reading.years) { year in
                    YearCard(year: year.year, books: year.books)
                        .padding(.horizontal, 16)
                }
                if !reading.undated.isEmpty {
                    UndatedCard(books: reading.undated)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
        }
    }

    /// The favourites as one shelf that scrolls sideways.
    private var topFavourites: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Favourites")
                .font(.inter(.title3, .bold))
                .padding(.horizontal, 16)
            if shelf.isEmpty {
                Text("Open any book and switch on Favourite to put it on this shelf.")
                    .font(.inter(.subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(shelf) { book in
                            NavigationLink(value: book) {
                                VStack(alignment: .leading, spacing: 10) {
                                    CoverView(book: book, width: Self.favouriteWidth)
                                    caption(book)
                                }
                                .frame(width: Self.favouriteWidth, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
            }
        }
    }

    /// Wide enough that two and a half covers show: a shelf, not a grid.
    private static let favouriteWidth: CGFloat = 132

    /// Title, author, and a two-part tag: the book's place on the shelf, then its rating.
    private func caption(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(book.title)
                .font(.inter(.subheadline, .semibold))
                .lineLimit(3)
            Text(book.authorLine)
                .font(.inter(.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            tag(book)
                .padding(.top, 2)
            if let note = book.recommendationNote, !note.isEmpty {
                Text("“\(note)”")
                    .font(.inter(.caption).italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.top, 2)
            }
        }
        .multilineTextAlignment(.leading)
    }

    private func tag(_ book: Book) -> some View {
        HStack(spacing: 0) {
            Text("#\(book.favoriteRank ?? 0)")
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 9)
            if let rating = book.rating, rating > 0 {
                Text("\(Image(systemName: "star.fill")) \(rating)")
                    .foregroundStyle(Theme.background)
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                    .background(Theme.accent)
            }
        }
        .font(.inter(.caption, .semibold).monospacedDigit())
        .frame(height: 22)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.accent, lineWidth: 1))
    }

    // MARK: Editing

    private var editList: some View {
        List {
            Section {
                ForEach(shelf) { book in
                    FavoriteEditRow(book: book)
                }
                .onMove { source, destination in
                    FavoritesShelf.move(library: shelf, fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    let removing = offsets.map { shelf[$0] }
                    for book in removing {
                        FavoritesShelf.remove(book, library: shelf)
                    }
                }
            } footer: {
                Text("Drag to reorder. Swipe to remove from the shelf (the book stays in your library).")
            }
        }
        .environment(\.editMode, .constant(.active))
    }
}

private struct FavoriteEditRow: View {
    @Bindable var book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("#\(book.favoriteRank ?? 0)  \(book.title)")
                .font(.inter(.headline))
            TextField("Why do you recommend it?", text: $book.recommendationNoteText, axis: .vertical)
            .font(.inter(.subheadline))
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    FavoritesShelfView()
        .modelContainer(SampleData.previewContainer)
}
