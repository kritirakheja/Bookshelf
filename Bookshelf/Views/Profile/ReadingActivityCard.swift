import SwiftUI

/// Every day you read, as a grid of squares, a column per week: pale for a little
/// reading, bright for a lot. A year at a time; tap a square for that day.
struct ReadingActivityCard: View {
    let books: [Book]
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var selected: Date?

    private let cell: CGFloat = 13
    private let gap: CGFloat = 3

    var body: some View {
        let activity = ReadingActivity(books: books)
        let thisYear = Calendar.current.component(.year, from: .now)
        let years = Array(Set(activity.years + [thisYear])).sorted(by: >)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Reading activity")
                Spacer()
                if years.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(years, id: \.self) { option in
                            Button(String(option)) {
                                year = option
                                selected = nil
                            }
                            .font(.inter(.caption, .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .foregroundStyle(option == year ? Theme.background : Color.secondary)
                            .background(option == year ? Theme.accent : Theme.rule.opacity(0.45), in: Capsule())
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(option == year ? .isSelected : [])
                        }
                    }
                }
            }

            summary(activity)

            ScrollView(.horizontal, showsIndicators: false) {
                grid(activity)
            }
            .defaultScrollAnchor(.trailing)   // open on the most recent weeks
            .id(year)

            HStack(spacing: 4) {
                Text(selectedLine(activity))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text("Less")
                ForEach(0...4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3).fill(color(level)).frame(width: 11, height: 11)
                }
                Text("More")
            }
            .font(.inter(.caption2))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Only when nothing is logged yet: how the grid fills in.
    @ViewBuilder
    private func summary(_ activity: ReadingActivity) -> some View {
        if activity.totalPages(in: year) == 0 {
            Text("Update a book's progress and the day lights up.")
                .font(.inter(.footnote))
                .foregroundStyle(.secondary)
        }
    }

    private func grid(_ activity: ReadingActivity) -> some View {
        let layout = activity.grid(for: year)
        let monthAt = Dictionary(layout.monthStarts.map { ($0.week, $0.name) }, uniquingKeysWith: { first, _ in first })
        return HStack(alignment: .top, spacing: gap) {
            ForEach(Array(layout.weeks.enumerated()), id: \.offset) { index, week in
                VStack(spacing: gap) {
                    // The month's name sits over the week it starts in, and may run wider.
                    Color.clear
                        .frame(width: cell, height: 12)
                        .overlay(alignment: .leading) {
                            if let month = monthAt[index] {
                                Text(month)
                                    .font(.inter(.caption2))
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        }
                    ForEach(0..<7, id: \.self) { row in
                        if let day = week[row] {
                            square(day, activity)
                        } else {
                            Color.clear.frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        .padding(.trailing, 14)   // room for the last month's name
    }

    private func square(_ day: Date, _ activity: ReadingActivity) -> some View {
        let pages = activity.pages(on: day)
        return Button {
            selected = selected == day ? nil : day
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(color(activity.level(on: day)))
                .frame(width: cell, height: cell)
                .overlay {
                    if selected == day {
                        RoundedRectangle(cornerRadius: 3).stroke(Color.primary, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))): \(pages) pages")
    }

    private func color(_ level: Int) -> Color {
        switch level {
        case 0: Theme.rule.opacity(0.55)
        case 1: Theme.accent.opacity(0.3)
        case 2: Theme.accent.opacity(0.5)
        case 3: Theme.accent.opacity(0.75)
        default: Theme.accent
        }
    }

    /// "Fri 9 Oct · 85 pages · Sapiens (60), Circe (25)" for the tapped square.
    private func selectedLine(_ activity: ReadingActivity) -> String {
        guard let selected else { return "Tap a day" }
        let date = selected.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        guard let day = activity.days[selected] else { return "\(date) · no reading" }
        let books = day.books.count == 1
            ? day.books[0].title
            : day.books.map { "\($0.title) (\($0.pages))" }.joined(separator: ", ")
        return "\(date) · \(day.pages) pages · \(books)"
    }
}
