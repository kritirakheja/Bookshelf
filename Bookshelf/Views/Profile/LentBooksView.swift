import SwiftUI
import SwiftData

/// Everything that's out on loan right now, grouped by who has it.
struct LentBooksView: View {
    struct Group: Identifiable {
        let name: String
        /// Longest-away first.
        let books: [Book]
        var id: String { name.lowercased() }
    }

    @Query private var books: [Book]

    /// Friends alphabetically; the same name typed with different capitals or spacing
    /// counts as one person.
    static func groups(from books: [Book]) -> [Group] {
        let lent = books.compactMap { book in book.currentLoan.map { (book: book, loan: $0) } }
        let byFriend = Dictionary(grouping: lent) {
            $0.loan.borrowerName.trimmingCharacters(in: .whitespaces).lowercased()
        }
        return byFriend.values
            .map { entries in
                let sorted = entries.sorted { $0.loan.lentAt < $1.loan.lentAt }
                // The newest spelling is the likeliest to be right (e.g. picked from Contacts).
                return Group(
                    name: sorted.last!.loan.borrowerName.trimmingCharacters(in: .whitespaces),
                    books: sorted.map(\.book)
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let groups = Self.groups(from: books)
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.books) { book in
                        NavigationLink(value: book) {
                            LentBookRow(book: book)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Returned", systemImage: "arrow.down.backward.circle") {
                                withAnimation { book.markReturned() }
                            }
                            .tint(.green)
                        }
                    }
                } header: {
                    HStack {
                        Label(group.name, systemImage: "person.crop.circle")
                        Spacer()
                        Text("\(group.books.count) \(group.books.count == 1 ? "book" : "books")")
                    }
                }
            }
        }
        .navigationTitle("Lent Out")
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView(
                    "Nothing lent out",
                    systemImage: "books.vertical",
                    description: Text("Lend a book from its page and it shows up here, under your friend's name.")
                )
            }
        }
    }
}

private struct LentBookRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            CoverView(book: book)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(book.authorLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let loan = book.currentLoan {
                    Text(Self.away(since: loan.lentAt))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }

    static func away(since date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0
        switch days {
        case 0: return "Lent today"
        case 1: return "Lent yesterday"
        default: return "Away \(days) days · since \(date.formatted(date: .abbreviated, time: .omitted))"
        }
    }
}

#Preview {
    NavigationStack { LentBooksView() }
        .modelContainer(SampleData.previewContainer)
        .environment(AccountStore(container: SampleData.previewContainer))
}
