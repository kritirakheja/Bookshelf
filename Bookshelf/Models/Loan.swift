import Foundation
import SwiftData

/// A book changing hands with a friend, in either direction:
/// - lent (`isBorrowed == false`): my book, with `borrowerName` until `returnedAt`
/// - borrowed (`isBorrowed == true`): `borrowerName`'s book, with me until I give it
///   back (`returnedAt`)
/// Finished ones are kept as history.
@Model
final class Loan {
    var id: UUID = UUID()
    /// The friend involved: who has my book, or whose book I have.
    var borrowerName: String
    /// The Contacts entry picked, if any. Identifiers are per-device, so this is only
    /// a convenience; the name is what's shown and synced.
    var contactID: String?
    var lentAt: Date = Date.now
    var returnedAt: Date?
    /// True when I borrowed the book from `borrowerName`.
    var isBorrowed: Bool = false
    var book: Book?

    init(borrowerName: String, contactID: String? = nil, lentAt: Date = .now, isBorrowed: Bool = false) {
        self.borrowerName = borrowerName
        self.contactID = contactID
        self.lentAt = lentAt
        self.isBorrowed = isBorrowed
    }
}

extension Loan {
    /// When it started, in words: "Lent today", "Borrowed 29 Sep 2026 · 7 days ago".
    func sinceText(verb: String, now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lentAt), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case 0: return "\(verb) today"
        case 1: return "\(verb) yesterday"
        default: return "\(verb) \(lentAt.formatted(date: .abbreviated, time: .omitted)) · \(days) days ago"
        }
    }

    /// From when to when: "29 Sep – 6 Oct 2026" (to today if it isn't back yet).
    var rangeText: String {
        let start = lentAt.formatted(.dateTime.day().month(.abbreviated))
        let end = (returnedAt ?? .now).formatted(.dateTime.day().month(.abbreviated).year())
        return "\(start) – \(end)"
    }
}
