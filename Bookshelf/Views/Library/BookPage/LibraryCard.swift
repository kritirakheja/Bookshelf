import SwiftUI
import SwiftData

/// Lending and borrowing as an old library card: the book's details at the top,
/// a rubber stamp for whoever has it now, and earlier loans written in below.
struct LibraryCard: View {
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
        PaperCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    ShelfHeading(text: "Library card")
                    Spacer()
                    Text("Added \(book.dateAdded.formatted(.dateTime.day().month(.abbreviated).year()))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let isbn = book.isbn {
                    cardLine("ISBN", isbn, monospaced: true)
                }
                current
                if !book.pastLoans.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(book.pastLoans) { loan in
                            cardLine(loan.borrowerName, Self.range(loan))
                                .contextMenu {
                                    Button("Remove from history", systemImage: "trash", role: .destructive) {
                                        withAnimation { context.delete(loan) }
                                    }
                                }
                        }
                    }
                }
                actions
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

    /// The stamp for where the book is right now, if anywhere.
    @ViewBuilder
    private var current: some View {
        if let borrowing = book.borrowing {
            if borrowing.returnedAt == nil {
                stamped("Borrowed from \(borrowing.borrowerName)", color: .indigo,
                        detail: Self.since(borrowing.lentAt, verb: "Borrowed"))
            } else {
                stamped("Returned to \(borrowing.borrowerName)", color: .secondary,
                        detail: "Borrowed \(Self.range(borrowing))")
            }
        } else if let loan = book.currentLoan {
            stamped("Lent to \(loan.borrowerName)", color: .orange,
                    detail: Self.since(loan.lentAt, verb: "Lent"))
        } else if book.pastLoans.isEmpty {
            Text("On the shelf. Never lent out.")
                .font(BookPageStyle.serif(.footnote).italic())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            if let borrowing = book.borrowing, borrowing.returnedAt == nil {
                Button("Give back", systemImage: "arrow.uturn.backward") {
                    withAnimation { book.giveBack() }
                }
                .buttonStyle(.borderedProminent)
                Button("Not borrowed", role: .destructive) {
                    withAnimation { context.delete(borrowing) }
                }
                .buttonStyle(.bordered)
            } else if book.isOwned {
                if book.currentLoan != nil {
                    Button("Mark as returned", systemImage: "arrow.down.backward") {
                        withAnimation { book.markReturned() }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Lend", systemImage: "person.crop.circle.badge.plus") { choosing = .lend }
                        .buttonStyle(.borderedProminent)
                    Button("Borrowed it", systemImage: "arrow.down.backward") { choosing = .borrow }
                        .buttonStyle(.bordered)
                }
            }
        }
        .controlSize(.small)
        .tint(BookPageStyle.brown)
    }

    private func stamped(_ text: String, color: Color, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RubberStamp(text: text, color: color)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// A ruled line on the card: label on the left, value on the right.
    private func cardLine(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(monospaced ? .footnote.monospaced() : .footnote)
                .foregroundStyle(.secondary)
        }
        .font(BookPageStyle.serif(.subheadline))
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BookPageStyle.rule.opacity(0.6)).frame(height: 0.5)
        }
    }

    private func record(_ action: Action, name: String, contactID: String?) {
        withAnimation {
            switch action {
            case .lend: book.lend(to: name, contactID: contactID)
            case .borrow: book.borrow(from: name, contactID: contactID)
            }
        }
    }

    static func since(_ date: Date, verb: String) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0
        switch days {
        case 0: return "\(verb) today"
        case 1: return "\(verb) yesterday"
        default: return "\(verb) \(date.formatted(date: .abbreviated, time: .omitted)) · \(days) days ago"
        }
    }

    static func range(_ loan: Loan) -> String {
        let start = loan.lentAt.formatted(.dateTime.day().month(.abbreviated))
        let end = (loan.returnedAt ?? .now).formatted(.dateTime.day().month(.abbreviated).year())
        return "\(start) – \(end)"
    }
}
