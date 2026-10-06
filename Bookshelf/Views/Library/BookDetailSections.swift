import SwiftUI
import SwiftData

// MARK: - About

/// What the book is about: the first few lines, with the rest a tap away.
struct AboutBlock: View {
    @Bindable var book: Book
    @State private var expanded = false
    @State private var search = DescriptionSearch()

    private var isLong: Bool { (book.summary?.count ?? 0) > 260 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "About the book")
            if let summary = book.summary {
                Text(summary)
                    .font(.inter(.body))
                    .lineSpacing(3)
                    .lineLimit(expanded || !isLong ? nil : 5)
                    .textSelection(.enabled)
                if isLong {
                    Button(expanded ? "Less" : "Read more") {
                        withAnimation { expanded.toggle() }
                    }
                    .font(.inter(.subheadline, .semibold))
                }
            } else if search.isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Looking for a description…").foregroundStyle(.secondary)
                }
            } else {
                Button("Find description", systemImage: "text.magnifyingglass") {
                    search.run(for: book)
                }
                if search.notFound {
                    Text("No description found online. You can add one with Edit.")
                        .font(.inter(.caption))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Status

/// Unread · Reading · Read. Once read, the finish date and rating sit underneath.
struct StatusSection: View {
    @Bindable var book: Book

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(ReadingStatus.allCases) { status in
                    statusButton(status)
                }
            }
            if book.status == .reading, let started = book.dateStarted {
                Text("Started \(started.formatted(date: .abbreviated, time: .omitted))")
                    .font(.inter(.footnote))
                    .foregroundStyle(.secondary)
            }
            if book.status == .read {
                HStack {
                    finished
                    Spacer()
                    StarRating(rating: $book.rating, usesTint: true)
                }
                .font(.inter(.footnote))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func statusButton(_ status: ReadingStatus) -> some View {
        let selected = book.status == status
        return Button {
            withAnimation(.snappy) { book.setStatus(status) }
        } label: {
            Label(status.rawValue, systemImage: status.systemImage)
                .font(.inter(.subheadline, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(selected ? Theme.background : Color.secondary)
                .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Theme.rule.opacity(0.45)), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var finished: some View {
        if book.dateReadYearOnly, let year = book.finishDateText {
            Button("Finished in \(year) · set date") {
                book.dateReadYearOnly = false
            }
        } else if let date = book.dateRead {
            HStack(spacing: 6) {
                Text("Finished")
                DatePicker("Finished", selection: Binding(get: { date }, set: { book.dateRead = $0 }),
                           in: ...Date.now, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
        } else {
            Button("Add finish date") {
                book.dateRead = Calendar.current.startOfDay(for: .now)
            }
        }
    }
}

// MARK: - More

/// One line in the "More" list: a label on the left, its value or control on the right.
struct MoreRow<Trailing: View>: View {
    let label: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
            Spacer(minLength: 8)
            trailing
                .foregroundStyle(.secondary)
        }
        .font(.inter(.subheadline))
        .frame(minHeight: 30)
    }
}

/// Favourite: a switch, and once on, its place on the shelf and why you recommend it.
struct FavouriteRows: View {
    @Bindable var book: Book
    let shelf: [Book]
    @Binding var showingShelfFull: Bool

    var body: some View {
        Toggle(isOn: Binding(
            get: { book.favoriteRank != nil },
            set: { on in
                withAnimation {
                    if on {
                        showingShelfFull = FavoritesShelf.add(book, library: shelf) == .shelfFull
                    } else {
                        FavoritesShelf.remove(book, library: shelf)
                    }
                }
            }
        )) {
            HStack(spacing: 6) {
                Text("Favourite")
                if let rank = book.favoriteRank {
                    Text("#\(rank)").foregroundStyle(.secondary)
                }
            }
            .font(.inter(.subheadline))
        }
        .frame(minHeight: 30)
        if book.favoriteRank != nil {
            TextField("Why would you recommend it?", text: $book.recommendationNoteText, axis: .vertical)
            .font(.inter(.subheadline))
            .lineLimit(1...5)
        }
    }
}

/// Lending and borrowing: where the book is now, the one thing you can do about it,
/// and earlier loans.
struct LendingRows: View {
    private enum Action {
        case lend, borrow

        var question: String {
            switch self {
            case .lend: "Who are you lending it to?"
            case .borrow: "Who did you borrow it from?"
            }
        }
    }

    @Bindable var book: Book
    @Environment(\.modelContext) private var context
    @State private var choosing: Action?
    @State private var typing: Action?
    @State private var typedName = ""

    var body: some View {
        Group {
            current
            ForEach(book.pastLoans) { loan in
                MoreRow(label: loan.borrowerName) { Text(loan.rangeText) }
                    .foregroundStyle(.secondary)
                    .contextMenu {
                        Button("Remove from history", systemImage: "trash", role: .destructive) {
                            withAnimation { context.delete(loan) }
                        }
                    }
            }
        }
        .confirmationDialog(
            choosing == .borrow ? "Borrowed “\(book.title)” from…" : "Lend “\(book.title)” to…",
            isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }),
            titleVisibility: .visible,
            presenting: choosing
        ) { action in
            Button("Choose from Contacts") {
                ContactPicker.present { picked in
                    record(action, name: picked.name, contactID: picked.contactID)
                }
            }
            Button("Type a name") {
                typedName = ""
                typing = action
            }
        }
        .alert(
            typing?.question ?? "",
            isPresented: Binding(get: { typing != nil }, set: { if !$0 { typing = nil } }),
            presenting: typing
        ) { action in
            TextField("Name", text: $typedName)
                .textInputAutocapitalization(.words)
            Button("Save") { record(action, name: typedName, contactID: nil) }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Where the book is right now, with what you can do next.
    @ViewBuilder
    private var current: some View {
        if let borrowing = book.borrowing, borrowing.returnedAt == nil {
            place("Borrowed from \(borrowing.borrowerName)", borrowing.sinceText(verb: "Borrowed")) {
                Menu {
                    Button("Give back", systemImage: "arrow.uturn.backward") { withAnimation { book.giveBack() } }
                    Button("Not borrowed", systemImage: "xmark", role: .destructive) {
                        withAnimation { context.delete(borrowing) }
                    }
                } label: {
                    Text("Give back…")
                }
            }
        } else if let borrowing = book.borrowing {
            place("Returned to \(borrowing.borrowerName)", "Borrowed \(borrowing.rangeText)") { EmptyView() }
        } else if let loan = book.currentLoan {
            place("Lent to \(loan.borrowerName)", loan.sinceText(verb: "Lent")) {
                Button("Mark returned") { withAnimation { book.markReturned() } }
            }
        } else if book.isOwned {
            place("On your shelf", nil) {
                Menu {
                    Button("Lend to a friend", systemImage: "person.crop.circle.badge.plus") { choosing = .lend }
                    Button("I borrowed this", systemImage: "arrow.down.backward") { choosing = .borrow }
                } label: {
                    Text("Lend…")
                }
            }
        }
    }

    private func place(_ text: String, _ detail: String?, @ViewBuilder action: () -> some View) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.inter(.subheadline))
                if let detail {
                    Text(detail)
                        .font(.inter(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            action()
                .font(.inter(.subheadline, .semibold))
        }
        .frame(minHeight: 30)
    }

    private func record(_ action: Action, name: String, contactID: String?) {
        withAnimation {
            switch action {
            case .lend: book.lend(to: name, contactID: contactID)
            case .borrow: book.borrow(from: name, contactID: contactID)
            }
        }
    }
}
