import SwiftUI
import SwiftData

extension ReadingStatus {
    /// One colour per status everywhere: list icons, swipe buttons, the book page's ribbons.
    var tint: Color {
        switch self {
        case .unread: Color(red: 0.45, green: 0.50, blue: 0.58)
        case .reading: Color(red: 0.20, green: 0.45, blue: 0.70)
        case .read: Color(red: 0.62, green: 0.20, blue: 0.22)
        }
    }
}

/// Books with one reading status, with swipe actions to move them on.
/// Has no NavigationStack of its own, so it can be a tab's root or pushed from Profile.
struct StatusBooksList: View {
    let status: ReadingStatus
    @Query private var books: [Book]
    @State private var bookToDelete: Book?

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
                BookRow(book: book, showsFinishDate: status == .read, showsStartDate: status == .reading)
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
            }
        }
        .paperScreen()
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
        default: "Swipe right on a book to change its status."
        }
    }
}

struct CurrentlyReadingView: View {
    var body: some View {
        NavigationStack {
            StatusBooksList(status: .reading)
                .paperScreen()
                .navigationTitle("Currently Reading")
                .navigationDestination(for: Book.self) { BookDetailView(book: $0) }
        }
    }
}

#Preview {
    CurrentlyReadingView()
        .modelContainer(SampleData.previewContainer)
        .environment(AccountStore(container: SampleData.previewContainer))
}
