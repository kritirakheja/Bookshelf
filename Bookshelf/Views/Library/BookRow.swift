import SwiftUI

struct BookRow: View {
    let book: Book
    /// Shows when the book was finished (used in the Read list).
    var showsFinishDate = false
    /// Shows when the book was started (used in Currently Reading).
    var showsStartDate = false

    var body: some View {
        HStack(spacing: 12) {
            CoverView(book: book)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(book.authorLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if showsFinishDate {
                    Text(book.finishDateText.map { book.dateReadYearOnly ? "Finished in \($0)" : "Finished \($0)" } ?? "No finish date")
                        .font(.caption)
                        .foregroundStyle(book.dateRead == nil ? .tertiary : .secondary)
                }
                if let loan = book.currentLoan {
                    Text("Lent to \(loan.borrowerName)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                } else if let borrowing = book.borrowing {
                    Text(borrowing.returnedAt == nil
                         ? "Borrowed from \(borrowing.borrowerName)"
                         : "Returned to \(borrowing.borrowerName)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(borrowing.returnedAt == nil ? AnyShapeStyle(.indigo) : AnyShapeStyle(.secondary))
                }
                if showsStartDate, let started = book.dateStarted {
                    Text("Started \(started.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if book.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Favourite")
            }
            if book.status != .unread {
                Image(systemName: book.status.systemImage)
                    .foregroundStyle(book.status.tint)
                    .accessibilityLabel(book.status.rawValue)
            }
        }
        .padding(.vertical, 2)
    }
}
