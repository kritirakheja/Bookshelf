import SwiftUI
import SwiftData

struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BookCategory.name) private var categories: [BookCategory]
    @State private var showingNew = false
    @State private var newName = ""
    @State private var renaming: BookCategory?
    @State private var renameText = ""
    @State private var deleting: BookCategory?
    /// Why a new name or a rename wasn't accepted.
    @State private var nameProblem: String?

    var body: some View {
        List {
            ForEach(categories) { category in
                NavigationLink(value: category) {
                    LabeledContent(category.name, value: "\(category.books.count)")
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash") {
                        deleting = category
                    }
                    .tint(.red)
                    Button("Rename", systemImage: "pencil") {
                        renameText = category.name
                        renaming = category
                    }
                    .tint(.orange)
                }
            }
        }
        .themedScreen()
        .navigationTitle("Categories")
        .toolbar {
            Button("New category", systemImage: "plus") { showingNew = true }
        }
        .overlay {
            if categories.isEmpty {
                ContentUnavailableView(
                    "No categories yet",
                    systemImage: "square.grid.2x2",
                    description: Text("Tap + to create one, or add categories from a book's page.")
                )
            }
        }
        .alert("New category", isPresented: $showingNew) {
            TextField("Name", text: $newName)
                .textInputAutocapitalization(.words)
            Button("Add") { addNew() }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        .alert(
            "Rename category",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField("Name", text: $renameText)
                .textInputAutocapitalization(.words)
            Button("Rename") { rename() }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { category in
            Button("Delete", role: .destructive) {
                withAnimation { context.delete(category) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { category in
            Text(Self.deleteWarning(bookCount: category.books.count))
        }
        .alert("That name won't work", isPresented: Binding(get: { nameProblem != nil }, set: { if !$0 { nameProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(nameProblem ?? "")
        }
    }

    static func deleteWarning(bookCount: Int) -> String {
        switch bookCount {
        case 0: "No books are in this category."
        case 1: "1 book will lose this category. The book itself stays in your library."
        default: "\(bookCount) books will lose this category. The books themselves stay in your library."
        }
    }

    /// What's wrong with `name` for a category (other than `current`), or nil if it's fine.
    static func problem(with name: String, existing: [String], current: String? = nil) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Type a name for the category." }
        let taken = existing.contains {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame && $0.caseInsensitiveCompare(current ?? "") != .orderedSame
        }
        return taken ? "You already have a category called “\(trimmed)”." : nil
    }

    private func addNew() {
        defer { newName = "" }
        if let problem = Self.problem(with: newName, existing: categories.map(\.name)) {
            nameProblem = problem
        } else {
            _ = BookCategory.named(newName, in: context)
        }
    }

    private func rename() {
        guard let renaming else { return }
        if let problem = Self.problem(with: renameText, existing: categories.map(\.name), current: renaming.name) {
            nameProblem = problem
        } else {
            renaming.name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

struct CategoryBooksView: View {
    let category: BookCategory

    private var books: [Book] {
        category.books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        List(books) { book in
            NavigationLink(value: book) {
                BookRow(book: book)
            }
        }
        .themedScreen()
        .navigationTitle(category.name)
        .overlay {
            if books.isEmpty {
                ContentUnavailableView("No books in \(category.name)", systemImage: "books.vertical")
            }
        }
    }
}

#Preview {
    NavigationStack { CategoriesView() }
        .modelContainer(SampleData.previewContainer)
}
