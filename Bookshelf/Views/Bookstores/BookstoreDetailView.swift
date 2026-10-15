import SwiftUI
import SwiftData
import MapKit

/// A saved bookstore: where it is, how to get there, and your note.
struct BookstoreDetailView: View {
    @Bindable var store: Bookstore
    let here: CLLocation?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmingRemove = false

    private var phoneURL: URL? {
        guard let phone = store.phone else { return nil }
        return URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" })
    }

    private var websiteURL: URL? {
        store.website.flatMap(URL.init(string:))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    mapHeader
                    heading
                    actions
                    note
                    footer
                }
                .padding(.horizontal, 20)
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

    private var mapHeader: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: store.coordinate, latitudinalMeters: 600, longitudinalMeters: 600)),
            interactionModes: []) {
            Annotation(store.name, coordinate: store.coordinate) {
                BookstorePin(saved: true, selected: true)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture { openInAppleMaps() }
        .accessibilityLabel("Map of \(store.name)")
    }

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
    }

    private func openInAppleMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: store.coordinate))
        item.name = store.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}
