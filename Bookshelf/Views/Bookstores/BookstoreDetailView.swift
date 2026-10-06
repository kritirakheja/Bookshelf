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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Map(initialPosition: .region(MKCoordinateRegion(center: store.coordinate, latitudinalMeters: 700, longitudinalMeters: 700)),
                        interactionModes: []) {
                        Marker(store.name, systemImage: "books.vertical.fill", coordinate: store.coordinate)
                            .tint(.indigo)
                    }
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.name).font(.title2.weight(.bold))
                        if !store.address.isEmpty {
                            Text(store.address).foregroundStyle(.secondary)
                        }
                        if let here {
                            Label(BookstoreSearch.distanceText(here.distance(from: store.location)) + " away", systemImage: "figure.walk")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("Directions in Apple Maps", systemImage: "map") { openInAppleMaps() }
                    Button("Open in Google Maps", systemImage: "globe") {
                        openURL(BookstoreSearch.googleMapsURL(name: store.name, address: store.address,
                                                              latitude: store.latitude, longitude: store.longitude))
                    }
                    if let phone = store.phone, let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) {
                        Button("Call \(phone)", systemImage: "phone") { openURL(url) }
                    }
                    if let website = store.website, let url = URL(string: website) {
                        Button("Website", systemImage: "safari") { openURL(url) }
                    }
                }

                Section("Your note") {
                    TextField("What's special about it?", text: $store.note, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section {
                    Button("Remove bookstore", systemImage: "trash", role: .destructive) { confirmingRemove = true }
                } footer: {
                    Text("Saved \(store.dateSaved.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            .paperScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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

    private func openInAppleMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: store.coordinate))
        item.name = store.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}
