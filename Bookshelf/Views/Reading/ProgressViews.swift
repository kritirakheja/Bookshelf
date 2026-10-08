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

/// A book on the Reading tab: how far in you are, and buttons to log today's reading
/// or finish it.
struct ReadingRow: View {
    let book: Book
    let onUpdate: () -> Void
    let onFinish: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverView(book: book, width: 56)
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.inter(.headline))
                        .lineLimit(2)
                    Text(book.authorLine)
                        .font(.inter(.subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ProgressBar(fraction: book.progressFraction ?? 0)
                HStack(spacing: 6) {
                    Text(book.progressSummary)
                    let today = book.pagesRead(on: .now)
                    if today > 0 {
                        Text("· +\(today) today").foregroundStyle(.tint)
                    }
                }
                .font(.inter(.caption))
                .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Update progress", action: onUpdate)
                        .buttonStyle(.borderedProminent)
                    Button("Finished", action: onFinish)
                        .buttonStyle(.bordered)
                }
                .font(.inter(.footnote, .semibold))
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
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
private struct WeekChart: View {
    let days: [(day: Date, pages: Int)]

    private let barHeight: CGFloat = 44

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
        .frame(height: barHeight + 34, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pages read each day this week: " + days.map { "\($0.pages)" }.joined(separator: ", "))
    }
}
