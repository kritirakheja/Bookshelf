import SwiftUI
import SwiftData

/// Entry point for adding a book: search by title or author, scan a barcode, type an
/// ISBN, photograph the front cover, or enter details manually. `AddBookModel` runs
/// the lookups; a pre-filled draft goes to `BookFormView`, unless the book is already
/// in the library.
struct AddBookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var library: [Book]

    @State private var model = AddBookModel()
    @State private var isbnText = ""
    @State private var scanning = false
    @State private var photographing = false

    var body: some View {
        if let form = model.form {
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
                        BookSearchView(isLoading: model.progress != nil) { candidate in
                            Task { await model.add(candidate, library: library) }
                        }
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
                        model.coverISBN = ""
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
                            .disabled(AddBookModel.normalizedISBN(isbnText) == nil)
                    }
                }

                Section {
                    Button {
                        model.enterManually()
                    } label: {
                        Label("Enter details manually", systemImage: "square.and.pencil")
                    }
                }
            }
            .themedScreen()
            .navigationTitle("Add a Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .disabled(model.progress != nil)
            .overlay {
                if let progress = model.progress {
                    VStack(spacing: 10) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.tint)
                            .symbolEffect(.variableColor.iterative.reversing)
                        Text(progress)
                            .font(.inter(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .fullScreenCover(isPresented: $scanning) {
                BarcodeScanScreen { isbn in
                    scanning = false
                    lookUp(isbn)
                } onCancel: {
                    scanning = false
                }
            }
            .fullScreenCover(isPresented: $photographing) {
                CoverCapture { image in
                    Task { await model.identify(image, library: library) }
                }
            }
            .alert(
                "Couldn't find this barcode",
                isPresented: Binding(get: { model.unknownISBN != nil }, set: { if !$0 { model.unknownISBN = nil } }),
                presenting: model.unknownISBN
            ) { isbn in
                Button("Scan front cover") {
                    model.coverISBN = isbn
                    photographing = true
                }
                Button("Enter manually") {
                    model.enterManually(isbn: isbn)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Scan the front cover and we'll try to recognise the book from it.")
            }
            .alert(
                "Already in your library",
                isPresented: Binding(get: { model.duplicate != nil }, set: { if !$0 { model.duplicate = nil } }),
                presenting: model.duplicate
            ) { duplicate in
                if let pending = duplicate.pending {
                    Button("Add anyway") { model.form = pending }
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

    private func lookUp(_ text: String) {
        Task { await model.lookUp(text, library: library) }
    }
}
