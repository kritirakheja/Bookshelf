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
            .background(WoodGrain())
            .navigationDestination(for: Book.self) { BookDetailView(book: $0) }
        }
    }

    // MARK: Showcase

    /// The bookcase: a cream title pill, then the favourites face-out in rows of
    /// three, each row on its own shelf with the titles written underneath.
    private var showcase: some View {
        ScrollView {
            VStack(spacing: 34) {
                header
                if shelf.isEmpty {
                    emptyShelf
                } else {
                    ForEach(Array(shelves.enumerated()), id: \.offset) { _, row in
                        shelfRow(row)
                    }
                }
            }
            .padding(.bottom, 30)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var shelves: [[Book]] {
        stride(from: 0, to: shelf.count, by: perShelf).map { Array(shelf[$0..<min($0 + perShelf, shelf.count)]) }
    }

    private var header: some View {
        ZStack {
            HStack(spacing: 6) {
                Text("Top Favourites")
                    .font(.headline)
                Text("\(shelf.count) of \(FavoritesShelf.capacity)")
                    .font(.subheadline)
                    .foregroundStyle(WoodenShelfStyle.faded)
            }
            .foregroundStyle(WoodenShelfStyle.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(WoodenShelfStyle.cream, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)

            if !shelf.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        withAnimation { editing = true }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(CreamButtonStyle())
                    .accessibilityLabel("Rearrange favourites")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func shelfRow(_ row: [Book]) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(0..<perShelf, id: \.self) { column in
                    if column < row.count {
                        NavigationLink(value: row[column]) {
                            CoverView(book: row[column], width: 104)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    } else {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, -14)   // covers stand on the shelf
            WallShelf()
            HStack(alignment: .top, spacing: 18) {
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
            .padding(.horizontal, 20)
        }
    }

    /// Title, author, and a two-part tag: the book's place on the shelf, then its rating.
    private func caption(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(book.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WoodenShelfStyle.ink)
                .lineLimit(3)
            Text(book.authorLine)
                .font(.caption)
                .foregroundStyle(WoodenShelfStyle.faded)
                .lineLimit(1)
            tag(book)
                .padding(.top, 2)
            if let note = book.recommendationNote, !note.isEmpty {
                Text("“\(note)”")
                    .font(BookPageStyle.handwriting(13))
                    .foregroundStyle(WoodenShelfStyle.ink.opacity(0.8))
                    .lineLimit(3)
                    .padding(.top, 2)
            }
        }
        .multilineTextAlignment(.leading)
    }

    private func tag(_ book: Book) -> some View {
        HStack(spacing: 0) {
            Text("#\(book.favoriteRank ?? 0)")
                .padding(.horizontal, 9)
            if let rating = book.rating, rating > 0 {
                Text("\(Image(systemName: "star.fill")) \(rating)")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                    .background(WoodenShelfStyle.tag)
            }
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .foregroundStyle(WoodenShelfStyle.ink)
        .frame(height: 22)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(WoodenShelfStyle.tag, lineWidth: 1))
    }

    private var emptyShelf: some View {
        VStack(spacing: 18) {
            WallShelf()
                .padding(.top, 120)
            VStack(spacing: 8) {
                Text("Your shelf is empty")
                    .font(.headline)
                Text("Open any book and tap “Recommend it” to put it here.")
                    .font(.subheadline)
                    .foregroundStyle(WoodenShelfStyle.faded)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(WoodenShelfStyle.ink)
            .padding(.horizontal, 40)
        }
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
                .listRowBackground(WoodenShelfStyle.cream)
            } footer: {
                Text("Drag to reorder. Swipe to remove from the shelf (the book stays in your library).")
                    .foregroundStyle(WoodenShelfStyle.ink.opacity(0.75))
            }
        }
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Rearrange")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Done") {
                withAnimation { editing = false }
            }
            .fontWeight(.semibold)
        }
    }
}

private struct FavoriteEditRow: View {
    @Bindable var book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("#\(book.favoriteRank ?? 0)  \(book.title)")
                .font(.headline)
            TextField("Why do you recommend it?", text: Binding(
                get: { book.recommendationNote ?? "" },
                set: { book.recommendationNote = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    FavoritesShelfView()
        .modelContainer(SampleData.previewContainer)
}
