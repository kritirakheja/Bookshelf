import SwiftUI
import SwiftData

/// Tick the categories a book belongs to, or create a new one inline.
struct CategoryPickerView: View {
    @Bindable var book: Book
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BookCategory.name) private var categories: [BookCategory]
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New category", text: $newName)
                            .onSubmit(addNew)
                        Button("Add", action: addNew)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    ForEach(categories) { category in
                        Button {
                            toggle(category)
                        } label: {
                            HStack {
                                Text(category.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isSelected(category) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }

    private func isSelected(_ category: BookCategory) -> Bool {
        book.categories.contains { $0 === category }
    }

    private func toggle(_ category: BookCategory) {
        if let index = book.categories.firstIndex(where: { $0 === category }) {
            book.categories.remove(at: index)
        } else {
            book.categories.append(category)
        }
    }

    private func addNew() {
        if let category = BookCategory.named(newName, in: context), !isSelected(category) {
            book.categories.append(category)
        }
        newName = ""
    }
}
