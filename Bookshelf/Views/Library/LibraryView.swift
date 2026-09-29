import SwiftUI
import SwiftData

enum LibrarySort: String, CaseIterable, Identifiable {
    case title = "Title"
    case author = "Author"
    case dateAdded = "Recently added"

    var id: Self { self }

    func areInIncreasingOrder(_ a: Book, _ b: Book) -> Bool {
        switch self {
        case .title:
            a.title.localizedStandardCompare(b.title) == .orderedAscending
        case .author:
            a.authorLine.localizedStandardCompare(b.authorLine) == .orderedAscending
        case .dateAdded:
            a.dateAdded > b.dateAdded
        }
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query private var books: [Book]
    @State private var searchText = ""
    @State private var sort: LibrarySort = .title
    @State private var showingAdd = false
    @State private var fillingCovers = false
    @State private var bookToDelete: Book?
    @State private var coverResult: (found: Int, total: Int)?

    private var booksWithoutCovers: [Book] { books.filter { $0.coverImage == nil } }

    private var visibleBooks: [Book] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let matching = query.isEmpty ? books : books.filter { book in
            book.title.localizedStandardContains(query)
                || book.authors.contains { $0.localizedStandardContains(query) }
        }
        return matching.sorted(by: sort.areInIncreasingOrder)
    }

    var body: some View {
        List {
            ForEach(visibleBooks) { book in
                NavigationLink(value: book) {
                    BookRow(book: book)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) { bookToDelete = book }
                }
            }
        }
        .confirmDeletingBook($bookToDelete)
        .navigationTitle("All Books")
        .searchable(text: $searchText, prompt: "Title or author")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Section {
                        Button("Find missing covers", systemImage: "photo.on.rectangle") {
                            findMissingCovers()
                        }
                        .disabled(fillingCovers || booksWithoutCovers.isEmpty)
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
            if fillingCovers {
                ToolbarItem(placement: .principal) {
                    ProgressView().controlSize(.small)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add book", systemImage: "plus") { showingAdd = true }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddBookSheet()
        }
        .alert(
            "Covers",
            isPresented: Binding(get: { coverResult != nil }, set: { if !$0 { coverResult = nil } }),
            presenting: coverResult
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { result in
            Text("Found \(result.found) of \(result.total) missing covers.")
        }
        .overlay {
            if books.isEmpty {
                ContentUnavailableView(
                    "No books yet",
                    systemImage: "books.vertical",
                    description: Text("Tap + to add the first book on your shelf.")
                )
            } else if visibleBooks.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    /// One book at a time, to go easy on Open Library's free API.
    private func findMissingCovers() {
        let missing = booksWithoutCovers
        fillingCovers = true
        Task {
            let client = BookLookup()
            var found = 0
            for book in missing {
                if await client.fillMissingCover(of: book) {
                    found += 1
                }
            }
            fillingCovers = false
            coverResult = (found, missing.count)
        }
    }

}

#Preview {
    NavigationStack { LibraryView() }
        .modelContainer(SampleData.previewContainer)
        .environment(AccountStore(container: SampleData.previewContainer))
}
