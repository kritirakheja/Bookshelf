import SwiftUI
import SwiftData

/// The Reading tab: the book you last picked up, large, then the others in progress.
/// Whichever book you update moves to the top.
struct CurrentlyReadingView: View {
    @Query(filter: #Predicate<Book> { $0.isReading && !$0.isRead }) private var books: [Book]
    @State private var showingAdd = false
    @State private var bookToDelete: Book?
    /// The book whose progress is being logged.
    @State private var updating: Book?
    @Environment(\.colorScheme) private var colorScheme

    /// Most recently updated (or started) first.
    static func ordered(_ books: [Book]) -> [Book] {
        books.sorted { ($0.lastActivity, $0.title) > ($1.lastActivity, $1.title) }
    }

    var body: some View {
        let reading = Self.ordered(books)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let latest = reading.first {
                        FeaturedReadingCard(book: latest, onUpdate: { updating = latest }, onFinish: { finish(latest) })
                            .tint(latest.accentColor(for: colorScheme))
                            .contextMenu { menu(for: latest) }
                            .id(latest.persistentModelID)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                    if reading.count > 1 {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: "Also reading")
                                .padding(.horizontal, 4)
                            VStack(spacing: 0) {
                                ForEach(Array(reading.dropFirst().enumerated()), id: \.element.persistentModelID) { index, book in
                                    if index > 0 { Divider() }
                                    ReadingRow(book: book) { updating = book }
                                        .contextMenu { menu(for: book) }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.rule.opacity(0.6), lineWidth: 0.5))
                        }
                    }
                }
                // Full width even with nothing in it: an empty stack would collapse the
                // whole screen to a sliver.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .animation(.snappy, value: reading.map(\.persistentModelID))
            }
            .themedScreen()
            .navigationTitle("Currently Reading")
            .navigationDestination(for: Book.self) { BookDetailView(book: $0) }
            .toolbar {
                Button("Add book", systemImage: "plus") { showingAdd = true }
            }
            .sheet(isPresented: $showingAdd) {
                AddBookSheet()
            }
            .sheet(item: $updating) { book in
                ProgressSheet(book: book)
            }
            .confirmDeletingBook($bookToDelete)
            .overlay {
                if reading.isEmpty {
                    ContentUnavailableView(
                        "Not reading anything",
                        systemImage: ReadingStatus.reading.systemImage,
                        description: Text("Pick something from Explore and tap “Start reading”.")
                    )
                }
            }
        }
    }

    private func finish(_ book: Book) {
        withAnimation { book.setStatus(.read) }
    }

    /// Long-press actions on any book here.
    @ViewBuilder
    private func menu(for book: Book) -> some View {
        Button("Update progress", systemImage: "bookmark") { updating = book }
        Button("Finished", systemImage: ReadingStatus.read.systemImage) { finish(book) }
        Button("Back to unread", systemImage: ReadingStatus.unread.systemImage) {
            withAnimation { book.setStatus(.unread) }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { bookToDelete = book }
    }
}

#Preview {
    CurrentlyReadingView()
        .modelContainer(SampleData.previewContainer)
        .environment(AccountStore(container: SampleData.previewContainer))
}
