import SwiftUI
import SwiftData

/// Books with one reading status, with swipe actions to move them on.
/// Has no NavigationStack of its own, so it can be a tab's root or pushed from Profile.
struct StatusBooksList: View {
    let status: ReadingStatus
    @Query private var books: [Book]
    @State private var bookToDelete: Book?
    /// The book whose progress is being logged.
    @State private var updating: Book?

    private var visible: [Book] {
        let matching = books.filter { $0.status == status }
        switch status {
        case .unread:   // newest additions first
            return matching.sorted { $0.dateAdded > $1.dateAdded }
        case .reading:  // most recently started first
            return matching.sorted { ($0.dateStarted ?? .distantPast) > ($1.dateStarted ?? .distantPast) }
        case .read:     // most recently finished first
            return matching.sorted { ($0.dateRead ?? .distantPast) > ($1.dateRead ?? .distantPast) }
        }
    }

    var body: some View {
        List(visible) { book in
            NavigationLink(value: book) {
                if status == .reading {
                    ReadingRow(book: book, onUpdate: { updating = book }, onFinish: { withAnimation { book.setStatus(.read) } })
                } else {
                    BookRow(book: book, showsFinishDate: status == .read)
                }
            }
            .swipeActions(edge: .leading) {
                // One button for each status the book isn't in yet.
                ForEach(ReadingStatus.allCases.filter { $0 != book.status }.reversed()) { newStatus in
                    Button(newStatus.actionTitle, systemImage: newStatus.systemImage) {
                        withAnimation { book.setStatus(newStatus) }
                    }
                    .tint(newStatus.tint)
                }
            }
            .swipeActions(edge: .trailing) {
                Button("Delete", systemImage: "trash", role: .destructive) { bookToDelete = book }
                .tint(.red)
            }
        }
        .themedScreen()
        .sheet(item: $updating) { book in
            ProgressSheet(book: book)
        }
        .confirmDeletingBook($bookToDelete)
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: status.systemImage, description: Text(emptyMessage))
            }
        }
    }

    private var emptyTitle: String {
        switch status {
        case .unread: "All caught up"
        case .reading: "Not reading anything"
        case .read: "Nothing finished yet"
        }
    }

    private var emptyMessage: String {
        switch status {
        case .reading: "Pick something from Explore and tap “Start reading”."
        default: "Books show up here when you mark them as read."
        }
    }
}

struct CurrentlyReadingView: View {
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            StatusBooksList(status: .reading)
                .themedScreen()
                .navigationTitle("Currently Reading")
                .navigationDestination(for: Book.self) { BookDetailView(book: $0) }
                .toolbar {
                    Button("Add book", systemImage: "plus") { showingAdd = true }
                }
                .sheet(isPresented: $showingAdd) {
                    AddBookSheet()
                }
        }
    }
}

#Preview {
    CurrentlyReadingView()
        .modelContainer(SampleData.previewContainer)
        .environment(AccountStore(container: SampleData.previewContainer))
}
