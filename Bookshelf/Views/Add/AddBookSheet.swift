import SwiftUI
import SwiftData

/// Entry point for adding a book: search by title or author, scan a barcode, type an
/// ISBN, photograph the front cover, or enter details manually. Lookups hand a
/// pre-filled draft to `BookFormView`, unless the book is already in the library.
struct AddBookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var library: [Book]

    /// Once set, the sheet switches to the form for reviewing and saving.
    private struct FormState {
        var draft: BookDraft
        var notice: String?
    }

    /// A book that's already in the library. `pending` is the form to continue to if
    /// it's only a title match (possibly a different edition); nil for the same ISBN.
    private struct Duplicate {
        let book: Book
        let pending: FormState?
    }

    @State private var form: FormState?
    @State private var duplicate: Duplicate?
    @State private var isbnText = ""
    @State private var scanning = false
    @State private var photographing = false
    /// A scanned ISBN no source knew; offers the cover scan instead.
    @State private var unknownISBN: String?
    /// Carried into a cover scan so the saved book keeps the edition's ISBN.
    @State private var coverISBN = ""
    @State private var progress: String?

    private let client = BookLookup()

    var body: some View {
        if let form {
            BookFormView(draft: form.draft, notice: form.notice)
        } else {
            chooser
        }
    }

    private var chooser: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        BookSearchView(isLoading: progress != nil) { candidate in add(candidate) }
                    } label: {
                        Label("Search by title or author", systemImage: "magnifyingglass")
                    }
                }

                Section {
                    Button {
                        scanning = true
                    } label: {
                        Label("Scan barcode", systemImage: "barcode.viewfinder")
                    }
                    .disabled(!ScannerView.isAvailable)
                } footer: {
                    if !ScannerView.isAvailable {
                        Text("Scanning needs the camera on a real iPhone.")
                    }
                }

                Section {
                    Button {
                        coverISBN = ""
                        photographing = true
                    } label: {
                        Label("Scan front cover", systemImage: "camera.viewfinder")
                    }
                } footer: {
                    Text("For books without a barcode: scan the cover and the details are looked up from it.")
                }

                Section("Look up by ISBN") {
                    HStack {
                        TextField("e.g. 9780141439518", text: $isbnText)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled()
                            .onSubmit { lookUp(isbnText) }
                        Button("Find") { lookUp(isbnText) }
                            .disabled(normalized(isbnText) == nil)
                    }
                }

                Section {
                    Button {
                        form = FormState(draft: BookDraft())
                    } label: {
                        Label("Enter details manually", systemImage: "square.and.pencil")
                    }
                }
            }
            .navigationTitle("Add a Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .disabled(progress != nil)
            .overlay {
                if let progress {
                    ProgressView(progress)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .fullScreenCover(isPresented: $scanning) {
                ScannerView { isbn in
                    scanning = false
                    lookUp(isbn)
                }
                .ignoresSafeArea()
                .overlay(alignment: .topTrailing) {
                    Button("Cancel") { scanning = false }
                        .buttonStyle(.borderedProminent)
                        .padding()
                }
            }
            .fullScreenCover(isPresented: $photographing) {
                CoverCapture { image in identify(image) }
            }
            .alert(
                "Couldn't find this barcode",
                isPresented: Binding(get: { unknownISBN != nil }, set: { if !$0 { unknownISBN = nil } }),
                presenting: unknownISBN
            ) { isbn in
                Button("Scan front cover") {
                    coverISBN = isbn
                    photographing = true
                }
                Button("Enter manually") {
                    var draft = BookDraft()
                    draft.isbn = isbn
                    form = FormState(draft: draft)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Scan the front cover and we'll try to recognise the book from it.")
            }
            .alert(
                "Already in your library",
                isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate = nil } }),
                presenting: duplicate
            ) { duplicate in
                if let pending = duplicate.pending {
                    Button("Add anyway") { form = pending }
                    Button("Cancel", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: { duplicate in
                Text(duplicate.pending == nil
                     ? "You already have “\(duplicate.book.title)” by \(duplicate.book.authorLine)."
                     : "You already have “\(duplicate.book.title)” by \(duplicate.book.authorLine). Add this one as well? (For example, a different edition.)")
            }
        }
    }

    // MARK: Already owned?

    private func ownedBook(isbn: String) -> Book? {
        library.first { $0.isbn == isbn }
    }

    private func ownedBook(title: String, author: String?) -> Book? {
        guard !title.isEmpty else { return nil }
        let key = BookMatcher.key(title: title, author: author)
        return library.first { BookMatcher.key(title: $0.title, author: $0.authors.first) == key }
    }

    /// Opens the form, unless the book turns out to be in the library already.
    private func show(_ state: FormState) {
        if let isbn = state.draft.normalizedISBN, let owned = ownedBook(isbn: isbn) {
            duplicate = Duplicate(book: owned, pending: nil)
        } else if let owned = ownedBook(title: state.draft.trimmedTitle, author: state.draft.authorList.first) {
            duplicate = Duplicate(book: owned, pending: state)
        } else {
            form = state
        }
    }

    // MARK: Lookups

    private func normalized(_ text: String) -> String? {
        var draft = BookDraft()
        draft.isbn = text
        guard let isbn = draft.normalizedISBN, isbn.count == 10 || isbn.count == 13 else { return nil }
        return isbn
    }

    private func lookUp(_ text: String) {
        guard let isbn = normalized(text), progress == nil else { return }
        // Same barcode as a book already here: say so straight away, no lookup needed.
        if let owned = ownedBook(isbn: isbn) {
            duplicate = Duplicate(book: owned, pending: nil)
            return
        }
        progress = "Looking up book…"
        Task {
            defer { progress = nil }
            do {
                show(FormState(draft: try await client.lookup(isbn: isbn)))
            } catch OpenLibraryClient.LookupError.notFound {
                unknownISBN = isbn
            } catch {
                var draft = BookDraft()
                draft.isbn = isbn
                form = FormState(draft: draft, notice: "Couldn't look this book up right now. You can fill in the details yourself.")
            }
        }
    }

    /// A search result picked: fetch its cover, then review it in the form.
    private func add(_ candidate: BookCandidate) {
        guard progress == nil else { return }
        progress = "Getting book details…"
        Task {
            defer { progress = nil }
            show(FormState(draft: await client.draft(for: candidate)))
        }
    }

    /// Reads the cover scan, then looks the book up from its title and author.
    private func identify(_ photo: UIImage) {
        let isbn = coverISBN
        progress = "Reading the cover…"
        Task {
            defer { progress = nil }
            let lines = (try? await CoverTextReader.read(photo)) ?? []
            let prominent = CoverTextReader.prominentLines(lines)

            progress = "Finding the book…"
            let queries = CoverTextReader.searchQueries(lines)
            if var draft = await client.identify(coverLines: prominent, queries: queries, isbn: isbn) {
                if draft.coverImage == nil {
                    draft.coverImage = photo.coverJPEG()
                }
                show(FormState(draft: draft, notice: "Recognised from the cover. Check the details before saving."))
                return
            }

            // Not found online: keep what the cover says, and the scan as the cover.
            var draft = BookDraft()
            let guess = CoverTextReader.guess(from: lines)
            draft.title = guess.title
            draft.authors = guess.author ?? ""
            draft.isbn = isbn
            draft.coverImage = photo.coverJPEG()
            let notice = prominent.isEmpty
                ? "Couldn't read the cover. Try again in better light, or fill in the details."
                : "Couldn't find this book online, so the details below were read from the cover. Please check them."
            show(FormState(draft: draft, notice: notice))
        }
    }
}
