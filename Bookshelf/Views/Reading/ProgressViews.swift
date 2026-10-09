import SwiftUI

/// A thin bar filled as far as the book is read, in the surrounding tint.
struct ProgressBar: View {
    let fraction: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.rule.opacity(0.6))
                Capsule().fill(.tint)
                    .frame(width: max(fraction > 0 ? height : 0, proxy.size.width * fraction))
            }
        }
        .frame(height: height)
        .animation(.snappy, value: fraction)
        .accessibilityHidden(true)
    }
}

extension Book {
    /// "36% · page 110 of 304", or what's known when the page count or log is missing.
    var progressSummary: String {
        let page = currentPage ?? 0
        if let percent = progressPercent, let pageCount {
            return "\(percent)% · page \(page) of \(pageCount)"
        }
        return page > 0 ? "Page \(page)" : "No progress logged yet"
    }
}

/// The book you last picked up, large, at the top of the Reading tab: how far in you
/// are, this week's reading, and buttons to log today's pages or finish it.
struct FeaturedReadingCard: View {
    let book: Book
    let onUpdate: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: book) {
                HStack(alignment: .top, spacing: 12) {
                    CoverView(book: book, width: 70)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(book.title)
                            .font(.inter(.headline))
                            .foregroundStyle(Color.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(book.authorLine)
                            .font(.inter(.footnote))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        // The percentage sits on the bar's line; the detail underneath.
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if let percent = book.progressPercent {
                                Text("\(percent)%")
                                    .font(.inter(size: 24, .bold))
                                    .foregroundStyle(.tint)
                                    .contentTransition(.numericText())
                            }
                            let today = book.pagesRead(on: .now)
                            if today > 0 {
                                Text("+\(today) today")
                                    .font(.inter(.caption, .semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                        ProgressBar(fraction: book.progressFraction ?? 0, height: 7)
                        Text(detail)
                            .font(.inter(.caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !book.progress.isEmpty {
                WeekChart(days: book.dailyPages(last: 7), barHeight: 26)
            }

            HStack(spacing: 8) {
                Button(action: onUpdate) {
                    Text("Update progress").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: onFinish) {
                    Text("Finished").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.inter(.footnote, .semibold))
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.rule.opacity(0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }

    private var detail: String {
        guard let pageCount = book.pageCount, pageCount > 0 else {
            return book.currentPage.map { "Page \($0)" } ?? "No progress logged yet"
        }
        var text = "Page \(book.currentPage ?? 0) of \(pageCount)"
        if let left = book.pagesToGo, left > 0 { text += " · \(left) to go" }
        return text
    }
}

/// Another book in progress, compact: how far in you are, and a button to log more.
struct ReadingRow: View {
    let book: Book
    let onUpdate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: book) {
                HStack(spacing: 12) {
                    CoverView(book: book, width: 48)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(book.title)
                            .font(.inter(.headline))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                        Text(book.authorLine)
                            .font(.inter(.caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        ProgressBar(fraction: book.progressFraction ?? 0)
                        Text(book.progressSummary)
                            .font(.inter(.caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button("Update", action: onUpdate)
                .font(.inter(.footnote, .semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .accessibilityLabel("Update progress for \(book.title)")
        }
        .padding(.vertical, 6)
    }
}

/// On a book's page while reading it: the percentage, large, with the bar, what's
/// left, and the last week's reading day by day.
struct ProgressBlock: View {
    let book: Book
    let onUpdate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                if let percent = book.progressPercent {
                    Text("\(percent)%")
                        .font(.inter(size: 40, .bold))
                        .foregroundStyle(.tint)
                        .contentTransition(.numericText())
                    Text("read")
                        .font(.inter(.subheadline))
                        .foregroundStyle(.secondary)
                } else {
                    Text(book.currentPage.map { "Page \($0)" } ?? "Reading")
                        .font(.inter(.title2, .bold))
                }
                Spacer()
                Button("Update progress", action: onUpdate)
                    .font(.inter(.footnote, .semibold))
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
            if let fraction = book.progressFraction {
                ProgressBar(fraction: fraction, height: 8)
            }
            Text(detail)
                .font(.inter(.footnote))
                .foregroundStyle(.secondary)
            if !book.progress.isEmpty {
                WeekChart(days: book.dailyPages(last: 7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detail: String {
        var parts: [String] = []
        if let pageCount = book.pageCount, pageCount > 0 {
            parts.append("Page \(book.currentPage ?? 0) of \(pageCount)")
            if let left = book.pagesToGo, left > 0 { parts.append("\(left) to go") }
        } else {
            parts.append("Add the number of pages to see a percentage")
        }
        if let started = book.dateStarted {
            parts.append("started \(started.formatted(.dateTime.day().month(.abbreviated)))")
        }
        return parts.joined(separator: " · ")
    }
}

/// Pages read on each of the last seven days, as small bars.
struct WeekChart: View {
    let days: [(day: Date, pages: Int)]
    var barHeight: CGFloat = 44

    var body: some View {
        let most = max(days.map(\.pages).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(days, id: \.day) { entry in
                VStack(spacing: 4) {
                    Text(entry.pages > 0 ? "\(entry.pages)" : " ")
                        .font(.inter(.caption2, .medium))
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(entry.pages > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(Theme.rule.opacity(0.6)))
                        .frame(height: entry.pages > 0 ? max(4, barHeight * CGFloat(entry.pages) / CGFloat(most)) : 3)
                    Text(entry.day.formatted(.dateTime.weekday(.narrow)))
                        .font(.inter(.caption2))
                        .foregroundStyle(Calendar.current.isDateInToday(entry.day) ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: barHeight + 32, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pages read each day this week: " + days.map { "\($0.pages)" }.joined(separator: ", "))
    }
}
