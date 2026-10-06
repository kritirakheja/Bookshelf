import SwiftUI
import SwiftData

enum LibraryLayout: String {
    /// Stored as "shelves", its name when covers stood on drawn shelves.
    case covers = "shelves"
    case list
}

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
    /// Rows of covers (default) or the plain list; remembered.
    @AppStorage("libraryLayout") private var layout = LibraryLayout.covers

    private var booksWithoutCovers: [Book] { books.filter { $0.coverImage == nil } }

    private var visibleBooks: [Book] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let matching = query.isEmpty ? books : books.filter { $0.matches(search: query) }
        return matching.sorted(by: sort.areInIncreasingOrder)
    }

    var body: some View {
        Group {
            switch layout {
            case .covers:
                CoverRows(sections: LibrarySections.split(visibleBooks)) { book in bookMenu(book) }
            case .list:
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
            }
        }
        .confirmDeletingBook($bookToDelete)
        .themedScreen()
        .navigationTitle("All Books")
        .searchable(text: $searchText, prompt: "Title or author")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("View", selection: $layout) {
                        Label("Shelves", systemImage: "books.vertical").tag(LibraryLayout.covers)
                        Label("List", systemImage: "list.bullet").tag(LibraryLayout.list)
                    }
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

    /// Long-press actions on a cover.
    @ViewBuilder
    private func bookMenu(_ book: Book) -> some View {
        if book.status != .reading {
            Button("Start reading", systemImage: ReadingStatus.reading.systemImage) {
                withAnimation { book.setStatus(.reading) }
            }
        }
        if book.status != .read {
            Button("Mark as read", systemImage: ReadingStatus.read.systemImage) {
                withAnimation { book.setStatus(.read) }
            }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { bookToDelete = book }
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
