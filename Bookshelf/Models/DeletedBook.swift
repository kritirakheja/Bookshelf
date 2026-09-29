import Foundation
import SwiftData

/// Marker left behind when a synced book is deleted, so the next sync can
/// delete it online too (otherwise it would come back from the backup).
@Model
final class DeletedBook {
    var remoteID: UUID
    var deletedAt: Date = Date.now

    init(remoteID: UUID) {
        self.remoteID = remoteID
    }
}
