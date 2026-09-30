import Foundation
import MapKit
import SwiftData

/// A bookstore found on Apple Maps, before it's saved.
struct BookstoreResult: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var address: String
    var city: String
    var latitude: Double
    var longitude: Double
    var phone: String?
    var website: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
}

/// Finds bookstores with Apple Maps (free, no account or key).
enum BookstoreSearch {
    /// Bookstores around a place (the map's current area, or where you are).
    static func nearby(center: CLLocationCoordinate2D, radiusMeters: Double = 5_000) async throws -> [BookstoreResult] {
        try await search("bookstore", center: center, radiusMeters: radiusMeters)
    }

    /// A particular shop by name, e.g. "Blossom Book House Bangalore".
    static func named(_ text: String, near center: CLLocationCoordinate2D?) async throws -> [BookstoreResult] {
        try await search(text, center: center, radiusMeters: 50_000)
    }

    private static func search(_ query: String, center: CLLocationCoordinate2D?, radiusMeters: Double) async throws -> [BookstoreResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        if let center {
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: radiusMeters * 2, longitudinalMeters: radiusMeters * 2)
        }
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map(result(from:))
    }

    static func result(from item: MKMapItem) -> BookstoreResult {
        let placemark = item.placemark
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let address = [street, placemark.subLocality, placemark.locality]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return BookstoreResult(
            name: item.name ?? "Bookstore",
            address: address,
            city: placemark.locality ?? "",
            latitude: placemark.coordinate.latitude,
            longitude: placemark.coordinate.longitude,
            phone: item.phoneNumber,
            website: item.url?.absoluteString
        )
    }

    // MARK: Saving

    /// Within this distance and with the same name, it's the same shop.
    static let sameShopMeters: CLLocationDistance = 150

    static func saved(_ result: BookstoreResult, in stores: [Bookstore]) -> Bookstore? {
        let location = CLLocation(latitude: result.latitude, longitude: result.longitude)
        return stores.first { store in
            store.name.caseInsensitiveCompare(result.name) == .orderedSame
                && store.location.distance(from: location) < sameShopMeters
        }
    }

    /// Saves a search result, unless that shop is already saved (then returns it).
    @MainActor
    @discardableResult
    static func save(_ result: BookstoreResult, in context: ModelContext, existing: [Bookstore]) -> Bookstore {
        if let already = saved(result, in: existing) { return already }
        let store = Bookstore(name: result.name, latitude: result.latitude, longitude: result.longitude)
        store.address = result.address
        store.city = result.city
        store.phone = result.phone
        store.website = result.website
        context.insert(store)
        return store
    }

    // MARK: Showing distance

    /// "350 m" / "2.4 km"
    static func distanceText(_ meters: CLLocationDistance) -> String {
        meters < 1_000
            ? "\(Int((meters / 10).rounded()) * 10) m"
            : String(format: "%.1f km", meters / 1_000)
    }

    /// Opens the shop in Google Maps (the app if installed, else the website).
    static func googleMapsURL(name: String, address: String, latitude: Double, longitude: Double) -> URL {
        var components = URLComponents(string: "https://www.google.com/maps/search/")!
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: [name, address].filter { !$0.isEmpty }.joined(separator: ", ")),
        ]
        return components.url!
    }
}
