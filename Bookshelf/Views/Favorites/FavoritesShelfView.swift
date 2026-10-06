import SwiftUI
import SwiftData

struct FavoritesShelfView: View {
    @Query(filter: #Predicate<Book> { $0.favoriteRank != nil }, sort: \Book.favoriteRank)
    private var shelf: [Book]
    @State private var editing = false

    private let perShelf = 3

    var body: some View {
        NavigationStack {
            Group {
                if editing {
                    editList
                } else {
                    showcase
                }
            }
            .paperScreen()
            .navigationTitle(editing ? "Rearrange" : "Top Favourites")
            .navigationDestination(for: Book.self) { BookDetailView(book: $0) }
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
            .overlay {
                if shelf.isEmpty {
                    ContentUnavailableView(
                        "Your shelf is empty",
                        systemImage: "star",
                        description: Text("Open any book and tap “Recommend it” to put it here.")
                    )
                }
            }
        }
    }

    // MARK: Showcase

    /// The favourites in rows of three, with the titles written underneath.
    private var showcase: some View {
        ScrollView {
            VStack(spacing: 30) {
                ForEach(Array(shelves.enumerated()), id: \.offset) { _, row in
                    shelfRow(row)
                }
            }
            .padding(.vertical, 24)
        }
    }

    private var shelves: [[Book]] {
        stride(from: 0, to: shelf.count, by: perShelf).map { Array(shelf[$0..<min($0 + perShelf, shelf.count)]) }
    }

    private func shelfRow(_ row: [Book]) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 16) {
                    ForEach(0..<perShelf, id: \.self) { column in
                        if column < row.count {
                            NavigationLink(value: row[column]) {
                                CoverView(book: row[column], width: 100)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
                .padding(.horizontal, 22)
            }
            HStack(alignment: .top, spacing: 16) {
                ForEach(0..<perShelf, id: \.self) { column in
                    if column < row.count {
                        NavigationLink(value: row[column]) {
                            caption(row[column])
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
            .padding(.horizontal, 22)
        }
    }

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
                    .foregroundStyle(Theme.paper)
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
            TextField("Why do you recommend it?", text: Binding(
                get: { book.recommendationNote ?? "" },
                set: { book.recommendationNote = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .font(.inter(.subheadline))
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    FavoritesShelfView()
        .modelContainer(SampleData.previewContainer)
}
