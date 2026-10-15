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
/// are, and buttons to log today's pages or finish it.
struct FeaturedReadingCard: View {
    let book: Book
    let onUpdate: () -> Void
    let onFinish: () -> Void

    private static let coverWidth: CGFloat = 58

    var body: some View {
        // The cover says which book it is, so there's no title or author here: just
        // how far in you are and the two buttons, in a block no taller than the cover.
        HStack(alignment: .center, spacing: 12) {
            NavigationLink(value: book) {
                CoverView(book: book, width: Self.coverWidth)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                // Without a cover image the placeholder is only a colour: name the book.
                if book.coverImage == nil {
                    Text(book.title)
                        .font(.inter(.subheadline, .semibold))
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let percent = book.progressPercent {
                        Text("\(percent)%")
                            .font(.inter(.headline, .bold))
                            .foregroundStyle(.tint)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    ProgressBar(fraction: book.progressFraction ?? 0, height: 7)
                }
                Text(detail)
                    .font(.inter(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.rule.opacity(0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }

    private var detail: String {
        guard let pageCount = book.pageCount, pageCount > 0 else {
            return book.currentPage.map { "Page \($0)" } ?? "No progress logged yet"
        }
        guard let page = book.currentPage, page > 0 else { return "Not started · \(pageCount) pages" }
        var text = "Page \(page) of \(pageCount)"
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

/// On a book's page while reading it: the percentage, large, with the bar and what's left.
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
