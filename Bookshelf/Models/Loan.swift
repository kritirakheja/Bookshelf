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
