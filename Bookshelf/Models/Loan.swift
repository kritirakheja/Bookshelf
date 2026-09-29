import Foundation
import SwiftData

/// One time a book was lent to someone. Still out while `returnedAt` is nil;
/// returned loans are kept as the book's lending history.
@Model
final class Loan {
    var id: UUID = UUID()
    var borrowerName: String
    /// The Contacts entry picked, if any. Identifiers are per-device, so this is only
    /// a convenience; the name is what's shown and synced.
    var contactID: String?
    var lentAt: Date = Date.now
    var returnedAt: Date?
    var book: Book?

    init(borrowerName: String, contactID: String? = nil, lentAt: Date = .now) {
        self.borrowerName = borrowerName
        self.contactID = contactID
        self.lentAt = lentAt
    }
}
