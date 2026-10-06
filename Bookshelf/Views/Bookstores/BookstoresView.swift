import SwiftUI
import SwiftData
import MapKit

/// Bookstores you've saved, on a map, plus Apple Maps search for ones nearby
/// (or around wherever the map is showing, e.g. a city you're about to visit).
struct BookstoresView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Bookstore.dateSaved, order: .reverse) private var stores: [Bookstore]

    /// Starts on where you are (city level), falling back to fitting the saved pins.
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var lastSearchCenter: CLLocationCoordinate2D?
    @State private var results: [BookstoreResult] = []
    @State private var resultsTitle = "Nearby"
    @State private var searchText = ""
    @State private var searching = false
    @State private var message: String?
    @State private var selectedStore: Bookstore?
    @State private var selectedResult: BookstoreResult?
    @State private var location = LocationProvider()

    /// Results not already saved (saved ones show as saved pins).
    private var newResults: [BookstoreResult] {
        results.filter { BookstoreSearch.saved($0, in: stores) == nil }
    }

    /// The map has moved well away from the last search: offer to search there.
    private var mapMovedAway: Bool {
        guard let region = visibleRegion else { return false }
        guard let last = lastSearchCenter else { return !stores.isEmpty || !results.isEmpty }
        let a = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let b = CLLocation(latitude: last.latitude, longitude: last.longitude)
        return a.distance(from: b) > 2_000
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                map
                list
            }
            .paperScreen()
            .navigationTitle("Bookstores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Bookstores").font(Theme.serif(.headline, .bold))
                }
            }
            // A solid bar, so the search box doesn't sit on top of the map.
            .toolbarBackground(.visible, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search bookstores by name")
            .onSubmit(of: .search) { searchByName() }
            .sheet(item: $selectedStore) { store in
                BookstoreDetailView(store: store, here: location.location)
            }
            .sheet(item: $selectedResult) { result in
                ResultCard(result: result, distance: distance(to: result.coordinate)) {
                    let store = BookstoreSearch.save(result, in: context, existing: stores)
                    selectedResult = nil
                    selectedStore = store
                }
                .presentationDetents([.height(230)])
            }
            .alert("Bookstores", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(stores) { store in
                Annotation(store.name, coordinate: store.coordinate) {
                    Pin(symbol: "books.vertical.fill", tint: .indigo)
                        .onTapGesture { selectedStore = store }
                }
            }
            ForEach(newResults) { result in
                Annotation(result.name, coordinate: result.coordinate) {
                    Pin(symbol: "book.closed.fill", tint: .orange, size: 28)
                        .onTapGesture { selectedResult = result }
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
        }
        .frame(height: 360)
        // Keep the map inside its card (Maps otherwise draws up under the search bar).
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .padding(.top, 8)
        .overlay(alignment: .bottom) {
            HStack(spacing: 10) {
                Button {
                    findNearby()
                } label: {
                    Label("Find nearby", systemImage: "location.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)

                if mapMovedAway {
                    Button {
                        searchHere()
                    } label: {
                        Label("Search this area", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .background(.regularMaterial, in: Capsule())
                }
            }
            .controlSize(.regular)
            .disabled(searching)
            .padding(.bottom, 20)
        }
        .overlay {
            if searching {
                ProgressView("Looking for bookstores…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: List

    private var list: some View {
        List {
            if !newResults.isEmpty {
                Section(resultsTitle) {
                    ForEach(newResults) { result in
                        HStack {
                            Button {
                                selectedResult = result
                                focus(on: result.coordinate)
                            } label: {
                                StoreRow(name: result.name, detail: result.address,
                                         distance: distance(to: result.coordinate), symbol: "book.closed.fill", tint: .orange)
                            }
                            .buttonStyle(.plain)
                            Button("Save") {
                                BookstoreSearch.save(result, in: context, existing: stores)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            Section {
                ForEach(stores) { store in
                    Button {
                        selectedStore = store
                        focus(on: store.coordinate)
                    } label: {
                        StoreRow(name: store.name, detail: store.note.isEmpty ? store.address : store.note,
                                 distance: distance(to: store.coordinate), symbol: "books.vertical.fill", tint: .indigo)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            withAnimation { context.deleteBookstore(store) }
                        }
                    }
                }
            } header: {
                Text("Saved (\(stores.count))")
            } footer: {
                if stores.isEmpty {
                    Text("Save bookstores you love or want to visit. Tap “Find nearby”, or search for a shop by name.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Searching

    private func distance(to coordinate: CLLocationCoordinate2D) -> String? {
        guard let here = location.location else { return nil }
        return BookstoreSearch.distanceText(here.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)))
    }

    private func focus(on coordinate: CLLocationCoordinate2D) {
        withAnimation {
            position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1_500, longitudinalMeters: 1_500))
        }
    }

    private func findNearby() {
        searching = true
        Task {
            defer { searching = false }
            let here = await location.current()
            guard let center = here?.coordinate ?? visibleRegion?.center else {
                message = "Location is off for Bookshelf. Move the map to an area and tap “Search this area”, or allow location in Settings."
                return
            }
            if here == nil, location.isDenied {
                message = "Location is off for Bookshelf, so this searched the area on the map instead."
            }
            await runSearch(title: "Nearby", center: center) { try await BookstoreSearch.nearby(center: center) }
        }
    }

    private func searchHere() {
        guard let center = visibleRegion?.center else { return }
        searching = true
        Task {
            defer { searching = false }
            await runSearch(title: "In this area", center: center, recenter: false) {
                try await BookstoreSearch.nearby(center: center, radiusMeters: max(2_000, (visibleRegion?.span.latitudeDelta ?? 0.05) * 55_000))
            }
        }
    }

    private func searchByName() {
        let text = searchText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searching = true
        Task {
            defer { searching = false }
            let center = location.location?.coordinate ?? visibleRegion?.center
            await runSearch(title: "Results for “\(text)”", center: center) {
                try await BookstoreSearch.named(text, near: center)
            }
        }
    }

    private func runSearch(title: String, center: CLLocationCoordinate2D?, recenter: Bool = true,
                           _ search: () async throws -> [BookstoreResult]) async {
        do {
            let found = try await search()
            results = found
            resultsTitle = title
            lastSearchCenter = center
            if found.isEmpty {
                message = "No bookstores found here. Try zooming out, or searching by name."
            } else if recenter {
                withAnimation { position = .automatic }
            }
        } catch {
            message = "Couldn't search Apple Maps right now. Check your connection and try again."
        }
    }
}

// MARK: - Pieces

private struct Pin: View {
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

private struct StoreRow: View {
    let name: String
    let detail: String
    let distance: String?
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Pin(symbol: symbol, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline).lineLimit(1)
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let distance {
                Text(distance).font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// A search result tapped on the map, with Save.
private struct ResultCard: View {
    let result: BookstoreResult
    let distance: String?
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(result.name).font(.title3.weight(.bold))
            if !result.address.isEmpty {
                Text(result.address).font(.subheadline).foregroundStyle(.secondary)
            }
            if let distance {
                Label(distance + " away", systemImage: "figure.walk").font(.caption).foregroundStyle(.secondary)
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

extension ModelContext {
    /// Removes a saved bookstore, leaving a marker so the removal syncs.
    func deleteBookstore(_ store: Bookstore) {
        if store.syncedFingerprint != nil {
            insert(DeletedBookstore(remoteID: store.id))
        }
        delete(store)
    }
}

#Preview {
    BookstoresView()
        .modelContainer(SampleData.previewContainer)
        .environment(AccountStore(container: SampleData.previewContainer))
}
