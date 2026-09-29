import SwiftUI

/// "About this book" on a book's page: the publisher's description.
struct AboutSection: View {
    @Bindable var book: Book
    @State private var expanded = false
    @State private var searching = false
    @State private var notFound = false

    /// Long descriptions start folded, so the rest of the page stays in reach.
    private var isLong: Bool { (book.summary?.count ?? 0) > 320 }

    var body: some View {
        Section("About this book") {
            if let summary = book.summary {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary)
                        .font(.callout)
                        .lineLimit(expanded || !isLong ? nil : 6)
                        .textSelection(.enabled)
                    if isLong {
                        Button(expanded ? "Less" : "More") {
                            withAnimation { expanded.toggle() }
                        }
                        .font(.callout.weight(.semibold))
                        .buttonStyle(.borderless)
                    }
                }
            } else if searching {
                HStack {
                    Text("Looking for a description…").foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                }
            } else {
                Button("Find description", systemImage: "text.magnifyingglass") {
                    searching = true
                    Task {
                        notFound = !(await BookLookup().fillMissingDescription(of: book))
                        searching = false
                    }
                }
                if notFound {
                    Text("No description found online. You can add one with Edit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
