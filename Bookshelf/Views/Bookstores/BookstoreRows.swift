import SwiftUI
import MapKit

/// A bookstore on the map or in the cards: one you've saved, or one a search found.
enum BookstorePlace: Identifiable {
    case saved(Bookstore)
    case found(BookstoreResult)

    var id: String {
        switch self {
        case .saved(let store): "saved-" + store.id.uuidString
        case .found(let result): "found-" + result.id.uuidString
        }
    }

    var name: String {
        switch self {
        case .saved(let store): store.name
        case .found(let result): result.name
        }
    }

    /// Your note if you wrote one, otherwise the address.
    var detail: String {
        switch self {
        case .saved(let store): store.note.isEmpty ? store.address : store.note
        case .found(let result): result.address
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .saved(let store): store.coordinate
        case .found(let result): result.coordinate
        }
    }

    var isSaved: Bool {
        if case .saved = self { true } else { false }
    }
}

/// A pin: solid green for a saved shop, white with a green ring for one a search found.
struct BookstorePin: View {
    let saved: Bool
    var selected = false

    var body: some View {
        Image(systemName: saved ? "books.vertical.fill" : "book.closed.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(saved ? Color.white : Theme.accent)
            .frame(width: 30, height: 30)
            .background(saved ? Theme.accent : Theme.card, in: Circle())
            .overlay(Circle().stroke(saved ? Color.white : Theme.accent, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1.5)
            .scaleEffect(selected ? 1.3 : 1)
            .animation(.snappy, value: selected)
    }
}

/// One shop in the strip of cards under the map. Found shops have Save on them.
struct BookstoreCard: View {
    let place: BookstorePlace
    let distance: String?
    /// Among search results, say which are already saved (on the Saved list it goes without saying).
    var marksSaved = false
    let onSave: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: place.isSaved ? "books.vertical.fill" : "book.closed.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(.inter(.headline))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !place.detail.isEmpty {
                    Text(place.detail)
                        .font(.inter(.subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                HStack {
                    if let distance {
                        Label(distance, systemImage: "figure.walk")
                            .font(.inter(.caption))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if place.isSaved {
                        if marksSaved {
                            Label("Saved", systemImage: "checkmark")
                                .font(.inter(.caption, .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    } else {
                        Button(action: onSave) {
                            Label("Save", systemImage: "bookmark")
                                .font(.inter(.subheadline, .semibold))
                                .foregroundStyle(Theme.background)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Theme.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(height: 118)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

/// A small rounded button floating over the map.
struct MapChip: View {
    let title: String
    var systemImage: String?
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).lineLimit(1)
            }
            .font(.inter(.subheadline, .semibold))
            .foregroundStyle(selected ? Theme.background : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.regularMaterial), in: Capsule())
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
