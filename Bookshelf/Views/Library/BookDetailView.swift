import SwiftUI
import SwiftData

/// A book's full details, in order of importance: the cover on a wash of its own
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
    @State private var coverArt: UIImage?
    @State private var scrolledPastCover = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Query(filter: #Predicate<Book> { $0.favoriteRank != nil }) private var shelf: [Book]

    /// The share of the screen the cover and its backdrop take.
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
                            // Where the title is on screen, to know when it meets the bar.
                            .background(GeometryReader { title in
                                Color.clear.preference(key: TitleTop.self, value: title.frame(in: .global).minY)
                            })
                        AboutBlock(book: book)
                        StatusSection(book: book)
                    }
                    .padding(.horizontal, 20)
                    more
                }
                .padding(.bottom, 30)
            }
            .ignoresSafeArea(edges: .top)
            .modifier(NoTopEdgeHaze())
            .onPreferenceChange(TitleTop.self) { top in
                let past = top < proxy.safeAreaInsets.top + 6
                if past != scrolledPastCover {
                    withAnimation(.easeInOut(duration: 0.2)) { scrolledPastCover = past }
                }
            }
            // Once the cover has scrolled away, a plain bar with the title, so the
            // text below doesn't run under the clock and the buttons.
            .overlay(alignment: .top) {
                Theme.background
                    .frame(height: proxy.safeAreaInsets.top)
                    .overlay(alignment: .bottom) { Divider() }
                    .ignoresSafeArea(edges: .top)
                    .opacity(scrolledPastCover ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .task(id: book.coverImage) {
                // Drawn at up to 3× the size it's shown, sharpened if the file is small.
                let width = heroHeight * Self.coverShare / 1.5
                coverArt = book.coverImage.flatMap { CoverImage.enlarged($0, toWidth: width * 3) }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .confirmDeletingBook($bookToDelete) {
            // Leave this page first, so it never shows a deleted book.
            dismiss()
            try? await Task.sleep(for: .milliseconds(450))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(book.title)
                    .font(.inter(.headline))
                    .lineLimit(1)
                    .opacity(scrolledPastCover ? 1 : 0)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }
            }
        }
        .keyboardDoneButton()
        // The screens that open from here are their own places: back to the app's green.
        .sheet(isPresented: $editing) {
            BookFormView(book: book)
                .tint(Theme.accent)
        }
        .sheet(isPresented: $choosingCover) {
            CoverChooserView(title: book.title, author: book.authors.first, isbn: book.isbn,
                             previous: book.previousCoverImage) { data in
                // Chosen by hand: the automatic sharpening leaves it alone from now on.
                if data != book.coverImage { book.previousCoverImage = book.coverImage }
                book.coverImage = data
                book.coverIsCustom = true
            }
            .tint(Theme.accent)
        }
        .sheet(isPresented: $pickingCategories) {
            CategoryPickerView(book: book)
                .tint(Theme.accent)
        }
        // Everything tinted on this page takes the book's own colour.
        .tint(book.accentColor(for: colorScheme))
        .alert("Your shelf is full", isPresented: $showingShelfFull) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can have up to \(FavoritesShelf.capacity) favourites. Remove one from the Favourites tab first.")
        }
    }

    // MARK: - Cover

    /// The cover's height as a share of the hero's.
    private static let coverShare = 0.64

    /// The cover, large, on a soft wash of its own colours.
    private func hero(height: CGFloat, topInset: CGFloat) -> some View {
        let coverHeight = height * Self.coverShare
        let coverWidth = coverHeight / 1.5
        return ZStack {
            backdrop
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
            .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 14)
            // Centred in the space below the navigation bar.
            .padding(.top, topInset * 0.6)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }

    /// The cover itself, blown up and blurred until only its colours are left, washed
    /// out a little and melting gradually into the page.
    private var backdrop: some View {
        let wash = colorScheme == .dark ? Color.black.opacity(0.45) : Color.white.opacity(0.35)
        return GeometryReader { proxy in
            ZStack {
                if let data = book.coverImage, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(1.5)
                        .blur(radius: 70, opaque: true)
                        .clipped()
                } else {
                    Theme.accent.opacity(0.18)
                }
                wash
                LinearGradient(stops: [
                    .init(color: Theme.background.opacity(0), location: 0.35),
                    .init(color: Theme.background.opacity(0.55), location: 0.7),
                    .init(color: Theme.background.opacity(0.9), location: 0.9),
                    .init(color: Theme.background, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
        }
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
        .foregroundStyle(quiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(quiet ? AnyShapeStyle(.clear) : AnyShapeStyle(.tint.opacity(0.12)), in: Capsule())
        .overlay(Capsule().stroke(Theme.rule, lineWidth: quiet ? 1 : 0))
    }

    // MARK: - More

    /// Everything else, as one plain list.
    private var more: some View {
        Card {
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

private struct TitleTop: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = min(value, nextValue()) }
}

/// iOS 26 hazes whatever scrolls under the navigation bar; over the cover's backdrop
/// that shows as a pale band, so it's turned off here.
private struct NoTopEdgeHaze: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
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
