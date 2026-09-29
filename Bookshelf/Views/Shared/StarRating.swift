import SwiftUI

/// Five tappable stars. Tapping the current rating again clears it.
struct StarRating: View {
    @Binding var rating: Int?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = rating == star ? nil : star
                } label: {
                    Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                        .foregroundStyle(star <= (rating ?? 0) ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(rating.map { "\($0) of 5" } ?? "Not rated")
    }
}
