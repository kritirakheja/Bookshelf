import SwiftUI

/// A book cover at a fixed 2:3 ratio. Falls back to a coloured placeholder
/// (showing the title when there's room) if the book has no cover image.
struct CoverView: View {
    let book: Book
    var width: CGFloat = 44

    var body: some View {
        Group {
            if let data = book.coverImage, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: width > 60 ? 8 : 4))
        .shadow(color: .black.opacity(0.15), radius: width > 60 ? 4 : 1, y: 1)
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(placeholderColor.gradient)
            if width >= 80 {
                Text(book.title)
                    .font(.system(size: width / 8, weight: .semibold, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(6)
            } else {
                Image(systemName: "book.closed")
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    /// Same title always gets the same colour, so placeholders stay stable.
    private var placeholderColor: Color {
        let palette: [Color] = [.indigo, .teal, .brown, .purple, .orange, .mint, .pink, .blue]
        let hash = book.title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[hash % palette.count]
    }
}
