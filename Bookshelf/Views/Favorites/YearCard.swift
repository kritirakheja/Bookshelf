import SwiftUI

/// A year's page: every book finished that year.
struct YearRoute: Hashable {
    /// nil = read books with no finish date.
    let year: Int?
}

/// One year of reading: how many books (against the goal, if there is one) and a
/// row of their covers. The heading opens the whole year.
struct YearCard: View {
    let year: Int
    let books: [Book]
    @State private var editingGoal = false

    private var goal: Int? { ReadingGoals.shared.goal(for: year) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                NavigationLink(value: YearRoute(year: year)) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(year))
                            .font(.inter(.title3, .bold))
                            .foregroundStyle(Color.primary)
                        Text(countText)
                            .font(.inter(.subheadline))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !books.isEmpty {
                            Image(systemName: "chevron.right")
                                .font(.inter(.footnote, .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(books.isEmpty)

                if let goal {
                    ProgressView(value: Double(min(books.count, goal)), total: Double(goal))
                        .tint(Theme.accent)
                        .accessibilityLabel("\(books.count) of \(goal) books")
                }
                HStack {
                    if goal != nil {
                        Label(goalText, systemImage: goalMet ? "checkmark.seal.fill" : "target")
                            .foregroundStyle(goalMet ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    }
                    Spacer(minLength: 0)
                    Button(goal == nil ? "Set a goal" : "Change goal") {
                        editingGoal = true
                    }
                }
                .font(.inter(.footnote, .medium))
            }
            .padding(.horizontal, 16)

            if !books.isEmpty {
                CoverStrip(books: books, value: { $0 }, menu: { _ in EmptyView() })
            }
        }
        .padding(.vertical, 16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .sheet(isPresented: $editingGoal) {
            GoalEditor(year: year, read: books.count)
                .presentationDetents([.height(300)])
        }
    }

    private var goalMet: Bool { goal.map { books.count >= $0 } ?? false }

    private var countText: String {
        if let goal { return "\(books.count) of \(goal) books" }
        return books.count == 1 ? "1 book" : "\(books.count) books"
    }

    private var goalText: String {
        guard let goal else { return "" }
        return goalMet ? "Goal of \(goal) reached" : "\(goal - books.count) to go"
    }
}

/// Pick how many books to read in a year.
private struct GoalEditor: View {
    let year: Int
    let read: Int
    @State private var goal: Int
    @Environment(\.dismiss) private var dismiss

    init(year: Int, read: Int) {
        self.year = year
        self.read = read
        _goal = State(initialValue: ReadingGoals.shared.goal(for: year) ?? max(read, 12))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $goal, in: ReadingGoals.range) {
                        Text("\(goal) books")
                            .font(.inter(.title3, .semibold))
                            .monospacedDigit()
                    }
                } footer: {
                    Text(read == 1 ? "You've read 1 book in \(String(year))." : "You've read \(read) books in \(String(year)).")
                }
                if ReadingGoals.shared.goal(for: year) != nil {
                    Section {
                        Button("Remove goal", role: .destructive) {
                            ReadingGoals.shared.set(nil, for: year)
                            dismiss()
                        }
                    }
                }
            }
            .themedScreen()
            .navigationTitle("Goal for \(String(year))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ReadingGoals.shared.set(goal, for: year)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Read books with no finish date, so they aren't in any year yet.
struct UndatedCard: View {
    let books: [Book]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                NavigationLink(value: YearRoute(year: nil)) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Year not set")
                            .font(.inter(.title3, .bold))
                            .foregroundStyle(Color.primary)
                        Text(books.count == 1 ? "1 book" : "\(books.count) books")
                            .font(.inter(.subheadline))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.inter(.footnote, .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text("Open a book and add its finish date to count it in a year.")
                    .font(.inter(.footnote))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            CoverStrip(books: books, value: { $0 }, menu: { _ in EmptyView() })
        }
        .padding(.vertical, 16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}
