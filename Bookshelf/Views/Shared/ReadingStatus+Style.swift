import SwiftUI

extension ReadingStatus {
    /// One colour per status everywhere: list icons, swipe buttons, the status buttons on the book page.
    var tint: Color {
        switch self {
        case .unread: Color(red: 0.45, green: 0.50, blue: 0.58)
        case .reading: Color(red: 0.20, green: 0.45, blue: 0.70)
        case .read: Color(red: 0.62, green: 0.20, blue: 0.22)
        }
    }
}
