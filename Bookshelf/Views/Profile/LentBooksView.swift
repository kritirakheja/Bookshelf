import SwiftUI
import SwiftData

/// Books that have changed hands, grouped by friend: my books out on loan
/// (`.lent`), or friends' books I have (`.borrowed`).
struct LentBooksView: View {
    enum Direction {
        case lent, borrowed
    }

    struct Group: Identifiable {
        let name: String
        /// Longest-away first.
        let books: [Book]
        var id: String { name.lowercased() }
    }

    var direction: Direction = .lent
    @Query private var books: [Book]

    /// Friends alphabetically; the same name typed with different capitals or spacing
    /// counts as one person. Only loans still open (not yet returned / given back).
    static func groups(from books: [Book], direction: Direction = .lent) -> [Group] {
        let lent = books.compactMap { book -> (book: Book, loan: Loan)? in
            let loan = direction == .lent ? book.currentLoan : book.borrowing.flatMap { $0.returnedAt == nil ? $0 : nil }
            return loan.map { (book, $0) }
        }
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
        let groups = Self.groups(from: books, direction: direction)
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.books) { book in
                        NavigationLink(value: book) {
                            LentBookRow(book: book, direction: direction)
                        }
                        .swipeActions(edge: .leading) {
                            if direction == .lent {
                                Button("Returned", systemImage: "arrow.down.backward.circle") {
                                    withAnimation { book.markReturned() }
                                }
                                .tint(.green)
                            } else {
                                Button("Given back", systemImage: "arrow.uturn.backward.circle") {
                                    withAnimation { book.giveBack() }
                                }
                                .tint(.green)
                            }
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
        .paperScreen()
        .navigationTitle(direction == .lent ? "Lent Out" : "Borrowed")
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView(
                    direction == .lent ? "Nothing lent out" : "Nothing borrowed",
                    systemImage: "books.vertical",
                    description: Text(direction == .lent
                        ? "Lend a book from its page and it shows up here, under your friend's name."
                        : "Mark a book as borrowed from its page and it shows up here, under its owner's name.")
                )
            }
        }
    }
}

private struct LentBookRow: View {
    let book: Book
    let direction: LentBooksView.Direction

    var body: some View {
        HStack(spacing: 12) {
            CoverView(book: book)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.inter(.headline))
                    .lineLimit(2)
                Text(book.authorLine)
                    .font(.inter(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if direction == .lent, let loan = book.currentLoan {
                    Text(Self.away(since: loan.lentAt))
                        .font(.inter(.caption))
                        .foregroundStyle(.orange)
                } else if direction == .borrowed, let borrowing = book.borrowing {
                    Text(LibraryCard.since(borrowing.lentAt, verb: "Borrowed"))
                        .font(.inter(.caption))
                        .foregroundStyle(.indigo)
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
