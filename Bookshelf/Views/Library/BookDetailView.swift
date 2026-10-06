import SwiftUI
import SwiftData

/// A book's full details, in order of importance: the cover on a gradient of its own
/// colours, its name and categories, what it's about, reading status, then the rest.
struct BookDetailView: View {
    @Bindable var book: Book
    @State private var editing = false
    @State private var pickingCategories = false
    @State private var showingShelfFull = false
    @State private var searchingCover = false
    @State private var coverNotFound = false
    @State private var bookToDelete: Book?
    @State private var choosingCover = false
    @State private var gradient = (top: CoverColor.fallback, bottom: CoverColor.fallback)
    @State private var coverArt: UIImage?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Query(filter: #Predicate<Book> { $0.favoriteRank != nil }) private var shelf: [Book]

    /// The share of the screen the cover and its gradient take.
    private static let heroShare = 0.6

    var body: some View {
        GeometryReader { proxy in
            let screenHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            let heroHeight = (screenHeight * Self.heroShare).rounded()
            ScrollView {
                VStack(spacing: 24) {
                    hero(height: heroHeight, topInset: proxy.safeAreaInsets.top)
                    Group {
                        name
                        AboutBlock(book: book)
                        StatusSection(book: book)
                    }
                    .padding(.horizontal, 20)
                    more
                }
                .padding(.bottom, 30)
            }
            .ignoresSafeArea(edges: .top)
            .task(id: book.coverImage) {
                gradient = CoverColor.gradient(of: book.coverImage)
                // Drawn at up to 3× the size it's shown, sharpened if the file is small.
                let width = heroHeight * Self.coverShare / 1.5
                coverArt = book.coverImage.flatMap { CoverImage.enlarged($0, toWidth: width * 3) }
            }
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

    // MARK: - Cover

    /// The cover's height as a share of the hero's.
    private static let coverShare = 0.64

    /// The cover, large, on a gradient made from its own top and bottom colours.
    private func hero(height: CGFloat, topInset: CGFloat) -> some View {
        let coverHeight = height * Self.coverShare
        let coverWidth = coverHeight / 1.5
        return ZStack {
            LinearGradient(colors: [color(gradient.top), color(gradient.bottom)], startPoint: .top, endPoint: .bottom)
            // Melt into the page rather than ending in a line.
            LinearGradient(colors: [.clear, Theme.paper], startPoint: UnitPoint(x: 0.5, y: 0.8), endPoint: .bottom)
            Group {
                if let coverArt {
                    Image(uiImage: coverArt)
                        .resizable()
                        .scaledToFill()
                        .frame(width: coverWidth, height: coverHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    CoverView(book: book, width: coverWidth)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 14)
            // Centred in the space below the navigation bar.
            .padding(.top, topInset * 0.6)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.3), value: gradient.top)
    }

    /// Dimmed in dark mode, so a pale cover doesn't glare or hide the status bar.
    private func color(_ rgb: CoverColor.RGB) -> Color {
        let dim = colorScheme == .dark ? 0.55 : 1
        return Color(red: rgb.r * dim, green: rgb.g * dim, blue: rgb.b * dim)
    }

    // MARK: - Name

    private var name: some View {
        VStack(spacing: 6) {
            Text(book.title)
                .font(.inter(.title, .bold))
                .multilineTextAlignment(.center)
            if !book.authors.isEmpty {
                Text(book.authorLine)
                    .font(.inter(.title3))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            categories
                .padding(.vertical, 6)
            if !facts.isEmpty {
                Text(facts.joined(separator: "  ·  "))
                    .font(.inter(.footnote))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var facts: [String] {
        var facts: [String] = []
        if let year = book.publishedYear { facts.append(String(year)) }
        if let pages = book.pageCount { facts.append("\(pages) pages") }
        return facts
    }

    // MARK: - Categories

    /// Categories as chips; tap to change them.
    private var categories: some View {
        FlowLayout(spacing: 8) {
            ForEach(book.sortedCategories) { category in
                Button { pickingCategories = true } label: {
                    chip(category.name)
                }
            }
            Button { pickingCategories = true } label: {
                chip(book.categories.isEmpty ? "Add categories" : "Edit",
                     systemImage: book.categories.isEmpty ? "plus" : "pencil", quiet: true)
            }
        }
        .buttonStyle(.plain)
    }

    private func chip(_ text: String, systemImage: String? = nil, quiet: Bool = false) -> some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.inter(.caption2)) }
            Text(text)
        }
        .font(.inter(.footnote, .medium))
        .foregroundStyle(quiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.accent))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(quiet ? Color.clear : Theme.accent.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(Theme.rule, lineWidth: quiet ? 1 : 0))
    }

    // MARK: - More

    /// Everything else, as one plain list.
    private var more: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                FavouriteRows(book: book, shelf: shelf, showingShelfFull: $showingShelfFull)
                Divider()
                LendingRows(book: book)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(.inter(.subheadline))
                    TextField("Your thoughts on this book…", text: $book.notes, axis: .vertical)
                        .font(.inter(.subheadline))
                        .lineLimit(1...10)
                }
                Divider()
                if let isbn = book.isbn {
                    MoreRow(label: "ISBN") { Text(isbn).font(.footnote.monospaced()) }
                }
                MoreRow(label: "Added") {
                    Text(book.dateAdded.formatted(.dateTime.day().month(.abbreviated).year()))
                }
                Divider()
                coverButton
                Divider()
                Button("Remove book", systemImage: "trash", role: .destructive) {
                    bookToDelete = book
                }
                .font(.inter(.subheadline))
                .frame(minHeight: 30)
            }
        }
    }

    @ViewBuilder
    private var coverButton: some View {
        Group {
            if book.coverImage != nil {
                Button("Change cover", systemImage: "photo.on.rectangle") { choosingCover = true }
            } else if searchingCover {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Looking for a cover…").foregroundStyle(.secondary)
                }
            } else {
                Button(coverNotFound ? "No cover found online" : "Find cover online", systemImage: "magnifyingglass") {
                    findCover()
                }
                .disabled(coverNotFound)
            }
        }
        .font(.inter(.subheadline))
        .frame(minHeight: 30)
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
