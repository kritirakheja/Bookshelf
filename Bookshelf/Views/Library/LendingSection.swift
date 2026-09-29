import SwiftUI
import SwiftData

/// "Lending & borrowing" on a book's page: who has my book, or whose book this is,
/// plus past loans.
struct LendingSection: View {
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
        Section {
            if let borrowing = book.borrowing {
                borrowingRow(borrowing)
            }

            if book.isOwned {
                if let loan = book.currentLoan {
                    personRow(
                        text: "With **\(loan.borrowerName)**",
                        detail: Self.since(loan.lentAt, verb: "Lent"),
                        icon: "arrow.up.forward.circle.fill",
                        tint: .orange
                    )
                    Button("Mark as returned", systemImage: "arrow.down.backward.circle") {
                        withAnimation { book.markReturned() }
                    }
                } else {
                    Button("Lend to a friend…", systemImage: "person.crop.circle.badge.plus") {
                        choosing = .lend
                    }
                    Button("Borrowed from someone…", systemImage: "arrow.down.backward.circle") {
                        choosing = .borrow
                    }
                    .foregroundStyle(.secondary)
                }
            }

            ForEach(book.pastLoans) { loan in
                LabeledContent(loan.borrowerName, value: Self.range(loan))
                    .foregroundStyle(.secondary)
            }
            .onDelete { offsets in
                let past = book.pastLoans
                offsets.map { past[$0] }.forEach(context.delete)
            }
        } header: {
            Text("Lending & borrowing")
        } footer: {
            if book.isBorrowed {
                Text("Swipe the row above if this was marked as borrowed by mistake.")
            } else if !book.pastLoans.isEmpty {
                Text("Earlier loans are kept as history. Swipe one to remove it.")
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

    @ViewBuilder
    private func borrowingRow(_ borrowing: Loan) -> some View {
        if borrowing.returnedAt == nil {
            personRow(
                text: "From **\(borrowing.borrowerName)**",
                detail: Self.since(borrowing.lentAt, verb: "Borrowed"),
                icon: "arrow.down.backward.circle.fill",
                tint: .indigo
            )
            .swipeActions {
                Button("Not borrowed", systemImage: "xmark", role: .destructive) {
                    withAnimation { context.delete(borrowing) }
                }
            }
            Button("Give back to \(borrowing.borrowerName)", systemImage: "arrow.uturn.backward.circle") {
                withAnimation { book.giveBack() }
            }
        } else {
            personRow(
                text: "Returned to **\(borrowing.borrowerName)**",
                detail: "Borrowed \(Self.range(borrowing))",
                icon: "checkmark.circle",
                tint: .secondary
            )
        }
    }

    private func personRow(text: LocalizedStringKey, detail: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(text)
            } icon: {
                Image(systemName: icon).foregroundStyle(tint)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 34)
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
