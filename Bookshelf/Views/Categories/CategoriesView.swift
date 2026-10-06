import SwiftUI
import SwiftData

struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BookCategory.name) private var categories: [BookCategory]
    @State private var showingNew = false
    @State private var newName = ""
    @State private var renaming: BookCategory?
    @State private var renameText = ""

    var body: some View {
        List {
            ForEach(categories) { category in
                NavigationLink(value: category) {
                    LabeledContent(category.name, value: "\(category.books.count)")
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        context.delete(category)
                    }
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
            Button("Add") {
                _ = BookCategory.named(newName, in: context)
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        .alert(
            "Rename category",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField("Name", text: $renameText)
            Button("Rename") { rename() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func rename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = categories.contains {
            $0 !== renaming && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
        if let renaming, !name.isEmpty, !taken {
            renaming.name = name
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
