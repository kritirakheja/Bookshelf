import SwiftUI
import SwiftData
import PhotosUI

/// Add a new book (optionally pre-filled from a draft) or edit an existing one.
struct BookFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \BookCategory.name) private var existingCategories: [BookCategory]

    private let book: Book?
    private let notice: String?
    @State private var draft: BookDraft
    @State private var photoItem: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var scanningCover = false
    @State private var duplicate: Book?
    @State private var newCategory = ""
    @State private var coverSearch: CoverSearch = .idle

    private enum CoverSearch { case idle, searching, notFound }

    /// - Parameter notice: shown at the top of the form, e.g. when an ISBN lookup failed.
    init(book: Book? = nil, draft: BookDraft = BookDraft(), notice: String? = nil) {
        self.book = book
        self.notice = notice
        _draft = State(initialValue: book.map(BookDraft.init(book:)) ?? draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let notice {
                    Section {
                        Label(notice, systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(spacing: 12) {
                        Menu {
                            Button("Scan cover", systemImage: "camera.viewfinder") { scanningCover = true }
                            Button("Choose from library", systemImage: "photo.on.rectangle") { choosingPhoto = true }
                        } label: {
                            coverPreview
                        }
                        findCoverButton
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("Book") {
                    TextField("Title", text: $draft.title)
                    TextField("Authors (comma separated)", text: $draft.authors)
                        .textContentType(.name)
                }

                Section("Details") {
                    TextField("ISBN", text: $draft.isbn)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Year published", text: $draft.publishedYear)
                        .keyboardType(.numberPad)
                    TextField("Pages", text: $draft.pageCount)
                        .keyboardType(.numberPad)
                }

                // Only when adding: an existing book's categories are edited from its page.
                if book == nil {
                    categoriesSection
                }
            }
            .navigationTitle(book == nil ? "New Book" : "Edit Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!draft.isValid)
                }
            }
            .photosPicker(isPresented: $choosingPhoto, selection: $photoItem, matching: .images)
            .fullScreenCover(isPresented: $scanningCover) {
                CoverCapture { image in draft.coverImage = image.coverJPEG() }
            }
            .onChange(of: photoItem) {
                Task {
                    // Library photos are full camera size; covers are shown small.
                    if let data = try? await photoItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        draft.coverImage = image.coverJPEG()
                    }
                }
            }
            .alert(
                "Already in your library",
                isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate = nil } }),
                presenting: duplicate
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { existing in
                Text("You already have “\(existing.title)” with this ISBN.")
            }
        }
    }

    private var coverPreview: some View {
        ZStack(alignment: .bottomTrailing) {
            if let data = draft.coverImage, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 100, height: 150)
                    .overlay {
                        Label("Add cover", systemImage: "photo")
                            .labelStyle(.iconOnly)
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
            }
            Image(systemName: "pencil.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.multicolor)
                .offset(x: 8, y: 8)
        }
    }

    // MARK: Cover search

    @ViewBuilder
    private var findCoverButton: some View {
        if coverSearch == .searching {
            ProgressView("Searching for a cover…")
                .font(.footnote)
        } else if draft.coverImage == nil {
            VStack(spacing: 4) {
                Button("Find cover online", systemImage: "magnifyingglass") {
                    findCover()
                }
                .font(.footnote)
                .disabled(draft.trimmedTitle.isEmpty && draft.normalizedISBN == nil)
                if coverSearch == .notFound {
                    Text("No cover found. Tap the cover to pick a photo instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func findCover() {
        coverSearch = .searching
        let (title, author, isbn) = (draft.trimmedTitle, draft.authorList.first, draft.normalizedISBN)
        Task {
            let data = await BookLookup().findCover(title: title, author: author, isbn: isbn)
            if let data {
                draft.coverImage = data
                coverSearch = .idle
            } else {
                coverSearch = .notFound
            }
        }
    }

    // MARK: Categories (new books only)

    /// Existing categories plus any suggested by the lookup that don't exist yet.
    private var categoryOptions: [String] {
        var names = existingCategories.map(\.name)
        for name in draft.categoryNames where !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            names.append(name)
        }
        return names
    }

    private var categoriesSection: some View {
        Section {
            ForEach(categoryOptions, id: \.self) { name in
                Button {
                    toggleCategory(name)
                } label: {
                    HStack {
                        Text(name).foregroundStyle(.primary)
                        Spacer()
                        if isCategorySelected(name) {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
            }
            HStack {
                TextField("New category", text: $newCategory)
                    .onSubmit(addNewCategory)
                Button("Add", action: addNewCategory)
                    .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Categories")
        } footer: {
            if !draft.categoryNames.isEmpty {
                Text("Ticked categories were suggested from the book's subjects. Untick any you don't want.")
            }
        }
    }

    private func isCategorySelected(_ name: String) -> Bool {
        draft.categoryNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func toggleCategory(_ name: String) {
        if isCategorySelected(name) {
            draft.categoryNames.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        } else {
            draft.categoryNames.append(name)
        }
    }

    private func addNewCategory() {
        let name = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && !isCategorySelected(name) {
            draft.categoryNames.append(name)
        }
        newCategory = ""
    }

    // MARK: Saving

    private func save() {
        if let existing = existingBook(withISBN: draft.normalizedISBN) {
            duplicate = existing
            return
        }
        if let book {
            draft.apply(to: book)
        } else {
            let newBook = draft.makeBook()
            context.insert(newBook)
            newBook.categories = draft.categoryNames.compactMap { BookCategory.named($0, in: context) }
            // Typed in by hand with no cover? Look one up in the background;
            // it appears in the library a moment later if found.
            if newBook.coverImage == nil {
                Task { await BookLookup().fillMissingCover(of: newBook) }
            }
        }
        dismiss()
    }

    /// Another book (not the one being edited) that already has this ISBN.
    private func existingBook(withISBN isbn: String?) -> Book? {
        guard let isbn else { return nil }
        let target: String? = isbn
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.isbn == target })
        let matches = (try? context.fetch(descriptor)) ?? []
        return matches.first { $0 !== book }
    }
}

#Preview {
    BookFormView()
        .modelContainer(SampleData.previewContainer)
}
