import SwiftUI

/// Entry point for adding a book: scan a barcode, type an ISBN, or enter details manually.
/// Scanning and ISBN entry look the book up, then hand a pre-filled draft to `BookFormView`.
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
    @State private var lookingUp = false

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
            .disabled(lookingUp)
            .overlay {
                if lookingUp {
                    ProgressView("Looking up book…")
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
        }
    }

    private func normalized(_ text: String) -> String? {
        var draft = BookDraft()
        draft.isbn = text
        guard let isbn = draft.normalizedISBN, isbn.count == 10 || isbn.count == 13 else { return nil }
        return isbn
    }

    private func lookUp(_ text: String) {
        guard let isbn = normalized(text), !lookingUp else { return }
        lookingUp = true
        Task {
            defer { lookingUp = false }
            do {
                let draft = try await client.lookup(isbn: isbn)
                form = FormState(draft: draft)
            } catch {
                var draft = BookDraft()
                draft.isbn = isbn
                let message = (error as? OpenLibraryClient.LookupError)?.errorDescription
                    ?? "Couldn't reach Open Library. You can fill in the details yourself."
                form = FormState(draft: draft, notice: message)
            }
        }
    }
}
