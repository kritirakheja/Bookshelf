import SwiftUI
import SwiftData
import MapKit

struct BookstorePin: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 2, y: 1)
    }
}

struct BookstoreRow: View {
    let name: String
    let detail: String
    let distance: String?
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            BookstorePin(symbol: symbol, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.inter(.headline)).lineLimit(1)
                if !detail.isEmpty {
                    Text(detail).font(.inter(.caption)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let distance {
                Text(distance).font(.inter(.caption)).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// A search result tapped on the map, with Save.
struct BookstoreResultCard: View {
    let result: BookstoreResult
    let distance: String?
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(result.name).font(.inter(.title3, .bold))
            if !result.address.isEmpty {
                Text(result.address).font(.inter(.subheadline)).foregroundStyle(.secondary)
            }
            if let distance {
                Label(distance + " away", systemImage: "figure.walk").font(.inter(.caption)).foregroundStyle(.secondary)
            }
            Button(action: onSave) {
                Label("Save bookstore", systemImage: "bookmark.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}
