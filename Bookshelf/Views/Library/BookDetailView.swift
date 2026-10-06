import SwiftUI
import SwiftData

/// A book's page: the cover on a shelf, its categories, then plain cards for
/// reading status, favourite, description, lending and notes.
struct BookDetailView: View {
    @Bindable var book: Book
    @State private var editing = false
    @State private var pickingCategories = false
    @State private var showingShelfFull = false
    @State private var searchingCover = false
    @State private var coverNotFound = false
    @State private var bookToDelete: Book?
    @State private var choosingCover = false
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Book> { $0.favoriteRank != nil }) private var shelf: [Book]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hero
                shelfLabels
                ReadingCard(book: book)
                FavouriteCard(book: book, shelf: shelf, showingShelfFull: $showingShelfFull)
                BlurbCard(book: book)
                LibraryCard(book: book)
                NotesCard(book: book)
                footer
            }
            .padding(.bottom, 30)
        }
        .background(Theme.paper.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .confirmDeletingBook($bookToDelete) {
            // Leave this page first, so it never shows a deleted book.
            dismiss()
            try? await Task.sleep(for: .milliseconds(450))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { editing = true }
        }
        .sheet(isPresented: $editing) {
            BookFormView(book: book)
        }
        .sheet(isPresented: $choosingCover) {
            CoverChooserView(title: book.title, author: book.authors.first, isbn: book.isbn) { data in
                book.coverImage = data
            }
        }
        .sheet(isPresented: $pickingCategories) {
            CategoryPickerView(book: book)
        }
        .alert("Your shelf is full", isPresented: $showingShelfFull) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can have up to \(FavoritesShelf.capacity) favourites. Remove one from the Favourites tab first.")
        }
    }

    // MARK: - Display shelf

    /// The cover standing face-out on a shelf under a spotlight, its own colours
    /// blurred into the wall behind it.
    private var hero: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .bottom) {
                backdrop
                VStack(spacing: 0) {
                    CoverView(book: book, width: 150)
                        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 10)
                        .padding(.bottom, -2)
                    Plank()
                        .padding(.horizontal, 50)
                }
                .padding(.top, 36)
            }
            VStack(spacing: 6) {
                Text(book.title)
                    .font(Theme.serif(.title, .bold))
                    .multilineTextAlignment(.center)
                if !book.authors.isEmpty {
                    Text("by \(book.authorLine)")
                        .font(Theme.serif(.title3).italic())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if !facts.isEmpty {
                    Text(facts.joined(separator: "  ·  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private var backdrop: some View {
        ZStack {
            if let data = book.coverImage, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 40)
                    .opacity(0.45)
            }
            // Spotlight from above.
            RadialGradient(colors: [.white.opacity(0.55), .clear], center: .top, startRadius: 10, endRadius: 260)
                .blendMode(.softLight)
            LinearGradient(colors: [.clear, Theme.paper], startPoint: .center, endPoint: .bottom)
        }
        .frame(height: 290)
        .frame(maxWidth: .infinity)
        .clipped()
        .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .bottom))
    }

    private var facts: [String] {
        var facts: [String] = []
        if let year = book.publishedYear { facts.append(String(year)) }
        if let pages = book.pageCount { facts.append("\(pages) pages") }
        return facts
    }

    // MARK: - Shelf labels

    /// Categories as chips; tap to change them.
    private var shelfLabels: some View {
        FlowLayout(spacing: 8) {
            ForEach(book.sortedCategories) { category in
                Button { pickingCategories = true } label: {
                    shelfLabel(category.name)
                }
            }
            Button { pickingCategories = true } label: {
                shelfLabel(book.categories.isEmpty ? "Add categories" : "Edit", systemImage: book.categories.isEmpty ? "plus" : "pencil", faded: true)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    private func shelfLabel(_ text: String, systemImage: String? = nil, faded: Bool = false) -> some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.caption2) }
            Text(text)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(faded ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.brown))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(faded ? Color.clear : Theme.brown.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(Theme.rule, lineWidth: faded ? 1 : 0))
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                if book.coverImage != nil {
                    Button("Change cover", systemImage: "photo.on.rectangle") { choosingCover = true }
                } else if searchingCover {
                    ProgressView()
                } else {
                    Button("Find cover online", systemImage: "magnifyingglass") { findCover() }
                }
                Button("Edit details", systemImage: "pencil") { editing = true }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(Theme.brown)
            if coverNotFound {
                Text("No cover found online.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Delete book", systemImage: "trash", role: .destructive) {
                bookToDelete = book
            }
            .font(.footnote)
        }
    }

    private func findCover() {
        searchingCover = true
        Task {
            let found = await BookLookup().fillMissingCover(of: book)
            coverNotFound = !found
            searchingCover = false
        }
    }
}

#Preview {
    let container = SampleData.previewContainer
    let book = try! container.mainContext.fetch(FetchDescriptor<Book>()).first!
    return NavigationStack { BookDetailView(book: book) }
        .modelContainer(container)
        .environment(AccountStore(container: container))
}
