import SwiftUI

/// Share your favourites as an image: a preview, Story or Square, and the share sheet.
struct ShareFavouritesSheet: View {
    let books: [Book]
    let name: String
    @Environment(\.dismiss) private var dismiss
    @State private var format = ShareFormat.story
    @State private var image: UIImage?

    private var title: String {
        let owner = FavouritesShareCard.owner(name)
        return owner == "MY" ? "My Favourite Books" : owner.capitalized.replacingOccurrences(of: "’S", with: "’s") + " Favourite Books"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Size", selection: $format) {
                    ForEach(ShareFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 40)
                .zIndex(1)

                // The card itself, scaled to fit, exactly as it will be sent.
                GeometryReader { proxy in
                    let size = format.size
                    let fit = min(proxy.size.width / size.width, proxy.size.height / size.height)
                    FavouritesShareCard(books: books, name: name, format: format)
                        .clipShape(RoundedRectangle(cornerRadius: 6 / fit))
                        .scaleEffect(fit)
                        .frame(width: size.width * fit, height: size.height * fit)
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                        // Only a picture: its blurred background reaches past its edges
                        // and would otherwise take the taps meant for Story / Square.
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 24)

                if let image {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview(title, image: Image(uiImage: image))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.inter(.headline))
                            .foregroundStyle(Theme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Theme.accent, in: Capsule())
                    }
                    .padding(.horizontal, 24)
                } else {
                    ProgressView().frame(height: 52)
                }
            }
            .padding(.vertical, 12)
            .themedScreen()
            .navigationTitle("Share favourites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task(id: format) {
                image = nil
                image = Self.render(books: books, name: name, format: format)
            }
        }
    }

    /// The card as a picture, 1080 pixels wide.
    @MainActor
    static func render(books: [Book], name: String, format: ShareFormat) -> UIImage? {
        let renderer = ImageRenderer(content: FavouritesShareCard(books: books, name: name, format: format))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(format.size)
        return renderer.uiImage
    }
}
