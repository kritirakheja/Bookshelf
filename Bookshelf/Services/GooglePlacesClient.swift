import Foundation
import CoreLocation
import UIKit

/// A photo of a shop from Google Maps, with the credit Google asks to be shown.
struct PlacePhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    /// The person who took it ("Photo: Priya S.").
    let credit: String?
}

/// Finds a bookstore's photos online. `GooglePlacesClient` does it; tests use a fake.
protocol PlacePhotoFinding {
    func placeID(name: String, address: String, near coordinate: CLLocationCoordinate2D) async -> String?
    func photos(placeID: String, limit: Int) async -> [PlacePhoto]
}

/// Google Places (New): a shop's photos. Needs "Places API (New)" switched on for the
/// key in `GOOGLE_PLACES_KEY` (Config/Local.xcconfig). Photos are only shown, never
/// stored (Google's terms); only the place's id is kept. Every failure (no key, API
/// off, quota) just means no Google photos.
struct GooglePlacesClient: PlacePhotoFinding {
    let apiKey: String
    var session: URLSession = .shared

    /// For the app: nil when this build has no key, and while tests drive the app
    /// (they'd go online for every shop opened).
    static func forApp() -> GooglePlacesClient? {
        #if DEBUG
        if PreviewArgs.uiTesting { return nil }
        #endif
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return nil }
        return fromBundle()
    }

    /// nil when this build has no key.
    static func fromBundle() -> GooglePlacesClient? {
        guard let key = Bundle.main.infoDictionary?["GooglePlacesKey"] as? String,
              !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return GooglePlacesClient(apiKey: key)
    }

    // MARK: Finding the shop

    func placeID(name: String, address: String, near coordinate: CLLocationCoordinate2D) async -> String? {
        let body: [String: Any] = [
            "textQuery": [name, address].filter { !$0.isEmpty }.joined(separator: ", "),
            "locationBias": ["circle": [
                "center": ["latitude": coordinate.latitude, "longitude": coordinate.longitude],
                "radius": 300.0,
            ]],
        ]
        var request = self.request("https://places.googleapis.com/v1/places:searchText", fields: "places.id,places.displayName,places.location")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let data = await fetch(request), let places = try? Self.parsePlaces(data) else { return nil }
        return Self.match(places, name: name, near: coordinate)?.id
    }

    /// The same shop: close by (as when saving a search result twice) and sharing a
    /// word of its name, so a café next door doesn't count.
    static func match(_ places: [Place], name: String, near coordinate: CLLocationCoordinate2D) -> Place? {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let words = significantWords(name)
        return places.first { place in
            guard let location = place.location else { return false }
            let close = here.distance(from: CLLocation(latitude: location.latitude, longitude: location.longitude)) < BookstoreSearch.sameShopMeters
            let named = words.isEmpty || !words.isDisjoint(with: significantWords(place.displayName?.text ?? ""))
            return close && named
        }
    }

    private static func significantWords(_ text: String) -> Set<String> {
        let common: Set<String> = ["the", "and", "book", "books", "bookstore", "bookshop", "store", "shop", "house", "of"]
        return Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 1 && !common.contains($0) })
    }

    // MARK: Photos

    func photos(placeID: String, limit: Int = 6) async -> [PlacePhoto] {
        let details = request("https://places.googleapis.com/v1/places/\(placeID)", fields: "photos")
        guard let data = await fetch(details), let refs = try? Self.parsePhotos(data) else { return [] }
        return await withTaskGroup(of: (Int, PlacePhoto?).self) { group in
            for (index, ref) in refs.prefix(limit).enumerated() {
                group.addTask { (index, await photo(ref)) }
            }
            var found: [(Int, PlacePhoto)] = []
            for await (index, photo) in group {
                if let photo { found.append((index, photo)) }
            }
            return found.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func photo(_ ref: PhotoRef) async -> PlacePhoto? {
        var media = request("https://places.googleapis.com/v1/\(ref.name)/media", fields: nil)
        var components = URLComponents(url: media.url!, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "maxWidthPx", value: "1200"),
            URLQueryItem(name: "skipHttpRedirect", value: "true"),
        ]
        media.url = components.url
        guard let data = await fetch(media),
              let uri = (try? JSONDecoder().decode(MediaResponse.self, from: data))?.photoUri,
              let url = URL(string: uri),
              let (imageData, _) = try? await session.data(from: url),
              let image = UIImage(data: imageData) else { return nil }
        return PlacePhoto(image: image, credit: ref.authorAttributions?.first?.displayName)
    }

    // MARK: Requests

    private func request(_ url: String, fields: String?) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        if let fields { request.setValue(fields, forHTTPHeaderField: "X-Goog-FieldMask") }
        // The key is restricted to this app; Google checks this header.
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        return request
    }

    private func fetch(_ request: URLRequest) async -> Data? {
        guard let (data, response) = try? await session.data(for: request) else { return nil }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 {
            #if DEBUG
            print("Google Places \(status): \(String(decoding: data.prefix(300), as: UTF8.self))")
            #endif
            return nil
        }
        return data
    }

    // MARK: Parsing

    struct Place: Decodable {
        struct Name: Decodable { let text: String? }
        struct Location: Decodable { let latitude: Double; let longitude: Double }
        let id: String
        let displayName: Name?
        let location: Location?
    }

    struct PhotoRef: Decodable {
        struct Author: Decodable { let displayName: String? }
        let name: String
        let authorAttributions: [Author]?
    }

    private struct PlacesResponse: Decodable { let places: [Place]? }
    private struct DetailsResponse: Decodable { let photos: [PhotoRef]? }
    private struct MediaResponse: Decodable { let photoUri: String? }

    static func parsePlaces(_ data: Data) throws -> [Place] {
        try JSONDecoder().decode(PlacesResponse.self, from: data).places ?? []
    }

    static func parsePhotos(_ data: Data) throws -> [PhotoRef] {
        try JSONDecoder().decode(DetailsResponse.self, from: data).photos ?? []
    }
}

/// Google photos already loaded this session, by place, so reopening a shop doesn't
/// download them again (kept in memory only, per Google's terms).
@MainActor
enum PlacePhotoCache {
    private static var photos: [String: [PlacePhoto]] = [:]

    static func photos(for store: Bookstore, finder: (any PlacePhotoFinding)?) async -> [PlacePhoto] {
        guard let finder else { return [] }
        if store.googlePlaceID == nil {
            store.googlePlaceID = await finder.placeID(name: store.name, address: store.address, near: store.coordinate)
        }
        guard let id = store.googlePlaceID else { return [] }
        if let cached = photos[id] { return cached }
        let found = await finder.photos(placeID: id, limit: 6)
        if !found.isEmpty { photos[id] = found }
        return found
    }
}
