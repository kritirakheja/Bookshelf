import SwiftUI

/// Entry point for adding a book: scan a barcode, type an ISBN, photograph the front
/// cover, or enter details manually. Lookups hand a pre-filled draft to `BookFormView`.
struct AddBookSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Once set, the sheet switches to the form for reviewing and saving.
    private struct FormState {
        var draft: BookDraft
        var notice: String?
    }

    @State private var form: FormState?
    @State private var isbnText = ""
    @State private var scanning = false
    @State private var photographing = false
    /// A scanned ISBN Open Library didn't know; offers the cover scan instead.
    @State private var unknownISBN: String?
    /// Carried into a cover scan so the saved book keeps the edition's ISBN.
    @State private var coverISBN = ""
    @State private var progress: String?

    private let client = OpenLibraryClient()

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
                    Text("For books without a barcode: take a photo of the cover and the details are looked up from it.")
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
                CameraPicker { image in identify(image) }
                    .ignoresSafeArea()
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
                Text("Take a photo of the front cover and we'll try to recognise the book from it.")
            }
        }
    }

    private func normalized(_ text: String) -> String? {
        var draft = BookDraft()
        draft.isbn = text
        guard let isbn = draft.normalizedISBN, isbn.count == 10 || isbn.count == 13 else { return nil }
        return isbn
    }

    private func lookUp(_ text: String) {
        guard let isbn = normalized(text), progress == nil else { return }
        progress = "Looking up book…"
        Task {
            defer { progress = nil }
            do {
                form = FormState(draft: try await client.lookup(isbn: isbn))
            } catch OpenLibraryClient.LookupError.notFound {
                unknownISBN = isbn
            } catch {
                var draft = BookDraft()
                draft.isbn = isbn
                let message = (error as? OpenLibraryClient.LookupError)?.errorDescription
                    ?? "Couldn't reach Open Library. You can fill in the details yourself."
                form = FormState(draft: draft, notice: message)
            }
        }
    }

    /// Reads the cover photo, then looks the book up from its title and author.
    private func identify(_ photo: UIImage) {
        let isbn = coverISBN
        progress = "Reading the cover…"
        Task {
            defer { progress = nil }
            let lines = (try? await CoverTextReader.read(photo)) ?? []
            let prominent = CoverTextReader.prominentLines(lines)

            progress = "Finding the book…"
            if var draft = try? await client.identify(coverLines: prominent, isbn: isbn) {
                if draft.coverImage == nil {
                    draft.coverImage = photo.coverJPEG()
                }
                form = FormState(draft: draft, notice: "Recognised from the cover. Check the details before saving.")
                return
            }

            // Not found online: keep what the cover says, and the photo as the cover.
            var draft = BookDraft()
            let guess = CoverTextReader.guess(from: prominent)
            draft.title = guess.title
            draft.authors = guess.author ?? ""
            draft.isbn = isbn
            draft.coverImage = photo.coverJPEG()
            let notice = prominent.isEmpty
                ? "Couldn't read the cover. Try again in better light, or fill in the details."
                : "Couldn't find this book online, so the details below were read from the cover. Please check them."
            form = FormState(draft: draft, notice: notice)
        }
    }
}
