import SwiftUI
import SwiftData

/// "Lending" on a book's page: who has it now, lend / mark returned, and past loans.
struct LendingSection: View {
    @Bindable var book: Book
    @Environment(\.modelContext) private var context
    @State private var choosingHow = false
    @State private var typingName = false
    @State private var typedName = ""

    var body: some View {
        Section {
            if let loan = book.currentLoan {
                VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text("With **\(loan.borrowerName)**")
                    } icon: {
                        Image(systemName: "arrow.up.forward.circle.fill").foregroundStyle(.orange)
                    }
                    Text(sinceText(loan.lentAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 34)
                }
                Button("Mark as returned", systemImage: "arrow.down.backward.circle") {
                    withAnimation { book.markReturned() }
                }
            } else {
                Button("Lend to a friend…", systemImage: "person.crop.circle.badge.plus") {
                    choosingHow = true
                }
            }

            ForEach(book.pastLoans) { loan in
                LabeledContent(loan.borrowerName, value: rangeText(loan))
                    .foregroundStyle(.secondary)
            }
            .onDelete { offsets in
                let past = book.pastLoans
                offsets.map { past[$0] }.forEach(context.delete)
            }
        } header: {
            Text("Lending")
        } footer: {
            if !book.pastLoans.isEmpty {
                Text("Earlier loans are kept as history. Swipe one to remove it.")
            }
        }
        .confirmationDialog("Lend “\(book.title)” to…", isPresented: $choosingHow, titleVisibility: .visible) {
            Button("Choose from Contacts") {
                ContactPicker.present { picked in
                    withAnimation { book.lend(to: picked.name, contactID: picked.contactID) }
                }
            }
            Button("Type a name") {
                typedName = ""
                typingName = true
            }
        }
        .alert("Who are you lending it to?", isPresented: $typingName) {
            TextField("Name", text: $typedName)
                .textInputAutocapitalization(.words)
            Button("Lend") {
                withAnimation { book.lend(to: typedName) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func sinceText(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: .now)).day ?? 0
        let since = date.formatted(date: .abbreviated, time: .omitted)
        switch days {
        case 0: return "Since today"
        case 1: return "Since yesterday"
        default: return "Since \(since) · \(days) days"
        }
    }

    private func rangeText(_ loan: Loan) -> String {
        let start = loan.lentAt.formatted(.dateTime.day().month(.abbreviated))
        let end = (loan.returnedAt ?? .now).formatted(.dateTime.day().month(.abbreviated).year())
        return "\(start) – \(end)"
    }
}
