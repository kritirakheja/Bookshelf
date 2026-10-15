import SwiftUI

/// A bookstore photo: one you added, or one from Google Maps (shown with its credit).
enum ShopPhoto: Identifiable {
    case mine(BookstorePhoto)
    case google(PlacePhoto)

    var id: String {
        switch self {
        case .mine(let photo): "mine-" + photo.id.uuidString
        case .google(let photo): "google-" + photo.id.uuidString
        }
    }

    var image: UIImage? {
        switch self {
        case .mine(let photo): UIImage(data: photo.data)
        case .google(let photo): photo.image
        }
    }

    /// "Photo: Priya S." for Google's, as Google asks.
    var credit: String? {
        guard case .google(let photo) = self else { return nil }
        return photo.credit.map { "Photo: \($0)" } ?? "Photo: Google Maps"
    }
}

/// The shop's photos full screen, swiping between them. Your own can be deleted here.
struct BookstorePhotoViewer: View {
    let photos: [ShopPhoto]
    @State var current: String
    let onDelete: (BookstorePhoto) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    private var currentPhoto: ShopPhoto? { photos.first { $0.id == current } }

    var body: some View {
        NavigationStack {
            TabView(selection: $current) {
                ForEach(photos) { photo in
                    VStack(spacing: 12) {
                        if let image = photo.image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if let credit = photo.credit {
                            Text(credit)
                                .font(.inter(.caption))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            .background(Color.black.ignoresSafeArea())
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if case .mine = currentPhoto {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if case .mine(let photo) = currentPhoto {
                        dismiss()
                        onDelete(photo)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
