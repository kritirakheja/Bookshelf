import SwiftUI
import SwiftData
import MapKit

/// Bookstores you've saved, on a full-screen map, plus Apple Maps search for ones
/// nearby (or around wherever the map is showing, e.g. a city you're about to visit).
/// The shops show as a strip of cards along the bottom; swiping them moves the map.
struct BookstoresView: View {
    private enum Showing { case saved, found }

    @Environment(\.modelContext) private var context
    @Query(sort: \Bookstore.dateSaved, order: .reverse) private var stores: [Bookstore]

    /// Starts on your saved shops (see `.task`); with none saved, on where you are.
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var lastSearchCenter: CLLocationCoordinate2D?
    @State private var results: [BookstoreResult] = []
    @State private var resultsTitle = "Nearby"
    @State private var showing = Showing.saved
    @State private var selectedID: String?
    @State private var searchText = ""
    @State private var searching = false
    @State private var message: String?
    @State private var openStore: Bookstore?
    @State private var location = LocationProvider()
    @FocusState private var searchFocused: Bool

    /// The cards along the bottom: saved shops, or what the last search found
    /// (shops in there you've already saved show as saved).
    private var places: [BookstorePlace] {
        switch showing {
        case .saved:
            stores.map(BookstorePlace.saved)
        case .found:
            results.map { result in
                BookstoreSearch.saved(result, in: stores).map(BookstorePlace.saved) ?? .found(result)
            }
        }
    }

    /// Found shops not already saved (saved ones are already on the map as saved pins).
    private var newResults: [BookstoreResult] {
        guard showing == .found else { return [] }
        return results.filter { BookstoreSearch.saved($0, in: stores) == nil }
    }

    /// The map is looking somewhere new (well away from the last search and from you):
    /// offer to search there.
    private var mapMovedAway: Bool {
        guard let region = visibleRegion else { return false }
        let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let anchors = [lastSearchCenter, location.location?.coordinate].compactMap { $0 }
        guard !anchors.isEmpty else { return false }
        return anchors.allSatisfy { center.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) > 2_000 }
    }

    var body: some View {
        map
            .safeAreaInset(edge: .top, spacing: 0) { topBar }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomPanel }
            // The keyboard covers the cards rather than pushing them up the map.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .background(Theme.background.ignoresSafeArea())
            .task {
                if !stores.isEmpty { fitMap(to: stores.map(\.coordinate), animated: false) }
                await location.currentIfAllowed()
            }
            .onChange(of: selectedID) { _, id in
                guard let place = places.first(where: { $0.id == id }) else { return }
                focus(on: place.coordinate)
            }
            .sheet(item: $openStore) { store in
                BookstoreDetailView(store: store, here: location.location)
            }
            .alert("Bookstores", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(stores) { store in
                let place = BookstorePlace.saved(store)
                Annotation(store.name, coordinate: store.coordinate) {
                    BookstorePin(saved: true, selected: selectedID == place.id)
                        .onTapGesture { select(place) }
                }
            }
            ForEach(newResults) { result in
                let place = BookstorePlace.found(result)
                Annotation(result.name, coordinate: result.coordinate) {
                    BookstorePin(saved: false, selected: selectedID == place.id)
                        .onTapGesture { select(place) }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
        }
    }

    // MARK: Search box

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search bookstores", text: $searchText)
                    .font(.inter(.body))
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { searchByName() }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Theme.card, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

            if searching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for bookstores…")
                }
                .font(.inter(.subheadline, .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .transition(.opacity)
            } else if mapMovedAway {
                MapChip(title: "Search this area", systemImage: "arrow.clockwise") { searchHere() }
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(.snappy, value: searching)
        .animation(.snappy, value: mapMovedAway)
    }

    // MARK: Cards

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                MapChip(title: "Saved", selected: showing == .saved) { show(.saved) }
                if !results.isEmpty {
                    MapChip(title: resultsTitle, selected: showing == .found) { show(.found) }
                }
                Spacer(minLength: 0)
                MapChip(title: "Find nearby", systemImage: "location.fill") { findNearby() }
                    .disabled(searching)
            }
            .padding(.horizontal, 16)

            if places.isEmpty {
                emptyCard
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(places) { place in
                            BookstoreCard(place: place, distance: distance(to: place.coordinate), marksSaved: showing == .found) {
                                save(place)
                            }
                            .containerRelativeFrame(.horizontal) { width, _ in
                                places.count == 1 ? width - 32 : width - 64
                            }
                            .onTapGesture { open(place) }
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selectedID, anchor: .leading)
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .frame(height: 140)
            }
        }
        .padding(.top, 8)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No saved bookstores yet")
                .font(.inter(.headline))
            Text("Tap Find nearby, or search for a shop you love by name.")
                .font(.inter(.subheadline))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(.horizontal, 16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.bottom, 22)
    }

    // MARK: Choosing

    private func show(_ which: Showing) {
        withAnimation(.snappy) {
            showing = which
            selectedID = nil
        }
        if which == .found { fitMap(to: results.map(\.coordinate)) }
    }

    /// A pin was tapped: bring its card into view (which moves the map to it).
    private func select(_ place: BookstorePlace) {
        searchFocused = false
        if !places.contains(where: { $0.id == place.id }) { showing = .saved }
        withAnimation(.snappy) { selectedID = place.id }
    }

    private func open(_ place: BookstorePlace) {
        switch place {
        case .saved(let store): openStore = store
        case .found: withAnimation(.snappy) { selectedID = place.id }
        }
    }

    private func save(_ place: BookstorePlace) {
        guard case .found(let result) = place else { return }
        let store = withAnimation { BookstoreSearch.save(result, in: context, existing: stores) }
        selectedID = BookstorePlace.saved(store).id
    }

    private func distance(to coordinate: CLLocationCoordinate2D) -> String? {
        guard let here = location.location else { return nil }
        return BookstoreSearch.distanceText(here.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)))
    }

    private func focus(on coordinate: CLLocationCoordinate2D) {
        withAnimation {
            position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1_500, longitudinalMeters: 1_500))
        }
    }

    /// Shows all these places at once, with a little room around them.
    private func fitMap(to coordinates: [CLLocationCoordinate2D], animated: Bool = true) {
        guard !coordinates.isEmpty else { return }
        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.6, 0.012),
                                    longitudeDelta: max((lons.max()! - lons.min()!) * 1.6, 0.012))
        withAnimation(animated ? .default : nil) { position = .region(MKCoordinateRegion(center: center, span: span)) }
    }

    // MARK: Searching

    private func findNearby() {
        searchFocused = false
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
            await runSearch(title: "In this area", center: center) {
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
            await runSearch(title: "“\(text)”", center: center) {
                try await BookstoreSearch.named(text, near: center)
            }
        }
    }

    private func runSearch(title: String, center: CLLocationCoordinate2D?,
                           _ search: () async throws -> [BookstoreResult]) async {
        do {
            let found = try await search()
            lastSearchCenter = center
            guard !found.isEmpty else {
                message = "No bookstores found here. Try zooming out, or searching by name."
                return
            }
            withAnimation(.snappy) {
                results = found
                resultsTitle = title
            }
            show(.found)
        } catch {
            message = "Couldn't search Apple Maps right now. Check your connection and try again."
        }
    }
}

#Preview {
    BookstoresView()
        .modelContainer(SampleData.previewContainer)
        .environment(AccountStore(container: SampleData.previewContainer))
}
