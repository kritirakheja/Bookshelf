import SwiftUI
import SwiftData
import MapKit
import PhotosUI

/// A saved bookstore: what it looks like, how to get there, your ratings and your note.
struct BookstoreDetailView: View {
    @Bindable var store: Bookstore
    let here: CLLocation?
    /// Where Google photos come from; nil shows only your own.
    var photoFinder: (any PlacePhotoFinding)? = GooglePlacesClient.forApp()

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmingRemove = false
    @State private var googlePhotos: [PlacePhoto] = []
    @State private var pickedItem: PhotosPickerItem?
    @State private var choosingFromLibrary = false
    @State private var takingPhoto = false
    @State private var viewing: String?

    private var phoneURL: URL? {
        guard let phone = store.phone else { return nil }
        return URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" })
    }

    private var websiteURL: URL? {
        store.website.flatMap(URL.init(string:))
    }

    /// Yours first, then Google's.
    private var allPhotos: [ShopPhoto] {
        store.sortedPhotos.map(ShopPhoto.mine) + googlePhotos.map(ShopPhoto.google)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    photoStrip
                    heading
                    actions
                    ratings
                    mapView
                    note
                    footer
                }
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .themedScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .keyboardDoneButton()
            .task(id: store.id) {
                googlePhotos = await PlacePhotoCache.photos(for: store, finder: photoFinder)
            }
            .photosPicker(isPresented: $choosingFromLibrary, selection: $pickedItem, matching: .images)
            .onChange(of: pickedItem) {
                guard let item = pickedItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        addPhoto(image)
                    }
                    pickedItem = nil
                }
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraPicker { addPhoto($0) }
                    .ignoresSafeArea()
            }
            .fullScreenCover(item: Binding(get: { viewing.map(ViewingID.init) }, set: { viewing = $0?.id })) { start in
                BookstorePhotoViewer(photos: allPhotos, current: start.id) { photo in
                    withAnimation { context.delete(photo) }
                }
            }
            .confirmationDialog("Remove “\(store.name)”?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    let store = store
                    dismiss()
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        context.deleteBookstore(store)
                    }
                }
            }
        }
    }

    // MARK: Photos

    private var photoStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(allPhotos) { photo in
                    photoTile(photo)
                }
                addPhotoTile
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .frame(height: 200)
        .padding(.top, 4)
    }

    private func photoTile(_ photo: ShopPhoto) -> some View {
        Button {
            viewing = photo.id
        } label: {
            Group {
                if let image = photo.image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Theme.rule
                }
            }
            .frame(width: allPhotos.count == 1 ? 280 : 240, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .bottomLeading) {
                if let credit = photo.credit {
                    Text(credit)
                        .font(.inter(.caption2, .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(photo.credit ?? "Your photo")
    }

    private var addPhotoTile: some View {
        Menu {
            Button("Take photo", systemImage: "camera") { takingPhoto = true }
            Button("Choose from library", systemImage: "photo.on.rectangle") { choosingFromLibrary = true }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 22, weight: .semibold))
                Text("Add photo")
                    .font(.inter(.subheadline, .semibold))
            }
            .foregroundStyle(Theme.accent)
            .frame(width: allPhotos.isEmpty ? 350 : 140, height: 200)
            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
    }

    private func addPhoto(_ image: UIImage) {
        guard let jpeg = image.fitted(maxSide: 1600).jpegData(compressionQuality: 0.8) else { return }
        let photo = BookstorePhoto(data: jpeg)
        context.insert(photo)
        withAnimation { photo.store = store }
    }

    // MARK: Details

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.name)
                .font(.inter(.title2, .bold))
            if !store.address.isEmpty {
                Text(store.address)
                    .font(.inter(.subheadline))
                    .foregroundStyle(.secondary)
            }
            if let here {
                Label(BookstoreSearch.distanceText(here.distance(from: store.location)) + " away", systemImage: "figure.walk")
                    .font(.inter(.footnote, .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 20)
    }

    /// Directions first and filled; calling and the website beside it when known.
    private var actions: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Apple Maps", systemImage: "map") { openInAppleMaps() }
                Button("Google Maps", systemImage: "globe") {
                    openURL(BookstoreSearch.googleMapsURL(name: store.name, address: store.address,
                                                          latitude: store.latitude, longitude: store.longitude))
                }
            } label: {
                actionTile("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill", filled: true)
            }
            if let phoneURL {
                Button { openURL(phoneURL) } label: { actionTile("Call", systemImage: "phone.fill") }
            }
            if let websiteURL {
                Button { openURL(websiteURL) } label: { actionTile("Website", systemImage: "safari.fill") }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private func actionTile(_ title: String, systemImage: String, filled: Bool = false) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
            Text(title)
                .font(.inter(.footnote, .semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .foregroundStyle(filled ? Theme.background : Theme.accent)
        .background(filled ? Theme.accent : Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    /// Two things worth knowing before you go: can you sit and read, and is there coffee.
    private var ratings: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Your ratings")
            VStack(spacing: 0) {
                ratingRow("Good for reading", systemImage: "book", rating: $store.readingRating)
                Divider().padding(.leading, 44)
                ratingRow("Coffee nearby", systemImage: "cup.and.saucer", rating: $store.coffeeRating)
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.rule.opacity(0.6), lineWidth: 0.5))
        }
        .padding(.horizontal, 20)
    }

    private func ratingRow(_ title: String, systemImage: String, rating: Binding<Int?>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
            Text(title)
                .font(.inter(.subheadline))
            Spacer(minLength: 8)
            StarRating(rating: rating, usesTint: true)
                .font(.system(size: 17))
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
    }

    private var mapView: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: store.coordinate, latitudinalMeters: 600, longitudinalMeters: 600)),
            interactionModes: []) {
            Annotation(store.name, coordinate: store.coordinate) {
                BookstorePin(saved: true, selected: true)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture { openInAppleMaps() }
        .accessibilityLabel("Map of \(store.name)")
        .padding(.horizontal, 20)
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Your note")
            TextField("What's special about it?", text: $store.note, axis: .vertical)
                .font(.inter(.body))
                .lineLimit(2...6)
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.rule.opacity(0.6), lineWidth: 0.5))
        }
        .padding(.horizontal, 20)
    }

    private var footer: some View {
        HStack {
            Text("Saved \(store.dateSaved.formatted(date: .abbreviated, time: .omitted))")
                .font(.inter(.footnote))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Remove", role: .destructive) { confirmingRemove = true }
                .font(.inter(.footnote, .semibold))
                .foregroundStyle(.red)
        }
        .padding(.top, 4)
        .padding(.horizontal, 20)
    }

    private func openInAppleMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: store.coordinate))
        item.name = store.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}

/// Which photo the viewer opens on.
private struct ViewingID: Identifiable {
    let id: String
}
