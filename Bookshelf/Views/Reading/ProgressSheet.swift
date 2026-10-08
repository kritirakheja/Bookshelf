import SwiftUI

/// Log today's reading: type the page you're on. Asks for the book's length first
/// if it isn't known, and offers to mark the book read when you reach the end.
struct ProgressSheet: View {
    @Bindable var book: Book
    @State private var pageText: String
    @State private var totalText = ""
    @State private var askingFinished = false
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field { case total, page }

    init(book: Book) {
        self.book = book
        _pageText = State(initialValue: book.currentPage.map(String.init) ?? "")
    }

    private var total: Int? { book.pageCount.flatMap { $0 > 0 ? $0 : nil } ?? Int(totalText).flatMap { $0 > 0 ? $0 : nil } }
    private var page: Int? { Int(pageText).flatMap { $0 >= 0 ? $0 : nil } }
    private var needsTotal: Bool { (book.pageCount ?? 0) <= 0 }

    var body: some View {
        NavigationStack {
            Form {
                if needsTotal {
                    Section {
                        TextField("Pages in the book", text: $totalText)
                            .keyboardType(.numberPad)
                            .focused($focus, equals: .total)
                    } footer: {
                        Text("Needed once, to work out the percentage.")
                    }
                }
                Section {
                    HStack {
                        Text("I'm on page")
                        TextField("0", text: $pageText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.inter(.title3, .semibold))
                            .focused($focus, equals: .page)
                        if let total {
                            Text("of \(total)").foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(preview)
                }
            }
            .themedScreen()
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(page == nil || (needsTotal && !totalText.isEmpty && total == nil))
                }
            }
            .onAppear { focus = needsTotal ? .total : .page }
            .alert("Finished the book?", isPresented: $askingFinished) {
                Button("Mark as read") {
                    book.setStatus(.read)
                    dismiss()
                }
                Button("Not yet", role: .cancel) { dismiss() }
            } message: {
                Text("You're on the last page of “\(book.title)”.")
            }
        }
        .presentationDetents([.medium])
    }

    /// What saving would record, e.g. "36% · 60 pages since last time".
    private var preview: String {
        guard var page else { return "Type the page you stopped on." }
        if let total { page = min(page, total) }
        var parts: [String] = []
        if let total { parts.append("\(Int((min(1, Double(page) / Double(total)) * 100).rounded(.down)))% of the book") }
        let before = book.sortedProgress.last { !Calendar.current.isDateInToday($0.date) }?.page ?? 0
        if page > before { parts.append("\(page - before) pages today") }
        return parts.joined(separator: " · ")
    }

    private func save() {
        guard let page else { return }
        if needsTotal, let total { book.pageCount = total }
        book.logProgress(page: page)
        if let pageCount = book.pageCount, pageCount > 0, page >= pageCount {
            askingFinished = true
        } else {
            dismiss()
        }
    }
}
