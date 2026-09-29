import SwiftUI
import SwiftData

/// Your unread books as a browsable grid of covers, filterable by category.
struct ExploreView: View {
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]
    @State private var category: String?
    @State private var searchText = ""
    @State private var showingAdd = false

    private var unread: [Book] { books.filter { $0.status == .unread } }

    /// Only categories that have unread books, most books first.
    private var categoryNames: [String] {
        Dictionary(grouping: unread.flatMap { $0.categories.map(\.name) }, by: { $0 })
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .map(\.key)
    }

    private var visible: [Book] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return unread.filter { book in
            (category == nil || book.categories.contains { $0.name == category })
                && (query.isEmpty
                    || book.title.localizedStandardContains(query)
                    || book.authors.contains { $0.localizedStandardContains(query) })
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 16, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if !categoryNames.isEmpty {
                    categoryChips
                }
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(visible) { book in
                        NavigationLink(value: book) {
                            ExploreTile(book: book)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Start reading", systemImage: ReadingStatus.reading.systemImage) {
                                withAnimation { book.setStatus(.reading) }
                            }
                            Button("Mark as read", systemImage: ReadingStatus.read.systemImage) {
                                withAnimation { book.setStatus(.read) }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Explore")
            .navigationDestination(for: Book.self) { BookDetailView(book: $0) }
            .searchable(text: $searchText, prompt: "Search unread books")
            .toolbar {
                Button("Add book", systemImage: "plus") { showingAdd = true }
            }
            .sheet(isPresented: $showingAdd) {
                AddBookSheet()
            }
            .overlay {
                if unread.isEmpty {
                    ContentUnavailableView(
                        "Nothing unread",
                        systemImage: "books.vertical",
                        description: Text("Books you haven't read yet show up here. Tap + to add one.")
                    )
                } else if visible.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", isSelected: category == nil) { category = nil }
                ForEach(categoryNames, id: \.self) { name in
                    chip(name, isSelected: category == name) {
                        category = category == name ? nil : name
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy) { action() } }) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ExploreTile: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverView(book: book, width: 100)
            Text(book.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            Text(book.authorLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 100, alignment: .leading)
    }
}

#Preview {
    ExploreView()
        .modelContainer(SampleData.previewContainer)
}
