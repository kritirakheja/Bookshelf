import SwiftUI
import SwiftData

/// Search Open Library and Google Books by title or author, and pick a result to add.
struct BookSearchView: View {
    /// Shows a "getting details" overlay while the picked book is fetched.
    var isLoading = false
    let onPick: (BookCandidate) -> Void

    @Query private var library: [Book]
    @State private var text = ""
    @State private var results: [BookCandidate] = []
    @State private var searching = false
    @State private var failed = false

    private let client = BookLookup()

    /// Title + first author of every book already owned, to mark results as owned.
    private var owned: Set<String> {
        Set(library.map { Self.key(title: $0.title, author: $0.authors.first) })
    }

    static func key(title: String, author: String?) -> String {
        BookMatcher.key(title: title, author: author)
    }

    var body: some View {
        List {
            ForEach(results) { candidate in
                Button {
                    onPick(candidate)
                } label: {
                    SearchResultRow(
                        candidate: candidate,
                        isOwned: owned.contains(Self.key(title: candidate.title, author: candidate.authors.first))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .disabled(isLoading)
        .overlay {
            if isLoading {
                ProgressView("Getting book details…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .paperScreen()
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Title or author")
        .overlay {
            if searching && results.isEmpty {
                ProgressView()
            } else if failed {
                ContentUnavailableView("Couldn't search", systemImage: "wifi.slash", description: Text("Check your connection and try again."))
            } else if results.isEmpty {
                if text.trimmingCharacters(in: .whitespaces).count >= 2 && !searching {
                    ContentUnavailableView.search(text: text)
                } else {
                    ContentUnavailableView("Find a book", systemImage: "magnifyingglass", description: Text("Type a title or an author."))
                }
            }
        }
        // Runs again whenever the text changes; the pause means we search once
        // typing stops, not on every letter.
        .task(id: text) {
            let query = text
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            do {
                let found = try await client.search(query)
                guard !Task.isCancelled else { return }
                results = found
                failed = false
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}

private struct SearchResultRow: View {
    let candidate: BookCandidate
    let isOwned: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: candidate.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(.quaternary)
                    .overlay { Image(systemName: "book.closed").foregroundStyle(.secondary) }
            }
            .frame(width: 44, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title)
                    .font(.inter(.headline))
                    .lineLimit(2)
                Text(candidate.authors.prefix(2).joined(separator: ", "))
                    .font(.inter(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let year = candidate.year {
                        Text(String(year))
                    }
                    if isOwned {
                        Label("In your library", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .font(.inter(.caption))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
