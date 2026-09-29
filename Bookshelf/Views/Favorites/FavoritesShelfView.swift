import SwiftUI
import SwiftData

struct FavoritesShelfView: View {
    @Query(filter: #Predicate<Book> { $0.favoriteRank != nil }, sort: \Book.favoriteRank)
    private var shelf: [Book]
    @State private var editing = false

    var body: some View {
        NavigationStack {
            Group {
                if editing {
                    editList
                } else {
                    showcase
                }
            }
            .navigationTitle("Top Favourites")
            .navigationDestination(for: Book.self) { BookDetailView(book: $0) }
            .toolbar {
                if !shelf.isEmpty {
                    Button(editing ? "Done" : "Edit") {
                        withAnimation { editing.toggle() }
                    }
                }
            }
            .overlay {
                if shelf.isEmpty {
                    ContentUnavailableView(
                        "Your shelf is empty",
                        systemImage: "star",
                        description: Text("Open any book and tap “Add to favourites” to recommend it here.")
                    )
                }
            }
        }
    }

    // MARK: Showcase

    private var showcase: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 16) {
                        ForEach(shelf) { book in
                            NavigationLink(value: book) {
                                CoverView(book: book, width: 120)
                                    .overlay(alignment: .topLeading) { rankBadge(book) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                    .background(alignment: .bottom) { plank }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Why I recommend them")
                        .font(.title3.weight(.semibold))
                    ForEach(shelf) { book in
                        NavigationLink(value: book) {
                            recommendationCard(book)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
        }
    }

    private var plank: some View {
        LinearGradient(colors: [.brown.opacity(0.9), .brown.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 3)
            .offset(y: 8)
    }

    private func rankBadge(_ book: Book) -> some View {
        Text("\(book.favoriteRank ?? 0)")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(.yellow.gradient, in: Circle())
            .shadow(radius: 1)
            .offset(x: -6, y: -6)
    }

    private func recommendationCard(_ book: Book) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("#\(book.favoriteRank ?? 0)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title).font(.headline)
                Text(book.authorLine).font(.subheadline).foregroundStyle(.secondary)
                if let note = book.recommendationNote, !note.isEmpty {
                    Text("“\(note)”")
                        .font(.body.italic())
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
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
