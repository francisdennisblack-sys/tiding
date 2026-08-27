import SwiftUI
import MapKit
import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import LinkPresentation

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var lastKnownLocation: CLLocation? = nil

    private let manager: CLLocationManager

    override init() {
        let locationManager = CLLocationManager()
        self.manager = locationManager
        self.authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastKnownLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastKnownLocation = nil
    }
}

private struct RouteMapPoint: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let tint: Color
}

private enum LiveRouteCodec {
    static func encode(start: String, end: String, isRunBranding: Bool = false) -> String {
        var components = URLComponents()
        components.scheme = "spotroute"
        components.host = "route"
        components.queryItems = [
            URLQueryItem(name: "start", value: start.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "end", value: end.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "brand", value: isRunBranding ? "run" : "trip")
        ]
        return components.string ?? "spotroute://route"
    }

    static func decode(_ raw: String) -> (start: String, end: String, isRunBranding: Bool)? {
        guard let components = URLComponents(string: raw), components.scheme == "spotroute" else {
            return nil
        }

        let start = components.queryItems?.first(where: { $0.name == "start" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let end = components.queryItems?.first(where: { $0.name == "end" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let brand = components.queryItems?.first(where: { $0.name == "brand" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "trip"
        let isRunBranding = brand == "run"

        guard !start.isEmpty || !end.isEmpty else { return nil }
        return (start: start, end: end, isRunBranding: isRunBranding)
    }

    static func resolvedMapPoints(start: String, end: String, nearbyPlaces: [NearbyPlace]) -> [RouteMapPoint] {
        let trimmedStart = start.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEnd = end.trimmingCharacters(in: .whitespacesAndNewlines)

        var points: [RouteMapPoint] = []
        if !trimmedStart.isEmpty {
            let coordinate = coordinateForPlace(named: trimmedStart, nearbyPlaces: nearbyPlaces)
            points.append(RouteMapPoint(id: "start-\(trimmedStart)", name: trimmedStart, coordinate: coordinate, tint: .green))
        }
        if !trimmedEnd.isEmpty {
            let coordinate = coordinateForPlace(named: trimmedEnd, nearbyPlaces: nearbyPlaces)
            points.append(RouteMapPoint(id: "end-\(trimmedEnd)", name: trimmedEnd, coordinate: coordinate, tint: .red))
        }
        return points
    }

    static func region(for points: [RouteMapPoint]) -> MKCoordinateRegion {
        guard let first = points.first else {
            return MKCoordinateRegion(
                center: NearbyPlaceLoader.defaultCenter,
                span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
            )
        }

        if points.count == 1 {
            return MKCoordinateRegion(
                center: first.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.14, longitudeDelta: 0.14)
            )
        }

        let latitudes = points.map { $0.coordinate.latitude }
        let longitudes = points.map { $0.coordinate.longitude }
        let minLat = latitudes.min() ?? first.coordinate.latitude
        let maxLat = latitudes.max() ?? first.coordinate.latitude
        let minLon = longitudes.min() ?? first.coordinate.longitude
        let maxLon = longitudes.max() ?? first.coordinate.longitude

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.08, (maxLat - minLat) * 1.9),
            longitudeDelta: max(0.08, (maxLon - minLon) * 1.9)
        )

        return MKCoordinateRegion(center: center, span: span)
    }

    private static func coordinateForPlace(named place: String, nearbyPlaces: [NearbyPlace]) -> CLLocationCoordinate2D {
        let normalized = place.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let local = nearbyPlaces.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }) {
            return CLLocationCoordinate2D(latitude: local.latitude, longitude: local.longitude)
        }

        let fallbackPool = NearbyPlaceLoader.loadAllPlaces(from: NearbyPlaceLoader.defaultCenter, limit: 240)
        if let known = fallbackPool.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }) {
            return CLLocationCoordinate2D(latitude: known.latitude, longitude: known.longitude)
        }

        let hashSeed = abs(normalized.hashValue % 1000)
        let latOffset = Double(hashSeed % 35) / 1000.0
        let lonOffset = Double((hashSeed / 7) % 35) / 1000.0
        return CLLocationCoordinate2D(
            latitude: NearbyPlaceLoader.defaultCenter.latitude + latOffset,
            longitude: NearbyPlaceLoader.defaultCenter.longitude - lonOffset
        )
    }
}

private enum GuidePostCodec {
    static func encode(steps: [String]) -> String {
        let cleanedSteps = normalizedSteps(steps)
        var components = URLComponents()
        components.scheme = "spotguide"
        components.host = "slides"
        components.queryItems = cleanedSteps.enumerated().map { pair in
            URLQueryItem(name: "s\(pair.offset + 1)", value: pair.element)
        }
        return components.string ?? "spotguide://slides"
    }

    static func decode(_ raw: String) -> [String] {
        guard let components = URLComponents(string: raw), components.scheme == "spotguide" else {
            return []
        }

        let keyed = (components.queryItems ?? [])
            .filter { $0.name.hasPrefix("s") }
            .compactMap { item -> (Int, String)? in
                let indexRaw = String(item.name.dropFirst())
                guard let index = Int(indexRaw), index >= 1, index <= 10 else { return nil }
                let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !value.isEmpty else { return nil }
                return (index, value)
            }
            .sorted { $0.0 < $1.0 }

        return normalizedSteps(keyed.map { $0.1 })
    }

    static func normalizedSteps(_ steps: [String]) -> [String] {
        let cleaned = steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(cleaned.prefix(10))
    }
}

private struct WorkPostDetails {
    let listings: [String]
    let phone: String
    let email: String
    let dmResume: Bool
}

private enum WorkPostCodec {
    static func encode(listings: [String], phone: String, email: String, dmResume: Bool) -> String {
        let cleanedListings = normalizedListings(listings)
        var components = URLComponents()
        components.scheme = "spotwork"
        components.host = "listing"

        var items: [URLQueryItem] = cleanedListings.enumerated().map { pair in
            URLQueryItem(name: "j\(pair.offset + 1)", value: pair.element)
        }
        items.append(URLQueryItem(name: "phone", value: phone.trimmingCharacters(in: .whitespacesAndNewlines)))
        items.append(URLQueryItem(name: "email", value: email.trimmingCharacters(in: .whitespacesAndNewlines)))
        items.append(URLQueryItem(name: "dmresume", value: dmResume ? "1" : "0"))
        components.queryItems = items

        return components.string ?? "spotwork://listing"
    }

    static func decode(_ raw: String) -> WorkPostDetails? {
        guard let components = URLComponents(string: raw), components.scheme == "spotwork" else {
            return nil
        }

        let listings = normalizedListings(
            (components.queryItems ?? [])
                .filter { $0.name.hasPrefix("j") }
                .compactMap { item -> (Int, String)? in
                    let rawIndex = String(item.name.dropFirst())
                    guard let index = Int(rawIndex), index >= 1, index <= 10 else { return nil }
                    let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !value.isEmpty else { return nil }
                    return (index, value)
                }
                .sorted { $0.0 < $1.0 }
                .map { $0.1 }
        )

        let phone = components.queryItems?.first(where: { $0.name == "phone" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let email = components.queryItems?.first(where: { $0.name == "email" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dmResume = components.queryItems?.first(where: { $0.name == "dmresume" })?.value == "1"

        if listings.isEmpty && phone.isEmpty && email.isEmpty {
            return nil
        }

        return WorkPostDetails(listings: listings, phone: phone, email: email, dmResume: dmResume)
    }

    static func normalizedListings(_ listings: [String]) -> [String] {
        let cleaned = listings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(cleaned.prefix(10))
    }

    static func sanitizedPhoneDigits(_ raw: String) -> String {
        raw.filter { $0.isWholeNumber }
    }
}

private struct SaleDraftPersistence: Codable {
    let item: String
    let price: String
    let phone: String
    let email: String
    let description: String
    let photoData: Data?
}

struct SalePostDetails {
    let items: [String]
    let price: String
    let phone: String
    let email: String
}

enum SalePostCodec {
    static func encode(items: [String], price: String, phone: String, email: String) -> String {
        let cleanedItems = normalizedItems(items)
        var components = URLComponents()
        components.scheme = "spotsale"
        components.host = "listing"

        var queryItems: [URLQueryItem] = cleanedItems.enumerated().map { pair in
            URLQueryItem(name: "i\(pair.offset + 1)", value: pair.element)
        }
        queryItems.append(URLQueryItem(name: "price", value: price.trimmingCharacters(in: .whitespacesAndNewlines)))
        queryItems.append(URLQueryItem(name: "phone", value: phone.trimmingCharacters(in: .whitespacesAndNewlines)))
        queryItems.append(URLQueryItem(name: "email", value: email.trimmingCharacters(in: .whitespacesAndNewlines)))
        components.queryItems = queryItems

        return components.string ?? "spotsale://listing"
    }

    static func decode(_ raw: String) -> SalePostDetails? {
        guard let components = URLComponents(string: raw), components.scheme == "spotsale" else {
            return nil
        }

        let items = normalizedItems(
            (components.queryItems ?? [])
                .filter { $0.name.hasPrefix("i") }
                .compactMap { pair -> (Int, String)? in
                    let indexValue = String(pair.name.dropFirst())
                    guard let index = Int(indexValue), index >= 1, index <= 10 else { return nil }
                    let value = pair.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !value.isEmpty else { return nil }
                    return (index, value)
                }
                .sorted { $0.0 < $1.0 }
                .map { $0.1 }
        )

        let price = components.queryItems?.first(where: { $0.name == "price" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let phone = components.queryItems?.first(where: { $0.name == "phone" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let email = components.queryItems?.first(where: { $0.name == "email" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !items.isEmpty || !price.isEmpty || !phone.isEmpty || !email.isEmpty else {
            return nil
        }

        return SalePostDetails(items: items, price: price, phone: phone, email: email)
    }

    static func normalizedItems(_ items: [String]) -> [String] {
        let cleaned = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(cleaned.prefix(10))
    }
}

private enum SongPostRules {
    static let allowedExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac"]

    static func isSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allowedExtensions.contains(ext)
    }

    static func allowedFormatsText() -> String {
        "Supported song files: .mp3, .m4a, .aac, .wav, .aiff, .flac"
    }

    static func embeddedArtworkImage(from url: URL?) -> UIImage? {
        guard let url else { return nil }

        let asset = AVAsset(url: url)
        let metadataItems = asset.commonMetadata.filter { item in
            guard let key = item.commonKey else { return false }
            return key == .commonKeyArtwork || key == .commonKeyTitle || key == .commonKeyAlbumName
        }

        for item in metadataItems {
            if let data = item.value as? Data,
               let image = UIImage(data: data) {
                return image
            }

            if let value = item.value,
               let image = UIImage(data: value as? Data ?? Data()) {
                return image
            }
        }

        for item in asset.metadata {
            guard let key = item.commonKey,
                  key == .commonKeyArtwork else {
                continue
            }

            if let data = item.value as? Data,
               let image = UIImage(data: data) {
                return image
            }
        }

        for item in asset.metadata {
            guard let key = item.key as? String else { continue }
            let isArtworkKey = key == "com.apple.iTunesArtwork" || key == "artwork"
            guard isArtworkKey else { continue }
            if let data = item.value as? Data,
               let image = UIImage(data: data) {
                return image
            }
        }

        return nil
    }
}

private struct LiveRouteMiniMapView: View {
    let startName: String
    let endName: String
    var nearbyPlaces: [NearbyPlace] = []
    var height: CGFloat = 210

    private var points: [RouteMapPoint] {
        LiveRouteCodec.resolvedMapPoints(start: startName, end: endName, nearbyPlaces: nearbyPlaces)
    }

    private var region: MKCoordinateRegion {
        LiveRouteCodec.region(for: points)
    }

    var body: some View {
        Map(coordinateRegion: .constant(region), annotationItems: points) { point in
            MapMarker(coordinate: point.coordinate, tint: point.tint)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .allowsHitTesting(false)
    }
}

struct NearbyPlace: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let latitude: Double
    let longitude: Double
}

private struct NearbyPlaceRecord: Decodable {
    let poi_id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let category: String
}

private enum NearbyPlaceLoader {
    static let defaultCenter = CLLocationCoordinate2D(latitude: 40.7608, longitude: -111.8910)
    private static var cachedBundledPlaces: [NearbyPlace]?

    static func loadNearbyPlaces(from location: CLLocation, limit: Int = 50) -> [NearbyPlace] {
        let allPlaces = loadAllPlaces(from: location.coordinate)
        return Array(allPlaces.prefix(limit))
    }

    static func loadAllPlaces(from coordinate: CLLocationCoordinate2D, limit: Int = 120) -> [NearbyPlace] {
        let fallback = [
            NearbyPlace(id: "salt_lake_1", name: "Temple Square", category: "landmark", latitude: 40.7707, longitude: -111.8910),
            NearbyPlace(id: "salt_lake_2", name: "City Creek Center", category: "shopping", latitude: 40.7675, longitude: -111.8897),
            NearbyPlace(id: "salt_lake_3", name: "Liberty Park", category: "park", latitude: 40.7362, longitude: -111.8597),
            NearbyPlace(id: "salt_lake_4", name: "Natural History Museum of Utah", category: "museum", latitude: 40.7647, longitude: -111.8261)
        ]

        let allPlaces: [NearbyPlace]
        if let cachedBundledPlaces {
            allPlaces = cachedBundledPlaces
        } else {
            allPlaces = loadBundledPOIs()
            cachedBundledPlaces = allPlaces
        }

        // If no places loaded, return fallback
        guard !allPlaces.isEmpty else {
            return fallback
        }

        let rankedPlaces = allPlaces
            .sorted { lhs, rhs in
                let distanceA = haversineMiles(from: coordinate, to: CLLocationCoordinate2D(latitude: lhs.latitude, longitude: lhs.longitude))
                let distanceB = haversineMiles(from: coordinate, to: CLLocationCoordinate2D(latitude: rhs.latitude, longitude: rhs.longitude))
                return distanceA < distanceB
            }
            .prefix(limit)

        return Array(rankedPlaces)
    }

    private static func loadBundledPOIs() -> [NearbyPlace] {
        // Keep local fallback lightweight and reliable to avoid startup/watchdog termination.
        guard let url = Bundle.main.url(forResource: "salt_lake_city_pois", withExtension: "json") else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let items = try JSONDecoder().decode([NearbyPlaceRecord].self, from: data)
            var seen = Set<String>()

            return items.compactMap { item -> NearbyPlace? in
                if item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
                if seen.contains(item.poi_id) { return nil }
                seen.insert(item.poi_id)
                return NearbyPlace(id: item.poi_id, name: item.name, category: item.category, latitude: item.latitude, longitude: item.longitude)
            }
        } catch {
            return []
        }
    }

    static func haversineMiles(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let radiusMiles = 3958.8
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLat = (to.latitude - from.latitude) * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2) + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return radiusMiles * c
    }
}

enum LocationSuggestionRanker {
    static func rankedSuggestions(
        query: String,
        nearbyPlaces: [NearbyPlace],
        fallback: [String],
        userCoordinate: CLLocationCoordinate2D
    ) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let nearbyMatches: [String]
        if trimmed.isEmpty {
            nearbyMatches = nearbyPlaces
                .sorted { lhs, rhs in
                    let lhsDistance = NearbyPlaceLoader.haversineMiles(
                        from: userCoordinate,
                        to: CLLocationCoordinate2D(latitude: lhs.latitude, longitude: lhs.longitude)
                    )
                    let rhsDistance = NearbyPlaceLoader.haversineMiles(
                        from: userCoordinate,
                        to: CLLocationCoordinate2D(latitude: rhs.latitude, longitude: rhs.longitude)
                    )
                    return lhsDistance < rhsDistance
                }
                .prefix(50)
                .map(\.name)
        } else {
            nearbyMatches = nearbyPlaces
                .map { place -> (name: String, score: Double) in
                    let lower = place.name.lowercased()
                    let distance = NearbyPlaceLoader.haversineMiles(
                        from: userCoordinate,
                        to: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
                    )

                    let isQueryMatch = lower == trimmed
                        || lower.hasPrefix(trimmed)
                        || lower.contains(trimmed)
                        || place.category.lowercased().contains(trimmed)
                    guard isQueryMatch else {
                        return (place.name, 0)
                    }

                    let textScore: Double = {
                        var score = 0.0
                        if lower == trimmed { score += 100000 }
                        if lower.hasPrefix(trimmed) { score += 60000 }
                        if lower.contains(trimmed) { score += 25000 }
                        if place.category.lowercased().contains(trimmed) { score += 15000 }
                        return score
                    }()

                    let proximityScore = max(0.0, 1000.0 - (distance * 70.0))
                    let combinedScore = textScore + (proximityScore * 0.25)
                    return (place.name, combinedScore)
                }
                .filter { $0.score > 0 }
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    let lhsDistance = distanceForPlace(named: lhs.name, nearbyPlaces: nearbyPlaces, userCoordinate: userCoordinate)
                    let rhsDistance = distanceForPlace(named: rhs.name, nearbyPlaces: nearbyPlaces, userCoordinate: userCoordinate)
                    return lhsDistance < rhsDistance
                }
                .map(\.name)
        }

        let fallbackMatches = fallback
            .map { suggestion -> (name: String, score: Double) in
                let lower = suggestion.lowercased()
                let textScore = fallbackScore(for: suggestion, query: trimmed)
                return (suggestion, textScore)
            }
            .filter { suggestion in
                if trimmed.isEmpty { return true }
                let lower = suggestion.name.lowercased()
                return lower.contains(trimmed) || lower.hasPrefix(trimmed) || lower == trimmed
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.name < rhs.name
            }
            .map(\.name)

        var ordered: [String] = []
        for name in nearbyMatches + fallbackMatches {
            if !ordered.contains(name) {
                ordered.append(name)
            }
        }

        return ordered
    }

    private static func distanceForPlace(
        named name: String,
        nearbyPlaces: [NearbyPlace],
        userCoordinate: CLLocationCoordinate2D
    ) -> Double {
        guard let place = nearbyPlaces.first(where: { $0.name == name }) else {
            return Double.greatestFiniteMagnitude
        }

        return NearbyPlaceLoader.haversineMiles(
            from: userCoordinate,
            to: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        )
    }

    private static func fallbackScore(for suggestion: String, query: String) -> Double {
        let lower = suggestion.lowercased()
        if query.isEmpty { return 1 }
        if lower == query { return 100000 }
        if lower.hasPrefix(query) { return 60000 }
        if lower.contains(query) { return 25000 }
        return 0
    }
}

struct ContentView: View {
    private struct SavedAccountCredential: Codable, Identifiable {
        let email: String
        var username: String
        var displayName: String
        var lastUsedAt: TimeInterval

        var id: String {
            email.lowercased()
        }
    }

    private let feedLocationDefaultsKey = "spot_feed_location"
    private let videoLocationDefaultsKey = "spot_video_location"
    private let postLocationDefaultsKey = "spot_post_location"
    private let savedLocationsDefaultsKey = "spot_saved_locations"
    private let recentLocationsDefaultsKey = "spot_recent_locations"
    private let profilePhotoDefaultsKey = "spot_profile_photo_data"
    private let phoneNumberDefaultsKey = "spot_phone_number"
    private let backupPhoneNumberDefaultsKey = "spot_backup_phone_number"
    private let accountUsernameDefaultsKey = "spot_account_username"
    private let profileNameDefaultsKey = "spot_profile_name"
    private let accountEmailDefaultsKey = "spot_account_email"
    private let accountPasswordDefaultsKey = "spot_account_password"
    private let accountSignedInDefaultsKey = "spot_account_signed_in"
    private let savedAccountsDefaultsKey = "spot_saved_accounts"
    private let draftAudioRecordingDefaultsKey = "spot_draft_recorded_audio_url"
    private let anonymousModeDefaultsKey = "spot_anonymous_mode_enabled"
    private static let locationPostCooldownDefaultsKey = "spot_location_post_cooldown_history"
    private let profilePhotoLastWriteAtDefaultsKey = "spot_profile_photo_last_write_at"
    private let profilePhotoPendingSyncDefaultsKey = "spot_profile_photo_pending_sync"

    private static let anonymousDisplayName = "Anonymous"
    private static let anonymousHandle = "anonymous"
    private static let anonymousTagMarker = "spot:anonymous"
    private static let boostedTagMarker = "spot:boosted"
    private static let adminPinnedPostsByRealmDefaultsKey = "spot_admin_pinned_posts_by_realm"
    private static let adminPinnedPostsAtDefaultsKey = "spot_admin_pinned_posts_at"
    private static let adminGlobalPinCodeDefaultsKey = "spot_admin_global_pin_code"
    private static let adminUnpinCodeDefaultsKey = "spot_admin_unpin_code"
    private static let adminPinAllNonMetricMarker = "spot:all-non-metric"
    private static let adminPinRealmTagPrefix = "spot:admin-pin:realm:"
    private static let adminPinTimestampTagPrefix = "spot:admin-pin:at:"
    private static let perLocationPostLimit = 5
    private static let perLocationCooldownWindowSeconds: TimeInterval = 3600
    private static let maxAudioRecordingDurationSeconds: TimeInterval = 36_000
    private static let bottomSilverEndCapHeight: CGFloat = 3
    private static let sparseProfileBottomInset: CGFloat = 170

    @State private var sendTo = ""
    @State private var fromLocation = ""
    @State private var videoLocation = "Metric"
    @State private var postLocation = "Tokyo, Japan"
    @State private var selectedPostType = "Photo"
    @State private var currentScreen: Screen = .home
    @State private var locationContext: LocationContext = .feed

    @State private var draftTitle = ""
    @State private var draftBody = ""
    @State private var draftUrl = ""
    @State private var draftLocation = "Tokyo, Japan"
    @State private var draftPollQuestion = ""
    @State private var draftPollOptionA = ""
    @State private var draftPollOptionB = ""
    @State private var draftRouteStart = ""
    @State private var draftRouteEnd = ""
    @State private var draftRouteIsRunBranding = false
    @State private var draftGuideSteps: [String] = [""]
    @State private var draftWorkListings: [String] = [""]
    @State private var draftWorkContactPhone = ""
    @State private var draftWorkContactEmail = ""
    @State private var draftWorkDMResumeEnabled = false
    @State private var draftSaleItems: [String] = [""]
    @State private var draftSalePrice = ""
    @State private var draftSaleContactPhone = ""
    @State private var draftSaleContactEmail = ""
    @State private var draftPhotoItem: PhotosPickerItem? = nil
    private static let saleDraftPersistenceKey = "spot_draft_sale_state"
    @State private var draftPhotoImage: UIImage? = nil
    @State private var draftPhotoCropScale: CGFloat = 1.0
    @State private var draftPhotoCropOffset: CGSize = .zero
    @State private var draftVideoItem: PhotosPickerItem? = nil
    @State private var draftVideoURL: URL? = nil
    @State private var isPreparingVideoSelection = false
    @State private var draftRecordedAudioURL: URL? = nil
    @State private var draftSongFileURL: URL? = nil
    @State private var isSongFileImporterPresented = false
    @State private var draftAudioRecorder: AVAudioRecorder? = nil
    @State private var isRecordingAudio = false
    @State private var isAudioPlaybackActive = false
    @State private var hasPlayedRecordedAudio = false
    @State private var audioPlaybackPlayer: AVAudioPlayer? = nil

    @State private var profileName = UserDefaults.standard.string(forKey: "spot_profile_name") ?? ""
    @State private var pendingProfileNameSaveTask: Task<Void, Never>? = nil
    @State private var profileNameSaveMessage = "Saving..."
    @State private var isProfileNameSavePending = false
    @State private var profileUsername = UserDefaults.standard.string(forKey: "spot_account_username") ?? ""
    @State private var isCheckingUsernameAvailability = false
    @State private var usernameAvailabilityIsAvailable = false
    @State private var usernameAvailabilityMessage = "Not checked"
    @State private var accountUsername = UserDefaults.standard.string(forKey: "spot_account_username") ?? ""
    @State private var showPasswordResetSpamNotice = false
    @State private var accountEmail = UserDefaults.standard.string(forKey: "spot_account_email") ?? ""
    @State private var accountPassword = UserDefaults.standard.string(forKey: "spot_account_password") ?? ""
    @State private var isSignedInToAccount = UserDefaults.standard.bool(forKey: "spot_account_signed_in")
    @State private var accountAuthMessage = ""
    @State private var composerStatusMessage = ""
    @State private var isAnonymousModeEnabled = UserDefaults.standard.bool(forKey: "spot_anonymous_mode_enabled")
    @State private var draftIsAnonymous = UserDefaults.standard.bool(forKey: "spot_anonymous_mode_enabled")
    @State private var locationPostCooldownHistory = ContentView.loadLocationPostCooldownHistory()
    @State private var postLocationCooldownMessage = ""
    @State private var savedAccounts: [SavedAccountCredential] = []
    @State private var selectedSavedAccountEmail = ""
    @State private var followedUserIDs: Set<String> = []
    @State private var followerUserIDs: Set<String> = []
    @State private var profilePhotoRemoteURL: String = ""
    @State private var isActiveAuthorPhotoRefreshInFlight = false
    @State private var lastActiveAuthorPhotoRefreshAt: TimeInterval = 0

    private var hasSavedUsername: Bool {
        let savedUsername = UserDefaults.standard.string(forKey: accountUsernameDefaultsKey) ?? ""
        let trimmed = accountUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !savedUsername.isEmpty && trimmed == savedUsername
    }

    @State private var phoneNumber = ""
    @State private var pendingPhoneNumber = ""
    @State private var pendingPhoneVerificationID: String? = nil
    @State private var phoneVerificationCode = ""
    @State private var phoneAuthMessage = ""
    @State private var isSendingPhoneCode = false
    @State private var isVerifyingPhoneCode = false

    @State private var backupPhoneNumber = ""
    @State private var backupPendingPhoneNumber = ""
    @State private var backupPendingPhoneVerificationID: String? = nil
    @State private var backupPhoneVerificationCode = ""
    @State private var backupPhoneAuthMessage = ""
    @State private var isSendingBackupPhoneCode = false
    @State private var isVerifyingBackupPhoneCode = false
    @State private var profilePhotoText = "YO"
    @State private var profilePhotoItem: PhotosPickerItem? = nil
    @State private var profilePhotoImage: UIImage? = nil
    @State private var profilePhotoPreviewImage: UIImage? = nil
    @State private var pendingProfilePhotoSelection: UIImage? = nil
    @State private var isProfilePhotoUploadPending = false

    private var displayProfilePhotoImage: UIImage? {
        profilePhotoPreviewImage ?? profilePhotoImage
    }

    private var hasActiveProfilePhoto: Bool {
        displayProfilePhotoImage != nil
    }

    private func setSelectedProfilePhoto(_ image: UIImage) {
        profilePhotoImage = image
        profilePhotoPreviewImage = image
        pendingProfilePhotoSelection = image
        profilePhotoText = ""
        profilePhotoCropScale = 1.0
        profilePhotoCropOffset = .zero
    }

    private func resolvedUsernameForProfileSave(userID: String) async -> String {
        let trimmedCurrent = profileUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCurrent.isEmpty {
            let normalized = FirebaseSpotService.normalizeUsername(trimmedCurrent)
            if FirebaseSpotService.isValidUsername(normalized) {
                return normalized
            }
        }

        if let existingAccount = try? await FirebaseSpotService.shared.fetchUserAccount(userID: userID) {
            let existingUsername = FirebaseSpotService.normalizeUsername(existingAccount.username)
            if FirebaseSpotService.isValidUsername(existingUsername) {
                profileUsername = existingUsername
                return existingUsername
            }
        }

        let displayBase = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayBase.isEmpty {
            let fromName = FirebaseSpotService.normalizeUsername(displayBase)
            if FirebaseSpotService.isValidUsername(fromName) {
                profileUsername = fromName
                return fromName
            }
        }

        // Build a stable, user-specific fallback to avoid collisions on common names like "user".
        let fallback = "u\(userID)"
        let sanitized = FirebaseSpotService.normalizeUsername(fallback)
        let secondaryFallback = FirebaseSpotService.normalizeUsername("user_\(userID)")
        let valid: String
        if FirebaseSpotService.isValidUsername(sanitized) {
            valid = sanitized
        } else if FirebaseSpotService.isValidUsername(secondaryFallback) {
            valid = secondaryFallback
        } else {
            valid = "user123"
        }
        profileUsername = valid
        return valid
    }
    @State private var profilePhotoCropScale: CGFloat = 1.0
    @State private var profilePhotoCropOffset: CGSize = .zero
    @State private var activeSettingsEditor: SettingsEditor? = nil
    @State private var blockedUsers: [String] = (UserDefaults.standard.array(forKey: "spot_blocked_users") as? [String]) ?? []
    @State private var blockedUserSearchText = ""
    @State private var remainingBoosts: Int = UserDefaults.standard.integer(forKey: "spot_remaining_boosts")

    @State private var userSearchText = ""
    @State private var firestoreUserSearchResults: [FirebaseUserAccountRecord] = []
    @State private var firestorePOISearchResults: [FirebasePOIRecord] = []
    @State private var poiSearchRequestRevision: Int = 0
    @State private var locationAlertSearchText = ""
    @State private var notifySavedLocationPosts = true
    @State private var notifySavedLocationPhotos = true
    @State private var notifySavedLocationVideos = true
    @State private var notifySavedLocationAudio = false
    @State private var recipientSearchText = ""
    @State private var selectedSendRecipient: String? = nil
    @State private var selectedProfilePost: MockPost? = nil
    @State private var lastSentMessage: String? = nil
    @State private var showSavedPostsOnly = false
    @State private var reportedPostIds: Set<Int> = []
    @State private var reportedUsers: Set<String> = []
    @State private var feedWindowSize = 8
    @State private var feedLoadedCount = 3
    @State private var feedRankedPostIDs: [Int] = []
    @State private var feedRankingSignature = ""
    @State private var lazyVideoWindowSize = 8
    @State private var lazyVideoLoadedCount = 4
    @State private var videoFeedRankedPostIDs: [Int] = []
    @State private var videoFeedRankingSignature = ""
    @State private var viewedPostIDs: Set<Int> = Self.loadViewedPostIDs()
    @State private var activeVideoID: Int? = nil
    @State private var videoEditorClips: [VideoEditorClip] = [
        .init(id: 1, name: "Opening", durationSeconds: 12, color: Color("spotBlue"), source: "Camera roll"),
        .init(id: 2, name: "Street motion", durationSeconds: 14, color: Color("spotBeige"), source: "Camera roll"),
        .init(id: 3, name: "Night detail", durationSeconds: 9, color: Color.purple.opacity(0.9), source: "Captured"),
        .init(id: 4, name: "End shot", durationSeconds: 11, color: Color.orange.opacity(0.9), source: "Library")
    ]
    @State private var videoEditorAudioTracks: [VideoEditorAudioTrack] = [
        .init(id: 1, name: "Original audio", volume: 0.75, isMusic: false),
        .init(id: 2, name: "Night drive beat", volume: 0.55, isMusic: true),
        .init(id: 3, name: "Atmosphere mix", volume: 0.35, isMusic: true)
    ]
    @State private var videoEditorTitleOverlay = "Untitled edit"
    @State private var videoEditorSelectedTransition = "Crossfade"
    @State private var videoEditorCurrentTool = "Split"
    @State private var isVideoEditorPro = false
    @State private var selectedVideoUpgradePlan: VideoUpgradePlan = .monthly

    @State private var posts: [MockPost] = []
    @State private var realtimeFeedListener: ListenerRegistration? = nil
    @State private var currentUserID: String = FirebaseSpotService.makeStableDeviceUserID()
    @State private var currentUserFollowerCount: Int = 0
    @State private var currentUserFollowingCount: Int = 0
    @State private var currentUserProfileListener: ListenerRegistration? = nil
    @State private var currentUserProfileListenerTargetID: String = ""

    @State private var communityUsers: [UserProfile] = []

    @State private var selectedUserProfile: FakeUserProfile? = nil
    @State private var selectedUserProfileListener: ListenerRegistration? = nil
    @State private var selectedUserProfileListenerTargetID: String = ""
    @State private var prefetchedProfilesByUserID: [String: FakeUserProfile] = [:]
    @State private var prefetchedProfilesByUsername: [String: FakeUserProfile] = [:]
    @State private var inFlightProfilePrefetchKeys: Set<String> = []
    @State private var inFlightAvatarPrefetchURLs: Set<String> = []
    @State private var selectedChatThread: DirectMessageThread? = nil
    @State private var pendingSharePost: MockPost? = nil
    @State private var chatComposerText = ""
    @State private var chatMessages: [Int: [ChatMessage]] = [
        1: [
            .init(id: 1, text: "I’m heading to that rooftop tonight — want to meet there?", isMine: false, time: "9:41 AM"),
            .init(id: 2, text: "Absolutely. I’ll bring the camera.", isMine: true, time: "9:42 AM"),
            .init(id: 3, text: "Perfect — I’ll save us a spot near the edge.", isMine: false, time: "9:43 AM")
        ],
        2: [
            .init(id: 1, text: "The photo from your last stop was incredible.", isMine: false, time: "Yesterday"),
            .init(id: 2, text: "Thanks! I was chasing the light just before sunset.", isMine: true, time: "Yesterday")
        ],
        3: [
            .init(id: 1, text: "I saved your café rec for next time I’m in Rome.", isMine: false, time: "1h ago"),
            .init(id: 2, text: "Amazing — it’s one of those tiny spots that feels like a secret.", isMine: true, time: "1h ago")
        ],
        4: [
            .init(id: 1, text: "Send me the location for the market you found.", isMine: true, time: "4h ago"),
            .init(id: 2, text: "It’s just past the old square, near the lantern stalls.", isMine: false, time: "4h ago")
        ],
        5: [
            .init(id: 1, text: "Let’s compare notes from the skyline view later.", isMine: true, time: "Yesterday"),
            .init(id: 2, text: "Definitely. I want to hear what you noticed from the left side.", isMine: false, time: "Yesterday")
        ],
        6: [
            .init(id: 1, text: "Your sound post from the waterfront was so good.", isMine: true, time: "Yesterday"),
            .init(id: 2, text: "Thank you — it felt like the whole street was in the audio.", isMine: false, time: "Yesterday")
        ]
    ]
    @State private var fakeUserProfiles: [FakeUserProfile] = []

    @State private var messages: [DirectMessageThread] = []

    @StateObject private var locationService = LocationService()
    @State private var locationSearchText = ""
    @State private var feedContentSearchText = ""
    @State private var isFeedSearchExpanded = false
    @State private var feedScrollOffset: CGFloat = 0
    @FocusState private var isFeedSearchFieldFocused: Bool
    @State private var isMainSearchFeedActive = false
    @State private var isVideoSearchFeedActive = false
    @State private var showFollowingOnly = false
    @State private var showFollowingVideoOnly = false
    @State private var isSubmittingPost = false
    @State private var hasRequestedLocationPermission = false
    @State private var nearbyPlaces: [NearbyPlace] = []
    @State private var isLoadingNearbyPlaces = false
    @State private var isBulkDeletingPosts = false
    @State private var platformBulkDeleteError = ""
    @State private var messagesTab: MessagesTab = .incoming
    @State private var savedLocations: [String] = []
    @State private var recentLocations: [String] = []
    let recommendedLocations: [String] = []
    let randomLocations: [String] = []

    enum Screen {
        case home
        case contentTypePicker
        case composer
        case photoEditor
        case videoEditor
        case videoUpgrade
        case videoCheckout
        case settings
        case savedPosts
        case anonymousPosts
        case profile
        case messages
        case chatDetail
        case locationPicker
        case postLocationPicker
        case locationFeed
        case userProfile
        case postDetail
    }

    enum MessagesTab {
        case incoming
        case sent
    }

    enum LocationContext {
        case feed
        case video
        case post
    }

    @State private var userProfileReturnScreen: Screen? = nil
    @State private var userProfileReturnSettingsEditor: SettingsEditor? = nil

    private struct FeedScrollOffsetKey: PreferenceKey {
        static var defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    enum SettingsEditor: String, Identifiable {
        case username
        case searchUsers
        case name
        case photo
        case accountInfo
        case locationAlerts
        case blockUsers
        case boostNextPosts
        case bulkDeletePosts

        var id: String { rawValue }
    }

    struct AppColorTheme: Identifiable {
        let id: String
        let name: String
        let primary: Color
        let secondary: Color
        let accent: Color
    }

    fileprivate static let appColorThemes: [AppColorTheme] = [
        AppColorTheme(id: "dark", name: "Dark", primary: Color(red: 0.09, green: 0.10, blue: 0.15), secondary: Color(red: 0.22, green: 0.24, blue: 0.35), accent: Color(red: 0.88, green: 0.90, blue: 0.96)),
        AppColorTheme(id: "original", name: "Original", primary: Color(red: 0.12, green: 0.43, blue: 0.87), secondary: Color(red: 0.54, green: 0.31, blue: 0.85), accent: Color(red: 0.96, green: 0.93, blue: 0.88)),
        AppColorTheme(id: "forest", name: "Forest", primary: Color(red: 0.20, green: 0.58, blue: 0.47), secondary: Color(red: 0.13, green: 0.78, blue: 0.65), accent: Color(red: 0.85, green: 0.97, blue: 0.85)),
        AppColorTheme(id: "midnight", name: "Midnight", primary: Color(red: 0.10, green: 0.12, blue: 0.26), secondary: Color(red: 0.41, green: 0.57, blue: 0.98), accent: Color(red: 0.77, green: 0.82, blue: 1.0)),
        AppColorTheme(id: "rose", name: "Rose", primary: Color(red: 0.90, green: 0.33, blue: 0.62), secondary: Color(red: 0.70, green: 0.35, blue: 0.87), accent: Color(red: 1.0, green: 0.85, blue: 0.92)),
        AppColorTheme(id: "ocean", name: "Ocean", primary: Color(red: 0.07, green: 0.52, blue: 0.76), secondary: Color(red: 0.13, green: 0.80, blue: 0.88), accent: Color(red: 0.82, green: 0.95, blue: 0.99)),
        AppColorTheme(id: "lavender", name: "Lavender", primary: Color(red: 0.53, green: 0.39, blue: 0.96), secondary: Color(red: 0.72, green: 0.58, blue: 0.99), accent: Color(red: 0.93, green: 0.90, blue: 1.0)),
        AppColorTheme(id: "citrus", name: "Citrus", primary: Color(red: 0.78, green: 0.72, blue: 0.15), secondary: Color(red: 0.92, green: 0.84, blue: 0.28), accent: Color(red: 1.0, green: 0.97, blue: 0.80)),
        AppColorTheme(id: "ember", name: "Ember", primary: Color(red: 0.89, green: 0.39, blue: 0.19), secondary: Color(red: 0.98, green: 0.62, blue: 0.26), accent: Color(red: 1.0, green: 0.91, blue: 0.74)),
        AppColorTheme(id: "slate", name: "Slate", primary: Color(red: 0.27, green: 0.42, blue: 0.57), secondary: Color(red: 0.44, green: 0.63, blue: 0.75), accent: Color(red: 0.89, green: 0.94, blue: 0.98))
    ]

    private static var citrusTheme: AppColorTheme {
        Self.appColorThemes.first { $0.id == "citrus" } ?? Self.appColorThemes[0]
    }
    
    fileprivate static var persistedThemeID: String {
        "white"
    }
    
    fileprivate static var appPrimaryThemeColor: Color {
        Color(red: 0.90, green: 0.90, blue: 0.90)
    }
    
    fileprivate static var appSecondaryThemeColor: Color {
        Color(red: 0.80, green: 0.80, blue: 0.80)
    }
    
    fileprivate static var appAccentThemeColor: Color {
        Color(red: 0.95, green: 0.95, blue: 0.95)
    }
    
    private func selectedThemeGradient() -> LinearGradient {
        LinearGradient(colors: [Color.white, Color.white], startPoint: .leading, endPoint: .trailing)
    }
    
    private func selectedThemeAccentGradient() -> LinearGradient {
        LinearGradient(colors: [Color.white, Color.white], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    struct VideoEditorClip: Identifiable {
        let id: Int
        var name: String
        var durationSeconds: Int
        let color: Color
        let source: String

        var duration: String {
            Self.formatDuration(durationSeconds)
        }

        static func formatDuration(_ seconds: Int) -> String {
            let total = max(0, seconds)
            let minutes = total / 60
            let secondsPart = total % 60
            return String(format: "%02d:%02d", minutes, secondsPart)
        }
    }

    struct VideoEditorAudioTrack: Identifiable {
        let id: Int
        let name: String
        var volume: Double
        let isMusic: Bool
    }

    struct VideoUpgradePlan: Identifiable {
        let id: String
        let name: String
        let price: String
        let subtitle: String
        let badge: String?
        let spotlight: Bool

        static let monthly = VideoUpgradePlan(
            id: "monthly",
            name: "Creator Pro",
            price: "$9.99/mo",
            subtitle: "Perfect for short-form edits",
            badge: "Most popular",
            spotlight: true
        )

        static let annual = VideoUpgradePlan(
            id: "annual",
            name: "Annual Creator",
            price: "$79.99/yr",
            subtitle: "Save 33% with a yearly plan",
            badge: "Best value",
            spotlight: false
        )

        static let all = [monthly, annual]
    }

    let locationSuggestions: [String] = []

    let postTypes = ["Text", "Photo", "Video", "Poll", "Audio", "Link", "Song", "Guide", "For Sale"]

    private static func seedPosts() -> [MockPost] {
        // Real posts will populate from the app's own data source.
        // The mock seed is intentionally empty so we can rebuild the feed from real user-generated content.
        []
    }

    init() {
        let defaultLocation = "Metric"
        let persistedFeed = UserDefaults.standard.string(forKey: "spot_feed_location") ?? defaultLocation
        let persistedVideo = UserDefaults.standard.string(forKey: "spot_video_location") ?? defaultLocation
        let persistedPost = UserDefaults.standard.string(forKey: "spot_post_location") ?? "Metric"
        let persistedSavedLocations = UserDefaults.standard.array(forKey: "spot_saved_locations") as? [String] ?? []
        let persistedRecentLocations = UserDefaults.standard.array(forKey: "spot_recent_locations") as? [String] ?? []
        let persistedProfilePhoto = Self.cachedImage(forKey: "spot_profile_photo_data")
        let persistedPhoneNumber = UserDefaults.standard.string(forKey: "spot_phone_number") ?? ""
        let persistedSavedAccounts = Self.loadSavedAccountsFromDefaults()
        let persistedSelectedEmail = (UserDefaults.standard.string(forKey: "spot_account_email") ?? "").lowercased()

        _fromLocation = State(initialValue: persistedFeed)
        _videoLocation = State(initialValue: persistedVideo)
        _postLocation = State(initialValue: persistedPost)
        _savedLocations = State(initialValue: persistedSavedLocations)
        _recentLocations = State(initialValue: persistedRecentLocations)
        _profilePhotoImage = State(initialValue: persistedProfilePhoto)
        _phoneNumber = State(initialValue: persistedPhoneNumber)
        _savedAccounts = State(initialValue: persistedSavedAccounts)
        _selectedSavedAccountEmail = State(initialValue: persistedSelectedEmail)
    }

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()
                .task {
                    await loadCurrentUserProfileFromRecord()
                    await loadCurrentUserPosts()
                    await refreshFollowingUIDs()
                    await MainActor.run {
                        prefetchBlockedUserProfiles()
                        startRealtimeFeedListener()
                        configureAudioSessionForAppUse()
                    }

                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        guard !Task.isCancelled else { return }

                        let shouldRefreshAuthorPhotos = await MainActor.run {
                            switch currentScreen {
                            case .home, .locationFeed, .profile, .userProfile, .postDetail:
                                return !posts.isEmpty
                            default:
                                return false
                            }
                        }

                        guard shouldRefreshAuthorPhotos else { continue }
                        await refreshActivePostAuthorPhotos()
                    }
                }
                .onDisappear {
                    stopCurrentUserProfileLiveListener()
                    stopRealtimeFeedListener()
                }
                .onChange(of: blockedUsers) { _, _ in
                    prefetchBlockedUserProfiles()
                }
                .onChange(of: firestoreUserSearchResults.map(\.uid)) { _, _ in
                    cacheAndPrefetchSearchResultProfiles()
                }

            Group {
                switch currentScreen {
                case .home:
                    GeometryReader { container in
                        let feedBodyMinHeight = max(320, container.size.height - 300)

                        ZStack(alignment: .bottom) {
                            Color(red: 0.93, green: 0.93, blue: 0.93)
                                .ignoresSafeArea()

                            ScrollView {
                                VStack(alignment: .leading, spacing: 0) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        feedModeToggle
                                            .padding(.horizontal, 18)
                                    }
                                    .padding(.top, 8)
                                    .padding(.bottom, 14)
                                    .background(Color(red: 0.93, green: 0.93, blue: 0.93))
                                    .overlay(alignment: .bottom) {
                                        Rectangle()
                                            .fill(Color.black.opacity(0.09))
                                            .frame(height: 0.6)
                                            .padding(.horizontal, 8)
                                    }

                                    VStack(alignment: .leading, spacing: 0) {
                                        feedSection
                                            .padding(.top, 14)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .frame(minHeight: feedBodyMinHeight, alignment: .top)
                                    .background(Color.white)

                                    Rectangle()
                                        .fill(Color(red: 0.93, green: 0.93, blue: 0.93))
                                        .frame(height: Self.bottomSilverEndCapHeight)
                                }
                                .padding(.bottom, 110)
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear
                                            .preference(
                                                key: FeedScrollOffsetKey.self,
                                                value: max(0, -proxy.frame(in: .named("feedScrollSpace")).minY)
                                            )
                                    }
                                )
                            }
                            .coordinateSpace(name: "feedScrollSpace")
                            .onPreferenceChange(FeedScrollOffsetKey.self) { value in
                                feedScrollOffset = min(max(value, 0), 24)
                            }

                            floatingHomeActions
                                .padding(.bottom, 12)
                                .padding(.horizontal, 18)
                        }
                    }
                case .contentTypePicker:
                    createTypePickerView
                case .composer:
                    createComposerView
                case .photoEditor:
                    photoEditorView
                case .videoEditor:
                    videoEditorView
                case .videoUpgrade:
                    videoUpgradeView
                case .videoCheckout:
                    videoCheckoutView
                case .settings:
                    settingsView
                case .savedPosts:
                    savedPostsView
                case .anonymousPosts:
                    anonymousPostsView
                case .profile:
                    profileView
                case .messages:
                    messagesView
                case .chatDetail:
                    chatDetailView
                case .locationPicker:
                    locationPickerView
                case .postLocationPicker:
                    postLocationPickerView
                case .locationFeed:
                    locationFeedView
                case .userProfile:
                    userProfileDetailView
                case .postDetail:
                    selectedPostDetailView
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.18), value: currentScreen)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }

    private var backgroundGradient: some View {
        Color.white
    }

    private var feedModeToggle: some View {
        let isVideoFeed = currentScreen == .locationFeed
        let isSearchFeedActive = isVideoFeed ? isVideoSearchFeedActive : isMainSearchFeedActive
        let activeFollowFilter = isVideoFeed ? showFollowingVideoOnly : showFollowingOnly
        let isMetricActive = !activeFollowFilter
        let activeLocation = isVideoFeed ? (videoLocation.isEmpty ? "Metric" : videoLocation) : (fromLocation.isEmpty ? "Metric" : fromLocation)

        return GeometryReader { geometry in
            let rawWidth = max(geometry.size.width, 1)
            // Keep pill sizing consistent when this toggle is hosted in different parent layouts.
            let totalWidth = min(rawWidth, 420)
            let expandedSearchWidth = min(120, max(88, totalWidth * 0.34))
            let searchWidth = isFeedSearchExpanded ? expandedSearchWidth : 44
            let remainingWidth = max(totalWidth - searchWidth - 24, 120)
            let followingWidth = min(82, max(72, remainingWidth * 0.38))
            let baseMetricWidth = max(72, remainingWidth - followingWidth - 8)
            let totalButtonWidth = baseMetricWidth + followingWidth + searchWidth + 16
            let overflow = max(0, totalButtonWidth - totalWidth)
            let metricWidth = max(72, baseMetricWidth - overflow / 2)
            let selectionDrift = min(max(feedScrollOffset * 0.22, 0), 12)
            let hasSearchSelection = isSearchFeedActive || isFeedSearchExpanded || isFeedSearchFieldFocused
            let metricSelectionWidth = max(26, metricWidth - 18)
            let followingSelectionWidth = max(26, followingWidth - 18)
            let searchSelectionWidth = max(24, searchWidth - 18)
            let metricSelectionOffset = (metricWidth - metricSelectionWidth) / 2
            let followingSelectionOffset = metricWidth + 8 + (followingWidth - followingSelectionWidth) / 2
            let searchStartX = metricWidth + 8 + followingWidth + 8
            let searchSelectionOffset = searchStartX + (searchWidth - searchSelectionWidth) / 2

            ZStack(alignment: .bottomLeading) {
                HStack(spacing: 8) {
                    Button {
                        if isVideoFeed {
                            if showFollowingVideoOnly {
                                showFollowingVideoOnly = false
                                currentScreen = .locationFeed
                            } else {
                                locationContext = .video
                                currentScreen = .locationPicker
                            }
                            isVideoSearchFeedActive = false
                            isFeedSearchExpanded = false
                            isFeedSearchFieldFocused = false
                            return
                        }
                        if currentScreen != .home {
                            showFollowingOnly = false
                            currentScreen = .home
                        } else if showFollowingOnly {
                            showFollowingOnly = false
                        } else {
                            locationContext = .feed
                            currentScreen = .locationPicker
                        }
                        isMainSearchFeedActive = false
                        isFeedSearchExpanded = false
                        isFeedSearchFieldFocused = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                            Text(activeLocation)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .truncationMode(.tail)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(width: metricWidth, height: 44)
                        .foregroundStyle(.primary)
                        .background {
                            if hasSearchSelection {
                                Color.white
                            } else if activeFollowFilter {
                                Color(.secondarySystemBackground)
                            } else {
                                LinearGradient(
                                    colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        if isVideoFeed {
                            showFollowingVideoOnly = true
                            isVideoSearchFeedActive = false
                            isFeedSearchExpanded = false
                            isFeedSearchFieldFocused = false
                            return
                        }
                        showFollowingOnly = true
                        if currentScreen == .locationFeed {
                            currentScreen = .home
                        }
                        isMainSearchFeedActive = false
                        isFeedSearchExpanded = false
                        isFeedSearchFieldFocused = false
                    } label: {
                        Image(systemName: "person.2.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: followingWidth, height: 44)
                            .foregroundStyle(activeFollowFilter ? .primary : Color.secondary)
                            .background {
                            if hasSearchSelection {
                                Color.white
                            } else if activeFollowFilter {
                                LinearGradient(
                                    colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            } else {
                                Color(.secondarySystemBackground)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Group {
                        if isFeedSearchExpanded {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)

                                TextField("Search content", text: $feedContentSearchText)
                                    .font(.subheadline)
                                    .focused($isFeedSearchFieldFocused)
                                    .submitLabel(.search)

                                Button {
                                    if feedContentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        if isVideoFeed {
                                            isVideoSearchFeedActive = false
                                        } else {
                                            isMainSearchFeedActive = false
                                        }
                                        isFeedSearchExpanded = false
                                        isFeedSearchFieldFocused = false
                                    } else {
                                        feedContentSearchText = ""
                                    }
                                } label: {
                                    Image(systemName: feedContentSearchText.isEmpty ? "xmark.circle" : "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .frame(width: searchWidth, height: 44)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else {
                            Button {
                                if isVideoFeed {
                                    isVideoSearchFeedActive = true
                                } else {
                                    isMainSearchFeedActive = true
                                }
                                isFeedSearchExpanded = true
                                DispatchQueue.main.async {
                                    isFeedSearchFieldFocused = true
                                }
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 44, height: 44)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: isFeedSearchExpanded)
                }
                .frame(width: totalWidth, alignment: .leading)
                .clipped()
            }
        }
        .frame(height: 56)
        .padding(6)
    }

    private var normalizedFeedSearchTokens: [String] {
        feedContentSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { character in
                !character.isLetter && !character.isNumber && character != "/"
            })
            .map(String.init)
    }

    private func canonicalTypeToken(for token: String) -> String? {
        let aliasesByType: [String: Set<String>] = [
            "text": ["text", "texts", "post", "posts", "story", "stories", "words", "writing"],
            "photo": ["photo", "photos", "image", "images", "pic", "pics", "picture", "pictures"],
            "video": ["video", "videos", "clip", "clips", "reel", "reels", "movie", "movies"],
            "link": ["link", "links", "url", "urls", "article", "articles", "website", "web"],
            "audio": ["audio", "audios", "voice", "voices", "sound", "sounds", "music", "podcast"],
            "song": ["song", "songs", "track", "tracks", "musicfile", "single"],
            "poll": ["poll", "polls", "vote", "votes", "voting", "question", "questions"],
            "live route": ["route", "trip", "journey", "travel", "itinerary", "path"],
            "guide": ["guide", "steps", "recipe", "tutorial", "howto", "walkthrough"],
            "work": ["work", "job", "jobs", "hiring", "career", "resume"],
            "for sale": ["sale", "sell", "selling", "forsale", "listing", "marketplace", "item", "items"]
        ]

        for (type, aliases) in aliasesByType {
            if aliases.contains(token) {
                return type
            }
        }

        return nil
    }

    private var requestedSearchContentTypes: Set<String> {
        Set(normalizedFeedSearchTokens.compactMap { canonicalTypeToken(for: $0) })
    }

    private var searchableFeedTextTokens: [String] {
        normalizedFeedSearchTokens.filter { canonicalTypeToken(for: $0) == nil }
    }

    private func canonicalPostContentTypes(_ postType: String) -> Set<String> {
        let normalized = postType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case "photo/video":
            return ["photo", "video"]
        case "text", "photo", "video", "link", "audio", "song", "poll":
            return [normalized]
        case "live route":
            return ["live route"]
        case "guide":
            return ["guide"]
        case "work":
            return ["work"]
        case "for sale":
            return ["for sale"]
        default:
            if normalized.contains("video") {
                return ["video"]
            }
            if normalized.contains("photo") || normalized.contains("image") {
                return ["photo"]
            }
            if normalized.contains("audio") || normalized.contains("sound") {
                return ["audio"]
            }
            if normalized.contains("song") || normalized.contains("track") {
                return ["song"]
            }
            if normalized.contains("link") || normalized.contains("url") {
                return ["link"]
            }
            if normalized.contains("poll") {
                return ["poll"]
            }
            if normalized.contains("route") || normalized.contains("trip") {
                return ["live route"]
            }
            if normalized.contains("guide") || normalized.contains("recipe") || normalized.contains("tutorial") {
                return ["guide"]
            }
            if normalized.contains("work") || normalized.contains("job") || normalized.contains("hiring") {
                return ["work"]
            }
            if normalized.contains("sale") || normalized.contains("selling") || normalized.contains("marketplace") {
                return ["for sale"]
            }
            return ["text"]
        }
    }

    private func postMatchesFeedSearch(_ post: MockPost) -> Bool {
        let rawTokens = normalizedFeedSearchTokens
        guard !rawTokens.isEmpty else { return true }

        let requiredTypes = requestedSearchContentTypes
        if !requiredTypes.isEmpty {
            let postTypes = canonicalPostContentTypes(post.type)
            if postTypes.isDisjoint(with: requiredTypes) {
                return false
            }
        }

        let textTokens = searchableFeedTextTokens
        guard !textTokens.isEmpty else { return true }

        let searchableText = [
            post.type,
            post.title,
            post.body,
            post.author,
            post.handle,
            post.location,
            post.tag,
            post.url,
            post.pollOptions.joined(separator: " "),
            post.comments.joined(separator: " "),
            post.postedInLocations.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()

        return textTokens.allSatisfy { token in
            searchableText.contains(token)
        }
    }

    private var floatingHomeActions: some View {
        let isProfileSelected = currentScreen == .profile
        let isMessagesSelected = currentScreen == .messages
        let isCreateSelected = currentScreen == .contentTypePicker
        let isHomeSelected = currentScreen == .home
        let isVideoSelected = currentScreen == .locationFeed

        return HStack(spacing: 12) {
            Button {
                currentScreen = .profile
            } label: {
                Image(systemName: "person.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: isProfileSelected ? 60 : 52, height: isProfileSelected ? 60 : 52)
                    .background(
                        LinearGradient(
                            colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black, lineWidth: isProfileSelected ? 1.5 : 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                currentScreen = .contentTypePicker
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: isCreateSelected ? 60 : 52, height: isCreateSelected ? 60 : 52)
                    .background(
                        LinearGradient(
                            colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black, lineWidth: isCreateSelected ? 1.5 : 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                if currentScreen != .home {
                    showFollowingOnly = false
                    isMainSearchFeedActive = false
                    isFeedSearchExpanded = false
                    isFeedSearchFieldFocused = false
                    currentScreen = .home
                    return
                }
                cycleMainFeedMode()
            } label: {
                Image(systemName: showFollowingOnly ? "person.2.fill" : "globe")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: isHomeSelected ? 60 : 52, height: isHomeSelected ? 60 : 52)
                    .background(
                        LinearGradient(
                            colors: showFollowingOnly ? [ContentView.appSecondaryThemeColor, ContentView.appPrimaryThemeColor] : [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black, lineWidth: isHomeSelected ? 1.5 : 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                if currentScreen != .locationFeed {
                    showFollowingVideoOnly = false
                    isVideoSearchFeedActive = false
                    isFeedSearchExpanded = false
                    isFeedSearchFieldFocused = false
                    currentScreen = .locationFeed
                    return
                }
                cycleVideoFeedMode()
            } label: {
                Image(systemName: "play.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: isVideoSelected ? 60 : 52, height: isVideoSelected ? 60 : 52)
                    .background(
                        LinearGradient(
                            colors: [ContentView.appSecondaryThemeColor, ContentView.appPrimaryThemeColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black, lineWidth: isVideoSelected ? 1.5 : 1)
                    )
            }
            .buttonStyle(.plain)

        }
        .padding(10)
        .background(
            Color(.systemBackground).opacity(0.9)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 8)
    }

    private func cycleMainFeedMode() {
        if isMainSearchFeedActive || isFeedSearchExpanded || isFeedSearchFieldFocused {
            // Search -> Metric
            isMainSearchFeedActive = false
            showFollowingOnly = false
            isFeedSearchExpanded = false
            isFeedSearchFieldFocused = false
            return
        }

        if showFollowingOnly {
            // Following -> Search
            showFollowingOnly = false
            isMainSearchFeedActive = true
            isFeedSearchExpanded = true
            DispatchQueue.main.async {
                isFeedSearchFieldFocused = true
            }
            return
        }

        // Metric -> Following
        showFollowingOnly = true
        isMainSearchFeedActive = false
        isFeedSearchExpanded = false
        isFeedSearchFieldFocused = false
    }

    private func cycleVideoFeedMode() {
        if isVideoSearchFeedActive || isFeedSearchExpanded || isFeedSearchFieldFocused {
            // Search -> Metric
            isVideoSearchFeedActive = false
            showFollowingVideoOnly = false
            isFeedSearchExpanded = false
            isFeedSearchFieldFocused = false
            return
        }

        if showFollowingVideoOnly {
            // Following -> Search
            showFollowingVideoOnly = false
            isVideoSearchFeedActive = true
            isFeedSearchExpanded = true
            DispatchQueue.main.async {
                isFeedSearchFieldFocused = true
            }
            return
        }

        // Metric -> Following
        showFollowingVideoOnly = true
        isVideoSearchFeedActive = false
        isFeedSearchExpanded = false
        isFeedSearchFieldFocused = false
    }

    private var expandedLocationHomeActions: some View {
        floatingHomeActions
            .scaleEffect(1.08)
    }

    private var feedSection: some View {
        let activeLocation = fromLocation.isEmpty ? "Tokyo, Japan" : fromLocation
        let isSearchFeedActive = isMainSearchFeedActive
        let includeVideoResults = requestedSearchContentTypes.contains("video")
        let isFriendsFeed = isFriendsRealm(activeLocation)
        let scopedPosts = (isFriendsFeed
            ? posts
            : Self.postsForLocationRealm(posts, activeLocation: activeLocation))
        let globalPinnedKeys = Set(
            adminPinnedRealmMap()
                .filter { $0.value == Self.adminPinAllNonMetricMarker }
                .map { $0.key }
        )
        let includeGlobalPinnedForLocation = !isFriendsFeed && Self.normalizedLocationRealm(activeLocation) != Self.normalizedLocationRealm("Metric")
        let globalPinnedPostsForLocation = includeGlobalPinnedForLocation
            ? posts.filter { globalPinnedKeys.contains(postAdminPinStorageKey($0)) }
            : []
        var seenRelevantPostIDs: Set<Int> = []
        let relevantPosts = (scopedPosts + globalPinnedPostsForLocation).filter { post in
            if seenRelevantPostIDs.contains(post.id) {
                return false
            }
            seenRelevantPostIDs.insert(post.id)
            return true
        }
            .filter { includeVideoResults || $0.type != "Video" }
            .filter { !reportedPostIds.contains($0.id) }
            .filter { postMatchesFeedSearch($0) }
        let visiblePosts = (isFriendsFeed
            ? relevantPosts.filter { post in
                isUserMutualFollowed(authorUserID: post.authorUserID, username: post.handle)
                    || Self.isPostOwnedByUser(post, currentUserID: currentUserID, currentUsername: profileUsername)
            }
            : (showFollowingOnly ? relevantPosts.filter { post in
                isUserFollowed(authorUserID: post.authorUserID, username: post.handle)
                    || Self.isPostOwnedByUser(post, currentUserID: currentUserID, currentUsername: profileUsername)
            } : relevantPosts))

        let feedCandidates = isSearchFeedActive ? [] : visiblePosts
        let rankedPosts = prioritizeAdminPinnedPosts(
            orderedPosts(feedCandidates, using: feedRankedPostIDs),
            activeLocation: activeLocation
        )
        let fallbackRankedPosts = rankedPosts.isEmpty
            ? prioritizeAdminPinnedPosts(
                rankedPostsForFeed(feedCandidates, activeLocation: activeLocation, isFriendsFeed: isFriendsFeed),
                activeLocation: activeLocation
            )
            : rankedPosts
        let loadedPosts = Array(fallbackRankedPosts.prefix(feedLoadedCount))

        return VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(loadedPosts.enumerated()), id: \.element.id) { index, post in
                PostCardView(
                    post: Binding(
                        get: {
                            // Get the latest version from the posts array
                            posts.first(where: { $0.id == post.id }) ?? post
                        },
                        set: { updatedPost in
                            // Update the post in the posts array
                            if let index = posts.firstIndex(where: { $0.id == post.id }) {
                                posts[index] = updatedPost
                            }
                            }
                        ),
                        isOwnPost: Self.isPostOwnedByUser(post, currentUserID: currentUserID, currentUsername: profileUsername),
                        currentUserProfilePhotoImage: displayProfilePhotoImage,
                        isReported: reportedPostIds.contains(post.id),
                        onSend: {
                            sharePostToFriends(post)
                        },
                        onSave: { savedPost in
                            toggleSavedState(for: savedPost)
                        },
                        onDelete: {
                            deletePost(post)
                        },
                        onReport: {
                            reportPost(post)
                        },
                        onProfileTap: {
                            openUserProfile(from: post)
                        },
                        onMessageTap: {
                            let matchingUser = fakeUserProfiles.first(where: { $0.username.lowercased() == post.handle.lowercased() })
                                ?? fallbackProfile(for: post.handle, displayName: post.author, userID: post.authorUserID, profilePhotoURL: post.authorProfilePhotoURL)
                            openDM(with: matchingUser)
                        },
                        onViewTracked: { updatedPost in
                            applyTrackedPostViewUpdate(updatedPost)
                        }
                    )
                    .padding(.horizontal, 0)
                    .onAppear {
                        if index >= max(0, loadedPosts.count - 2), feedLoadedCount < fallbackRankedPosts.count {
                            feedLoadedCount = min(feedLoadedCount + feedWindowSize, fallbackRankedPosts.count)
                        }
                    }
                }
        }
        .onAppear {
            rebuildMainFeedRanking(
                candidates: visiblePosts,
                activeLocation: activeLocation,
                followingOnly: showFollowingOnly,
                isFriendsFeed: isFriendsFeed,
                includeVideoResults: includeVideoResults,
                force: true
            )
        }
        .onChange(of: fromLocation) { _, _ in
            rebuildMainFeedRanking(
                candidates: visiblePosts,
                activeLocation: activeLocation,
                followingOnly: showFollowingOnly,
                isFriendsFeed: isFriendsFeed,
                includeVideoResults: includeVideoResults,
                force: true
            )
        }
        .onChange(of: showFollowingOnly) { _, _ in
            rebuildMainFeedRanking(
                candidates: visiblePosts,
                activeLocation: activeLocation,
                followingOnly: showFollowingOnly,
                isFriendsFeed: isFriendsFeed,
                includeVideoResults: includeVideoResults,
                force: true
            )
        }
        .onChange(of: feedContentSearchText) { _, _ in
            rebuildMainFeedRanking(
                candidates: visiblePosts,
                activeLocation: activeLocation,
                followingOnly: showFollowingOnly,
                isFriendsFeed: isFriendsFeed,
                includeVideoResults: includeVideoResults,
                force: true
            )
        }
        .onChange(of: posts.map(\.id)) { _, _ in
            rebuildMainFeedRanking(
                candidates: visiblePosts,
                activeLocation: activeLocation,
                followingOnly: showFollowingOnly,
                isFriendsFeed: isFriendsFeed,
                includeVideoResults: includeVideoResults,
                force: true
            )
        }
    }


    private func backButton(destination: Screen, title: String = "Back") -> some View {
        Button {
            currentScreen = destination
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private struct AnimatedLocationTag: View {
        let text: String
        @State private var revealedCount = 0

        private var characters: [String] {
            Array(text).map(String.init)
        }

        var body: some View {
            HStack(spacing: 0) {
                ForEach(0..<characters.count, id: \.self) { index in
                    let isRevealed = index < revealedCount
                    Text(characters[index])
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .offset(y: isRevealed ? 0 : 6)
                        .opacity(isRevealed ? 1 : 0)
                        .scaleEffect(isRevealed ? 1 : 0.75)
                        .animation(.spring(response: 0.18, dampingFraction: 0.9).delay(Double(index) * 0.04), value: revealedCount)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .onAppear {
                revealedCount = 0
                Task {
                    for index in 0..<characters.count {
                        try? await Task.sleep(nanoseconds: UInt64(40_000_000 * (index + 1)))
                        await MainActor.run {
                            withAnimation {
                                revealedCount = index + 1
                            }
                        }
                    }
                }
            }
        }
    }

    private func capUsernameInput(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutAt = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        let normalized = FirebaseSpotService.normalizeUsername(withoutAt)
        return String(normalized.prefix(15))
    }

    private func displayUsername(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutAt = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        let capped = String(FirebaseSpotService.normalizeUsername(withoutAt).prefix(15))
        return capped.isEmpty ? "@you" : "@\(capped)"
    }

    private var accountEditorStatusMessage: String {
        let cleaned = accountAuthMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }

        let lowered = cleaned.lowercased()
        let authKeywords = [
            "account",
            "sign up",
            "sign in",
            "signed in",
            "signed out",
            "log in",
            "email",
            "password",
            "verification",
            "reset",
            "username",
            "inbox",
            "spam",
            "junk"
        ]

        return authKeywords.contains { lowered.contains($0) } ? cleaned : ""
    }

    private func cachedProfile(userID: String, username: String) -> FakeUserProfile? {
        let trimmedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedUserID.isEmpty, let cachedByID = prefetchedProfilesByUserID[trimmedUserID] {
            return cachedByID
        }

        let normalizedUsername = FirebaseSpotService.normalizeUsername(username)
        if !normalizedUsername.isEmpty, let cachedByUsername = prefetchedProfilesByUsername[normalizedUsername] {
            return cachedByUsername
        }

        return nil
    }

    @MainActor
    private func cachePrefetchedProfile(_ profile: FakeUserProfile) {
        let trimmedUserID = profile.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedUserID.isEmpty {
            prefetchedProfilesByUserID[trimmedUserID] = profile
        }

        let normalizedUsername = FirebaseSpotService.normalizeUsername(profile.username)
        if !normalizedUsername.isEmpty {
            prefetchedProfilesByUsername[normalizedUsername] = profile
        }
    }

    @MainActor
    private func prefetchRemoteAvatarIfNeeded(_ rawURL: String?) {
        let cleanedURL = (rawURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedURL.isEmpty else { return }
        guard let url = URL(string: cleanedURL) else { return }
        guard inFlightAvatarPrefetchURLs.insert(cleanedURL).inserted else { return }

        Task {
            defer {
                Task { @MainActor in
                    inFlightAvatarPrefetchURLs.remove(cleanedURL)
                }
            }

            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 15
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    private func prefetchProfileIfNeeded(userID: String, username: String, displayName: String = "User", profilePhotoURL: String? = nil) {
        let initialUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUsername = FirebaseSpotService.normalizeUsername(username)
        let prefetchKey = !initialUserID.isEmpty ? "id:\(initialUserID)" : "u:\(normalizedUsername)"

        guard !prefetchKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let cached = cachedProfile(userID: initialUserID, username: normalizedUsername) {
            Task { @MainActor in
                prefetchRemoteAvatarIfNeeded(cached.profilePhotoURL ?? profilePhotoURL)
                applyProfilePhotoURLToPosts(
                    authorUserID: cached.userID.isEmpty ? initialUserID : cached.userID,
                    username: cached.username,
                    photoURL: cached.profilePhotoURL ?? profilePhotoURL
                )
            }
            return
        }

        Task { @MainActor in
            if inFlightProfilePrefetchKeys.contains(prefetchKey) {
                return
            }
            inFlightProfilePrefetchKeys.insert(prefetchKey)
        }

        Task {
            defer {
                Task { @MainActor in
                    inFlightProfilePrefetchKeys.remove(prefetchKey)
                }
            }

            var resolvedUserID = initialUserID
            if resolvedUserID.isEmpty, !normalizedUsername.isEmpty {
                resolvedUserID = (try? await FirebaseSpotService.shared.resolveUserID(username: normalizedUsername)) ?? ""
            }
            guard !resolvedUserID.isEmpty else { return }

            do {
                let account = try await FirebaseSpotService.shared.fetchUserAccount(userID: resolvedUserID)
                let liveCounts = try? await FirebaseSpotService.shared.fetchUserFollowCounts(userID: resolvedUserID)
                let resolvedUsername = FirebaseSpotService.normalizeUsername(account.username).isEmpty
                    ? (normalizedUsername.isEmpty ? "user" : normalizedUsername)
                    : FirebaseSpotService.normalizeUsername(account.username)
                let resolvedDisplayName = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? displayName
                    : account.displayName
                let resolvedPhotoURL = account.profilePhotoURL ?? profilePhotoURL
                let prefetched = FakeUserProfile(
                    userID: account.uid,
                    username: resolvedUsername,
                    name: resolvedDisplayName,
                    city: "",
                    bio: account.bio ?? "",
                    followerCount: liveCounts?.followers ?? account.followerCount,
                    followingCount: liveCounts?.following ?? account.followingCount,
                    profilePhotoText: String(resolvedDisplayName.prefix(2)).uppercased(),
                    profilePhotoURL: resolvedPhotoURL
                )

                await MainActor.run {
                    cachePrefetchedProfile(prefetched)
                    prefetchRemoteAvatarIfNeeded(resolvedPhotoURL)

                    if let index = fakeUserProfiles.firstIndex(where: { profile in
                        let byID = !profile.userID.isEmpty && profile.userID == prefetched.userID
                        let byUsername = FirebaseSpotService.normalizeUsername(profile.username) == FirebaseSpotService.normalizeUsername(prefetched.username)
                        return byID || byUsername
                    }) {
                        fakeUserProfiles[index] = prefetched
                    } else {
                        fakeUserProfiles.append(prefetched)
                    }

                    applyProfilePhotoURLToPosts(
                        authorUserID: prefetched.userID,
                        username: prefetched.username,
                        photoURL: prefetched.profilePhotoURL
                    )
                }
            } catch {
                // Ignore prefetch misses; profile screen still performs full refresh.
            }
        }
    }

    private func fallbackProfile(for username: String, displayName: String = "User", userID: String = "", profilePhotoURL: String? = nil) -> FakeUserProfile {
        let normalizedUsername = FirebaseSpotService.normalizeUsername(username)
        let resolvedUsername = normalizedUsername.isEmpty ? "you" : normalizedUsername
        let resolvedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = resolvedDisplayName.isEmpty ? (resolvedUsername == "you" ? "You" : resolvedUsername.capitalized) : resolvedDisplayName
        let normalizedCurrentUsername = FirebaseSpotService.normalizeUsername(profileUsername)
        let isCurrentUserByUsername = !normalizedCurrentUsername.isEmpty && normalizedCurrentUsername == resolvedUsername
        let isCurrentUserByUserID = !userID.isEmpty && !currentUserID.isEmpty && userID == currentUserID
        let resolvedPhotoURL = profilePhotoURL ?? ((isCurrentUserByUsername || isCurrentUserByUserID) ? profilePhotoRemoteURL : nil)
        let resolvedUserID = userID.isEmpty && (isCurrentUserByUsername || isCurrentUserByUserID) ? currentUserID : userID

        if let cached = cachedProfile(userID: resolvedUserID, username: resolvedUsername) {
            return FakeUserProfile(
                id: cached.id,
                userID: cached.userID,
                username: cached.username,
                name: cached.name,
                city: cached.city,
                bio: cached.bio,
                followerCount: cached.followerCount,
                followingCount: cached.followingCount,
                profilePhotoText: cached.profilePhotoText,
                profilePhotoURL: resolvedPhotoURL ?? cached.profilePhotoURL
            )
        }

        return FakeUserProfile(
            userID: resolvedUserID,
            username: resolvedUsername,
            name: finalName,
            city: "",
            bio: "",
            followerCount: 0,
            followingCount: 0,
            profilePhotoText: String(finalName.prefix(2)).uppercased(),
            profilePhotoURL: resolvedPhotoURL
        )
    }

    private func isOwnProfile(_ profile: FakeUserProfile) -> Bool {
        let trimmedProfileUserID = profile.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCurrentUserID = currentUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedProfileUserID.isEmpty, !trimmedCurrentUserID.isEmpty {
            return trimmedProfileUserID == trimmedCurrentUserID
        }

        let normalizedCurrent = FirebaseSpotService.normalizeUsername(profileUsername)
        let normalizedProfile = FirebaseSpotService.normalizeUsername(profile.username)
        return !normalizedCurrent.isEmpty && normalizedCurrent == normalizedProfile
    }

    private func refreshFollowingUIDs() async {
        let userID = await ensureAuthenticatedUserRecord()
        guard !userID.isEmpty else {
            await MainActor.run {
                followedUserIDs = []
                followerUserIDs = []
            }
            return
        }

        do {
            let followedIDs = try await FirebaseSpotService.shared.fetchFollowedUserIDs(followerUserID: userID)
            let followerIDs = try await FirebaseSpotService.shared.fetchFollowerUserIDs(followedUserID: userID)
            await MainActor.run {
                followedUserIDs = Set(followedIDs)
                followerUserIDs = Set(followerIDs)
            }
        } catch {
            print("Spot follow graph refresh failed: \(error)")
        }
    }

    private func openUserProfile(from post: MockPost) {
        guard !post.isAnonymous else { return }

        // Opening your own post should go to the signed-in profile screen, which always
        // reflects the latest local profile photo and account state.
        let isOwnTappedProfile = Self.isPostOwnedByUser(
            post,
            currentUserID: currentUserID,
            currentUsername: profileUsername
        )
        if isOwnTappedProfile {
            selectedUserProfile = nil
            currentScreen = .profile
            return
        }

        let matchingUser = fakeUserProfiles.first(where: {
            let byUserID = !post.authorUserID.isEmpty && !$0.userID.isEmpty && $0.userID == post.authorUserID
            let byUsername = $0.username.lowercased() == post.handle.lowercased()
            return byUserID || byUsername
        })

        let resolvedProfile = cachedProfile(userID: post.authorUserID, username: post.handle)
            ?? matchingUser
            ?? fallbackProfile(
                for: post.handle,
                displayName: post.author,
                userID: post.authorUserID,
                profilePhotoURL: post.authorProfilePhotoURL
            )

        openUserProfileScreen(with: resolvedProfile)
    }

    private func openUserProfileScreen(with profile: FakeUserProfile) {
        let originScreen: Screen
        if currentScreen == .userProfile {
            originScreen = userProfileReturnScreen ?? .home
        } else {
            originScreen = currentScreen
        }

        let originSettingsEditor = originScreen == .settings ? activeSettingsEditor : nil

        userProfileReturnScreen = originScreen
        userProfileReturnSettingsEditor = originSettingsEditor
        if originScreen == .settings {
            activeSettingsEditor = nil
        }
        selectedUserProfile = profile
        currentScreen = .userProfile

        Task {
            prefetchProfileIfNeeded(
                userID: profile.userID,
                username: profile.username,
                displayName: profile.name,
                profilePhotoURL: profile.profilePhotoURL
            )
            await refreshSelectedUserProfileFromRecord(expectedUserID: profile.userID)
        }
    }

    private func closeUserProfileScreen() {
        let destination = userProfileReturnScreen ?? .home
        let destinationSettingsEditor = userProfileReturnSettingsEditor
        userProfileReturnScreen = nil
        userProfileReturnSettingsEditor = nil
        currentScreen = destination
        if destination == .settings {
            activeSettingsEditor = destinationSettingsEditor
        }
    }

    private func refreshSelectedUserProfileFromRecord(expectedUserID: String? = nil) async {
        let resolvedExpectedID = expectedUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectedSnapshot = await MainActor.run { selectedUserProfile }
        guard let selectedSnapshot else { return }

        let selectedUsername = FirebaseSpotService.normalizeUsername(selectedSnapshot.username)
        var targetUserID = selectedSnapshot.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        if targetUserID.isEmpty, !selectedUsername.isEmpty {
            targetUserID = (try? await FirebaseSpotService.shared.resolveUserID(username: selectedUsername)) ?? ""
        }

        guard !targetUserID.isEmpty else { return }
        if !resolvedExpectedID.isEmpty, resolvedExpectedID != targetUserID { return }

        do {
            let account = try await FirebaseSpotService.shared.fetchUserAccount(userID: targetUserID)
            let liveCounts = try? await FirebaseSpotService.shared.fetchUserFollowCounts(userID: targetUserID)
            let normalizedUsername = FirebaseSpotService.normalizeUsername(account.username)
            let resolvedUsername = normalizedUsername.isEmpty ? selectedSnapshot.username : normalizedUsername
            let resolvedName = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? selectedSnapshot.name
                : account.displayName
            let resolvedBio = (account.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? selectedSnapshot.bio
                : (account.bio ?? selectedSnapshot.bio)
            let resolvedPhotoURL = account.profilePhotoURL ?? selectedSnapshot.profilePhotoURL
            let resolvedFollowerCount = liveCounts?.followers ?? account.followerCount
            let resolvedFollowingCount = liveCounts?.following ?? account.followingCount

            await MainActor.run {
                guard currentScreen == .userProfile else { return }
                if let currentSelected = selectedUserProfile,
                   !currentSelected.userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   currentSelected.userID.trimmingCharacters(in: .whitespacesAndNewlines) != targetUserID {
                    return
                }

                let refreshed = FakeUserProfile(
                    userID: account.uid,
                    username: resolvedUsername,
                    name: resolvedName,
                    city: selectedSnapshot.city,
                    bio: resolvedBio,
                    followerCount: resolvedFollowerCount,
                    followingCount: resolvedFollowingCount,
                    profilePhotoText: String((resolvedName.isEmpty ? selectedSnapshot.name : resolvedName).prefix(2)).uppercased(),
                    profilePhotoURL: resolvedPhotoURL
                )

                cachePrefetchedProfile(refreshed)

                selectedUserProfile = refreshed

                if let index = fakeUserProfiles.firstIndex(where: { profile in
                    let byID = !profile.userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && profile.userID.trimmingCharacters(in: .whitespacesAndNewlines) == targetUserID
                    let byUsername = FirebaseSpotService.normalizeUsername(profile.username) == FirebaseSpotService.normalizeUsername(selectedSnapshot.username)
                    return byID || byUsername
                }) {
                    fakeUserProfiles[index] = refreshed
                }

                applyProfilePhotoURLToPosts(
                    authorUserID: targetUserID,
                    username: refreshed.username,
                    photoURL: refreshed.profilePhotoURL
                )
            }
        } catch {
            print("Spot profile detail hydrate failed: \(error)")
        }
    }

    private func startSelectedUserProfileLiveListener(for userID: String) {
        let targetUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetUserID.isEmpty else {
            stopSelectedUserProfileLiveListener()
            return
        }

        guard selectedUserProfileListenerTargetID != targetUserID else { return }
        stopSelectedUserProfileLiveListener()

        selectedUserProfileListenerTargetID = targetUserID
        selectedUserProfileListener = Firestore.firestore()
            .collection("users")
            .document(targetUserID)
            .addSnapshotListener { _, error in
                if let error {
                    print("Spot profile live follower listener error: \(error)")
                    return
                }

                Task {
                    await refreshSelectedUserProfileFromRecord(expectedUserID: targetUserID)
                }
            }
    }

    private func stopSelectedUserProfileLiveListener() {
        selectedUserProfileListener?.remove()
        selectedUserProfileListener = nil
        selectedUserProfileListenerTargetID = ""
    }

    private func startCurrentUserProfileLiveListener(for userID: String) {
        let targetUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetUserID.isEmpty else {
            stopCurrentUserProfileLiveListener()
            return
        }

        guard currentUserProfileListenerTargetID != targetUserID else { return }
        stopCurrentUserProfileLiveListener()

        currentUserProfileListenerTargetID = targetUserID
        currentUserProfileListener = Firestore.firestore()
            .collection("users")
            .document(targetUserID)
            .addSnapshotListener { _, error in
                if let error {
                    print("Spot current user profile listener error: \(error)")
                    return
                }

                Task {
                    await loadCurrentUserProfileFromRecord()
                }
            }
    }

    private func stopCurrentUserProfileLiveListener() {
        currentUserProfileListener?.remove()
        currentUserProfileListener = nil
        currentUserProfileListenerTargetID = ""
    }

    static func isCurrentUserDMProfile(_ profile: FakeUserProfile, currentUsername: String) -> Bool {
        let normalizedCurrent = FirebaseSpotService.normalizeUsername(currentUsername)
        let normalizedProfile = FirebaseSpotService.normalizeUsername(profile.username)
        return !normalizedCurrent.isEmpty && normalizedCurrent == normalizedProfile
    }

    private func usernameText(_ raw: String) -> some View {
        Text(displayUsername(raw))
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func profileAvatarText(_ value: String, size: CGFloat, circleSize: CGFloat) -> some View {
        let trimmed = String(value.prefix(20))
        let display = trimmed.isEmpty ? "YO" : trimmed
        let count = display.count
        let targetFontSize = max(12, min(size, size * 1.15))
        let offsetY: CGFloat = {
            if count <= 3 { return 4 }
            if count <= 6 { return 2 }
            if count <= 10 { return 0 }
            if count <= 15 { return -2 }
            if count <= 20 { return -3 }
            return -4
        }()

        return Text(display)
            .font(.system(size: targetFontSize, weight: .bold, design: .rounded))
            .foregroundStyle(.black)
            .frame(width: max(10, circleSize - 10), height: max(10, circleSize - 10), alignment: .center)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .allowsTightening(true)
            .contentShape(Rectangle())
            .offset(y: offsetY)
            .clipped()
    }

    private func profileAvatarView(size: CGFloat, textSize: CGFloat = 26, border: Bool = true) -> some View {
        let activeProfileImage = displayProfilePhotoImage

        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.992, green: 0.996, blue: 1.0), Color(red: 0.97, green: 0.982, blue: 0.995)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            if let image = activeProfileImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)

                profileAvatarText(profilePhotoText.isEmpty ? "YO" : profilePhotoText, size: textSize, circleSize: size)
                    .frame(width: size, height: size)
            }

            if border {
                Circle()
                    .stroke(Color.black.opacity(0.13), lineWidth: 0.9)
                    .frame(width: size, height: size)

                Circle()
                    .stroke(Color.white.opacity(0.75), lineWidth: 0.55)
                    .padding(0.8)
                    .frame(width: size, height: size)
            }
        }
        .shadow(color: Color.black.opacity(0.07), radius: 7, x: 0, y: 3)
    }

    private func profileControlChrome(cornerRadius: CGFloat = 16) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.992, green: 0.996, blue: 1.0), Color(red: 0.97, green: 0.982, blue: 0.995)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 0.9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.75), lineWidth: 0.55)
                    .padding(0.65)
            )
            .shadow(color: Color.black.opacity(0.055), radius: 7, x: 0, y: 3)
    }

    private var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    backButton(destination: .profile)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                VStack(alignment: .center, spacing: 14) {
                    PhotosPicker(selection: $profilePhotoItem, matching: .images, photoLibrary: .shared()) {
                        profileAvatarView(size: 84, textSize: 26)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .center, spacing: 6) {
                        Text(displayUsername(profileUsername))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .frame(maxWidth: .infinity)

                if remainingBoosts > 0 {
                    let availableBoosts = min(max(remainingBoosts, 0), 3)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Boost ready")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text("\(availableBoosts) out of 3")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [ContentView.appPrimaryThemeColor.opacity(0.18), ContentView.appSecondaryThemeColor.opacity(0.12)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 12) {
                    settingsRow(title: "Account name", value: profileName.isEmpty ? "Add" : profileName, action: { activeSettingsEditor = .name })
                    settingsRow(title: "Username", value: profileUsername.isEmpty ? "Add" : displayUsername(profileUsername), action: { activeSettingsEditor = .username })
                    settingsRow(title: "Account", value: phoneNumber.isEmpty ? "Open" : phoneNumber, action: {
                        accountAuthMessage = ""
                        showPasswordResetSpamNotice = false
                        activeSettingsEditor = .accountInfo
                    })
                    settingsRow(title: "Search users", value: "Open", action: { activeSettingsEditor = .searchUsers })
                    settingsRow(title: "Block Users", value: "\(blockedUsers.count)", action: { activeSettingsEditor = .blockUsers })
                    settingsRow(title: "Saved posts", value: "Open", action: { currentScreen = .savedPosts })
                    settingsRow(title: "Location alerts", value: "\(min(savedLocations.count, 10)) saved", action: { activeSettingsEditor = .locationAlerts })
                    settingsRow(title: "Boost Next Posts", value: "Open", action: { activeSettingsEditor = .boostNextPosts })

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $isAnonymousModeEnabled) {
                            Text("Anonymous")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .black))

                        Text("When Anonymous is on, every new post hides your account name and username. People also cannot open your profile from those posts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            currentScreen = .anonymousPosts
                        } label: {
                            HStack {
                                Text("Anonymous Posts")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 18)

            }
        }
        .overlay {
            if let editor = activeSettingsEditor {
                settingsDetailSheet(for: editor)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: activeSettingsEditor)
            }
        }
        .onChange(of: profilePhotoItem) { _, newItem in
            guard let newItem else {
                return
            }
            handleProfilePhotoSelection(newItem)
        }
        .onChange(of: isAnonymousModeEnabled) { _, enabled in
            UserDefaults.standard.set(enabled, forKey: anonymousModeDefaultsKey)
            accountAuthMessage = enabled
                ? "Anonymous mode enabled. New posts hide your identity."
                : "Anonymous mode disabled. New posts show your profile again."
        }
    }

    private var messagesView: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Search users", text: $userSearchText)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    let results = directMessageSuggestions
                    if results.isEmpty {
                        Text(userSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No suggested users yet" : "No users found")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(results, id: \ .username) { user in
                                Button {
                                    openDM(with: user)
                                } label: {
                                    HStack(alignment: .center, spacing: 10) {
                                        Circle()
                                            .fill(LinearGradient(colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(width: 34, height: 34)
                                            .overlay(Text(user.profilePhotoText).font(.caption.weight(.bold)).foregroundStyle(.black))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(user.name.isEmpty ? user.username : user.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Text(displayUsername(user.username))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 10)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                HStack(spacing: 8) {
                    Button {
                        messagesTab = .incoming
                    } label: {
                        Text("Incoming")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(.primary)
                            .background {
                                if messagesTab == .incoming {
                                    LinearGradient(colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor], startPoint: .leading, endPoint: .trailing)
                                } else {
                                    Color(.secondarySystemBackground)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.black, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        messagesTab = .sent
                    } label: {
                        Text("Sent")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(.primary)
                            .background {
                                if messagesTab == .sent {
                                    LinearGradient(colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor], startPoint: .leading, endPoint: .trailing)
                                } else {
                                    Color(.secondarySystemBackground)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.black, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        let visibleThreads = (messagesTab == .incoming ? messages.filter { $0.isIncoming } : messages.filter { !$0.isIncoming })
                            .sorted {
                                if $0.isPinned != $1.isPinned {
                                    return $0.isPinned && !$1.isPinned
                                }
                                return false
                            }

                        ForEach(visibleThreads) { thread in
                            messageThreadRow(for: thread)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 100)
                }
            }

            floatingHomeActions
                .padding(.bottom, 12)
                .padding(.horizontal, 18)
        }
    }

    private func messageThreadRow(for thread: DirectMessageThread) -> some View {
        Button {
            selectedChatThread = thread
            if let post = pendingSharePost {
                addSharedPostToThread(thread, post: post, isMine: true)
            } else {
                chatComposerText = ""
            }
            currentScreen = .chatDetail
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(LinearGradient(colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 42, height: 42)
                    .overlay(Text(thread.initials).font(.caption.weight(.bold)).foregroundStyle(.black))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(thread.participant)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(thread.time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(displayUsername(thread.username))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(thread.preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var chatDetailView: some View {
        guard let thread = selectedChatThread else {
            return AnyView(
                VStack(spacing: 0) {
                    HStack {
                        backButton(destination: .messages)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .background(.gray.opacity(0.1))
                    
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "message")
                            .font(.system(size: 48))
                            .foregroundStyle(.gray)
                        Text("Select a conversation to start")
                            .font(.callout)
                            .foregroundStyle(.gray)
                    }
                    Spacer()
                }
            )
        }

        let messagesForThread = chatMessages[thread.id] ?? []
        let resolvedUsername = thread.username.isEmpty ? "you" : (thread.username.hasPrefix("@") ? String(thread.username.dropFirst()) : thread.username)
        let fallbackProfile = FakeUserProfile(username: resolvedUsername, name: thread.participant, city: "", bio: "", followerCount: 0, followingCount: 0, profilePhotoText: thread.initials)
        let profileForThread = fakeUserProfiles.first(where: {
            $0.username.lowercased() == thread.username.lowercased() || $0.name.lowercased() == thread.participant.lowercased()
        }) ?? fallbackProfile

        return AnyView(VStack(spacing: 0) {
            HStack {
                backButton(destination: .messages)
                Spacer()

                Button {
                    openUserProfileScreen(with: profileForThread)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(LinearGradient(colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 32, height: 32)
                            .overlay(Text(profileForThread.profilePhotoText).font(.caption.weight(.bold)).foregroundStyle(.black))

                        Text(profileForThread.username.isEmpty ? thread.participant : displayUsername(profileForThread.username))
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    togglePinThread(thread)
                } label: {
                    Image(systemName: thread.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    deleteChatThread(thread)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(messagesForThread) { message in
                        messageRow(for: message)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }

            HStack(spacing: 10) {
                TextField("Message", text: $chatComposerText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    guard !chatComposerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    var updatedMessages = chatMessages[thread.id] ?? []
                    updatedMessages.append(
                        ChatMessage(id: (updatedMessages.last?.id ?? 0) + 1, text: chatComposerText, isMine: true, time: "now")
                    )
                    chatMessages[thread.id] = updatedMessages
                    chatComposerText = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(LinearGradient(colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor], startPoint: .leading, endPoint: .trailing))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .background(Color(.systemBackground).opacity(0.98))
        )
    }

    private func messageRow(for message: ChatMessage) -> some View {
        HStack {
            if message.isMine { Spacer() }

            if let post = message.sharedPost {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Shared post")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(message.time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            Circle()
                                .fill(LinearGradient(colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 28, height: 28)
                                .overlay(Text(post.author.prefix(2).uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.white))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(post.author)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(displayUsername(post.handle))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(post.title.isEmpty ? "Shared post" : post.title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if !post.body.isEmpty {
                            Text(post.body)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !post.location.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "location.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(post.location)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if post.type != "Text" {
                            HStack(spacing: 6) {
                                Image(systemName: post.type == "Video" ? "video.fill" : post.type == "Photo" ? "photo.fill" : post.type == "Audio" ? "waveform" : post.type == "Song" ? "music.note.list" : post.type == "Poll" ? "chart.bar.fill" : post.type == "Live Route" ? "point.topleft.down.curvedto.point.bottomright.up" : post.type == "Guide" ? "list.number" : post.type == "Work" ? "briefcase.fill" : post.type == "For Sale" ? "tag.fill" : "link")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(post.type)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .frame(maxWidth: .infinity, alignment: message.isMine ? .trailing : .leading)
            } else {
                VStack(alignment: message.isMine ? .trailing : .leading, spacing: 4) {
                    Text(message.text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(messageBubbleBackground(for: message.isMine))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.black, lineWidth: message.isMine ? 1 : 0)
                        )

                    Text(message.time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !message.isMine { Spacer() }
        }
        .frame(maxWidth: .infinity)
    }

    private func messageBubbleBackground(for isMine: Bool) -> some View {
        Group {
            if isMine {
                Color.white
            } else {
                Color(.secondarySystemBackground)
            }
        }
    }

    private func persistLocationSelection(_ value: String, context: LocationContext) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        switch context {
        case .feed:
            UserDefaults.standard.set(cleaned, forKey: feedLocationDefaultsKey)
        case .video:
            UserDefaults.standard.set(cleaned, forKey: videoLocationDefaultsKey)
        case .post:
            UserDefaults.standard.set(cleaned, forKey: postLocationDefaultsKey)
        }
    }

    private func applyLocationSelection(_ value: String, context: LocationContext) {
        switch context {
        case .feed:
            fromLocation = value
        case .video:
            videoLocation = value
        case .post:
            postLocation = value
        }
        persistLocationSelection(value, context: context)
    }

    private func persistSavedLocations() {
        UserDefaults.standard.set(savedLocations, forKey: savedLocationsDefaultsKey)
    }

    private func persistRecentLocations() {
        UserDefaults.standard.set(recentLocations, forKey: recentLocationsDefaultsKey)
    }

    static func loadLocationPostCooldownHistory() -> [String: [TimeInterval]] {
        guard let raw = UserDefaults.standard.dictionary(forKey: Self.locationPostCooldownDefaultsKey) else {
            return [:]
        }

        var mapped: [String: [TimeInterval]] = [:]
        for (key, value) in raw {
            guard let locationKey = key as? String else {
                continue
            }

            let canonicalKey = cooldownKeyForLocation(locationKey)
            guard !canonicalKey.isEmpty else {
                continue
            }

            let numbers: [TimeInterval]
            if let values = value as? [Double] {
                numbers = values
            } else if let values = value as? [NSNumber] {
                numbers = values.map { $0.doubleValue }
            } else {
                continue
            }

            mapped[canonicalKey] = numbers
        }

        let legacyGlobalKeys = Set(["all", "global", "location", "locations", "everywhere", "alllocations"])
        if mapped.keys.count == 1, let onlyKey = mapped.keys.first, legacyGlobalKeys.contains(onlyKey) {
            UserDefaults.standard.removeObject(forKey: Self.locationPostCooldownDefaultsKey)
            return [:]
        }

        return mapped
    }

    private func persistLocationPostCooldownHistory() {
        UserDefaults.standard.set(locationPostCooldownHistory, forKey: Self.locationPostCooldownDefaultsKey)
    }

    static func cooldownKeyForLocation(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }

        let lower = cleaned.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let stripped = lower.replacingOccurrences(of: "[,_/\\-]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9 ]+", with: " ", options: .regularExpression)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return stripped
    }

    private func activeCooldownTimestamps(for location: String, now: TimeInterval = Date().timeIntervalSince1970) -> [TimeInterval] {
        let key = Self.cooldownKeyForLocation(location)
        let source = locationPostCooldownHistory[key] ?? []
        return source.filter { now - $0 < Self.perLocationCooldownWindowSeconds }
    }

    private func isLocationOnCooldownForPosting(_ location: String) -> Bool {
        let active = activeCooldownTimestamps(for: location)
        return active.count >= Self.perLocationPostLimit
    }

    private func cooldownSecondsRemaining(for location: String, now: TimeInterval = Date().timeIntervalSince1970) -> Int {
        let active = activeCooldownTimestamps(for: location, now: now)
        guard active.count >= Self.perLocationPostLimit, let earliest = active.min() else {
            return 0
        }

        let elapsed = now - earliest
        let remaining = max(0, Int(Self.perLocationCooldownWindowSeconds - elapsed))
        return remaining
    }

    private func showLocationCooldownMessage(for location: String) {
        let remainingSeconds = cooldownSecondsRemaining(for: location)
        let remainingMinutes = max(1, Int(ceil(Double(remainingSeconds) / 60.0)))
        let baseMessage = "Cool off! You only get five posts per hour in each location."
        let detail = " Try this location again in about \(remainingMinutes)m."
        postLocationCooldownMessage = baseMessage + detail
        lastSentMessage = baseMessage
        accountAuthMessage = baseMessage
    }

    private func recordPostForCooldown(at location: String, now: TimeInterval = Date().timeIntervalSince1970) {
        let key = Self.cooldownKeyForLocation(location)
        var active = activeCooldownTimestamps(for: location, now: now)
        active.append(now)
        locationPostCooldownHistory[key] = active
        persistLocationPostCooldownHistory()
    }

    private func rememberRecentLocation(_ value: String) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if let index = recentLocations.firstIndex(of: cleaned) {
            recentLocations.remove(at: index)
        }

        recentLocations.insert(cleaned, at: 0)
        if recentLocations.count > 3 {
            recentLocations.removeLast()
        }

        persistRecentLocations()
    }

    static func orderedSavedLocations(_ current: [String], adding value: String, limit: Int = 8) -> [String] {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.lowercased() != "metric" else { return current }

        var next = current.filter { $0.lowercased() != cleaned.lowercased() }
        next.insert(cleaned, at: 0)
        if next.count > limit {
            next = Array(next.prefix(limit))
        }
        return next
    }

    private func rememberSavedLocation(_ value: String) {
        savedLocations = Self.orderedSavedLocations(savedLocations, adding: value, limit: 8)
        persistSavedLocations()
    }

    static func closeScreenAfterLocationSelection(context: LocationContext, currentScreen: Screen) -> Screen {
        switch context {
        case .video:
            return .locationFeed
        case .feed:
            return .home
        case .post:
            return currentScreen == .postLocationPicker ? .home : .home
        }
    }

    private func handleLocationSelection(_ value: String, context: LocationContext, closeScreen: Screen? = nil, saveToRecent: Bool = false, saveToFavorites: Bool = false) {
        let chosen = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chosen.isEmpty else { return }

        if context == .post, isLocationOnCooldownForPosting(chosen) {
            showLocationCooldownMessage(for: chosen)
            return
        }

        if context == .post {
            postLocationCooldownMessage = ""
        }

        applyLocationSelection(chosen, context: context)

        if saveToRecent {
            rememberRecentLocation(chosen)
        }

        if saveToFavorites {
            rememberSavedLocation(chosen)
        }

        if let screen = closeScreen {
            currentScreen = screen
        }
    }

    private func handleFirestorePOISearchSelection(_ value: String, context: LocationContext, closeScreen: Screen? = nil) {
        let chosen = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chosen.isEmpty else { return }

        guard let matchedPOI = firestorePOISearchResults.first(where: { poi in
            Self.normalizedLocationRealm(poi.name) == Self.normalizedLocationRealm(chosen)
        }) else {
            // Fallback suggestions can be city/country text; still allow selecting them.
            handleLocationSelection(chosen, context: context, closeScreen: closeScreen, saveToRecent: true, saveToFavorites: false)
            return
        }

        handleLocationSelection(matchedPOI.name, context: context, closeScreen: closeScreen, saveToRecent: true, saveToFavorites: false)
    }

    private func nearestNearbyLocation(for context: LocationContext) -> String {
        if let nearest = nearbyPlaces.first?.name {
            return nearest
        }

        switch context {
        case .feed:
            return fromLocation.isEmpty ? "Metric" : fromLocation
        case .video:
            return videoLocation.isEmpty ? "Metric" : videoLocation
        case .post:
            return postLocation.isEmpty ? "Metric" : postLocation
        }
    }

    private func requestNearbyLocationsIfNeeded(context: LocationContext) {
        let status = locationService.authorizationStatus

        if status == .notDetermined {
            if !hasRequestedLocationPermission {
                hasRequestedLocationPermission = true
                locationService.requestPermission()
            }
        }

        let location = locationService.lastKnownLocation ?? CLLocation(latitude: NearbyPlaceLoader.defaultCenter.latitude, longitude: NearbyPlaceLoader.defaultCenter.longitude)
        let localNearby = NearbyPlaceLoader.loadNearbyPlaces(from: location, limit: 12)

        // Always show locally bundled nearby places even without permission/network.
        if !localNearby.isEmpty {
            nearbyPlaces = localNearby

            if let nearest = localNearby.first?.name {
                switch context {
                case .feed:
                    let current = fromLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                    if current.isEmpty || current == "Metric" {
                        fromLocation = nearest
                        persistLocationSelection(nearest, context: .feed)
                    }
                case .video:
                    let current = videoLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                    if current.isEmpty || current == "Metric" {
                        videoLocation = nearest
                        persistLocationSelection(nearest, context: .video)
                    }
                case .post:
                    let current = postLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                    if current.isEmpty {
                        postLocation = nearest
                        persistLocationSelection(nearest, context: .post)
                    }
                }
            }
        }

        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return
        }

        isLoadingNearbyPlaces = true

        Task {
            var resolvedNearby = localNearby

            do {
                let remotePOIs = try await FirebaseSpotService.shared.fetchNearbyPOIs(
                    around: location.coordinate,
                    limit: 12
                )
                if !remotePOIs.isEmpty {
                    resolvedNearby = remotePOIs.map { poi in
                        NearbyPlace(
                            id: poi.id,
                            name: poi.name,
                            category: poi.category,
                            latitude: poi.latitude,
                            longitude: poi.longitude
                        )
                    }
                } else {
                    resolvedNearby = localNearby
                    let firestorePOIs = localNearby.map { poi in
                        FirebasePOIRecord(
                            id: poi.id,
                            name: poi.name,
                            category: poi.category,
                            latitude: poi.latitude,
                            longitude: poi.longitude,
                            city: "",
                            country: "",
                            geohash: nil,
                            updatedAt: Date().timeIntervalSince1970
                        )
                    }
                    try? await FirebaseSpotService.shared.savePOIs(firestorePOIs)
                }
            } catch {
                resolvedNearby = localNearby
            }

            await MainActor.run {
                nearbyPlaces = resolvedNearby
                isLoadingNearbyPlaces = false
                if let nearest = nearbyPlaces.first?.name {
                    switch context {
                    case .feed:
                        let current = fromLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                        if current.isEmpty || current == "Metric" {
                            fromLocation = nearest
                            persistLocationSelection(nearest, context: .feed)
                        }
                    case .video:
                        let current = videoLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                        if current.isEmpty || current == "Metric" {
                            videoLocation = nearest
                            persistLocationSelection(nearest, context: .video)
                        }
                    case .post:
                        let current = postLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                        if current.isEmpty {
                            postLocation = nearest
                            persistLocationSelection(nearest, context: .post)
                        }
                    }
                }
            }
        }
    }

    private func selectedLocationBackground(_ isSelected: Bool) -> AnyView {
        AnyView(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isSelected
                            ? [Color(red: 0.84, green: 0.95, blue: 1.0), Color(red: 0.78, green: 0.92, blue: 0.99)]
                            : [Color(red: 0.992, green: 0.996, blue: 1.0), Color(red: 0.97, green: 0.982, blue: 0.995)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isSelected ? Color(red: 0.22, green: 0.52, blue: 0.73).opacity(0.42) : Color.black.opacity(0.12),
                            lineWidth: 0.9
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(isSelected ? 0.62 : 0.78), lineWidth: 0.55)
                        .padding(0.65)
                )
                .shadow(
                    color: isSelected ? Color(red: 0.35, green: 0.67, blue: 0.85).opacity(0.2) : Color.black.opacity(0.055),
                    radius: isSelected ? 10 : 7,
                    x: 0,
                    y: isSelected ? 4 : 3
                )
        )
    }

    private func locationRegionChips(for context: LocationContext) -> [String] {
        let currentValue: String = {
            switch context {
            case .feed:
                return fromLocation
            case .video:
                return videoLocation
            case .post:
                return postLocation
            }
        }()

        var candidates: [String] = []

        let nearest = nearestNearbyLocation(for: context)
        if !nearest.isEmpty && nearest != "Metric" {
            candidates.append(nearest)
        }

        candidates.append(contentsOf: nearbyPlaces.prefix(4).map(\.name))
        candidates.append(contentsOf: firestorePOISearchResults.prefix(8).flatMap { poi -> [String] in
            var values: [String] = [poi.name]
            let city = (poi.city ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !city.isEmpty && city.lowercased() != poi.name.lowercased() {
                values.append(city)
            }
            return values
        })

        let active = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !active.isEmpty, active != "Metric" {
            candidates.append(active)
        }

        var unique: [String] = []
        var seen = Set<String>()

        for candidate in candidates {
            let cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned != "Metric" else { continue }
            let key = Self.normalizedLocationRealm(cleaned)
            if seen.contains(key) { continue }
            seen.insert(key)
            unique.append(cleaned)
        }

        return Array(unique.prefix(6))
    }

    private var locationPickerView: some View {
        let context = locationContext
        let currentValue: String = {
            switch context {
            case .feed:
                return fromLocation
            case .video:
                return videoLocation
            case .post:
                return postLocation
            }
        }()
        let normalizedCurrentValue = Self.normalizedLocationRealm(currentValue)
        let normalizedMetric = Self.normalizedLocationRealm("Metric")
        let isMetricSelected = normalizedCurrentValue == normalizedMetric
        let closeScreenAfterSelection = Self.closeScreenAfterLocationSelection(context: context, currentScreen: currentScreen)
        let shouldCloseAfterSingleSelection: (String) -> Bool = { selectedValue in
            Self.normalizedLocationRealm(selectedValue) != normalizedCurrentValue
        }

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            Button {
                                handleLocationSelection(
                                    "Metric",
                                    context: context,
                                    closeScreen: shouldCloseAfterSingleSelection("Metric") ? closeScreenAfterSelection : nil,
                                    saveToRecent: false,
                                    saveToFavorites: false
                                )
                            } label: {
                                HStack(spacing: 7) {
                                    TrendLineView()
                                        .frame(width: 18, height: 10)
                                    Text("Metric")
                                        .font(.subheadline.weight(.medium))
                                }
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(selectedLocationBackground(isMetricSelected))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 18)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            if isLoadingNearbyPlaces {
                                ProgressView()
                                    .padding(.horizontal, 18)
                            } else {
                                ForEach(nearbyPlaces) { place in
                                    let isSelected = normalizedCurrentValue == Self.normalizedLocationRealm(place.name)
                                    Button {
                                        handleLocationSelection(
                                            place.name,
                                            context: context,
                                            closeScreen: shouldCloseAfterSingleSelection(place.name) ? closeScreenAfterSelection : nil,
                                            saveToRecent: false,
                                            saveToFavorites: false
                                        )
                                    } label: {
                                        Text(place.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 12)
                                            .background(selectedLocationBackground(isSelected))
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                    }

                    LocationField(
                        title: "",
                        placeholder: "Search places or cities",
                        text: $locationSearchText,
                        suggestions: visibleLocationSuggestions,
                        onSuggestionSelected: { chosen in
                            let closeScreen = shouldCloseAfterSingleSelection(chosen) ? closeScreenAfterSelection : nil
                            handleFirestorePOISearchSelection(chosen, context: context, closeScreen: closeScreen)
                            locationSearchText = ""
                        }
                    )
                    .padding(.horizontal, 18)
                    .onSubmit {
                        // Free text should not auto-select; selection must come from Firestore POI suggestions.
                    }
                    .task(id: locationSearchText) {
                        await refreshFirestorePOISearchResults()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach((recentLocations.isEmpty ? savedLocations : recentLocations).prefix(8), id: \.self) { recent in
                            Button {
                                handleLocationSelection(
                                    recent,
                                    context: context,
                                    closeScreen: shouldCloseAfterSingleSelection(recent) ? closeScreenAfterSelection : nil,
                                    saveToRecent: true,
                                    saveToFavorites: false
                                )
                            } label: {
                                Text(recent)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
                                    .background(selectedLocationBackground(normalizedCurrentValue == Self.normalizedLocationRealm(recent)))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 132)
                }
                .padding(.top, 12)
            }

            expandedLocationHomeActions
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
        }
        .onAppear {
            requestNearbyLocationsIfNeeded(context: context)
        }
    }

    private var postLocationPickerView: some View {
        let normalizedPostLocation = Self.normalizedLocationRealm(postLocation)
        let normalizedMetric = Self.normalizedLocationRealm("Metric")
        let isMetricSelected = normalizedPostLocation == normalizedMetric
        let metricOnCooldown = isLocationOnCooldownForPosting("Metric")

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !postLocationCooldownMessage.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Text(postLocationCooldownMessage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.black)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.98, green: 0.87, blue: 0.45), Color(red: 0.95, green: 0.76, blue: 0.24)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.black.opacity(0.2), lineWidth: 1)
                        )
                        .padding(.horizontal, 18)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            Button {
                                handleLocationSelection("Metric", context: .post, closeScreen: nil, saveToRecent: false, saveToFavorites: false)
                            } label: {
                                HStack(spacing: 7) {
                                    TrendLineView()
                                        .frame(width: 18, height: 10)
                                    Text("Metric")
                                        .font(.subheadline.weight(.medium))
                                }
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(selectedLocationBackground(isMetricSelected))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                                .opacity(metricOnCooldown ? 0.58 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 18)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            if isLoadingNearbyPlaces {
                                ProgressView()
                                    .padding(.horizontal, 18)
                            } else {
                                ForEach(nearbyPlaces) { place in
                                    let isPlaceSelected = normalizedPostLocation == Self.normalizedLocationRealm(place.name)
                                    let isPlaceOnCooldown = isLocationOnCooldownForPosting(place.name)
                                    Button {
                                        handleLocationSelection(place.name, context: .post, closeScreen: nil, saveToRecent: false, saveToFavorites: false)
                                    } label: {
                                        Text(place.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 12)
                                            .frame(minWidth: 92)
                                            .background(selectedLocationBackground(isPlaceSelected))
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                                            .opacity(isPlaceOnCooldown ? 0.58 : 1)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                    }

                    LocationField(
                        title: "",
                        placeholder: "Search places or cities",
                        text: $locationSearchText,
                        suggestions: visibleLocationSuggestions,
                        onSuggestionSelected: { chosen in
                            handleFirestorePOISearchSelection(chosen, context: .post, closeScreen: nil)
                            locationSearchText = ""
                        }
                    )
                    .padding(.horizontal, 18)
                    .onSubmit {
                        // Free text should not auto-select; selection must come from Firestore POI suggestions.
                    }
                    .task(id: locationSearchText) {
                        await refreshFirestorePOISearchResults()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach((recentLocations.isEmpty ? savedLocations : recentLocations).prefix(8), id: \.self) { recent in
                            let isRecentOnCooldown = isLocationOnCooldownForPosting(recent)
                            Button {
                                handleLocationSelection(recent, context: .post, closeScreen: nil, saveToRecent: true, saveToFavorites: false)
                            } label: {
                                Text(recent)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
                                    .background(selectedLocationBackground(normalizedPostLocation == Self.normalizedLocationRealm(recent)))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                                    .opacity(isRecentOnCooldown ? 0.58 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 120)
                }
                .padding(.top, 12)
            }

            VStack(spacing: 12) {
                Button {
                    submitDraftPost()
                } label: {
                    Text(isSubmittingPost ? "Posting..." : "Post")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.99, green: 0.94, blue: 0.74), Color(red: 0.96, green: 0.78, blue: 0.44)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.black, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isSubmittingPost)
                .padding(.horizontal, 18)

                floatingHomeActions
                    .padding(.horizontal, 18)
            }
            .padding(.bottom, 12)
        }
        .onAppear {
            requestNearbyLocationsIfNeeded(context: .post)
        }
    }

    private var locationFeedView: some View {
        let activeLocation = videoLocation.isEmpty ? "Tokyo, Japan" : videoLocation
        let isSearchFeedActive = isVideoSearchFeedActive
        let isFriendsFeed = isFriendsRealm(activeLocation)
        let scopedVideoPosts = (isFriendsFeed
            ? posts
            : Self.postsForLocationRealm(posts, activeLocation: activeLocation))
        let globalPinnedKeys = Set(
            adminPinnedRealmMap()
                .filter { $0.value == Self.adminPinAllNonMetricMarker }
                .map { $0.key }
        )
        let includeGlobalPinnedForLocation = !isFriendsFeed && Self.normalizedLocationRealm(activeLocation) != Self.normalizedLocationRealm("Metric")
        let globalPinnedVideoPostsForLocation = includeGlobalPinnedForLocation
            ? posts.filter { globalPinnedKeys.contains(postAdminPinStorageKey($0)) }
            : []
        var seenVideoPostIDs: Set<Int> = []
        let locationVideoPosts = (scopedVideoPosts + globalPinnedVideoPostsForLocation).filter { post in
            if seenVideoPostIDs.contains(post.id) {
                return false
            }
            seenVideoPostIDs.insert(post.id)
            return true
        }
            .filter { $0.type == "Video" }
            .filter { postMatchesFeedSearch($0) }
        let visibleVideoPosts = (isFriendsFeed
            ? locationVideoPosts.filter {
                isUserMutualFollowed(authorUserID: $0.authorUserID, username: $0.handle)
                    || Self.isPostOwnedByUser($0, currentUserID: currentUserID, currentUsername: profileUsername)
            }
            : (showFollowingVideoOnly ? locationVideoPosts.filter {
                isUserFollowed(authorUserID: $0.authorUserID, username: $0.handle)
                    || Self.isPostOwnedByUser($0, currentUserID: currentUserID, currentUsername: profileUsername)
            } : locationVideoPosts))
        let videoCandidates = isSearchFeedActive ? [] : visibleVideoPosts
        let rankedVideoPosts = prioritizeAdminPinnedPosts(
            orderedPosts(videoCandidates, using: videoFeedRankedPostIDs),
            activeLocation: activeLocation
        )
        let fallbackRankedVideoPosts = rankedVideoPosts.isEmpty
            ? prioritizeAdminPinnedPosts(
                rankedPostsForFeed(videoCandidates, activeLocation: activeLocation, isFriendsFeed: isFriendsFeed),
                activeLocation: activeLocation
            )
            : rankedVideoPosts
        let loadedVideoPosts = Array(fallbackRankedVideoPosts.prefix(lazyVideoLoadedCount))

        return GeometryReader { container in
            let feedBodyMinHeight = max(320, container.size.height - 300)

            ZStack(alignment: .bottom) {
                Color(red: 0.93, green: 0.93, blue: 0.93)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            feedModeToggle
                                .padding(.horizontal, 18)
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 14)
                        .background(Color(red: 0.93, green: 0.93, blue: 0.93))
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.black.opacity(0.09))
                                .frame(height: 0.6)
                                .padding(.horizontal, 8)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            VStack(spacing: 16) {
                                ForEach(Array(loadedVideoPosts.enumerated()), id: \.element.id) { index, post in
                                    let livePostBinding = Binding<MockPost>(
                                        get: {
                                            posts.first(where: { $0.id == post.id }) ?? post
                                        },
                                        set: { updatedPost in
                                            if let postIndex = posts.firstIndex(where: { $0.id == updatedPost.id }) {
                                                posts[postIndex] = updatedPost
                                            }
                                        }
                                    )

                                    PostCardView(
                                        post: livePostBinding,
                                        isOwnPost: Self.isPostOwnedByUser(post, currentUserID: currentUserID, currentUsername: profileUsername),
                                        currentUserProfilePhotoImage: displayProfilePhotoImage,
                                        showsAuthorLine: true,
                                        videoPlaybackEnabled: activeVideoID == post.id,
                                        isReported: reportedPostIds.contains(post.id),
                                        onSend: {
                                            sharePostToFriends(post)
                                        },
                                        onSave: { savedPost in
                                            let currentPost = posts.first(where: { $0.id == savedPost.id }) ?? savedPost
                                            toggleSavedState(for: currentPost)
                                        },
                                        onDelete: {
                                            let currentPost = posts.first(where: { $0.id == post.id }) ?? post
                                            deletePost(currentPost)
                                        },
                                        onReport: {
                                            reportPost(post)
                                        },
                                        onProfileTap: {
                                            openUserProfile(from: post)
                                        },
                                        onMessageTap: {
                                            let matchingUser = fakeUserProfiles.first(where: { $0.username.lowercased() == post.handle.lowercased() })
                                                ?? fallbackProfile(for: post.handle, displayName: post.author, userID: post.authorUserID, profilePhotoURL: post.authorProfilePhotoURL)
                                            openDM(with: matchingUser)
                                        },
                                        onViewTracked: { updatedPost in
                                            applyTrackedPostViewUpdate(updatedPost)
                                        }
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 0)
                                    .onAppear {
                                        activeVideoID = post.id
                                        if index >= max(0, loadedVideoPosts.count - 2) && lazyVideoLoadedCount < fallbackRankedVideoPosts.count {
                                            lazyVideoLoadedCount = min(lazyVideoLoadedCount + lazyVideoWindowSize, fallbackRankedVideoPosts.count)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 14)
                            .padding(.bottom, 28)

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .frame(minHeight: feedBodyMinHeight, alignment: .top)
                        .background(Color.white)

                        Rectangle()
                            .fill(Color(red: 0.93, green: 0.93, blue: 0.93))
                            .frame(height: Self.bottomSilverEndCapHeight)
                    }
                    .padding(.bottom, 110)
                }

                floatingHomeActions
                    .padding(.bottom, 12)
                    .padding(.horizontal, 18)
            }
        }
        .onAppear {
            rebuildVideoFeedRanking(
                candidates: visibleVideoPosts,
                activeLocation: activeLocation,
                followingOnly: showFollowingVideoOnly,
                isFriendsFeed: isFriendsFeed,
                force: true
            )
            if activeVideoID == nil {
                activeVideoID = loadedVideoPosts.first?.id
            }
        }
        .onChange(of: videoLocation) { _, _ in
            rebuildVideoFeedRanking(
                candidates: visibleVideoPosts,
                activeLocation: activeLocation,
                followingOnly: showFollowingVideoOnly,
                isFriendsFeed: isFriendsFeed,
                force: true
            )
        }
        .onChange(of: showFollowingVideoOnly) { _, _ in
            rebuildVideoFeedRanking(
                candidates: visibleVideoPosts,
                activeLocation: activeLocation,
                followingOnly: showFollowingVideoOnly,
                isFriendsFeed: isFriendsFeed,
                force: true
            )
        }
        .onChange(of: feedContentSearchText) { _, _ in
            rebuildVideoFeedRanking(
                candidates: visibleVideoPosts,
                activeLocation: activeLocation,
                followingOnly: showFollowingVideoOnly,
                isFriendsFeed: isFriendsFeed,
                force: true
            )
        }
        .onChange(of: posts.map(\.id)) { _, _ in
            rebuildVideoFeedRanking(
                candidates: visibleVideoPosts,
                activeLocation: activeLocation,
                followingOnly: showFollowingVideoOnly,
                isFriendsFeed: isFriendsFeed,
                force: true
            )
        }
        .onChange(of: loadedVideoPosts.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                activeVideoID = nil
                return
            }

            if let activeVideoID, ids.contains(activeVideoID) {
                return
            }

            activeVideoID = ids.first
        }
    }

    private var allLocationSuggestions: [String] {
        let center = locationService.lastKnownLocation?.coordinate ?? NearbyPlaceLoader.defaultCenter
        let trimmedQuery = locationSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let firestoreNames = firestorePOISearchResults.flatMap { poi -> [String] in
            var values: [String] = [poi.name]

            let city = (poi.city ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let country = (poi.country ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if !city.isEmpty {
                values.append(city)
            }

            if !country.isEmpty {
                values.append(country)
            }

            if !city.isEmpty, !country.isEmpty {
                values.append("\(city), \(country)")
            }

            return values
        }

        let fallbackSuggestions = savedLocations + recentLocations + recommendedLocations + randomLocations + locationSuggestions + firestoreNames
        let mergedNearbyPlaces = mergedSearchNearbyPlaces(userCoordinate: center)
        let rankedLocalSuggestions = LocationSuggestionRanker.rankedSuggestions(
            query: locationSearchText,
            nearbyPlaces: mergedNearbyPlaces,
            fallback: fallbackSuggestions,
            userCoordinate: center
        )

        if !trimmedQuery.isEmpty {
            // For active search, prefer Firestore matches but keep local ranked fallback visible.
            var ordered: [String] = []
            var seenNormalized = Set<String>()
            for value in firestoreNames {
                let key = Self.normalizedLocationRealm(value)
                if !key.isEmpty && !seenNormalized.contains(key) {
                    seenNormalized.insert(key)
                    ordered.append(value)
                }
            }

            for value in rankedLocalSuggestions {
                let key = Self.normalizedLocationRealm(value)
                if !key.isEmpty && !seenNormalized.contains(key) {
                    seenNormalized.insert(key)
                    ordered.append(value)
                }
            }

            return ordered
        }

        return rankedLocalSuggestions
    }

    private func locationSuggestionSubtitle(for value: String) -> String {
        let normalizedValue = Self.normalizedLocationRealm(value)

        guard let matchingPOI = firestorePOISearchResults.first(where: { poi in
            Self.normalizedLocationRealm(poi.name) == normalizedValue
        }) else {
            return ""
        }

        let city = (matchingPOI.city ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let country = (matchingPOI.country ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !city.isEmpty && !country.isEmpty {
            return "\(city), \(country)"
        }
        if !city.isEmpty {
            return city
        }
        if !country.isEmpty {
            return country
        }
        return ""
    }

    private var visibleLocationSuggestions: [LocationSearchSuggestion] {
        let query = locationSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        if !firestorePOISearchResults.isEmpty {
            // Keep search results tied to Firestore global matches when the user is actively searching.
            var seen = Set<String>()
            let suggestions = firestorePOISearchResults.compactMap { poi -> LocationSearchSuggestion? in
                let normalized = Self.normalizedLocationRealm(poi.name)
                guard !normalized.isEmpty, !seen.contains(normalized) else { return nil }
                seen.insert(normalized)

                let city = (poi.city ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let country = (poi.country ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let subtitle: String
                if !city.isEmpty && !country.isEmpty {
                    subtitle = "\(city), \(country)"
                } else if !city.isEmpty {
                    subtitle = city
                } else if !country.isEmpty {
                    subtitle = country
                } else {
                    subtitle = ""
                }

                return LocationSearchSuggestion(
                    title: poi.name,
                    subtitle: subtitle,
                    value: poi.name
                )
            }

            return Array(suggestions.prefix(24))
        }

        return Array(allLocationSuggestions.prefix(18).map { title in
            LocationSearchSuggestion(
                title: title,
                subtitle: locationSuggestionSubtitle(for: title),
                value: title
            )
        })
    }

    private func mergedSearchNearbyPlaces(userCoordinate: CLLocationCoordinate2D) -> [NearbyPlace] {
        var merged: [NearbyPlace] = nearbyPlaces
        merged.append(contentsOf: firestorePOISearchResults.map { poi in
            NearbyPlace(
                id: poi.id,
                name: poi.name,
                category: poi.category,
                latitude: poi.latitude,
                longitude: poi.longitude
            )
        })

        let query = locationSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var seen = Set<String>()
        let deduped = merged.filter { place in
            let key = "\(Self.normalizedLocationRealm(place.name))|\(place.latitude)|\(place.longitude)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }

        if query.isEmpty {
            return deduped.sorted { lhs, rhs in
                let lhsDistance = NearbyPlaceLoader.haversineMiles(
                    from: userCoordinate,
                    to: CLLocationCoordinate2D(latitude: lhs.latitude, longitude: lhs.longitude)
                )
                let rhsDistance = NearbyPlaceLoader.haversineMiles(
                    from: userCoordinate,
                    to: CLLocationCoordinate2D(latitude: rhs.latitude, longitude: rhs.longitude)
                )
                return lhsDistance < rhsDistance
            }
        }

        let scored = deduped.map { place -> (place: NearbyPlace, score: Double) in
            let lowerName = place.name.lowercased()
            let lowerCategory = place.category.lowercased()
            let distance = NearbyPlaceLoader.haversineMiles(
                from: userCoordinate,
                to: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
            )

            var score = 0.0
            if lowerName == query { score += 1000 }
            if lowerName.hasPrefix(query) { score += 300 }
            if lowerName.contains(query) { score += 160 }
            if lowerCategory.contains(query) { score += 60 }
            score += max(0, 240 - distance * 16)
            return (place, score)
        }
        .filter { $0.score > 0 }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let lhsDistance = NearbyPlaceLoader.haversineMiles(
                from: userCoordinate,
                to: CLLocationCoordinate2D(latitude: lhs.place.latitude, longitude: lhs.place.longitude)
            )
            let rhsDistance = NearbyPlaceLoader.haversineMiles(
                from: userCoordinate,
                to: CLLocationCoordinate2D(latitude: rhs.place.latitude, longitude: rhs.place.longitude)
            )
            return lhsDistance < rhsDistance
        }

        return scored.map(\.place)
    }

    private func locationSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items, id: \.self) { item in
                        Button {
                            applyLocationSelection(item, context: .feed)
                            if !recentLocations.contains(item) {
                                recentLocations.insert(item, at: 0)
                                if recentLocations.count > 6 {
                                    recentLocations.removeLast()
                                }
                                persistRecentLocations()
                            }
                            currentScreen = .home
                        } label: {
                            Text(item)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .clipShape(Capsule())
                                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private var userProfileDetailView: some View {
        let resolvedProfile: FakeUserProfile
        if let selected = selectedUserProfile {
            resolvedProfile = selected
        } else if let firstProfile = fakeUserProfiles.first {
            resolvedProfile = firstProfile
        } else {
            resolvedProfile = fallbackProfile(for: profileUsername.isEmpty ? "you" : profileUsername, displayName: profileName.isEmpty ? "You" : profileName)
        }

        let profile = resolvedProfile
        let resolvedCurrentUserID = currentUserID.isEmpty ? (try? FirebaseSpotService.shared.currentUserID()) ?? "" : currentUserID
        let profilePosts = posts.filter {
            let include = Self.shouldIncludePostInViewedProfile(
                $0,
                viewedUsername: profile.username,
                signedInUsername: profileUsername,
                currentUserID: resolvedCurrentUserID
            )
            return include && !reportedPostIds.contains($0.id)
        }
        let showUserProfileSparseState = profilePosts.count <= 1

        return GeometryReader { container in
            let userProfileBodyMinHeight = max(320, container.size.height - Self.sparseProfileBottomInset)

            ZStack(alignment: .bottom) {
                Color(red: 0.93, green: 0.93, blue: 0.93)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        userProfileHeaderView(profile: profile)

                        VStack(alignment: .leading, spacing: 14) {
                            userProfilePostsView(profile: profile, profilePosts: profilePosts)

                            if showUserProfileSparseState {
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .frame(minHeight: showUserProfileSparseState ? userProfileBodyMinHeight : 0, alignment: .top)
                        .background(Color.white)

                        if showUserProfileSparseState {
                            Rectangle()
                                .fill(Color(red: 0.93, green: 0.93, blue: 0.93))
                                .frame(height: Self.bottomSilverEndCapHeight)
                        }
                    }
                    .padding(.bottom, 120)
                }

                floatingHomeActions
                    .padding(.bottom, 12)
                    .padding(.horizontal, 18)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    let isHorizontalSwipe = abs(horizontal) > abs(vertical)
                    if isHorizontalSwipe && horizontal > 70 {
                        closeUserProfileScreen()
                    }
                }
        )
        .task(id: selectedUserProfile?.userID ?? "") {
            let targetID = await MainActor.run {
                selectedUserProfile?.userID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            guard !targetID.isEmpty else {
                await MainActor.run {
                    stopSelectedUserProfileLiveListener()
                }
                return
            }

            await MainActor.run {
                startSelectedUserProfileLiveListener(for: targetID)
            }
            await refreshSelectedUserProfileFromRecord(expectedUserID: targetID)
        }
        .onDisappear {
            stopSelectedUserProfileLiveListener()
        }
    }

    private func userProfileHeaderView(profile: FakeUserProfile) -> some View {
        let isFollowingProfile = isUserFollowed(authorUserID: profile.userID, username: profile.username)
        let isOwnViewedProfile = isOwnProfile(profile)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    if let remoteURL = URL(string: profile.profilePhotoURL ?? ""),
                       !(profile.profilePhotoURL ?? "").isEmpty {
                        AsyncImage(url: remoteURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 78, height: 78)
                                    .clipShape(Circle())
                            default:
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 78, height: 78)

                                profileAvatarText(profile.profilePhotoText, size: 22, circleSize: 78)
                                    .frame(width: 78, height: 78)
                            }
                        }
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 78, height: 78)

                        profileAvatarText(profile.profilePhotoText, size: 22, circleSize: 78)
                            .frame(width: 78, height: 78)
                    }
                }
                .frame(width: 78, height: 78)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.13), lineWidth: 0.9)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.75), lineWidth: 0.55)
                        .padding(0.8)
                )
                .shadow(color: Color.black.opacity(0.07), radius: 7, x: 0, y: 3)
                .padding(.leading, 15)

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name.isEmpty ? "User" : profile.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    usernameText(profile.username)
                }

                Spacer()
            }
            .padding(.top, -4)

            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                    Text(formatFollowerCount(profile.followerCount))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.black)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minWidth: 120, alignment: .leading)
                .background(profileControlChrome(cornerRadius: 16))

                Button {
                    openDM(with: profile)
                } label: {
                    Image(systemName: "message")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.black)
                        .frame(width: 52, height: 52)
                        .background(profileControlChrome(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                if !isOwnViewedProfile {
                    Button {
                        toggleFollowState(for: profile)
                    } label: {
                        ZStack {
                            if isFollowingProfile {
                                Text("Following")
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.92).combined(with: .opacity),
                                        removal: .scale(scale: 1.08).combined(with: .opacity)
                                    ))
                            } else {
                                Text("Follow")
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.92).combined(with: .opacity),
                                        removal: .scale(scale: 1.08).combined(with: .opacity)
                                    ))
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 108, height: 52)
                        .foregroundStyle(.black)
                        .background(profileControlChrome(cornerRadius: 16))
                        .animation(.spring(response: 0.24, dampingFraction: 0.8), value: isFollowingProfile)
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.18, dampingFraction: 0.85), value: isFollowingProfile)
                }
            }
            .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, -2)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(Color(red: 0.93, green: 0.93, blue: 0.93))
        .overlay(
            Rectangle()
                .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.09))
                .frame(height: 0.6)
                .padding(.horizontal, 8)
        }
        .clipShape(Rectangle())
    }

    private func userProfilePostsView(profile: FakeUserProfile, profilePosts: [MockPost]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 12) {
                    ForEach(profilePosts, id: \.id) { post in
                        let binding = Binding<MockPost>(
                            get: { 
                                posts.first(where: { $0.id == post.id }) ?? post
                            },
                            set: { updatedPost in
                                if let index = posts.firstIndex(where: { $0.id == post.id }) {
                                    posts[index] = updatedPost
                                }
                            }
                        )
                        PostCardView(
                            post: binding,
                            isOwnPost: Self.isPostOwnedByUser(post, currentUserID: currentUserID, currentUsername: profileUsername),
                            currentUserProfilePhotoImage: displayProfilePhotoImage,
                            showsAuthorLine: false,
                            showProfileLocationBadge: false,
                            isReported: reportedPostIds.contains(post.id),
                            onSend: {
                                selectedSendRecipient = nil
                                currentScreen = .messages
                            },
                            onSave: { savedPost in
                                toggleSavedState(for: savedPost)
                            },
                            onDelete: {
                                deletePost(post)
                            },
                            onReport: {
                                reportPost(post)
                            },
                            onProfileTap: {
                                openUserProfile(from: post)
                            },
                            onMessageTap: {
                                let matchingUser = fakeUserProfiles.first(where: { $0.username.lowercased() == post.handle.lowercased() })
                                    ?? fallbackProfile(for: post.handle, displayName: post.author, userID: post.authorUserID, profilePhotoURL: post.authorProfilePhotoURL)
                                openDM(with: matchingUser)
                            },
                            onViewTracked: { updatedPost in
                                applyTrackedPostViewUpdate(updatedPost)
                            }
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 0)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var savedFeedForCurrentUser: [MockPost] {
        posts.filter { $0.isSaved && !reportedPostIds.contains($0.id) }
    }

    private var anonymousPostsFeedForCurrentUser: [MockPost] {
        posts.filter { $0.isAnonymous && !reportedPostIds.contains($0.id) }
    }

    private var anonymousPostsView: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        backButton(destination: .settings)
                        Spacer()
                        Color.clear.frame(width: 28, height: 28)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                    let items = anonymousPostsFeedForCurrentUser

                    if items.isEmpty {
                        Text("No anonymous posts yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(items, id: \ .id) { post in
                                let binding = Binding<MockPost>(
                                    get: { post },
                                    set: { _ in }
                                )

                                PostCardView(
                                    post: binding,
                                    isOwnPost: Self.isPostOwnedByUser(post, currentUserID: currentUserID, currentUsername: profileUsername),
                                    currentUserProfilePhotoImage: displayProfilePhotoImage,
                                    isReported: reportedPostIds.contains(post.id),
                                    onSend: {
                                        sharePostToFriends(post)
                                    },
                                    onSave: { savedPost in
                                        toggleSavedState(for: savedPost)
                                    },
                                    onDelete: {
                                        deletePost(post)
                                    },
                                    onReport: {
                                        reportPost(post)
                                    },
                                    onProfileTap: {
                                        openUserProfile(from: post)
                                    },
                                    onMessageTap: {
                                        let matchingUser = fakeUserProfiles.first(where: { $0.username.lowercased() == post.handle.lowercased() })
                                            ?? fallbackProfile(for: post.handle, displayName: post.author, userID: post.authorUserID, profilePhotoURL: post.authorProfilePhotoURL)
                                        openDM(with: matchingUser)
                                    },
                                    onViewTracked: { updatedPost in
                                        applyTrackedPostViewUpdate(updatedPost)
                                    }
                                )
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 110)
                    }
                }
            }

            floatingHomeActions
                .padding(.bottom, 12)
                .padding(.horizontal, 18)
        }
    }

    private var savedPostsView: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        backButton(destination: .settings)
                        Spacer()
                        Color.clear.frame(width: 28, height: 28)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                    let items = savedFeedForCurrentUser

                    if items.isEmpty {
                        Text("No saved posts yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(items, id: \.id) { post in
                                let binding = Binding<MockPost>(
                                    get: { post },
                                    set: { _ in }
                                )

                                PostCardView(
                                    post: binding,
                                    isOwnPost: Self.isPostOwnedByUser(post, currentUserID: currentUserID, currentUsername: profileUsername),
                                    currentUserProfilePhotoImage: displayProfilePhotoImage,
                                    isReported: reportedPostIds.contains(post.id),
                                    onSend: {
                                        sharePostToFriends(post)
                                    },
                                    onSave: { savedPost in
                                        toggleSavedState(for: savedPost)
                                    },
                                    onDelete: {
                                        deletePost(post)
                                    },
                                    onReport: {
                                        reportPost(post)
                                    },
                                    onProfileTap: {
                                        openUserProfile(from: post)
                                    },
                                    onMessageTap: {
                                        let matchingUser = fakeUserProfiles.first(where: { $0.username.lowercased() == post.handle.lowercased() })
                                            ?? fallbackProfile(for: post.handle, displayName: post.author, userID: post.authorUserID, profilePhotoURL: post.authorProfilePhotoURL)
                                        openDM(with: matchingUser)
                                    },
                                    onViewTracked: { updatedPost in
                                        applyTrackedPostViewUpdate(updatedPost)
                                    }
                                )
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 110)
                    }
                }
            }

            floatingHomeActions
                .padding(.bottom, 12)
                .padding(.horizontal, 18)
        }
    }

    private var profileView: some View {
        let cachedProfile = fakeUserProfiles.first(where: { $0.username.lowercased() == profileUsername.lowercased() })
        let currentProfile = FakeUserProfile(
            id: cachedProfile?.id ?? UUID(),
            userID: cachedProfile?.userID ?? currentUserID,
            username: cachedProfile?.username ?? (profileUsername.isEmpty ? "you" : (profileUsername.hasPrefix("@") ? String(profileUsername.dropFirst()) : profileUsername)),
            name: cachedProfile?.name ?? (profileUsername.isEmpty ? "You" : profileUsername),
            city: cachedProfile?.city ?? "Tokyo, Japan",
            bio: cachedProfile?.bio ?? "",
            followerCount: currentUserFollowerCount,
            followingCount: currentUserFollowingCount,
            profilePhotoText: cachedProfile?.profilePhotoText ?? profilePhotoText,
            profilePhotoURL: cachedProfile?.profilePhotoURL
        )
        let resolvedCurrentUserID = currentUserID.isEmpty ? (try? FirebaseSpotService.shared.currentUserID()) ?? "" : currentUserID
        let yourPosts = posts.filter {
            let include = Self.shouldIncludePostInViewedProfile(
                $0,
                viewedUsername: profileUsername,
                signedInUsername: profileUsername,
                currentUserID: resolvedCurrentUserID
            )
            return include && !reportedPostIds.contains($0.id)
        }
        let showOwnProfileSparseState = yourPosts.count <= 1

        return GeometryReader { container in
            let ownProfileBodyMinHeight = max(320, container.size.height - Self.sparseProfileBottomInset)

            ZStack(alignment: .bottom) {
                Color(red: 0.93, green: 0.93, blue: 0.93)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 16) {
                            Button {
                                currentScreen = .settings
                            } label: {
                                profileAvatarView(size: 78, textSize: 24)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 15)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(profileName.isEmpty ? "You" : profileName)
                                    .font(.title3.weight(.semibold))
                                Text(displayUsername(profileUsername))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                        }
                        .padding(.top, -4)

                        HStack(alignment: .center, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.2.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.black)
                                Text(formatFollowerCount(currentProfile.followerCount))
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.black)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minWidth: 120, alignment: .leading)
                            .background(profileControlChrome(cornerRadius: 16))

                            Button {
                                currentScreen = .messages
                            } label: {
                                Image(systemName: "message")
                                    .font(.title3.weight(.heavy))
                                    .foregroundStyle(.black)
                                    .frame(width: 52, height: 52)
                                    .background(profileControlChrome(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 18)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, -2)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 8)
                    .background(Color(red: 0.93, green: 0.93, blue: 0.93))
                    .overlay(
                        Rectangle()
                            .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                    )
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.black.opacity(0.09))
                            .frame(height: 0.6)
                            .padding(.horizontal, 8)
                    }
                    .clipShape(Rectangle())

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(spacing: 12) {
                            ForEach(yourPosts, id: \.id) { post in
                                let binding = Binding<MockPost>(
                                    get: {
                                        posts.first(where: { $0.id == post.id }) ?? post
                                    },
                                    set: { updatedPost in
                                        if let index = posts.firstIndex(where: { $0.id == post.id }) {
                                            posts[index] = updatedPost
                                        }
                                    }
                                )

                                PostCardView(
                                    post: binding,
                                    isOwnPost: Self.isPostOwnedByUser(post, currentUserID: currentUserID, currentUsername: profileUsername),
                                    currentUserProfilePhotoImage: displayProfilePhotoImage,
                                    showsAuthorLine: false,
                                    showProfileLocationBadge: false,
                                    isReported: reportedPostIds.contains(post.id),
                                    onSend: {
                                        sharePostToFriends(post)
                                    },
                                    onSave: { savedPost in
                                        toggleSavedState(for: savedPost)
                                    },
                                    onDelete: {
                                        deletePost(post)
                                    },
                                    onReport: {
                                        reportPost(post)
                                    },
                                    onProfileTap: {
                                        openUserProfile(from: post)
                                    },
                                    onMessageTap: {
                                        let matchingUser = fakeUserProfiles.first(where: { $0.username.lowercased() == post.handle.lowercased() })
                                            ?? fallbackProfile(for: post.handle, displayName: post.author, userID: post.authorUserID, profilePhotoURL: post.authorProfilePhotoURL)
                                        openDM(with: matchingUser)
                                    },
                                    onViewTracked: { updatedPost in
                                        applyTrackedPostViewUpdate(updatedPost)
                                    }
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 0)
                            }
                        }

                        if showOwnProfileSparseState {
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(minHeight: showOwnProfileSparseState ? ownProfileBodyMinHeight : 0, alignment: .top)
                    .background(Color.white)

                    if showOwnProfileSparseState {
                        Rectangle()
                            .fill(Color(red: 0.93, green: 0.93, blue: 0.93))
                            .frame(height: Self.bottomSilverEndCapHeight)
                    }
                    }
                    .padding(.bottom, 120)
                }

                floatingHomeActions
                    .padding(.bottom, 12)
                    .padding(.horizontal, 18)
            }
        }
    }

    private var selectedPostDetailView: some View {
        let post = selectedProfilePost ?? posts.first ?? MockPost(
            id: 0,
            author: "You",
            handle: "you",
            type: "Photo",
            location: "Tokyo, Japan",
            title: "Spot moment",
            body: "A moment worth keeping.",
            url: "spot.example",
            accent: "#DCE7FF",
            tag: "Photo",
            likes: 0,
            isLiked: false,
            comments: [],
            sentTo: []
        )
        let backDestination: Screen = selectedProfilePost != nil ? .profile : .home
        let hidesAuthorForOwnProfilePost = backDestination == .profile
            && Self.isPostOwnedByUser(post, currentUserID: currentUserID, currentUsername: profileUsername)

        return ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    HStack {
                        backButton(destination: backDestination)
                        Spacer()
                    }

                    Text("Post")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                PostCardView(
                    post: Binding(
                        get: { post },
                        set: { _ in }
                    ),
                    isOwnPost: Self.isPostOwnedByUser(post, currentUserID: currentUserID, currentUsername: profileUsername),
                    currentUserProfilePhotoImage: displayProfilePhotoImage,
                    showsAuthorLine: !hidesAuthorForOwnProfilePost,
                    showProfileLocationBadge: hidesAuthorForOwnProfilePost,
                    isReported: reportedPostIds.contains(post.id),
                    onSend: {
                        sharePostToFriends(post)
                    },
                    onSave: { savedPost in
                        toggleSavedState(for: savedPost)
                    },
                    onDelete: {
                        deletePost(post)
                    },
                    onReport: {
                        reportPost(post)
                    },
                    onProfileTap: {
                        let resolvedProfile = fakeUserProfiles.first(where: { $0.username.lowercased() == post.handle.lowercased() })
                            ?? fallbackProfile(for: post.handle, displayName: post.author, userID: post.authorUserID, profilePhotoURL: post.authorProfilePhotoURL)
                        openUserProfileScreen(with: resolvedProfile)
                    },
                    onMessageTap: {
                        let resolvedProfile = selectedUserProfile ?? fakeUserProfiles.first ?? fallbackProfile(for: post.handle, displayName: post.author, userID: post.authorUserID, profilePhotoURL: post.authorProfilePhotoURL)
                        openDM(with: resolvedProfile)
                    },
                    onViewTracked: { updatedPost in
                        applyTrackedPostViewUpdate(updatedPost)
                    }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 100)

                Spacer()
            }

            floatingHomeActions
                .padding(.bottom, 12)
                .padding(.horizontal, 18)
        }
    }

    private func settingsRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func purchaseBoostPack(_ pack: (posts: Int, price: Double, label: String)) {
        remainingBoosts = min(3, remainingBoosts + pack.posts)
        UserDefaults.standard.set(remainingBoosts, forKey: "spot_remaining_boosts")
        activeSettingsEditor = nil
    }

    private func consumeBoostIfAvailable() -> Bool {
        guard remainingBoosts > 0 else { return false }
        remainingBoosts -= 1
        UserDefaults.standard.set(max(0, remainingBoosts), forKey: "spot_remaining_boosts")
        return true
    }

    private func settingsActionRow(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.primary)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var blockUsersSearchResults: [String] {
        let query = blockedUserSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidateNames = (fakeUserProfiles.map { $0.username } + communityUsers.map { $0.username } + [profileUsername])
            .filter { !$0.isEmpty }
            .map { $0.hasPrefix("@") ? String($0.dropFirst()) : $0 }
            .filter { candidate in
                !blockedUsers.contains { blocked in
                    blocked.lowercased() == candidate.lowercased()
                }
            }

        guard !query.isEmpty else {
            return Array(Set(candidateNames).prefix(8))
        }

        return Array(Set(candidateNames).filter { candidate in
            candidate.lowercased().contains(query)
        }.prefix(8))
    }

    private func blockUser(_ username: String) {
        let cleaned = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let normalized = cleaned.hasPrefix("@") ? String(cleaned.dropFirst()) : cleaned
        guard !blockedUsers.contains(where: { $0.lowercased() == normalized.lowercased() }) else { return }

        blockedUsers.insert(normalized, at: 0)
        UserDefaults.standard.set(blockedUsers, forKey: "spot_blocked_users")
        blockedUserSearchText = ""
    }

    private func unblockUser(_ username: String) {
        blockedUsers.removeAll { $0.lowercased() == username.lowercased() }
        UserDefaults.standard.set(blockedUsers, forKey: "spot_blocked_users")
    }

    private func blockUsersEditorView() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Block Users")
                    .font(.title3.weight(.semibold))

                Text("Search for users and block them from your feed and interactions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Search by username", text: $blockedUserSearchText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if !blockedUserSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Search results")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if blockUsersSearchResults.isEmpty {
                            Text("No users found")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(blockUsersSearchResults, id: \ .self) { user in
                                Button {
                                    blockUser(user)
                                } label: {
                                    HStack(alignment: .center, spacing: 12) {
                                        Circle()
                                            .fill(LinearGradient(colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(width: 34, height: 34)
                                            .overlay(Text(String(user.prefix(2)).uppercased()).font(.caption.weight(.bold)).foregroundStyle(.black))

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(displayUsername(user))
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Text(displayUsername(user))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()
                                        Text("Block")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 10)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Blocked users")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if blockedUsers.isEmpty {
                        Text("No users blocked yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(blockedUsers, id: \ .self) { user in
                            HStack(alignment: .center, spacing: 12) {
                                Circle()
                                    .fill(LinearGradient(colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 34, height: 34)
                                    .overlay(Text(String(user.prefix(2)).uppercased()).font(.caption.weight(.bold)).foregroundStyle(.black))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(displayUsername(user))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(displayUsername(user))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                                Button {
                                    unblockUser(user)
                                } label: {
                                    Text("Unblock")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity)
    }

    private func boostNextPostsEditorView() -> some View {
        let boostPacks = [
            (posts: 1, price: 0.99, label: "Single post"),
            (posts: 2, price: 1.49, label: "Two-post pack"),
            (posts: 3, price: 1.99, label: "Three-post pack")
        ]

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Boost Next Posts")
                    .font(.title3.weight(.semibold))

                Text("Give your next posts a bigger push with affordable boost packs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(boostPacks, id: \ .posts) { pack in
                        Button {
                            purchaseBoostPack(pack)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(pack.posts) post\(pack.posts == 1 ? "" : "s")")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(pack.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("$\(String(format: "%.2f", pack.price))")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(.primary)
                                    Text(String(format: "$%.2f/post", pack.price / Double(pack.posts)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                LinearGradient(
                                    colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Why boost?")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Boosted posts rise higher in the feed and get more visibility for the next posts you publish.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
        }
    }

    private func bulkDeletePostsEditorView() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Hard reset platform posts")
                    .font(.title3.weight(.semibold))

                Text("This permanently removes every post currently stored on the platform. This action is destructive and should only be used as a last resort.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !platformBulkDeleteError.isEmpty {
                    Text(platformBulkDeleteError)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }

                Button {
                    Task {
                        isBulkDeletingPosts = true
                        platformBulkDeleteError = ""
                        do {
                            try await FirebaseSpotService.shared.deleteAllPosts()
                            posts = []
                            selectedProfilePost = nil
                            pendingSharePost = nil
                            reportedPostIds.removeAll()
                            activeSettingsEditor = nil
                        } catch {
                            platformBulkDeleteError = "Reset failed: \(error.localizedDescription)"
                        }
                        isBulkDeletingPosts = false
                    }
                } label: {
                    Text(isBulkDeletingPosts ? "Resetting…" : "Delete all posts on platform")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isBulkDeletingPosts ? Color.gray : Color.red)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isBulkDeletingPosts)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
        }
    }

    private func refreshUsernameAvailabilityStatus() {
        let cleaned = profileUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = FirebaseSpotService.normalizeUsername(cleaned)

        guard !cleaned.isEmpty else {
            usernameAvailabilityMessage = "Choose a username"
            usernameAvailabilityIsAvailable = false
            isCheckingUsernameAvailability = false
            return
        }

        guard FirebaseSpotService.isValidUsername(normalized) else {
            usernameAvailabilityMessage = "Taken or invalid"
            usernameAvailabilityIsAvailable = false
            isCheckingUsernameAvailability = false
            return
        }

        isCheckingUsernameAvailability = true
        usernameAvailabilityMessage = "Checking…"

        Task {
            do {
                let available = try await FirebaseSpotService.shared.checkUsernameAvailability(username: cleaned)
                await MainActor.run {
                    usernameAvailabilityIsAvailable = available
                    usernameAvailabilityMessage = available ? "Available" : "Taken or invalid"
                    isCheckingUsernameAvailability = false
                }
            } catch {
                await MainActor.run {
                    usernameAvailabilityIsAvailable = false
                    usernameAvailabilityMessage = "Check failed"
                    isCheckingUsernameAvailability = false
                }
            }
        }
    }

    private func settingsDetailSheet(for editor: SettingsEditor) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        activeSettingsEditor = nil
                    }

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Spacer()
                            Button {
                                activeSettingsEditor = nil
                            } label: {
                                Circle()
                                    .fill(Color.black.opacity(0.08))
                                    .frame(width: 32, height: 32)
                                    .overlay(Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.primary))
                            }
                        }

                        Group {
                            switch editor {
                            case .username:
                                usernameEditorView()
                            case .searchUsers:
                                searchUsersEditorView()
                            case .name:
                                nameEditorView()
                            case .photo:
                                profileTextEditorView()
                            case .accountInfo:
                                accountInfoEditorView()
                            case .locationAlerts:
                                locationAlertsEditorView()
                            case .blockUsers:
                                blockUsersEditorView()
                            case .boostNextPosts:
                                boostNextPostsEditorView()
                            case .bulkDeletePosts:
                                bulkDeletePostsEditorView()
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 380, maxHeight: min(geometry.size.height * 0.92, 820), alignment: .topLeading)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 21, x: 0, y: 12)
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func usernameEditorView() -> some View {
        let normalizedInput = FirebaseSpotService.normalizeUsername(profileUsername)
        let normalizedSaved = FirebaseSpotService.normalizeUsername(accountUsername)
        let canSaveUsername = isSignedInToAccount
            && FirebaseSpotService.isAllowedUsername(normalizedInput, reservedAgainst: normalizedSaved)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Username")
                .font(.title3.weight(.semibold))
            Text("Choose a unique handle people will see in your profile and posts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !isSignedInToAccount {
                Text("Sign up first to claim a username.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            TextField("@username", text: Binding(
                get: { profileUsername },
                set: { profileUsername = capUsernameInput($0) }
            ))
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onChange(of: profileUsername) { _, _ in
                refreshUsernameAvailabilityStatus()
            }

            Text(usernameAvailabilityMessage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(usernameAvailabilityIsAvailable && !isCheckingUsernameAvailability ? .green : .red)

            Button {
                Task { await persistCurrentUsername() }
            } label: {
                Text(isSignedInToAccount ? "Save username" : "Sign up to save username")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        canSaveUsername
                            ? Color.black
                            : Color.gray.opacity(0.35)
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSaveUsername)
        }
    }

    private var selectedSavedAccount: SavedAccountCredential? {
        let selected = selectedSavedAccountEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !selected.isEmpty else { return nil }
        return savedAccounts.first(where: { $0.id == selected })
    }

    private static func loadSavedAccountsFromDefaults() -> [SavedAccountCredential] {
        guard let data = UserDefaults.standard.data(forKey: "spot_saved_accounts") else {
            return []
        }

        do {
            let decoded = try JSONDecoder().decode([SavedAccountCredential].self, from: data)
            return decoded
                .filter { FirebaseSpotService.isValidEmail($0.email.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .sorted { $0.lastUsedAt > $1.lastUsedAt }
        } catch {
            return []
        }
    }

    private func persistSavedAccounts() {
        do {
            let data = try JSONEncoder().encode(savedAccounts)
            UserDefaults.standard.set(data, forKey: savedAccountsDefaultsKey)
        } catch {
            UserDefaults.standard.removeObject(forKey: savedAccountsDefaultsKey)
        }
    }

    private func upsertSavedAccount(email: String, username: String, displayName: String) {
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard FirebaseSpotService.isValidEmail(cleanedEmail) else {
            return
        }

        let cleanedUsername = FirebaseSpotService.normalizeUsername(username)
        let fallbackUsername = FirebaseSpotService.normalizeUsername(cleanedEmail.components(separatedBy: "@").first ?? "user")
        let resolvedUsername = cleanedUsername.isEmpty ? (fallbackUsername.isEmpty ? "user" : fallbackUsername) : cleanedUsername

        let cleanedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDisplayName = cleanedDisplayName.isEmpty ? resolvedUsername : cleanedDisplayName

        savedAccounts.removeAll { $0.id == cleanedEmail }
        savedAccounts.insert(
            SavedAccountCredential(
                email: cleanedEmail,
                username: resolvedUsername,
                displayName: resolvedDisplayName,
                lastUsedAt: Date().timeIntervalSince1970
            ),
            at: 0
        )

        if savedAccounts.count > 12 {
            savedAccounts = Array(savedAccounts.prefix(12))
        }

        selectedSavedAccountEmail = cleanedEmail
        persistSavedAccounts()
    }

    private func removeSavedAccount(_ account: SavedAccountCredential) {
        savedAccounts.removeAll { $0.id == account.id }
        if selectedSavedAccountEmail == account.id {
            selectedSavedAccountEmail = ""
        }
        persistSavedAccounts()
    }

    private func selectSavedAccount(_ account: SavedAccountCredential) {
        selectedSavedAccountEmail = account.id
        accountEmail = account.email
        accountUsername = account.username
        if profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profileName = account.displayName
        }
        accountPassword = ""
        accountAuthMessage = "Saved account selected. Enter password to continue."
    }

    private func quickSignInSavedAccount() async {
        guard let selected = selectedSavedAccount else {
            await MainActor.run {
                accountAuthMessage = "Select an account first."
            }
            return
        }

        await signInWithEmailPassword(email: selected.email, password: accountPassword)
    }

    private func resolvedAccountIdentityForEmail(_ email: String) -> (username: String, displayName: String) {
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fallbackUsername = FirebaseSpotService.normalizeUsername(
            cleanedEmail.components(separatedBy: "@").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "user"
        )
        let resolvedUsername = fallbackUsername.isEmpty ? "user" : fallbackUsername
        let resolvedDisplayName = profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? resolvedUsername
            : profileName
        return (resolvedUsername, resolvedDisplayName)
    }

    private func finishSuccessfulEmailAuth(
        user: User,
        email: String,
        password: String,
        fallbackUsername: String,
        fallbackDisplayName: String,
        successMessage: String
    ) async {
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let persistedProfileName = UserDefaults.standard.string(forKey: profileNameDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let persistedProfilePhoto = Self.cachedImage(forKey: profilePhotoDefaultsKey)
        let restoredProfileName = persistedProfileName.isEmpty ? fallbackDisplayName : persistedProfileName

        await MainActor.run {
            accountEmail = cleanedEmail
            accountUsername = fallbackUsername
            profileUsername = fallbackUsername
            profileName = restoredProfileName
            if let persistedPhoto = persistedProfilePhoto {
                profilePhotoImage = persistedPhoto
                profilePhotoPreviewImage = persistedPhoto
                pendingProfilePhotoSelection = nil
                profilePhotoText = ""
            }
            UserDefaults.standard.set(fallbackUsername, forKey: accountUsernameDefaultsKey)
            UserDefaults.standard.set(restoredProfileName, forKey: profileNameDefaultsKey)
            UserDefaults.standard.set(cleanedEmail, forKey: accountEmailDefaultsKey)
            UserDefaults.standard.set(cleanedPassword, forKey: accountPasswordDefaultsKey)
            UserDefaults.standard.set(true, forKey: accountSignedInDefaultsKey)
            isSignedInToAccount = true
            accountAuthMessage = successMessage
            persistResolvedUserID(user.uid)
            upsertSavedAccount(email: cleanedEmail, username: fallbackUsername, displayName: restoredProfileName)
        }

        await loadCurrentUserProfileFromRecord()
        await refreshFollowingUIDs()

        await MainActor.run {
            let syncedUsername = profileUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            let syncedDisplayName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
            upsertSavedAccount(
                email: cleanedEmail,
                username: syncedUsername.isEmpty ? fallbackUsername : syncedUsername,
                displayName: syncedDisplayName.isEmpty ? restoredProfileName : syncedDisplayName
            )
        }
    }

    private func createAccountWithEmailPassword(email: String, password: String) async {
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = resolvedAccountIdentityForEmail(cleanedEmail)

        do {
            let user = try await FirebaseSpotService.shared.signUp(
                email: cleanedEmail,
                password: cleanedPassword,
                username: identity.username,
                displayName: identity.displayName,
                bio: nil,
                photoURL: nil
            )

            do {
                try await FirebaseSpotService.shared.sendWelcomeEmailToCurrentUser()
            } catch {
                // Account creation remains successful even if welcome email backend is unavailable.
            }

            do {
                try await FirebaseSpotService.shared.migrateLegacyPostsForUser(
                    userID: user.uid,
                    username: FirebaseSpotService.normalizeUsername(identity.username),
                    displayName: identity.displayName,
                    photoURL: profilePhotoRemoteURL.isEmpty ? nil : profilePhotoRemoteURL
                )
            } catch {
                print("Spot legacy post migration warning: \(error)")
            }

            await finishSuccessfulEmailAuth(
                user: user,
                email: cleanedEmail,
                password: cleanedPassword,
                fallbackUsername: identity.username,
                fallbackDisplayName: identity.displayName,
                successMessage: "Account created. You're signed in."
            )

            await MainActor.run {
                accountAuthMessage = "Account created. Check your email to verify."
            }
        } catch {
            let nsError = error as NSError
            let authCode = AuthErrorCode(rawValue: nsError.code)

            if authCode == .emailAlreadyInUse {
                await MainActor.run {
                    accountAuthMessage = "Account already exists. Use Continue to sign in."
                }
                return
            }

            await MainActor.run {
                accountAuthMessage = "Couldn't create account. Try again."
            }
        }
    }

    private func continueWithEmailPassword() async {
        let cleanedEmail = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanedPassword = accountPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard FirebaseSpotService.isValidEmail(cleanedEmail) else {
            await MainActor.run { accountAuthMessage = "Enter a valid email." }
            return
        }

        guard FirebaseSpotService.isStrongPassword(cleanedPassword) else {
            await MainActor.run { accountAuthMessage = "Password must be at least 6 characters." }
            return
        }

        do {
            let user = try await FirebaseSpotService.shared.signIn(email: cleanedEmail, password: cleanedPassword)
            do {
                try await FirebaseSpotService.shared.sendWelcomeEmailToCurrentUser()
            } catch {
                // Keep sign-in successful even if welcome email backend is unavailable.
            }

            let identity = resolvedAccountIdentityForEmail(cleanedEmail)
            await finishSuccessfulEmailAuth(
                user: user,
                email: cleanedEmail,
                password: cleanedPassword,
                fallbackUsername: identity.username,
                fallbackDisplayName: identity.displayName,
                successMessage: "You're signed in."
            )
        } catch {
            let nsError = error as NSError
            let authCode = AuthErrorCode(rawValue: nsError.code)

            if authCode == .userNotFound {
                await createAccountWithEmailPassword(email: cleanedEmail, password: cleanedPassword)
                return
            }

            if authCode == .wrongPassword || authCode == .invalidCredential || authCode == .tooManyRequests {
                await MainActor.run {
                    accountAuthMessage = "Password is incorrect. Try again or reset it."
                }
                return
            }

            await MainActor.run {
                accountAuthMessage = "Couldn't continue. Check your info and try again."
            }
        }
    }

    private func signInWithEmailPassword(email: String, password: String) async {
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard FirebaseSpotService.isValidEmail(cleanedEmail) else {
            await MainActor.run { accountAuthMessage = "Enter a valid email." }
            return
        }

        guard FirebaseSpotService.isStrongPassword(cleanedPassword) else {
            await MainActor.run { accountAuthMessage = "Password must be at least 6 characters." }
            return
        }

        do {
            let user = try await FirebaseSpotService.shared.signIn(email: cleanedEmail, password: cleanedPassword)
            do {
                try await FirebaseSpotService.shared.sendWelcomeEmailToCurrentUser()
            } catch {
                // Keep sign-in successful even if the welcome email backend is unavailable.
            }

            let identity = resolvedAccountIdentityForEmail(cleanedEmail)
            await finishSuccessfulEmailAuth(
                user: user,
                email: cleanedEmail,
                password: cleanedPassword,
                fallbackUsername: identity.username,
                fallbackDisplayName: identity.displayName,
                successMessage: "You're signed in."
            )
        } catch {
            let nsError = error as NSError
            let authCode = AuthErrorCode(rawValue: nsError.code)

            if authCode == .wrongPassword || authCode == .invalidCredential || authCode == .tooManyRequests {
                await MainActor.run {
                    accountAuthMessage = "Incorrect password. Please try again or reset your password."
                }
                return
            }

            if authCode == .userNotFound {
                await MainActor.run {
                    accountAuthMessage = "No account found for this email."
                }
                return
            }

            if authCode == .emailAlreadyInUse {
                await MainActor.run {
                    accountAuthMessage = "This email is already connected to your account. Log in with the correct password or reset it."
                }
                return
            }

            await MainActor.run {
                accountAuthMessage = "Couldn't sign in. Try again."
            }
        }
    }

    private func accountInfoEditorView() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Account")
                .font(.title3.weight(.semibold))

            if !savedAccounts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Saved accounts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(savedAccounts) { account in
                                let isSelected = selectedSavedAccountEmail == account.id
                                Button {
                                    selectSavedAccount(account)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 34, height: 34)
                                                .overlay(
                                                    Text(String(account.username.prefix(2)).uppercased())
                                                        .font(.caption.weight(.bold))
                                                        .foregroundStyle(.black)
                                                )

                                            Button {
                                                removeSavedAccount(account)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }

                                        Text(account.displayName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        Text(displayUsername(account.username))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)

                                        Text(account.email)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .padding(12)
                                    .frame(width: 180, alignment: .leading)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(isSelected ? Color.black : Color.clear, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let selected = selectedSavedAccount {
                        Text("Quick sign in: \(selected.email)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(isSignedInToAccount ? "You're signed in." : "Use email and password. Continue will sign in or create your account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isSignedInToAccount {
                Text("Signed in as \(accountEmail.isEmpty ? displayUsername(accountUsername) : accountEmail)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            TextField("Email", text: $accountEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: accountEmail) { _, newValue in
                    selectedSavedAccountEmail = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }

            SecureField("Password", text: $accountPassword)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if !accountEditorStatusMessage.isEmpty {
                Text(accountEditorStatusMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if showPasswordResetSpamNotice {
                Text("Tip: if it doesn't show in inbox, check spam/junk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isSignedInToAccount {
                Button {
                    Task {
                        do {
                            try FirebaseSpotService.shared.signOut()
                            let persistedEmail = UserDefaults.standard.string(forKey: accountEmailDefaultsKey) ?? ""
                            await MainActor.run {
                                profileUsername = ""
                                accountUsername = ""
                                accountEmail = persistedEmail
                                accountPassword = ""
                                profileName = ""
                                profilePhotoImage = nil
                                profilePhotoPreviewImage = nil
                                pendingProfilePhotoSelection = nil
                                profilePhotoText = "YO"
                                accountAuthMessage = "Signed out."
                                isSignedInToAccount = false
                                selectedSavedAccountEmail = persistedEmail.lowercased()
                                followedUserIDs = []
                                profilePhotoRemoteURL = ""
                                UserDefaults.standard.set(false, forKey: accountSignedInDefaultsKey)
                                UserDefaults.standard.removeObject(forKey: "spot_firebase_user_id")
                            }
                        } catch {
                            await MainActor.run {
                                accountAuthMessage = "Could not sign out."
                            }
                        }
                    }
                } label: {
                    Text("Sign out")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                // PRIMARY ACTION: Sign in to selected account (if one is selected)
                if selectedSavedAccount != nil {
                    Button {
                        Task {
                            await quickSignInSavedAccount()
                        }
                    } label: {
                        Text("Sign in to selected account")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.black)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                // PRIMARY ACTION: Continue (sign in or create account)
                Button {
                    Task {
                        await continueWithEmailPassword()
                    }
                } label: {
                    Text("Continue")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(accountEmail.isEmpty || accountPassword.isEmpty ? Color.gray : ContentView.appPrimaryThemeColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(accountEmail.isEmpty || accountPassword.isEmpty)

                // SECONDARY ACTION: Password reset (less prominent, below main buttons)
                Button {
                    Task {
                        let cleanedEmail = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard FirebaseSpotService.isValidEmail(cleanedEmail) else {
                            await MainActor.run {
                                accountAuthMessage = "Enter your account email first."
                                showPasswordResetSpamNotice = false
                            }
                            return
                        }

                        do {
                            _ = try await FirebaseSpotService.shared.sendPasswordReset(email: cleanedEmail)
                            await MainActor.run {
                                accountAuthMessage = "Reset email sent. Check inbox and spam."
                                showPasswordResetSpamNotice = true
                            }
                        } catch {
                            await MainActor.run {
                                accountAuthMessage = "Couldn't send reset email. Try again."
                                showPasswordResetSpamNotice = false
                            }
                        }
                    }
                } label: {
                    Text("Forgot password?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dmDirectoryCandidates: [FakeUserProfile] {
        let firestoreProfiles = firestoreUserSearchResults.map { account in
            FakeUserProfile(
                userID: account.uid,
                username: account.username,
                name: account.displayName,
                city: "",
                bio: account.bio ?? "",
                followerCount: account.followerCount,
                followingCount: account.followingCount,
                profilePhotoText: String(account.displayName.prefix(2)).uppercased(),
                profilePhotoURL: account.profilePhotoURL
            )
        }

        let candidates = (firestoreProfiles + fakeUserProfiles + communityUsers.map { profile in
            FakeUserProfile(username: profile.username, name: profile.name, city: "", bio: "", followerCount: 0, followingCount: 0, profilePhotoText: String(profile.name.prefix(2)))
        } + [
            FakeUserProfile(username: profileUsername.isEmpty ? "you" : profileUsername, name: profileName.isEmpty ? "You" : profileName, city: "", bio: "", followerCount: 0, followingCount: 0, profilePhotoText: "YO")
        ])
            .filter { profile in
                !Self.isCurrentUserDMProfile(profile, currentUsername: profileUsername)
            }
            .reduce(into: [String: FakeUserProfile]()) { result, profile in
                let key = profile.username.lowercased()
                if result[key] == nil {
                    result[key] = profile
                }
            }
            .values
            .sorted { lhs, rhs in
                lhs.username.lowercased() < rhs.username.lowercased()
            }

        return Array(candidates)
    }

    private var directMessageSuggestions: [FakeUserProfile] {
        let query = userSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty else {
            return searchedUsersResults
        }

        let candidates = dmDirectoryCandidates
        guard !candidates.isEmpty else {
            return []
        }

        if candidates.count < 5 {
            return Array(candidates.prefix(candidates.count))
        }

        if candidates.count < 50 {
            return Array(candidates.prefix(5))
        }

        return Array(candidates.shuffled().prefix(5))
    }

    private var searchedUsersResults: [FakeUserProfile] {
        let query = userSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let firestoreProfiles = firestoreUserSearchResults.map { account in
            FakeUserProfile(
                userID: account.uid,
                username: account.username,
                name: account.displayName,
                city: "",
                bio: account.bio ?? "",
                followerCount: account.followerCount,
                followingCount: account.followingCount,
                profilePhotoText: String(account.displayName.prefix(2)).uppercased(),
                profilePhotoURL: account.profilePhotoURL
            )
        }
        let candidates = (firestoreProfiles + fakeUserProfiles + communityUsers.map { profile in
            FakeUserProfile(username: profile.username, name: profile.name, city: "", bio: "", followerCount: 0, followingCount: 0, profilePhotoText: String(profile.name.prefix(2)))
        } + [
            FakeUserProfile(username: profileUsername.isEmpty ? "you" : profileUsername, name: profileName.isEmpty ? "You" : profileName, city: "", bio: "", followerCount: 0, followingCount: 0, profilePhotoText: "YO")
        ])
            .filter { profile in
                !Self.isCurrentUserDMProfile(profile, currentUsername: profileUsername)
            }
            .filter { profile in
                let matchText = "\(profile.name) \(profile.username)".lowercased()
                return query.isEmpty || matchText.contains(query)
            }

        return Array(candidates.prefix(12))
    }

    @MainActor
    private func prefetchProfilesForVisiblePostAuthors(limit: Int = 120) {
        var seen: Set<String> = []
        for post in posts.prefix(limit) where !post.isAnonymous {
            let authorID = post.authorUserID.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedHandle = FirebaseSpotService.normalizeUsername(post.handle)
            let key = !authorID.isEmpty ? "id:\(authorID)" : "u:\(normalizedHandle)"
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            prefetchRemoteAvatarIfNeeded(post.authorProfilePhotoURL)
            prefetchProfileIfNeeded(
                userID: authorID,
                username: normalizedHandle,
                displayName: post.author,
                profilePhotoURL: post.authorProfilePhotoURL
            )
        }
    }

    @MainActor
    private func cacheAndPrefetchSearchResultProfiles() {
        for account in firestoreUserSearchResults {
            let prefetched = FakeUserProfile(
                userID: account.uid,
                username: account.username,
                name: account.displayName,
                city: "",
                bio: account.bio ?? "",
                followerCount: account.followerCount,
                followingCount: account.followingCount,
                profilePhotoText: String(account.displayName.prefix(2)).uppercased(),
                profilePhotoURL: account.profilePhotoURL
            )
            cachePrefetchedProfile(prefetched)
            prefetchRemoteAvatarIfNeeded(account.profilePhotoURL)
            prefetchProfileIfNeeded(
                userID: account.uid,
                username: account.username,
                displayName: account.displayName,
                profilePhotoURL: account.profilePhotoURL
            )
        }
    }

    @MainActor
    private func prefetchBlockedUserProfiles() {
        let normalizedBlocked = Set(blockedUsers.map { FirebaseSpotService.normalizeUsername($0) }.filter { !$0.isEmpty })
        guard !normalizedBlocked.isEmpty else { return }

        for profile in fakeUserProfiles {
            let normalized = FirebaseSpotService.normalizeUsername(profile.username)
            guard normalizedBlocked.contains(normalized) else { continue }
            prefetchRemoteAvatarIfNeeded(profile.profilePhotoURL)
            prefetchProfileIfNeeded(
                userID: profile.userID,
                username: profile.username,
                displayName: profile.name,
                profilePhotoURL: profile.profilePhotoURL
            )
        }

        for account in firestoreUserSearchResults {
            let normalized = FirebaseSpotService.normalizeUsername(account.username)
            guard normalizedBlocked.contains(normalized) else { continue }
            prefetchRemoteAvatarIfNeeded(account.profilePhotoURL)
            prefetchProfileIfNeeded(
                userID: account.uid,
                username: account.username,
                displayName: account.displayName,
                profilePhotoURL: account.profilePhotoURL
            )
        }
    }

    private func refreshFirestoreUserSearchResults() async {
        let query = userSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            await MainActor.run { firestoreUserSearchResults = [] }
            return
        }

        do {
            let matches = try await FirebaseSpotService.shared.searchUsers(query: query, limit: 12)
            await MainActor.run {
                firestoreUserSearchResults = matches
                cacheAndPrefetchSearchResultProfiles()
            }
        } catch {
            await MainActor.run { firestoreUserSearchResults = [] }
        }
    }

    private func refreshFirestorePOISearchResults() async {
        let query = locationSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let center = locationService.lastKnownLocation?.coordinate ?? NearbyPlaceLoader.defaultCenter

        let requestRevision = await MainActor.run { () -> Int in
            poiSearchRequestRevision += 1
            return poiSearchRequestRevision
        }

        if !query.isEmpty {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
        }

        do {
            let rawResults: [FirebasePOIRecord]
            if query.isEmpty {
                rawResults = try await FirebaseSpotService.shared.fetchNearbyPOIs(
                    around: center,
                    limit: 80
                )
            } else {
                rawResults = try await FirebaseSpotService.shared.searchPOIs(
                    query: query,
                    limit: 500,
                    center: center
                )
            }

            let loweredQuery = query.lowercased()
            let scored = rawResults.map { poi -> (poi: FirebasePOIRecord, score: Double, distance: Double) in
                let distance = NearbyPlaceLoader.haversineMiles(
                    from: center,
                    to: CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
                )

                let lowerName = poi.name.lowercased()
                let lowerCity = (poi.city ?? "").lowercased()
                let lowerCountry = (poi.country ?? "").lowercased()
                let lowerCategory = poi.category.lowercased()

                let textScore: Double = {
                    if loweredQuery.isEmpty { return max(0, 280 - distance * 14) }

                    var score = 0.0
                    if lowerName == loweredQuery { score += 100000 }
                    if lowerName.hasPrefix(loweredQuery) { score += 60000 }
                    if lowerName.contains(loweredQuery) { score += 25000 }
                    if lowerCity.contains(loweredQuery) { score += 15000 }
                    if lowerCountry.contains(loweredQuery) { score += 12000 }
                    if lowerCategory.contains(loweredQuery) { score += 10000 }
                    return score
                }()

                let proximityScore = max(0.0, 1000.0 - (distance * 70.0))
                let combinedScore = textScore + (proximityScore * 0.25)
                return (poi, combinedScore, distance)
            }
            .filter { loweredQuery.isEmpty ? true : $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.distance < rhs.distance
            }

            let ordered = Array(scored.prefix(200).map(\.poi))
            await MainActor.run {
                guard requestRevision == poiSearchRequestRevision else { return }
                let currentQuery = locationSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard currentQuery == query else { return }
                firestorePOISearchResults = ordered
            }
        } catch {
            await MainActor.run {
                guard requestRevision == poiSearchRequestRevision else { return }
                let currentQuery = locationSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard currentQuery == query else { return }

                // Keep existing suggestions for typed queries to avoid flicker on transient request failures.
                if query.isEmpty {
                    firestorePOISearchResults = []
                }
            }
        }
    }

    private func searchUsersEditorView() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Search users")
                    .font(.title3.weight(.semibold))
                Text("Find people by username or their account name.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Search by username or name", text: $userSearchText)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if searchedUsersResults.isEmpty {
                    Text("No matches found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(searchedUsersResults, id: \ .username) { user in
                            Button {
                                openUserProfileScreen(with: user)
                            } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    Circle()
                                        .fill(LinearGradient(colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 34, height: 34)
                                        .overlay(Text(user.profilePhotoText).font(.caption.weight(.bold)).foregroundStyle(.black))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(user.name.isEmpty ? user.username : user.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(displayUsername(user.username))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity)
        .task(id: userSearchText) {
            await refreshFirestoreUserSearchResults()
        }
    }

    private var locationAlertSuggestions: [String] {
        let base = (nearbyPlaces.map { $0.name } + recentLocations + savedLocations + ["Shanghai", "Tokyo", "Paris", "London", "Los Angeles", "New York", "Berlin", "Rome", "Seoul", "Singapore"])
        let query = locationAlertSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = query.lowercased()

        var seen: Set<String> = []
        let filtered = base.filter { item in
            let text = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return false }
            let matches = lower.isEmpty || text.lowercased().contains(lower)
            if !matches { return false }
            let key = text.lowercased()
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }

        return Array(filtered.prefix(8))
    }

    private func requestLocationAlertNotificationsIfNeeded() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            // Ignore notification permission errors and let the user try again later.
        }
    }

    private func addLocationAlert(_ value: String) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        if savedLocations.contains(cleaned) { locationAlertSearchText = ""; return }
        if savedLocations.count >= 10 {
            locationAlertSearchText = ""
            return
        }

        let isFirstSavedLocation = savedLocations.isEmpty
        savedLocations.insert(cleaned, at: 0)
        persistSavedLocations()
        locationAlertSearchText = ""

        if isFirstSavedLocation {
            Task {
                await requestLocationAlertNotificationsIfNeeded()
            }
        }
    }

    private func removeLocationAlert(_ value: String) {
        savedLocations.removeAll { $0.lowercased() == value.lowercased() }
        persistSavedLocations()
    }

    private func locationAlertsEditorView() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Location alerts")
                .font(.title3.weight(.semibold))

            Text("Save up to 10 places to get notified when new posts are shared there.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Search places or cities", text: $locationAlertSearchText)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if !locationAlertSuggestions.isEmpty && !locationAlertSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(locationAlertSuggestions, id: \ .self) { suggestion in
                        Button {
                            addLocationAlert(suggestion)
                        } label: {
                            HStack {
                                Text(suggestion)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Saved locations")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                if savedLocations.isEmpty {
                    Text("No saved locations yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(savedLocations.prefix(10), id: \ .self) { saved in
                        HStack {
                            Text(saved)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Button {
                                removeLocationAlert(saved)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }

        }
    }

    private func nameEditorView() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Account name")
                .font(.title3.weight(.semibold))
            Text("This is your display name. It can be different from your username.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Your account name", text: $profileName)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: profileName) { _, newValue in
                    let cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    UserDefaults.standard.set(cleaned, forKey: profileNameDefaultsKey)
                    pendingProfileNameSaveTask?.cancel()

                    guard FirebaseSpotService.isAllowedDisplayName(cleaned) else {
                        return
                    }

                    pendingProfileNameSaveTask = Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        await persistCurrentProfileName(expectedDisplayName: cleaned)
                    }
                }

            let nameIsValid = !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && FirebaseSpotService.isAllowedDisplayName(profileName)
            let validationMessage = nameIsValid ? "Looks good" : (profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add a name" : "Name contains a blocked term")
            
            HStack {
                Text(isProfileNameSavePending ? profileNameSaveMessage : validationMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isProfileNameSavePending ? .blue : (nameIsValid ? .green : .red))
                Spacer()
            }
        }
    }

    private func profileTextEditorView() -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Adjust profile photo")
                    .font(.title3.weight(.semibold))
                Text("Pick a photo, then frame it in the circle.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let image = displayProfilePhotoImage {
                ZStack {
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 280, height: 280)

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 280, height: 280)
                        .clipShape(Circle())
                        .scaleEffect(profilePhotoCropScale)
                        .offset(profilePhotoCropOffset)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        profilePhotoCropScale = max(1.0, min(2.5, value))
                                    },
                                DragGesture()
                                    .onChanged { value in
                                        profilePhotoCropOffset = CGSize(
                                            width: value.translation.width,
                                            height: value.translation.height
                                        )
                                    }
                            )
                        )

                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 280, height: 280)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                PhotosPicker(selection: $profilePhotoItem, matching: .images, photoLibrary: .shared()) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 280, height: 280)

                        VStack(spacing: 10) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.white)
                            Text("Choose photo")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                if hasActiveProfilePhoto {
                    PhotosPicker(selection: $profilePhotoItem, matching: .images, photoLibrary: .shared()) {
                        Text("Choose another")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if hasActiveProfilePhoto {
                    Button {
                        if let image = displayProfilePhotoImage {
                            profilePhotoImage = image
                            profilePhotoPreviewImage = image
                            pendingProfilePhotoSelection = image
                            Task { await persistCurrentProfilePhoto() }
                        }
                        profilePhotoCropScale = 1.0
                        profilePhotoCropOffset = .zero
                        activeSettingsEditor = nil
                    } label: {
                        Text("Save")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.black)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            if hasActiveProfilePhoto {
                Button {
                    Task {
                        await removeCurrentProfilePhoto()
                    }
                } label: {
                    Text("Remove photo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func handleProfilePhotoSelection(_ newItem: PhotosPickerItem) {
        Task {
            do {
                guard let data = try await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    await MainActor.run {
                        profilePhotoItem = nil
                        accountAuthMessage = "Unable to read that photo. Please choose a different image."
                    }
                    return
                }

                await MainActor.run {
                    setSelectedProfilePhoto(image)
                    profilePhotoItem = nil
                }

                await persistCurrentProfilePhoto()
            } catch {
                await MainActor.run {
                    profilePhotoItem = nil
                    accountAuthMessage = "Photo selection failed. Please try again."
                }
                print("Spot profile photo load error: \(error)")
            }
        }
    }

    private func postTypeSelectionButton(for type: String, compact: Bool = false) -> some View {
        let isCompact = compact
        let card: some View = VStack(alignment: .center, spacing: isCompact ? 8 : 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: isCompact ? 72 : 108)
                    .overlay(
                        Image(systemName: postTypeIcon(for: type))
                            .font(.system(size: isCompact ? 23 : 33, weight: .semibold))
                            .foregroundStyle(.black)
                    )
            }

            Text(displayNameForPostType(type))
                .font(isCompact ? .subheadline.weight(.semibold) : .headline.weight(.semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .center)
                .lineLimit(1)
        }
        .padding(isCompact ? 10 : 12)
        .frame(maxWidth: isCompact ? 120 : .infinity, minHeight: isCompact ? 120 : 188, alignment: .center)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 6)

        if type == "Photo" {
            return AnyView(
                PhotosPicker(selection: $draftPhotoItem, matching: .images, photoLibrary: .shared()) {
                    card
                }
                .buttonStyle(.plain)
                .task(id: draftPhotoItem) {
                    guard let newItem = draftPhotoItem else { return }
                    selectedPostType = type
                    resetDraftFor(type)
                    do {
                        if let data = try await newItem.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            await MainActor.run {
                                draftPhotoImage = image
                                draftPhotoCropScale = 1.0
                                draftPhotoCropOffset = .zero
                                currentScreen = .composer
                            }
                        }
                    } catch {
                        await MainActor.run {
                            draftPhotoImage = nil
                            currentScreen = .composer
                        }
                    }
                }
            )
        } else if type == "Video" {
            return AnyView(
                PhotosPicker(selection: $draftVideoItem, matching: .videos, photoLibrary: .shared()) {
                    card
                }
                .buttonStyle(.plain)
                .task(id: draftVideoItem) {
                    guard let newItem = draftVideoItem else { return }
                    selectedPostType = type
                    resetDraftFor(type)
                    isPreparingVideoSelection = true
                    currentScreen = .composer

                    do {
                        let itemURL = try? await newItem.loadTransferable(type: URL.self)
                        if let url = itemURL {
                            let stableURL = await MainActor.run { copyVideoToTemporaryLocation(sourceURL: url) } ?? url
                            await MainActor.run {
                                draftVideoURL = stableURL
                                draftUrl = stableURL.absoluteString
                                isPreparingVideoSelection = false
                                currentScreen = .composer
                            }
                        } else if let data = try? await newItem.loadTransferable(type: Data.self) {
                            let fallbackURL = URL(fileURLWithPath: NSTemporaryDirectory())
                                .appendingPathComponent(UUID().uuidString)
                                .appendingPathExtension("mp4")
                            try data.write(to: fallbackURL)
                            await MainActor.run {
                                draftVideoURL = fallbackURL
                                draftUrl = fallbackURL.absoluteString
                                isPreparingVideoSelection = false
                                currentScreen = .composer
                            }
                        } else {
                            await MainActor.run {
                                draftVideoURL = nil
                                isPreparingVideoSelection = false
                                currentScreen = .composer
                            }
                        }
                    } catch {
                        await MainActor.run {
                            draftVideoURL = nil
                            isPreparingVideoSelection = false
                            currentScreen = .composer
                        }
                    }
                }
            )
        } else {
            return AnyView(
                Button {
                    selectedPostType = type
                    resetDraftFor(type)
                    if type == "Guide" {
                        prepareGuideDefaultsIfNeeded()
                    } else if type == "For Sale" {
                        prepareSaleDefaultsIfNeeded()
                    } else if type == "Song" {
                        prepareSongDefaultsIfNeeded()
                    }
                    currentScreen = .composer
                } label: {
                    card
                }
                .buttonStyle(.plain)
            )
        }
    }

    private var createTypePickerView: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(postTypes, id: \.self) { type in
                            postTypeSelectionButton(for: type)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 0)
                    .padding(.bottom, 128)
                }
            }

            floatingHomeActions
                .padding(.bottom, 12)
                .padding(.horizontal, 18)
        }
    }

    private var createComposerView: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    backButton(destination: .contentTypePicker)
                    Spacer()
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        draftPreviewCard

                        if !composerStatusMessage.isEmpty {
                            Text(composerStatusMessage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 18)
                        }
                    }
                    .padding(.bottom, 140)
                }

                Spacer(minLength: 0)
            }

            .onAppear {
                restoreDraftAudioRecordingIfNeeded()
                if selectedPostType == "Guide" {
                    prepareGuideDefaultsIfNeeded()
                } else if selectedPostType == "Work" || selectedPostType == "Hiring" {
                    prepareWorkDefaultsIfNeeded()
                } else if selectedPostType == "For Sale" {
                    restoreSaleDraftStateIfNeeded()
                    prepareSaleDefaultsIfNeeded()
                } else if selectedPostType == "Song" {
                    prepareSongDefaultsIfNeeded()
                }
            }
            .fileImporter(
                isPresented: $isSongFileImporterPresented,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let selectedURL = urls.first else { return }
                    let resolvedURL = copyVideoToTemporaryLocation(sourceURL: selectedURL) ?? selectedURL
                    guard SongPostRules.isSupported(resolvedURL) else {
                        composerStatusMessage = SongPostRules.allowedFormatsText()
                        return
                    }

                    draftSongFileURL = resolvedURL
                    draftUrl = resolvedURL.absoluteString
                    composerStatusMessage = ""
                case .failure:
                    composerStatusMessage = "Unable to read that song file."
                }
            }

            VStack(spacing: 12) {
                Button {
                    currentScreen = .postLocationPicker
                } label: {
                    Text("Next")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.99, green: 0.94, blue: 0.74), Color(red: 0.96, green: 0.78, blue: 0.44)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.black, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)

                floatingHomeActions
                    .padding(.horizontal, 18)
            }
            .padding(.bottom, 12)
        }
    }

    private var photoEditorView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button {
                    currentScreen = .composer
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Photo")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            if let photo = draftPhotoImage {
                VStack(alignment: .center, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color(.secondarySystemBackground))
                            .frame(maxWidth: .infinity)
                            .frame(height: 420)

                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 420)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .scaleEffect(draftPhotoCropScale)
                            .offset(draftPhotoCropOffset)
                            .gesture(
                                SimultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            draftPhotoCropScale = max(1.0, min(2.5, value))
                                        },
                                    DragGesture()
                                        .onChanged { value in
                                            draftPhotoCropOffset = CGSize(
                                                width: value.translation.width,
                                                height: value.translation.height
                                            )
                                        }
                                )
                            )
                    }

                    HStack(spacing: 12) {
                        PhotosPicker(selection: $draftPhotoItem, matching: .images, photoLibrary: .shared()) {
                            Text("Choose another")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemBackground))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            draftPhotoCropScale = 1.0
                            draftPhotoCropOffset = .zero
                            currentScreen = .composer
                        } label: {
                            Text("Use photo")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.black)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            } else {
                VStack(alignment: .center, spacing: 18) {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(LinearGradient(colors: [Color("spotBlue"), Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(maxWidth: .infinity)
                        .frame(height: 420)
                        .overlay(
                            VStack(spacing: 12) {
                                Image(systemName: "photo.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.white)
                                Text("Add your photo")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text("Pick the image first, then adjust it before posting.")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.9))
                                    .multilineTextAlignment(.center)
                            }
                        )

                    PhotosPicker(selection: $draftPhotoItem, matching: .images, photoLibrary: .shared()) {
                        Text("Choose photo")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(Color.black)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18)
                }
            }

            Spacer()
        }
        .onChange(of: draftPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                do {
                    if let data = try await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            draftPhotoImage = image
                            draftPhotoCropScale = 1.0
                            draftPhotoCropOffset = .zero
                        }
                    }
                } catch {
                    await MainActor.run {
                        draftPhotoImage = nil
                    }
                }
            }
        }
    }

    private var videoEditorView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button {
                    currentScreen = .composer
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Video")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            if let videoURL = draftVideoURL {
                VStack(alignment: .center, spacing: 16) {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(.secondarySystemBackground))
                        .frame(maxWidth: .infinity)
                        .frame(height: 420)
                        .overlay(
                            VStack(spacing: 12) {
                                Image(systemName: "film.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.primary)
                                Text("Video selected")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(videoURL.lastPathComponent)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        )

                    HStack(spacing: 12) {
                        PhotosPicker(selection: $draftVideoItem, matching: .videos, photoLibrary: .shared()) {
                            Text("Choose another")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemBackground))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            draftUrl = videoURL.absoluteString
                            currentScreen = .composer
                        } label: {
                            Text("Use video")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.black)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            } else {
                VStack(alignment: .center, spacing: 18) {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(LinearGradient(colors: [Color("spotBlue"), Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(maxWidth: .infinity)
                        .frame(height: 420)
                        .overlay(
                            VStack(spacing: 12) {
                                if isPreparingVideoSelection {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Text("Loading selected video…")
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text("Your video will appear here when it’s ready.")
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.9))
                                        .multilineTextAlignment(.center)
                                } else {
                                    Image(systemName: "film.fill")
                                        .font(.system(size: 44))
                                        .foregroundStyle(.white)
                                    Text("Add your video")
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text("Pick the video first, then adjust it before posting.")
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.9))
                                        .multilineTextAlignment(.center)
                                }
                            }
                        )

                    PhotosPicker(selection: $draftVideoItem, matching: .videos, photoLibrary: .shared()) {
                        Text("Choose video")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(Color.black)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18)
                }
            }

            Spacer()
        }
        .onChange(of: draftVideoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                do {
                    if let url = try? await newItem.loadTransferable(type: URL.self) {
                        let stableURL = await MainActor.run { copyVideoToTemporaryLocation(sourceURL: url) } ?? url
                        await MainActor.run {
                            draftVideoURL = stableURL
                            draftUrl = stableURL.absoluteString
                        }
                    } else {
                        if let data = try await newItem.loadTransferable(type: Data.self) {
                            let fallbackURL = URL(fileURLWithPath: NSTemporaryDirectory())
                                .appendingPathComponent(UUID().uuidString)
                                .appendingPathExtension("mp4")
                            try data.write(to: fallbackURL)
                            await MainActor.run {
                                draftVideoURL = fallbackURL
                                draftUrl = fallbackURL.absoluteString
                            }
                        }
                    }
                } catch {
                    await MainActor.run {
                        draftVideoURL = nil
                    }
                }
            }
        }
    }

    private var videoUpgradeView: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Button {
                            currentScreen = .videoEditor
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Upgrade your video studio")
                            .font(.largeTitle.weight(.bold))
                        Text("Create polished short-form videos with more tools, smarter editing, and faster exports.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 18)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(VideoUpgradePlan.all) { plan in
                            let isSelected = selectedVideoUpgradePlan.id == plan.id
                            Button {
                                selectedVideoUpgradePlan = plan
                            } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(plan.name)
                                                .font(.headline)
                                            if let badge = plan.badge {
                                                Text(badge)
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.black)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        Text(plan.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(plan.price)
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(.primary)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity)
                                .background(isSelected ? ContentView.appPrimaryThemeColor.opacity(0.12) : Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Included with Creator Pro")
                            .font(.title3.weight(.semibold))

                        featureRow(icon: "scissors", title: "AI trim + cut tools", subtitle: "Precision edits for short-form storytelling")
                        featureRow(icon: "sparkles", title: "Templates + transitions", subtitle: "Motion overlays, crossfades, and cinematic layouts")
                        featureRow(icon: "waveform", title: "Multi-track audio", subtitle: "Mix music, voice, and ambient sound with clean volume controls")
                        featureRow(icon: "textformat", title: "Text overlays + captions", subtitle: "Auto captions, animated titles, and branded lower thirds")
                        featureRow(icon: "arrow.down.to.line", title: "4K export + faster renders", subtitle: "Quick exports for Instagram, TikTok, and Reels")
                        featureRow(icon: "chart.line.uptrend.xyaxis", title: "Story analytics", subtitle: "See watch time, retention, and share performance")
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 120)
            }

            VStack(spacing: 12) {
                Button {
                    currentScreen = .videoCheckout
                } label: {
                    Text("Continue to checkout")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)

                floatingHomeActions
                    .padding(.horizontal, 18)
            }
            .padding(.bottom, 12)
        }
    }

    private var videoCheckoutView: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button {
                        currentScreen = .videoUpgrade
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("Checkout")
                        .font(.headline)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Creator Pro")
                        .font(.largeTitle.weight(.bold))

                        Text("Demo checkout only — no live App Store payment is connected yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        checkoutSummaryRow(label: "Plan", value: selectedVideoUpgradePlan.name)
                        checkoutSummaryRow(label: "Billing", value: selectedVideoUpgradePlan.id == "annual" ? "Annual" : "Monthly")
                        checkoutSummaryRow(label: "Access", value: "All premium video tools")
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 8) {
                        Text("Why people upgrade")
                            .font(.headline)
                        Text("Trim faster, add better audio, create more polished short-form stories, and export in high quality without worrying about limits.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("Prototype only: StoreKit and Apple billing are not connected in this build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)

                Spacer()
            }

            VStack(spacing: 12) {
                Button {
                    isVideoEditorPro = true
                    currentScreen = .videoEditor
                } label: {
                    Text("Start demo trial")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)

                floatingHomeActions
                    .padding(.horizontal, 18)
            }
            .padding(.bottom, 12)
        }
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func checkoutSummaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private var videoEditorHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    currentScreen = .composer
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Video")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    withAnimation {
                        videoEditorClips.append(
                            .init(
                                id: Int(Date().timeIntervalSince1970) % 100000,
                                name: "New clip",
                                durationSeconds: 8,
                                color: .gray,
                                source: "Library"
                            )
                        )
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation {
                    videoEditorClips.append(
                        .init(
                            id: Int(Date().timeIntervalSince1970) % 100000,
                            name: "Selected clip",
                            durationSeconds: 7,
                            color: ContentView.appPrimaryThemeColor,
                            source: "Camera roll"
                        )
                    )
                }
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.black)
                        Text("Add your videos")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                            .frame(height: 56)

                        HStack(spacing: 8) {
                            ForEach(0..<5, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(index % 2 == 0 ? ContentView.appPrimaryThemeColor : ContentView.appAccentThemeColor)
                                    .frame(width: 28, height: 36)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var videoEditorToolbar: some View {
        let tabs: [String] = ["Split", "Title", "Audio"]
        let tabPairs = Array(tabs.enumerated())

        return HStack(spacing: 10) {
            ForEach(tabPairs, id: \.offset) { pair in
                let tab = pair.element

                Button {
                    videoEditorCurrentTool = tab
                } label: {
                    Text(tab)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(videoEditorCurrentTool == tab ? Color.white : Color.primary)
                        .background(videoEditorCurrentTool == tab ? Color.black : Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var videoEditorPreviewCard: some View {
        let totalDuration = videoEditorClips.reduce(0) { $0 + $1.durationSeconds }
        return Rectangle()
            .fill(LinearGradient(colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                VStack(alignment: .leading, spacing: 12) {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("00:00 / \(VideoEditorClip.formatDuration(totalDuration))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    Text(videoEditorTitleOverlay.isEmpty ? "Untitled edit" : videoEditorTitleOverlay)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
                .padding(16)
            )
    }

    private var videoEditorTimelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Clips")
                    .font(.headline)
                Spacer()
                Text("Up to 30s each")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(videoEditorClips) { clip in
                        videoEditorClipCard(clip)
                    }
                }
            }
        }
    }

    private func videoEditorClipCard(_ clip: VideoEditorClip) -> some View {
        let clipIndex = videoEditorClips.firstIndex(where: { $0.id == clip.id }) ?? 0

        return VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(clip.color)
                .frame(width: 104, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer()
                        Text(clip.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(clip.duration)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(8), alignment: .bottomLeading
                )

            HStack(spacing: 8) {
                Button {
                    if let idx = videoEditorClips.firstIndex(where: { $0.id == clip.id }) {
                        let current = videoEditorClips[idx].durationSeconds
                        videoEditorClips[idx].durationSeconds = max(1, current - 3)
                    }
                } label: { Image(systemName: "scissors") }
                .buttonStyle(.plain)

                Button {
                    if let idx = videoEditorClips.firstIndex(where: { $0.id == clip.id }) {
                        let current = videoEditorClips[idx].durationSeconds
                        let firstHalf = max(1, current / 2)
                        let secondHalf = max(1, current - firstHalf)
                        let first = VideoEditorClip(id: Int(Date().timeIntervalSince1970) % 100000 + 1, name: "Split A", durationSeconds: firstHalf, color: clip.color, source: clip.source)
                        let second = VideoEditorClip(id: Int(Date().timeIntervalSince1970) % 100000 + 2, name: "Split B", durationSeconds: secondHalf, color: clip.color.opacity(0.8), source: clip.source)
                        videoEditorClips.insert(first, at: idx)
                        videoEditorClips.insert(second, at: idx + 1)
                        videoEditorClips.remove(at: idx + 2)
                    }
                } label: { Image(systemName: "scissors.badge.ellipsis") }
                .buttonStyle(.plain)

                Button {
                    if let idx = videoEditorClips.firstIndex(where: { $0.id == clip.id }) {
                        if videoEditorClips[idx].durationSeconds > 30 {
                            videoEditorClips[idx].durationSeconds = 30
                        }
                    }
                } label: {
                    Text(clip.durationSeconds > 30 ? "Shorten" : "Trim")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var videoEditorToolDetailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch videoEditorCurrentTool {
            case "Split":
                VStack(alignment: .leading, spacing: 10) {
                    Text("Split clips")
                        .font(.headline)

                    HStack(spacing: 10) {
                        Button {
                            if let first = videoEditorClips.first {
                                let current = first.durationSeconds
                                let firstHalf = max(1, current / 2)
                                let secondHalf = max(1, current - firstHalf)
                                let clip = videoEditorClips[0]
                                let firstClip = VideoEditorClip(id: Int(Date().timeIntervalSince1970) % 100000 + 1, name: "Split A", durationSeconds: firstHalf, color: clip.color, source: clip.source)
                                let secondClip = VideoEditorClip(id: Int(Date().timeIntervalSince1970) % 100000 + 2, name: "Split B", durationSeconds: secondHalf, color: clip.color.opacity(0.8), source: clip.source)
                                videoEditorClips.insert(firstClip, at: 0)
                                videoEditorClips.insert(secondClip, at: 1)
                                videoEditorClips.remove(at: 2)
                            }
                        } label: {
                            Text("Split")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(.white)
                                .background(Color.black)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            if let first = videoEditorClips.first {
                                let current = first.durationSeconds
                                let trimmed = min(30, max(1, current - 3))
                                if let idx = videoEditorClips.firstIndex(where: { $0.id == first.id }) {
                                    videoEditorClips[idx].durationSeconds = trimmed
                                }
                            }
                        } label: {
                            Text("Trim 3s")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(.primary)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            case "Title":
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add a title")
                        .font(.headline)

                    TextField("Short video title", text: $videoEditorTitleOverlay)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            default:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Basic audio")
                        .font(.headline)

                    ForEach(videoEditorAudioTracks) { track in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(track.name)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text(track.isMusic ? "Music" : "Original")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Slider(value: Binding(
                                get: { track.volume },
                                set: { newValue in
                                    if let idx = videoEditorAudioTracks.firstIndex(where: { $0.id == track.id }) {
                                        videoEditorAudioTracks[idx].volume = newValue
                                    }
                                }
                            ))
                        }
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    static func canSubmitDraft(type: String, title: String, body: String, url: String, pollQuestion: String, pollOptionA: String, pollOptionB: String, hasPhoto: Bool, hasRecordedAudio: Bool) -> Bool {
        return true
    }

    static func canStartDraftSubmission(isSubmitting: Bool) -> Bool {
        !isSubmitting
    }

    private func restoreDraftAudioRecordingIfNeeded() {
        guard draftRecordedAudioURL == nil else { return }
        guard let savedURL = Self.loadDraftAudioRecordingURL() else { return }
        guard FileManager.default.fileExists(atPath: savedURL.path) else {
            Self.saveDraftAudioRecordingURL(nil)
            return
        }

        draftRecordedAudioURL = savedURL
        draftUrl = savedURL.absoluteString
        hasPlayedRecordedAudio = false
    }

    private func submitDraftPost() {
        guard Self.canStartDraftSubmission(isSubmitting: isSubmittingPost) else {
            return
        }

        let hasValidContent = Self.canSubmitDraft(
            type: selectedPostType,
            title: draftTitle,
            body: draftBody,
            url: draftUrl,
            pollQuestion: draftPollQuestion,
            pollOptionA: draftPollOptionA,
            pollOptionB: draftPollOptionB,
            hasPhoto: draftPhotoImage != nil,
            hasRecordedAudio: draftRecordedAudioURL != nil
        )

        guard hasValidContent else {
            if selectedPostType == "Poll" {
                draftPollOptionA = draftPollOptionA.isEmpty ? "Yes" : draftPollOptionA
                draftPollOptionB = draftPollOptionB.isEmpty ? "No" : draftPollOptionB
            }
            return
        }

        let resolvedLocation = Self.resolvedPostingLocation(
            postLocation: postLocation,
            feedLocation: fromLocation,
            nearbyPlaceName: nearbyPlaces.first?.name
        )

        if isLocationOnCooldownForPosting(resolvedLocation) {
            showLocationCooldownMessage(for: resolvedLocation)
            return
        }

        if selectedPostType == "Photo" && draftPhotoImage == nil {
            accountAuthMessage = "Choose a photo before posting."
            lastSentMessage = "Photo post needs an image."
            return
        }

        if selectedPostType == "Video" && draftVideoURL == nil && !Self.isRemoteURLString(draftUrl) {
            accountAuthMessage = "Choose a video before posting."
            lastSentMessage = "Video post needs a video file."
            return
        }

        if selectedPostType == "Audio" && draftRecordedAudioURL == nil && !Self.isRemoteURLString(draftUrl) {
            accountAuthMessage = "Record audio before posting."
            lastSentMessage = "Audio post needs a recording."
            return
        }

        if selectedPostType == "Song" {
            let hasRemoteSong = Self.isRemoteURLString(draftUrl)
            guard hasRemoteSong || draftSongFileURL != nil else {
                accountAuthMessage = "Choose a song file before posting."
                lastSentMessage = "Song post needs a song file."
                return
            }

            if let localSong = draftSongFileURL,
               !SongPostRules.isSupported(localSong) {
                accountAuthMessage = SongPostRules.allowedFormatsText()
                lastSentMessage = "Song file type is not supported."
                return
            }
        }

        if selectedPostType == "Live Route" {
            let start = draftRouteStart.trimmingCharacters(in: .whitespacesAndNewlines)
            let end = draftRouteEnd.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !start.isEmpty, !end.isEmpty else {
                accountAuthMessage = "Add both start and destination for your route."
                lastSentMessage = "Live route needs two locations."
                return
            }

            guard !description.isEmpty else {
                accountAuthMessage = "Add a route description before posting."
                lastSentMessage = "Live route needs a description."
                return
            }
        }

        if selectedPostType == "Guide" {
            let normalizedSteps = GuidePostCodec.normalizedSteps(draftGuideSteps)
            guard !normalizedSteps.isEmpty else {
                accountAuthMessage = "Add at least one guide step before posting."
                lastSentMessage = "Guide needs at least one step."
                return
            }
        }

        if selectedPostType == "Work" || selectedPostType == "Hiring" {
            let listings = WorkPostCodec.normalizedListings(draftWorkListings)
            guard !listings.isEmpty else {
                accountAuthMessage = "Add at least one job listing before posting."
                lastSentMessage = "Hiring post needs a job listing."
                return
            }

            let phoneDigits = WorkPostCodec.sanitizedPhoneDigits(draftWorkContactPhone)
            let email = draftWorkContactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasPhone = phoneDigits.count >= 7
            let hasEmail = email.contains("@") && email.contains(".")
            guard hasPhone || hasEmail else {
                accountAuthMessage = "Add a valid contact phone or email for the post."
                lastSentMessage = "Hiring post needs contact info."
                return
            }
        }

        if selectedPostType == "For Sale" {
            let items = SalePostCodec.normalizedItems(draftSaleItems)
            guard !items.isEmpty else {
                accountAuthMessage = "Add at least one item for sale."
                lastSentMessage = "For Sale post needs an item."
                return
            }

            let cleanedPrice = draftSalePrice.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedPrice.isEmpty else {
                accountAuthMessage = "Add a price for your listing."
                lastSentMessage = "For Sale post needs a price."
                return
            }

            let phoneDigits = WorkPostCodec.sanitizedPhoneDigits(draftSaleContactPhone)
            let email = draftSaleContactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasPhone = phoneDigits.count >= 7
            let hasEmail = email.contains("@") && email.contains(".")
            guard hasPhone || hasEmail else {
                accountAuthMessage = "Add a valid contact phone or email."
                lastSentMessage = "For Sale post needs contact info."
                return
            }
        }

        Task {
            defer {
                Task { @MainActor in
                    isSubmittingPost = false
                }
            }

            await MainActor.run {
                isSubmittingPost = true
            }

            guard let userID = await resolveUserIDForPosting() else {
                await MainActor.run {
                    accountAuthMessage = "Posting setup failed. Please try again."
                    lastSentMessage = "Posting setup failed."
                }
                return
            }

            let newPost = makeDraftPost(id: Int(Date().timeIntervalSince1970 * 1000))
            let isBoostedPost = consumeBoostIfAvailable()
            let postedRealms = Self.resolvedPostedRealms(location: resolvedLocation, postedInLocations: [resolvedLocation])
            let posted = MockPost(
                id: newPost.id,
                author: newPost.author,
                handle: newPost.handle,
                authorUserID: userID,
                authorProfilePhotoURL: newPost.authorProfilePhotoURL,
                type: newPost.type,
                location: resolvedLocation,
                title: newPost.title,
                body: newPost.body,
                url: newPost.url,
                accent: newPost.accent,
                tag: newPost.tag,
                likes: newPost.likes,
                viewCount: newPost.viewCount,
                isLiked: newPost.isLiked,
                comments: newPost.comments,
                sentTo: newPost.sentTo,
                isSaved: newPost.isSaved,
                pollOptions: newPost.pollOptions,
                pollVotes: newPost.pollVotes,
                mediaImage: newPost.mediaImage,
                mediaURLs: newPost.mediaURLs,
                sourceURL: newPost.sourceURL,
                isBoosted: isBoostedPost,
                postedInLocations: postedRealms,
                isAnonymous: newPost.isAnonymous
            )

            if let image = draftPhotoImage {
                Self.persistImage(image, forKey: Self.postPhotoCacheKey(forPostID: posted.id))
            }

            let mediaURLs: [String]
            do {
                mediaURLs = await uploadDraftMedia(postID: posted.id)
            } catch {
                await MainActor.run {
                    accountAuthMessage = "Media upload failed: \((error as NSError).localizedDescription)"
                    lastSentMessage = "Media upload failed."
                }
                print("Spot uploadDraftMedia error: \(error)")
                return
            }
            
            let resolvedMediaURLs = mediaURLs.isEmpty ? fallbackDraftMediaURLs(for: posted) : mediaURLs
            let requiresUploadedMedia = posted.type == "Audio" || posted.type == "Song" || posted.type == "Video" || posted.type == "Photo" || posted.type == "Photo/Video"
            if requiresUploadedMedia && resolvedMediaURLs.isEmpty {
                await MainActor.run {
                    accountAuthMessage = "Media failed to upload. Please stay signed in and try again."
                    lastSentMessage = "Media upload failed. Post not sent."
                }
                return
            }

            // If media upload failed and we have media-type post, don't use fake fallback URLs
            let isFallbackURL = resolvedMediaURLs.first?.lowercased().hasPrefix("local-") == true || resolvedMediaURLs.first?.lowercased().hasPrefix("file://") == true
            if requiresUploadedMedia && isFallbackURL {
                await MainActor.run {
                    accountAuthMessage = "Media upload verification failed. Please try again."
                    lastSentMessage = "Media upload failed. Post not sent."
                }
                return
            }

            if posted.type == "Video" {
                let hasRemoteVideoURL = resolvedMediaURLs.contains { Self.isRemoteURLString($0) }
                if !hasRemoteVideoURL {
                    await MainActor.run {
                        accountAuthMessage = "Video failed to upload. Please try posting again."
                        lastSentMessage = "Video upload failed. Post not sent."
                    }
                    return
                }
            }

            let payload = firebasePayload(for: posted, authorID: userID, mediaURLs: resolvedMediaURLs)

            let moderatedPostResult: FirebaseModeratedPostResult

            do {
                moderatedPostResult = try await FirebaseSpotService.shared.submitPostWithModeration(payload)
            } catch {
                let technicalReason = (error as NSError).localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedReason = technicalReason.isEmpty ? "Unknown error." : technicalReason
                await MainActor.run {
                    accountAuthMessage = "Post failed before save. \(resolvedReason)"
                    lastSentMessage = "Post failed before save. \(resolvedReason)"
                }
                print("Spot moderated submit error: \(error)")
                return
            }

            print("Spot submitDraftPost: Got moderation result - approved=\(moderatedPostResult.approved) posted=\(moderatedPostResult.posted)")

            guard moderatedPostResult.isApproved else {
                await MainActor.run {
                    let blockedMessage = moderatedPostResult.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "This post is not allowed by moderation policy."
                        : moderatedPostResult.message
                    accountAuthMessage = blockedMessage
                    lastSentMessage = blockedMessage
                }
                return
            }

            guard moderatedPostResult.posted else {
                await MainActor.run {
                    accountAuthMessage = "Post was approved but not saved. Please try again."
                    lastSentMessage = "Post was approved but not saved."
                }
                print("Spot submitDraftPost: BLOCKED - posted=false. Status: \(moderatedPostResult.status)")
                return
            }

            print("Spot submitDraftPost: SUCCESS - post was approved and saved with ID: \(moderatedPostResult.postID ?? "nil")")

            let persistedPostIDRaw = (moderatedPostResult.postID ?? String(posted.id)).trimmingCharacters(in: .whitespacesAndNewlines)
            let persistedPostID = persistedPostIDRaw.isEmpty ? String(posted.id) : persistedPostIDRaw

            do {
                try await FirebaseSpotService.shared.saveUserPostReference(
                    userID: userID,
                    postID: persistedPostID,
                    locationName: resolvedLocation,
                    contentType: posted.type,
                    feedInsertionIndex: 0
                )
            } catch {
                print("Spot post reference save warning: \(error)")
            }

            do {
                try await FirebaseSpotService.shared.saveUserLocationHistory(userID: userID, locationName: resolvedLocation)
            } catch {
                print("Spot location history save warning: \(error)")
            }

            Task(priority: .utility) {
                await loadCurrentUserPosts()
            }

            print("Spot submitDraftPost: About to update local feed and UI")

            await MainActor.run {
                print("Spot submitDraftPost: Inside MainActor.run block")
                var localPosted = posted
                localPosted.mediaURLs = resolvedMediaURLs
                localPosted.sourceURL = payload.sourceURL
                localPosted.firestoreID = persistedPostID
                posts.removeAll(where: { $0.id == localPosted.id })
                posts.insert(localPosted, at: 0)

                recordPostForCooldown(at: resolvedLocation)
                rememberSavedLocation(resolvedLocation)
                applyLocationSelection(resolvedLocation, context: .feed)
                applyLocationSelection(resolvedLocation, context: .post)
                if posted.type == "Video" {
                    applyLocationSelection(resolvedLocation, context: .video)
                }
                draftLocation = resolvedLocation
                lastSentMessage = "Posted in \(resolvedLocation)"
                if posted.type == "Video" {
                    currentScreen = .locationFeed
                } else {
                    currentScreen = .home
                }
                sendTo = ""
                recipientSearchText = ""
                selectedSendRecipient = nil
                
                print("Spot submitDraftPost: UI updated successfully, isSubmittingPost will be set to false in defer")
            }
        }
    }

    private var draftPreviewCard: some View {
        let previewPost = makeDraftPost()
        let identityBlurRadius: CGFloat = draftIsAnonymous ? 8 : 0

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profileName.isEmpty ? "You" : profileName)
                        .font(.headline)
                    Text(displayUsername(profileUsername.isEmpty ? "you" : profileUsername))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .blur(radius: identityBlurRadius)

                Spacer()
            }
            .padding(.horizontal, 12)

            if selectedPostType == "Photo" {
                Button {
                    currentScreen = .photoEditor
                } label: {
                    Group {
                        if let image = draftPhotoImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .frame(height: 230)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Spacer()
                                            ZStack {
                                                Circle()
                                                    .fill(Color.black.opacity(0.35))
                                                    .frame(width: 42, height: 42)
                                                Image(systemName: "photo.on.rectangle.angled")
                                                    .font(.title3)
                                                    .foregroundStyle(.white)
                                            }
                                            Spacer()
                                        }
                                        Spacer()
                                    }
                                    .padding(.bottom, 16)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(LinearGradient(colors: [Color(hex: previewPost.accent), ContentView.appPrimaryThemeColor.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                                .frame(maxWidth: .infinity)
                                .frame(height: 230)
                                .overlay(
                                    VStack(alignment: .center, spacing: 10) {
                                        Spacer()
                                        ZStack {
                                            Circle()
                                                .fill(Color.black.opacity(0.25))
                                                .frame(width: 52, height: 52)
                                            Image(systemName: "photo.on.rectangle.angled")
                                                .font(.title2)
                                                .foregroundStyle(.white)
                                        }
                                        Text("Add photo")
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                        Text("Choose a photo to continue")
                                            .font(.subheadline)
                                            .foregroundStyle(.white.opacity(0.9))
                                        Spacer()
                                    }
                                    .padding(18)
                                )
                        }
                    }
                }
                .buttonStyle(.plain)
            } else if selectedPostType == "Photo/Video" {
                PhotosPicker(selection: $draftPhotoItem, matching: .images, photoLibrary: .shared()) {
                    Group {
                        if let image = draftPhotoImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .frame(height: 230)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Spacer()
                                            ZStack {
                                                Circle()
                                                    .fill(Color.black.opacity(0.35))
                                                    .frame(width: 42, height: 42)
                                                Image(systemName: "photo.on.rectangle.angled")
                                                    .font(.title3)
                                                    .foregroundStyle(.white)
                                            }
                                            Spacer()
                                        }
                                        Spacer()
                                    }
                                    .padding(.bottom, 16)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(LinearGradient(colors: [Color(hex: previewPost.accent), ContentView.appPrimaryThemeColor.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                                .frame(maxWidth: .infinity)
                                .frame(height: 230)
                                .overlay(
                                    VStack(alignment: .center, spacing: 10) {
                                        Spacer()
                                        ZStack {
                                            Circle()
                                                .fill(Color.black.opacity(0.25))
                                                .frame(width: 52, height: 52)
                                            Image(systemName: "photo.on.rectangle.angled")
                                                .font(.title2)
                                                .foregroundStyle(.white)
                                        }
                                        Text("Add media")
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                        Text("Photo")
                                            .font(.subheadline)
                                            .foregroundStyle(.white.opacity(0.9))
                                        Spacer()
                                    }
                                    .padding(18)
                                )
                        }
                    }
                }
                .buttonStyle(.plain)
            } else if selectedPostType == "Video" {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(maxWidth: .infinity)
                    .frame(height: 230)
                    .overlay(
                        VStack(alignment: .center, spacing: 10) {
                            Spacer()
                            if isPreparingVideoSelection {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Loading")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            } else if let videoURL = draftVideoURL {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 56, height: 56)
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white)
                                }
                                Text("Video selected")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text(videoURL.lastPathComponent)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(1)
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 56, height: 56)
                                    Image(systemName: "play.rectangle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white)
                                }
                                Text("Add video")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                        }
                        .padding(18)
                    )
            } else if selectedPostType == "Audio" {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        if isRecordingAudio {
                            stopAudioRecording()
                        } else if draftRecordedAudioURL == nil {
                            startAudioRecording()
                        } else if hasPlayedRecordedAudio {
                            resetAudioRecordingState()
                            startAudioRecording()
                        } else {
                            playRecordedAudio()
                        }
                    } label: {
                        HStack {
                            Image(systemName: isRecordingAudio ? "stop.fill" : (draftRecordedAudioURL != nil ? "play.fill" : "mic.fill"))
                                .font(.subheadline.weight(.bold))
                            Text(Self.audioComposerPrimaryLabel(
                                isRecording: isRecordingAudio,
                                hasRecording: draftRecordedAudioURL != nil,
                                hasPlayedRecording: hasPlayedRecordedAudio,
                                isPlaying: isAudioPlaybackActive
                            ))
                            .font(.subheadline.weight(.semibold))
                            Spacer()
                            if isRecordingAudio {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isRecordingAudio ? Color.red.opacity(0.08) : Color.white)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.black, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    if draftRecordedAudioURL != nil {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Recording ready")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if selectedPostType == "Live Route" {
                let routeStart = draftRouteStart.trimmingCharacters(in: .whitespacesAndNewlines)
                let routeEnd = draftRouteEnd.trimmingCharacters(in: .whitespacesAndNewlines)
                let routeBrandingLabel = draftRouteIsRunBranding ? "Run" : "Trip"

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(previewPost.title.isEmpty ? routeBrandingLabel : previewPost.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                    }

                    LiveRouteMiniMapView(
                        startName: routeStart,
                        endName: routeEnd,
                        nearbyPlaces: nearbyPlaces,
                        height: 220
                    )

                    HStack(spacing: 8) {
                        Label(routeStart.isEmpty ? "Start" : routeStart, systemImage: "flag.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.14))
                            .clipShape(Capsule())

                        Label(routeEnd.isEmpty ? "Destination" : routeEnd, systemImage: "mappin.and.ellipse")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.14))
                            .clipShape(Capsule())
                    }
                }
            } else if selectedPostType == "Guide" {
                let normalizedSteps = GuidePostCodec.normalizedSteps(draftGuideSteps)

                VStack(alignment: .leading, spacing: 12) {
                    if !previewPost.title.isEmpty {
                        Text(previewPost.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(normalizedSteps.prefix(3).enumerated()), id: \.offset) { pair in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(pair.offset + 1)")
                                    .font(.caption.weight(.bold))
                                    .frame(width: 20, height: 20)
                                    .background(Color.black)
                                    .foregroundStyle(.white)
                                    .clipShape(Circle())
                                Text(pair.element)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if normalizedSteps.count > 3 {
                        Text("+\(normalizedSteps.count - 3) more steps")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if selectedPostType == "Work" || selectedPostType == "Hiring" {
                let listings = WorkPostCodec.normalizedListings(draftWorkListings)
                let phone = draftWorkContactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
                let primaryListing = listings.first ?? ""

                VStack(alignment: .leading, spacing: 12) {
                    if !primaryListing.isEmpty {
                        Text(primaryListing)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }

                    if !phone.isEmpty {
                        Text(phone)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if draftWorkDMResumeEnabled {
                        Text("DM resume enabled")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if selectedPostType == "For Sale" {
                let items = SalePostCodec.normalizedItems(draftSaleItems)
                let primaryItem = items.first ?? ""
                let phone = draftSaleContactPhone.trimmingCharacters(in: .whitespacesAndNewlines)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !primaryItem.isEmpty {
                            Text(primaryItem)
                                .font(.subheadline.weight(.semibold))
                        }

                        if !previewPost.body.isEmpty {
                            Text(previewPost.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !phone.isEmpty {
                        Text("Contact: \(phone)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if selectedPostType == "Song" {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        isSongFileImporterPresented = true
                    } label: {
                        HStack {
                            Image(systemName: "music.note.list")
                                .font(.subheadline.weight(.bold))
                            Text("Choose file")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.black, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Text("Most people share songs by linking a Spotify, Apple Music, or YouTube Music URL in the post title or description.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let selectedSongURL = draftSongFileURL {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("File ready")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(selectedSongURL.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            draftEditorForCurrentType()
                .padding(.horizontal, 12)

        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            if selectedPostType != "Text"
                && selectedPostType != "Photo"
                && selectedPostType != "Video"
                && selectedPostType != "Link"
                && selectedPostType != "Audio"
                && selectedPostType != "Song"
                && selectedPostType != "Poll"
                && selectedPostType != "Live Route"
                && selectedPostType != "Guide"
                && selectedPostType != "Work"
                && selectedPostType != "Hiring"
                && selectedPostType != "For Sale" {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black, lineWidth: 1)
            }
        }
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 8)
        .padding(.horizontal, 18)
        .onChange(of: draftPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    draftPhotoImage = image
                    persistSaleDraftState()
                }
            }
        }
    }

    static func cappedCaptionText(_ value: String, maxLength: Int = 350) -> String {
        String(value.prefix(maxLength))
    }

    private func draftEditorForCurrentType() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch selectedPostType {
            case "Text":
                let bodyBinding = Binding<String>(
                    get: { draftBody },
                    set: { draftBody = String($0.prefix(500)) }
                )

                TextEditor(text: bodyBinding)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(minHeight: 260, maxHeight: 320)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black, lineWidth: 1)
                    )
                    .lineSpacing(6)

            case "Photo":
                TextField("Add a caption (up to 350 characters)", text: Binding(
                    get: { draftBody },
                    set: { draftBody = Self.cappedCaptionText($0) }
                ))
                .font(.subheadline)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black, lineWidth: 1)
                )

            case "Video", "Photo/Video":
                TextField("Add a caption (up to 350 characters)", text: Binding(
                    get: { draftBody },
                    set: { draftBody = Self.cappedCaptionText($0) }
                ))
                .font(.subheadline)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black, lineWidth: 1)
                )

            case "Link":
                TextField("", text: Binding(
                    get: { draftUrl },
                    set: { draftUrl = String($0.prefix(300)) }
                ), prompt: Text("Link URL").foregroundStyle(.secondary))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black, lineWidth: 1)
                    )

                LinkPreviewCard(
                    urlString: draftUrl,
                    fallbackTitle: draftTitle.isEmpty ? "Link preview" : draftTitle,
                    fallbackDescription: draftBody,
                    accentColor: Color(hex: accentFor(selectedPostType))
                )
                .frame(maxWidth: .infinity)

                TextField("Add a caption (up to 350 characters)", text: Binding(
                    get: { draftBody },
                    set: { draftBody = Self.cappedCaptionText($0) }
                ))
                .font(.subheadline)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black, lineWidth: 1)
                )

            case "Audio":
                EmptyView()

            case "Song":
                EmptyView()

            case "Poll":
                TextEditor(text: Binding(
                    get: { draftPollQuestion },
                    set: { draftPollQuestion = String($0.prefix(100)) }
                ))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(minHeight: 88, maxHeight: 150)
                .padding(10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black, lineWidth: 1)
                )
                .scrollContentBackground(.hidden)
                .lineSpacing(4)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Top choice")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("", text: Binding(
                        get: { draftPollOptionA },
                        set: { draftPollOptionA = String($0.prefix(36)) }
                    ), prompt: Text("Top option").foregroundStyle(.secondary))
                        .font(.subheadline)
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.black, lineWidth: 1)
                        )

                    Text("Bottom choice")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("", text: Binding(
                        get: { draftPollOptionB },
                        set: { draftPollOptionB = String($0.prefix(36)) }
                    ), prompt: Text("Bottom option").foregroundStyle(.secondary))
                        .font(.subheadline)
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.black, lineWidth: 1)
                        )
                }

            case "Live Route":
                VStack(alignment: .leading, spacing: 12) {
                    Text(draftRouteIsRunBranding ? "Run description" : "Trip description")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextEditor(text: Binding(
                        get: { draftBody },
                        set: { draftBody = String($0.prefix(600)) }
                    ))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(minHeight: 180, maxHeight: 240)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black, lineWidth: 1)
                    )
                    .scrollContentBackground(.hidden)

                    TextField("Start location", text: Binding(
                        get: { draftRouteStart },
                        set: { draftRouteStart = String($0.prefix(70)) }
                    ))
                    .font(.subheadline)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black, lineWidth: 1)
                    )

                    TextField("Destination", text: Binding(
                        get: { draftRouteEnd },
                        set: { draftRouteEnd = String($0.prefix(70)) }
                    ))
                    .font(.subheadline)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black, lineWidth: 1)
                    )

                    Toggle(isOn: $draftRouteIsRunBranding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Brand as run")
                                .font(.subheadline.weight(.semibold))
                            Text("Turn off to keep trip branding")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .black))
                    .padding(.horizontal, 2)

                    LiveRouteMiniMapView(
                        startName: draftRouteStart,
                        endName: draftRouteEnd,
                        nearbyPlaces: nearbyPlaces,
                        height: 190
                    )
                }

            case "Guide":
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(draftGuideSteps.indices, id: \.self) { index in
                        let prompt = index == 0 ? "Step one" : "Step \(index + 1)"
                        TextField(prompt, text: Binding(
                            get: { draftGuideSteps[index] },
                            set: { draftGuideSteps[index] = String($0.prefix(120)) }
                        ), axis: .vertical)
                        .lineLimit(2...3)
                        .font(.subheadline)
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.black, lineWidth: 1)
                        )
                    }

                    HStack(spacing: 10) {
                        Button {
                            if draftGuideSteps.count < 10 {
                                draftGuideSteps.append("")
                            }
                        } label: {
                            Text("Add step")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(draftGuideSteps.count >= 10)

                        Button {
                            if draftGuideSteps.count > 1 {
                                draftGuideSteps.removeLast()
                            }
                        } label: {
                            Text("Remove")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(draftGuideSteps.count <= 1)
                    }

                    Text("Up to 10 steps. Readers press next to reveal each slide.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case "Work", "Hiring":
                VStack(alignment: .leading, spacing: 12) {
                    Text("Job")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("Job title", text: Binding(
                        get: { draftWorkListings.first ?? "" },
                        set: { newValue in
                            let sanitized = String(newValue.prefix(90))
                            if draftWorkListings.isEmpty {
                                draftWorkListings = [sanitized]
                            } else {
                                draftWorkListings[0] = sanitized
                                if draftWorkListings.count > 1 {
                                    draftWorkListings = [sanitized]
                                }
                            }
                        }
                    ))
                    .font(.subheadline)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black, lineWidth: 1)
                    )

                    TextField("Contact phone", text: Binding(
                        get: { draftWorkContactPhone },
                        set: { draftWorkContactPhone = String($0.prefix(24)) }
                    ))
                    .font(.subheadline)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black, lineWidth: 1)
                    )

                    TextField("Contact email", text: Binding(
                        get: { draftWorkContactEmail },
                        set: { draftWorkContactEmail = String($0.prefix(120)) }
                    ))
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled(true)
                    .font(.subheadline)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black, lineWidth: 1)
                    )
                }

            case "For Sale":
                VStack(alignment: .leading, spacing: 12) {
                    Text("Listing photo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    PhotosPicker(selection: $draftPhotoItem, matching: .images, photoLibrary: .shared()) {
                        HStack(spacing: 12) {
                            Group {
                                if let image = draftPhotoImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                } else {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(.secondarySystemBackground))
                                        .frame(width: 72, height: 72)
                                        .overlay(
                                            Image(systemName: "photo")
                                                .foregroundStyle(.secondary)
                                        )
                                }
                            }

                            Text(draftPhotoImage == nil ? "Add photo" : "Change photo")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.black, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    TextField("Description", text: Binding(
                        get: { draftSaleItems.first ?? "" },
                        set: { newValue in
                            let sanitized = String(newValue.prefix(100))
                            if draftSaleItems.isEmpty {
                                draftSaleItems = [sanitized]
                            } else {
                                draftSaleItems[0] = sanitized
                                if draftSaleItems.count > 1 {
                                    draftSaleItems = [sanitized]
                                }
                            }
                            persistSaleDraftState()
                        }
                    ))
                    .font(.subheadline)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black, lineWidth: 1)
                    )

                    TextField("Price", text: Binding(
                        get: { draftSalePrice },
                        set: {
                            draftSalePrice = String($0.prefix(24))
                            persistSaleDraftState()
                        }
                    ))
                    .font(.subheadline)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black, lineWidth: 1)
                    )

                    TextField("Contact phone", text: Binding(
                        get: { draftSaleContactPhone },
                        set: {
                            draftSaleContactPhone = String($0.prefix(24))
                            persistSaleDraftState()
                        }
                    ))
                    .font(.subheadline)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black, lineWidth: 1)
                    )

                    TextField("Contact email", text: Binding(
                        get: { draftSaleContactEmail },
                        set: {
                            draftSaleContactEmail = String($0.prefix(120))
                            persistSaleDraftState()
                        }
                    ))
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled(true)
                    .font(.subheadline)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black, lineWidth: 1)
                    )
                }

            default:
                TextField("", text: $draftTitle, prompt: Text("Type your post title").foregroundStyle(.secondary))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black, lineWidth: 1)
                    )

                TextField("", text: $draftBody, prompt: Text("Write your post here").foregroundStyle(.secondary), axis: .vertical)
                    .font(.body)
                    .lineLimit(5...8)
                    .foregroundStyle(.primary)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black, lineWidth: 1)
                    )
            }
        }
    }

    static func audioComposerPrimaryLabel(isRecording: Bool, hasRecording: Bool, hasPlayedRecording: Bool, isPlaying: Bool = false) -> String {
        if isRecording {
            return "Stop recording"
        }
        if !hasRecording {
            return "Record audio"
        }
        if isPlaying {
            return "Playing audio"
        }
        if hasPlayedRecording {
            return "Record again"
        }
        return "Play audio"
    }

    static func audioPostSourceURL(draftUrl: String, recordedAudioURL: URL?) -> String {
        if let recordedAudioURL {
            return recordedAudioURL.absoluteString
        }
        return draftUrl
    }

    static func isRemoteURLString(_ value: String) -> Bool {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "https" || scheme == "http"
    }

    static func persistedPostURL(contentType: String, sourceURL: String?, mediaURLs: [String]) -> String {
        let trimmedSource = sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let firstMedia = mediaURLs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        if contentType == "Audio" || contentType == "Song" {
            if !trimmedSource.isEmpty {
                return trimmedSource
            }
            if let firstMedia {
                return firstMedia
            }
        }

        let prefersMediaURL = contentType == "Video" || contentType == "Photo" || contentType == "Photo/Video"
        if prefersMediaURL, let firstMedia {
            return firstMedia
        }

        if !trimmedSource.isEmpty {
            return trimmedSource
        }

        return firstMedia ?? ""
    }

    static func photoDisplayURL(for post: MockPost) -> URL? {
        let orderedCandidates = (post.mediaURLs + [post.sourceURL ?? "", post.url])
            .compactMap { candidate in
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .filter { candidate in
                let lowered = candidate.lowercased()
                if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
                    return true
                }
                if lowered.hasPrefix("file://") || lowered.hasPrefix("/") || lowered.hasPrefix("~/") {
                    return false
                }
                return false
            }

        for candidate in orderedCandidates {
            if let url = URL(string: candidate), url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http" {
                return url
            }
        }

        return nil
    }

    static func videoDisplayURL(for post: MockPost) -> URL? {
        guard post.type == "Video" || post.type == "Photo/Video" else {
            return photoDisplayURL(for: post)
        }

        let orderedCandidates = (post.mediaURLs + [post.sourceURL ?? "", post.url])
            .compactMap { candidate in
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .filter { candidate in
                let lowered = candidate.lowercased()
                if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
                    return true
                }
                if lowered.hasPrefix("file://") {
                    return true
                }
                if lowered.hasPrefix("/") || lowered.hasPrefix("~/") {
                    return false
                }
                return false
            }

        for candidate in orderedCandidates {
            if let url = URL(string: candidate.replacingOccurrences(of: " ", with: "%20")),
               let scheme = url.scheme?.lowercased(),
               (scheme == "https" || scheme == "http" || scheme == "file") {
                return url
            }
        }

        return nil
    }

    static func ensureMediaURLsPopulated(for post: inout MockPost) {
        if post.mediaURLs.isEmpty, let sourceURL = post.sourceURL, !sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            post.mediaURLs = [sourceURL]
        }
        if post.mediaURLs.isEmpty, !post.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !post.url.hasPrefix("local-") && !post.url.hasPrefix("spot") {
            post.mediaURLs = [post.url]
        }
    }

    static func normalizedPollOptions(_ rawOptions: [String]) -> [String] {
        let cleaned = rawOptions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let bounded = Array(cleaned.prefix(4))

        if bounded.isEmpty {
            return ["Yes", "No"]
        }

        if bounded.count == 1 {
            let first = bounded.first ?? "Yes"
            return [first, "No"]
        }

        return bounded
    }

    static func saveDraftAudioRecordingURL(_ url: URL?) {
        guard let url else {
            UserDefaults.standard.removeObject(forKey: "spot_draft_recorded_audio_url")
            return
        }
        UserDefaults.standard.set(url.absoluteString, forKey: "spot_draft_recorded_audio_url")
    }

    static func loadDraftAudioRecordingURL() -> URL? {
        let raw = UserDefaults.standard.string(forKey: "spot_draft_recorded_audio_url")?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    private func makeAudioRecordingURL() -> URL {
        let baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let audioDirectory = baseURL.appendingPathComponent("RecordedAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        return audioDirectory.appendingPathComponent("spot-audio-\(UUID().uuidString).m4a")
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func startAudioRecording() {
        Task {
            guard await requestMicrophonePermission() else { return }

            await MainActor.run {
                let recordingURL = makeAudioRecordingURL()

                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                    try session.setActive(true)

                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 44100,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
                    ]

                    let recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
                    recorder.record(forDuration: Self.maxAudioRecordingDurationSeconds)
                    draftAudioRecorder = recorder
                    draftRecordedAudioURL = recordingURL
                    Self.saveDraftAudioRecordingURL(recordingURL)
                    draftUrl = recordingURL.absoluteString
                    isRecordingAudio = true
                } catch {
                    draftRecordedAudioURL = nil
                    Self.saveDraftAudioRecordingURL(nil)
                    isRecordingAudio = false
                }
            }
        }
    }

    private func stopAudioRecording() {
        draftAudioRecorder?.stop()
        draftAudioRecorder = nil
        isRecordingAudio = false
        isAudioPlaybackActive = false
        resetAudioSessionToAmbient()

        if let recorded = draftRecordedAudioURL {
            Self.saveDraftAudioRecordingURL(recorded)
            draftUrl = recorded.absoluteString
        }
    }

    private func resetAudioRecordingState() {
        audioPlaybackPlayer?.stop()
        audioPlaybackPlayer = nil
        draftAudioRecorder?.stop()
        draftAudioRecorder = nil
        draftRecordedAudioURL = nil
        Self.saveDraftAudioRecordingURL(nil)
        draftUrl = ""
        isRecordingAudio = false
        isAudioPlaybackActive = false
        hasPlayedRecordedAudio = false
        resetAudioSessionToAmbient()
    }

    private func playRecordedAudio() {
        guard let recordedURL = draftRecordedAudioURL else { return }
        isAudioPlaybackActive = true
        hasPlayedRecordedAudio = false
        playAudioPost(from: recordedURL.absoluteString)

        Task {
            guard let player = audioPlaybackPlayer else { return }
            let delay = player.duration > 0 ? player.duration : 1.0
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                if audioPlaybackPlayer === player {
                    audioPlaybackPlayer = nil
                    isAudioPlaybackActive = false
                    hasPlayedRecordedAudio = true
                    resetAudioSessionToAmbient()
                }
            }
        }
    }

    private func playAudioPost(from urlString: String) {
        let audioURL = URL(string: urlString) ?? URL(fileURLWithPath: urlString)

        if !audioURL.isFileURL {
            Task {
                do {
                    let (downloadedURL, _) = try await URLSession.shared.download(from: audioURL)
                    let fileExtension = audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("spot-audio-\(UUID().uuidString).\(fileExtension)")

                    if FileManager.default.fileExists(atPath: tempURL.path) {
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                    try FileManager.default.moveItem(at: downloadedURL, to: tempURL)

                    await MainActor.run {
                        playAudioPost(from: tempURL.absoluteString)
                    }
                } catch {
                    await MainActor.run {
                        audioPlaybackPlayer = nil
                        isAudioPlaybackActive = false
                        hasPlayedRecordedAudio = true
                        resetAudioSessionToAmbient()
                    }
                }
            }
            return
        }

        do {
            configureAudioSessionForExplicitAudioPlayback()

            let player = try AVAudioPlayer(contentsOf: audioURL)
            audioPlaybackPlayer = player
            player.prepareToPlay()
            player.play()
        } catch {
            audioPlaybackPlayer = nil
            isAudioPlaybackActive = false
            hasPlayedRecordedAudio = true
            resetAudioSessionToAmbient()
        }
    }

    private func configureAudioSessionForAppUse() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .ambient,
                mode: .default,
                options: [.mixWithOthers]
            )
        } catch {
            print("Spot audio session ambient configuration failed: \(error)")
        }
    }

    private func configureAudioSessionForExplicitAudioPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .default,
                options: []
            )
            try session.setActive(true)
        } catch {
            print("Spot audio session playback configuration failed: \(error)")
        }
    }

    private func resetAudioSessionToAmbient() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .ambient,
                mode: .default,
                options: [.mixWithOthers]
            )
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("Spot audio session reset to ambient failed: \(error)")
        }
    }

    static func normalizedLocationRealm(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return cleaned
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func resolvedPostingLocation(postLocation: String, feedLocation: String, nearbyPlaceName: String? = nil) -> String {
        let cleanedPost = postLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedFeed = feedLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNearby = nearbyPlaceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !cleanedPost.isEmpty {
            return cleanedPost
        }
        if !cleanedFeed.isEmpty {
            return cleanedFeed
        }
        if !cleanedNearby.isEmpty {
            return cleanedNearby
        }
        return "Metric"
    }

    static func resolvedPostedRealms(location: String, postedInLocations: [String]) -> [String] {
        let source = postedInLocations.isEmpty ? [location] : postedInLocations
        var seen: Set<String> = []
        var realms: [String] = []

        for raw in source {
            let normalized = normalizedLocationRealm(raw)
            guard !normalized.isEmpty else { continue }

            if seen.insert(normalized).inserted {
                realms.append(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        if realms.isEmpty {
            let fallback = location.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty {
                realms = [fallback]
            }
        }

        return realms
    }

    static func postsForLocationRealm(_ posts: [MockPost], activeLocation: String, includeVideos: Bool = true) -> [MockPost] {
        let selected = activeLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSelected = normalizedLocationRealm(selected.isEmpty ? "Tokyo, Japan" : selected)

        return posts.filter { post in
            let realms = resolvedPostedRealms(location: post.location, postedInLocations: post.postedInLocations)
            let matchesLocation = realms.contains { normalizedLocationRealm($0) == normalizedSelected }
            let matchesType = includeVideos || post.type != "Video"
            return matchesLocation && matchesType
        }
        .sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id > rhs.id
        }
    }

    static func loadViewedPostIDs() -> Set<Int> {
        let saved = UserDefaults.standard.array(forKey: "spot_viewed_post_ids") as? [Int] ?? []
        return Set(saved)
    }

    private func persistViewedPostIDs() {
        UserDefaults.standard.set(Array(viewedPostIDs), forKey: "spot_viewed_post_ids")
    }

    private func distanceMilesFromUser(to post: MockPost) -> Double? {
        guard let userCoordinate = locationService.lastKnownLocation?.coordinate else { return nil }

        let postRealms = Self.resolvedPostedRealms(location: post.location, postedInLocations: post.postedInLocations)
        let postRealmSet = Set(postRealms.map { Self.normalizedLocationRealm($0) })

        guard let matchedNearby = nearbyPlaces.first(where: { place in
            postRealmSet.contains(Self.normalizedLocationRealm(place.name))
        }) else {
            return nil
        }

        return NearbyPlaceLoader.haversineMiles(
            from: userCoordinate,
            to: CLLocationCoordinate2D(latitude: matchedNearby.latitude, longitude: matchedNearby.longitude)
        )
    }

    private func layeredFeedScore(for post: MockPost, activeLocation: String, isFriendsFeed: Bool) -> Double {
        let now = Date()
        let ageSeconds = max(1.0, now.timeIntervalSince(post.createdAt))
        let ageMinutes = max(1.0, ageSeconds / 60.0)
        let ageHours = ageMinutes / 60.0

        let trendVelocity = post.engagementScore / ageMinutes
        let trendScore = (trendVelocity * 120.0) + (post.engagementScore * 1.6)

        let recencyBoost: Double
        if ageSeconds <= 60 {
            recencyBoost = 240_000.0 - (ageSeconds * 1_200.0)
        } else if ageMinutes <= 10 {
            recencyBoost = 55_000.0 - (ageMinutes * 2_400.0)
        } else {
            recencyBoost = max(0.0, 8_000.0 - (ageHours * 350.0))
        }

        // Bring older, newly-surging posts back up.
        let resurgenceBonus: Double
        if ageHours > 6.0 && trendVelocity > 1.0 {
            resurgenceBonus = min(45_000.0, trendVelocity * 95.0)
        } else {
            resurgenceBonus = 0.0
        }

        let normalizedLocation = Self.normalizedLocationRealm(activeLocation)
        let localLayerEnabled = !isFriendsFeed && normalizedLocation != "metric"

        var localSuccessBonus = 0.0
        if localLayerEnabled {
            let preferredLocationSet = Set((recentLocations + savedLocations).map { Self.normalizedLocationRealm($0) })
            let postLocationSet = Set(Self.resolvedPostedRealms(location: post.location, postedInLocations: post.postedInLocations).map { Self.normalizedLocationRealm($0) })

            if !preferredLocationSet.isEmpty, !preferredLocationSet.intersection(postLocationSet).isEmpty {
                localSuccessBonus += 14_000.0
            }

            if let distanceMiles = distanceMilesFromUser(to: post) {
                localSuccessBonus += max(0.0, 9_000.0 - (distanceMiles * 750.0))
            }
        }

        let freshnessPenalty = ageHours > 72.0 ? min(30_000.0, (ageHours - 72.0) * 220.0) : 0.0
        let viewedPenalty = viewedPostIDs.contains(post.id) ? 90_000.0 : 0.0

        return trendScore + recencyBoost + resurgenceBonus + localSuccessBonus - freshnessPenalty - viewedPenalty
    }

    private func rankedPostsForFeed(_ candidates: [MockPost], activeLocation: String, isFriendsFeed: Bool) -> [MockPost] {
        candidates.sorted { lhs, rhs in
            let lhsScore = layeredFeedScore(for: lhs, activeLocation: activeLocation, isFriendsFeed: isFriendsFeed)
            let rhsScore = layeredFeedScore(for: rhs, activeLocation: activeLocation, isFriendsFeed: isFriendsFeed)

            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id > rhs.id
        }
    }

    private func adminPinnedRealmMap() -> [String: String] {
        var merged = UserDefaults.standard.dictionary(forKey: Self.adminPinnedPostsByRealmDefaultsKey) as? [String: String] ?? [:]

        for post in posts {
            guard let realmTag = post.tags.first(where: { $0.hasPrefix(Self.adminPinRealmTagPrefix) }) else {
                continue
            }

            let realm = String(realmTag.dropFirst(Self.adminPinRealmTagPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !realm.isEmpty else { continue }

            merged[postAdminPinStorageKey(post)] = realm
        }

        return merged
    }

    private func adminPinnedTimestampMap() -> [String: Double] {
        var merged = UserDefaults.standard.dictionary(forKey: Self.adminPinnedPostsAtDefaultsKey) as? [String: Double] ?? [:]

        for post in posts {
            guard let timestampTag = post.tags.first(where: { $0.hasPrefix(Self.adminPinTimestampTagPrefix) }) else {
                continue
            }

            let raw = String(timestampTag.dropFirst(Self.adminPinTimestampTagPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let timestamp = Double(raw) else { continue }

            merged[postAdminPinStorageKey(post)] = timestamp
        }

        return merged
    }

    private func postAdminPinStorageKey(_ post: MockPost) -> String {
        let trimmedFirestoreID = post.firestoreID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFirestoreID.isEmpty {
            return "f:\(trimmedFirestoreID)"
        }
        return "l:\(post.id)"
    }

    private func adminPinTimestamp(for post: MockPost, timestampMap: [String: Double]) -> Double {
        let key = postAdminPinStorageKey(post)
        return timestampMap[key] ?? 0
    }

    private func isAdminPinned(_ post: MockPost, for activeLocation: String, realmMap: [String: String]) -> Bool {
        let key = postAdminPinStorageKey(post)
        guard let pinnedRealm = realmMap[key] else { return false }
        let normalizedActive = Self.normalizedLocationRealm(activeLocation)
        if pinnedRealm == Self.adminPinAllNonMetricMarker {
            return normalizedActive != Self.normalizedLocationRealm("Metric")
        }
        return pinnedRealm == normalizedActive
    }

    private func prioritizeAdminPinnedPosts(_ candidates: [MockPost], activeLocation: String) -> [MockPost] {
        guard !candidates.isEmpty else { return candidates }

        let realmMap = adminPinnedRealmMap()
        if realmMap.isEmpty { return candidates }

        let timestampMap = adminPinnedTimestampMap()
        let pinned = candidates
            .filter { isAdminPinned($0, for: activeLocation, realmMap: realmMap) }
            .sorted { lhs, rhs in
                let lhsPinnedAt = adminPinTimestamp(for: lhs, timestampMap: timestampMap)
                let rhsPinnedAt = adminPinTimestamp(for: rhs, timestampMap: timestampMap)
                if lhsPinnedAt != rhsPinnedAt {
                    return lhsPinnedAt > rhsPinnedAt
                }
                return lhs.createdAt > rhs.createdAt
            }

        let unpinned = candidates.filter { !isAdminPinned($0, for: activeLocation, realmMap: realmMap) }
        return pinned + unpinned
    }

    private func orderedPosts(_ candidates: [MockPost], using rankedIDs: [Int]) -> [MockPost] {
        guard !rankedIDs.isEmpty else { return candidates }

        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        var ordered: [MockPost] = []
        ordered.reserveCapacity(candidates.count)

        for id in rankedIDs {
            if let post = byID[id] {
                ordered.append(post)
            }
        }

        let knownIDs = Set(ordered.map(\.id))
        for post in candidates where !knownIDs.contains(post.id) {
            ordered.append(post)
        }

        return ordered
    }

    private func feedRankingSignatureFor(candidates: [MockPost], location: String, followingOnly: Bool, isFriendsFeed: Bool, includeVideoResults: Bool) -> String {
        let idsPart = candidates.map { String($0.id) }.joined(separator: ",")
        return "\(Self.normalizedLocationRealm(location))|\(followingOnly)|\(isFriendsFeed)|\(includeVideoResults)|\(idsPart)"
    }

    @MainActor
    private func rebuildMainFeedRanking(candidates: [MockPost], activeLocation: String, followingOnly: Bool, isFriendsFeed: Bool, includeVideoResults: Bool, force: Bool = false) {
        let signature = feedRankingSignatureFor(
            candidates: candidates,
            location: activeLocation,
            followingOnly: followingOnly,
            isFriendsFeed: isFriendsFeed,
            includeVideoResults: includeVideoResults
        )

        guard force || signature != feedRankingSignature else { return }

        let ranked = rankedPostsForFeed(candidates, activeLocation: activeLocation, isFriendsFeed: isFriendsFeed)
        feedRankedPostIDs = ranked.map(\.id)
        feedRankingSignature = signature
        feedLoadedCount = min(max(3, feedLoadedCount), max(0, ranked.count))
        if force {
            feedLoadedCount = min(3, ranked.count)
        }
    }

    @MainActor
    private func rebuildVideoFeedRanking(candidates: [MockPost], activeLocation: String, followingOnly: Bool, isFriendsFeed: Bool, force: Bool = false) {
        let signature = feedRankingSignatureFor(
            candidates: candidates,
            location: activeLocation,
            followingOnly: followingOnly,
            isFriendsFeed: isFriendsFeed,
            includeVideoResults: true
        )

        guard force || signature != videoFeedRankingSignature else { return }

        let ranked = rankedPostsForFeed(candidates, activeLocation: activeLocation, isFriendsFeed: isFriendsFeed)
        videoFeedRankedPostIDs = ranked.map(\.id)
        videoFeedRankingSignature = signature
        lazyVideoLoadedCount = min(max(4, lazyVideoLoadedCount), max(0, ranked.count))
        if force {
            lazyVideoLoadedCount = min(4, ranked.count)
        }
    }

    static func persistImage(_ image: UIImage, forKey key: String) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func cachedImage(forKey key: String) -> UIImage? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return UIImage(data: data)
    }

    static func postPhotoCacheKey(forPostID postID: Int) -> String {
        "spot_post_photo_\(postID)"
    }

    private func makeDraftPost(id: Int = 999) -> MockPost {
        let location = draftLocation.isEmpty ? (postLocation.isEmpty ? "Tokyo, Japan" : postLocation) : draftLocation
        let cappedTitle = String(draftTitle.prefix(35))
        let cappedBody = (selectedPostType == "Photo" || selectedPostType == "Video" || selectedPostType == "Link" || selectedPostType == "Photo/Video")
            ? Self.cappedCaptionText(draftBody)
            : String(draftBody.prefix(500))
        let realName = profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "You" : profileName
        let realHandle = profileUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "you" : profileUsername.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@") ? String(profileUsername.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst()) : profileUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftAuthorName = draftIsAnonymous ? Self.anonymousDisplayName : realName
        let draftAuthorHandle = draftIsAnonymous ? Self.anonymousHandle : realHandle
        let brandedRouteTitle = draftRouteIsRunBranding
            ? (realName.hasSuffix("s") ? "\(realName)' run" : "\(realName)'s run")
            : (realName.hasSuffix("s") ? "\(realName)' trip" : "\(realName)'s trip")
        let brandedWorkTitle = realName.hasSuffix("s") ? "\(realName)' hiring" : "\(realName)'s hiring"
        let title = selectedPostType == "Poll" ? draftPollQuestion : (selectedPostType == "Live Route" ? brandedRouteTitle : ((selectedPostType == "Work" || selectedPostType == "Hiring") ? brandedWorkTitle : cappedTitle))
        let body = selectedPostType == "Poll"
            ? draftBody
            : ((selectedPostType == "Work" || selectedPostType == "Hiring") ? "" : cappedBody)
        let resolvedAudioURL = selectedPostType == "Audio" ? Self.audioPostSourceURL(draftUrl: draftUrl, recordedAudioURL: draftRecordedAudioURL) : (draftUrl.isEmpty ? defaultURLFor(selectedPostType) : draftUrl)
        let resolvedSongURL = selectedPostType == "Song" ? (draftSongFileURL?.absoluteString ?? (draftUrl.isEmpty ? defaultURLFor(selectedPostType) : draftUrl)) : (draftUrl.isEmpty ? defaultURLFor(selectedPostType) : draftUrl)
        let resolvedVideoURL = selectedPostType == "Video" ? (draftVideoURL?.absoluteString ?? (draftUrl.isEmpty ? defaultURLFor(selectedPostType) : draftUrl)) : (draftUrl.isEmpty ? defaultURLFor(selectedPostType) : draftUrl)
        let songArtworkImage = selectedPostType == "Song" ? SongPostRules.embeddedArtworkImage(from: draftSongFileURL ?? (URL(string: draftUrl) ?? nil)) : nil
        let routeStart = draftRouteStart.trimmingCharacters(in: .whitespacesAndNewlines)
        let routeEnd = draftRouteEnd.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedRouteURL = LiveRouteCodec.encode(start: routeStart, end: routeEnd, isRunBranding: draftRouteIsRunBranding)
        let resolvedGuideURL = GuidePostCodec.encode(steps: draftGuideSteps)
        let resolvedWorkURL = WorkPostCodec.encode(listings: draftWorkListings, phone: draftWorkContactPhone, email: draftWorkContactEmail, dmResume: draftWorkDMResumeEnabled)
        let resolvedSaleURL = SalePostCodec.encode(items: draftSaleItems, price: draftSalePrice, phone: draftSaleContactPhone, email: draftSaleContactEmail)
        let url = selectedPostType == "Audio"
            ? resolvedAudioURL
            : (selectedPostType == "Song"
                ? resolvedSongURL
            : (selectedPostType == "Video"
                ? resolvedVideoURL
                : (selectedPostType == "Live Route"
                    ? resolvedRouteURL
                    : (selectedPostType == "Guide"
                        ? resolvedGuideURL
                        : ((selectedPostType == "Work" || selectedPostType == "Hiring")
                            ? resolvedWorkURL
                            : (selectedPostType == "For Sale"
                                ? resolvedSaleURL
                                : (draftUrl.isEmpty ? defaultURLFor(selectedPostType) : draftUrl)))))))
        let accent = accentFor(selectedPostType)
        let routeTag = routeStart.isEmpty || routeEnd.isEmpty ? "Route" : "\(routeStart) -> \(routeEnd)"
        let guideStepsCount = GuidePostCodec.normalizedSteps(draftGuideSteps).count
        let guideTag = guideStepsCount == 1 ? "1 step" : "\(guideStepsCount) steps"
        let workCount = WorkPostCodec.normalizedListings(draftWorkListings).count
        let workTag = workCount == 1 ? "1 opening" : "\(workCount) openings"
        let saleCount = SalePostCodec.normalizedItems(draftSaleItems).count
        let saleTag = saleCount == 1 ? "1 item" : "\(saleCount) items"
        let resolvedAreaTag = selectedPostType == "Live Route" ? routeTag : (selectedPostType == "Guide" ? guideTag : ((selectedPostType == "Work" || selectedPostType == "Hiring") ? workTag : (selectedPostType == "For Sale" ? saleTag : location.trimmingCharacters(in: .whitespacesAndNewlines))))
        let tag = resolvedAreaTag.isEmpty ? "Anywhere" : resolvedAreaTag

        let pollOptions: [String]
        var pollVotes: [Int]

        if selectedPostType == "Poll" {
            let normalized = Self.normalizedPollOptions([draftPollOptionA, draftPollOptionB])
            pollOptions = normalized

            if pollOptions.isEmpty {
                pollVotes = [0, 0]
            } else if pollOptions.count == 1 {
                let firstVote = 0
                pollVotes = [firstVote, 0]
            } else {
                pollVotes = Array(repeating: 0, count: min(pollOptions.count, 2))
            }
        } else {
            pollOptions = []
            pollVotes = []
        }

        return MockPost(
            id: id,
            author: draftAuthorName,
            handle: draftAuthorHandle,
            authorProfilePhotoURL: draftIsAnonymous ? nil : (profilePhotoRemoteURL.isEmpty ? nil : profilePhotoRemoteURL),
            type: selectedPostType,
            location: location,
            title: title,
            body: body,
            url: url,
            accent: accent,
            tag: tag,
            likes: 0,
            isLiked: false,
            comments: [],
            sentTo: [],
            pollOptions: pollOptions,
            pollVotes: pollVotes,
            mediaImage: selectedPostType == "Song" ? (songArtworkImage ?? draftPhotoImage) : draftPhotoImage,
            postedInLocations: [location],
            isAnonymous: draftIsAnonymous
        )
    }

    private func resetDraftFor(_ type: String) {
        draftIsAnonymous = isAnonymousModeEnabled
        draftTitle = ""
        draftBody = ""
        draftUrl = ""
        draftLocation = postLocation.isEmpty ? "Tokyo, Japan" : postLocation
        draftPollQuestion = ""
        draftPollOptionA = ""
        draftPollOptionB = ""
        draftRouteStart = ""
        draftRouteEnd = ""
        draftRouteIsRunBranding = false
        draftGuideSteps = [""]
        draftWorkListings = [""]
        draftWorkContactPhone = ""
        draftWorkContactEmail = ""
        draftWorkDMResumeEnabled = false
        draftSaleItems = [""]
        draftSalePrice = ""
        draftSaleContactPhone = ""
        draftSaleContactEmail = ""
        draftPhotoItem = nil
        clearSaleDraftState()
        draftVideoItem = nil
        draftVideoURL = nil
        draftRecordedAudioURL = nil
        draftSongFileURL = nil
        Self.saveDraftAudioRecordingURL(nil)
        draftAudioRecorder?.stop()
        draftAudioRecorder = nil
        isRecordingAudio = false
        draftPhotoImage = nil
    }

    private func prepareSongDefaultsIfNeeded() {
        if draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftBody = ""
        }
    }

    private func prepareWorkDefaultsIfNeeded() {
        let normalizedListings = WorkPostCodec.normalizedListings(draftWorkListings)
        draftWorkListings = [normalizedListings.first ?? ""]

        if draftWorkContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let sourcePhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            draftWorkContactPhone = sourcePhone
        }

        if draftWorkContactEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftWorkContactEmail = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func prepareSaleDefaultsIfNeeded() {
        let normalizedItems = SalePostCodec.normalizedItems(draftSaleItems)
        draftSaleItems = [normalizedItems.first ?? ""]

        if draftSaleContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftSaleContactPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if draftSaleContactEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftSaleContactEmail = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        persistSaleDraftState()
    }

    private func persistSaleDraftState() {
        guard selectedPostType == "For Sale" else { return }
        let payload = SaleDraftPersistence(
            item: draftSaleItems.first ?? "",
            price: draftSalePrice,
            phone: draftSaleContactPhone,
            email: draftSaleContactEmail,
            description: draftBody,
            photoData: draftPhotoImage?.jpegData(compressionQuality: 0.85)
        )

        if let encoded = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(encoded, forKey: Self.saleDraftPersistenceKey)
        }
    }

    private func clearSaleDraftState() {
        UserDefaults.standard.removeObject(forKey: Self.saleDraftPersistenceKey)
    }

    private func restoreSaleDraftStateIfNeeded() {
        guard selectedPostType == "For Sale" else { return }
        guard let data = UserDefaults.standard.data(forKey: Self.saleDraftPersistenceKey),
              let payload = try? JSONDecoder().decode(SaleDraftPersistence.self, from: data) else {
            return
        }

        draftBody = payload.description
        draftSaleItems = payload.item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [""] : [payload.item]
        draftSalePrice = payload.price
        draftSaleContactPhone = payload.phone
        draftSaleContactEmail = payload.email

        if let photoData = payload.photoData, let restoredImage = UIImage(data: photoData) {
            draftPhotoImage = restoredImage
        } else {
            draftPhotoImage = nil
        }
    }

    private func prepareGuideDefaultsIfNeeded() {
        let normalized = GuidePostCodec.normalizedSteps(draftGuideSteps)
        if normalized.isEmpty {
            draftGuideSteps = [""]
        } else {
            draftGuideSteps = normalized
        }
    }

    private func prepareLiveRouteDefaultsIfNeeded() {
        if draftRouteStart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftRouteStart = nearbyPlaces.first?.name ?? (postLocation.isEmpty ? "Start" : postLocation)
        }

        if draftRouteEnd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if nearbyPlaces.count > 1 {
                draftRouteEnd = nearbyPlaces[1].name
            } else {
                draftRouteEnd = draftLocation.isEmpty ? "Destination" : draftLocation
            }
        }
    }

    private func postTypeBackground(for type: String) -> Color {
        return .white
    }

    private func postTypeIcon(for type: String) -> String {
        switch type {
        case "Text": return "text.alignleft"
        case "Photo": return "photo.fill"
        case "Video": return "play.fill"
        case "Photo/Video": return "photo.on.rectangle.angled"
        case "Link": return "link"
        case "Audio": return "waveform"
        case "Song": return "music.note.list"
        case "Poll": return "chart.pie.fill"
        case "Live Route": return "point.topleft.down.curvedto.point.bottomright.up"
        case "Guide": return "list.number"
        case "Work", "Hiring": return "briefcase.fill"
        case "For Sale": return "tag.fill"
        default: return "waveform"
        }
    }

    private func postTypeBorderColor(for type: String) -> Color {
        return .clear
    }

    private func postTypeIconColor(for type: String) -> Color {
        return .black
    }

    private func displayNameForPostType(_ type: String) -> String {
        switch type {
        case "For Sale": return "Listing"
        default: return type
        }
    }

    private func postTypeDescription(for type: String) -> String {
        switch type {
        case "Text": return "A thought, note, or story."
        case "Photo": return "Share a still image from this place."
        case "Video": return "Share a short moving moment from here."
        case "Photo/Video": return "Share a photo or video from this place."
        case "Link": return "Send a location or article."
        case "Audio": return "Share a short audio clip."
        case "Song": return "Share a full song file and tap play to listen."
        case "Poll": return "Ask a question and let people vote."
        case "Live Route": return "Share your trip with a route and story."
        case "Guide": return "Share a step-by-step guide with up to 10 slides."
        case "Work", "Hiring": return "Post jobs with phone or email contact."
        case "For Sale": return "List items with price and contact phone."
        default: return "Share a short audio clip."
        }
    }

    private func defaultTitleFor(_ type: String) -> String {
        ""
    }

    private func defaultBodyFor(_ type: String) -> String {
        ""
    }

    private func defaultURLFor(_ type: String) -> String {
        switch type {
        case "Link": return "spot-link.example"
        case "Photo", "Video", "Photo/Video": return "media-example.example"
        case "Audio": return "audio-example.example"
        case "Song": return "song-example.example"
        case "Poll": return "poll-example.example"
        case "Live Route": return "spotroute://route"
        case "Guide": return "spotguide://slides"
        case "Work", "Hiring": return "spotwork://listing"
        case "For Sale": return "spotsale://listing"
        default: return "place-example.example"
        }
    }

    private func accentFor(_ type: String) -> String {
        switch type {
        case "Text": return "#F7D7B5"
        case "Photo": return "#DCE7FF"
        case "Video": return "#E5D9FF"
        case "Photo/Video": return "#DCE7FF"
        case "Link": return "#DFF4E6"
        case "Audio": return "#DDEEFF"
        case "Song": return "#D7E6FF"
        case "Poll": return "#E5D9FF"
        case "Live Route": return "#D8F1EA"
        case "Guide": return "#FFF3D8"
        case "Work", "Hiring": return "#E9F0FF"
        case "For Sale": return "#FFE8D9"
        default: return "#DDEEFF"
        }
    }

    private func isUserFollowed(authorUserID: String = "", username: String = "") -> Bool {
        let trimmedAuthorID = authorUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAuthorID.isEmpty, followedUserIDs.contains(trimmedAuthorID) {
            return true
        }

        let target = username.lowercased()
        return communityUsers.contains { user in
            user.username.lowercased() == target && user.isFollowing
        }
    }

    private func isUserMutualFollowed(authorUserID: String = "", username: String = "") -> Bool {
        let trimmedAuthorID = authorUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAuthorID.isEmpty {
            return followedUserIDs.contains(trimmedAuthorID) && followerUserIDs.contains(trimmedAuthorID)
        }

        let normalizedTarget = FirebaseSpotService.normalizeUsername(username)
        guard !normalizedTarget.isEmpty else { return false }
        return communityUsers.contains { user in
            FirebaseSpotService.normalizeUsername(user.username) == normalizedTarget && user.isFollowing
        }
    }

    private func isFriendsRealm(_ locationName: String) -> Bool {
        Self.normalizedLocationRealm(locationName) == Self.normalizedLocationRealm("Friends")
    }

    private func applyFollowCountsLocally(userID: String, username: String, followers: Int, following: Int) {
        let trimmedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUsername = FirebaseSpotService.normalizeUsername(username)
        let normalizedCurrentUsername = FirebaseSpotService.normalizeUsername(profileUsername)

        let updatesCurrentUserByID = !trimmedUserID.isEmpty
            && !currentUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && trimmedUserID == currentUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatesCurrentUserByUsername = !normalizedUsername.isEmpty
            && !normalizedCurrentUsername.isEmpty
            && normalizedUsername == normalizedCurrentUsername
        if updatesCurrentUserByID || updatesCurrentUserByUsername {
            currentUserFollowerCount = max(0, followers)
            currentUserFollowingCount = max(0, following)
        }

        if !trimmedUserID.isEmpty {
            fakeUserProfiles = fakeUserProfiles.map { profile in
                guard profile.userID == trimmedUserID else { return profile }
                return FakeUserProfile(
                    userID: profile.userID,
                    username: profile.username,
                    name: profile.name,
                    city: profile.city,
                    bio: profile.bio,
                    followerCount: followers,
                    followingCount: following,
                    profilePhotoText: profile.profilePhotoText,
                    profilePhotoURL: profile.profilePhotoURL
                )
            }
        }

        if !normalizedUsername.isEmpty {
            fakeUserProfiles = fakeUserProfiles.map { profile in
                guard FirebaseSpotService.normalizeUsername(profile.username) == normalizedUsername else { return profile }
                return FakeUserProfile(
                    userID: profile.userID,
                    username: profile.username,
                    name: profile.name,
                    city: profile.city,
                    bio: profile.bio,
                    followerCount: followers,
                    followingCount: following,
                    profilePhotoText: profile.profilePhotoText,
                    profilePhotoURL: profile.profilePhotoURL
                )
            }
        }

        if let selected = selectedUserProfile {
            let selectedByID = !trimmedUserID.isEmpty && selected.userID == trimmedUserID
            let selectedByUsername = !normalizedUsername.isEmpty && FirebaseSpotService.normalizeUsername(selected.username) == normalizedUsername
            if selectedByID || selectedByUsername {
                selectedUserProfile = FakeUserProfile(
                    userID: selected.userID,
                    username: selected.username,
                    name: selected.name,
                    city: selected.city,
                    bio: selected.bio,
                    followerCount: followers,
                    followingCount: following,
                    profilePhotoText: selected.profilePhotoText,
                    profilePhotoURL: selected.profilePhotoURL
                )
            }
        }
    }

    private func toggleFollowState(for profile: FakeUserProfile) {
        guard !isOwnProfile(profile) else { return }

        let targetUserID = profile.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetUsername = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentlyFollowed = isUserFollowed(authorUserID: targetUserID, username: targetUsername)
        let shouldFollow = !currentlyFollowed

        Task {
            let followerUserID = await ensureAuthenticatedUserRecord()
            guard !followerUserID.isEmpty else {
                await MainActor.run {
                    accountAuthMessage = "Sign in to follow accounts."
                }
                return
            }

            if !targetUserID.isEmpty {
                do {
                    try await FirebaseSpotService.shared.setFollowState(
                        followerUserID: followerUserID,
                        followedUserID: targetUserID,
                        isFollowing: shouldFollow
                    )

                    let counts = try await FirebaseSpotService.shared.fetchUserFollowCounts(userID: targetUserID)
                    let currentUserCounts = try await FirebaseSpotService.shared.fetchUserFollowCounts(userID: followerUserID)
                    await MainActor.run {
                        if shouldFollow {
                            followedUserIDs.insert(targetUserID)
                        } else {
                            followedUserIDs.remove(targetUserID)
                        }

                        applyFollowCountsLocally(
                            userID: targetUserID,
                            username: targetUsername,
                            followers: counts.followers,
                            following: counts.following
                        )

                        applyFollowCountsLocally(
                            userID: followerUserID,
                            username: profileUsername,
                            followers: currentUserCounts.followers,
                            following: currentUserCounts.following
                        )
                    }
                } catch {
                    await MainActor.run {
                        accountAuthMessage = "Could not update follow right now."
                    }
                }
            }

            await MainActor.run {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                    if let index = communityUsers.firstIndex(where: { $0.username.lowercased() == targetUsername.lowercased() }) {
                        communityUsers[index].isFollowing = shouldFollow
                    } else if !targetUsername.isEmpty {
                        communityUsers.append(UserProfile(username: targetUsername, name: profile.name, isFollowing: shouldFollow))
                    }
                }
            }

            await refreshFollowingUIDs()

            if !targetUserID.isEmpty {
                await refreshSelectedUserProfileFromRecord(expectedUserID: targetUserID)
            }
        }
    }

    private func activeUserID() -> String {
        let stableDeviceID = FirebaseSpotService.makeStableDeviceUserID()
        currentUserID = stableDeviceID

        if let authenticatedID = try? FirebaseSpotService.shared.currentUserID() {
            currentUserID = authenticatedID
            return authenticatedID
        }

        Task {
            do {
                let user = try await FirebaseSpotService.shared.ensureAuthenticatedUser(username: profileUsername.isEmpty ? "user" : profileUsername)
                currentUserID = user.uid
            } catch {
                currentUserID = stableDeviceID
            }
        }

        return currentUserID
    }

    private func persistResolvedUserID(_ userID: String) {
        currentUserID = userID
        UserDefaults.standard.set(userID, forKey: "spot_firebase_user_id")
    }

    private func hydratePersistedIdentity() {
        let savedName = UserDefaults.standard.string(forKey: profileNameDefaultsKey) ?? ""
        let savedUsername = UserDefaults.standard.string(forKey: accountUsernameDefaultsKey) ?? ""
        let savedEmail = UserDefaults.standard.string(forKey: accountEmailDefaultsKey) ?? ""

        if !savedName.isEmpty {
            profileName = savedName
        }

        if !savedUsername.isEmpty {
            profileUsername = savedUsername
            accountUsername = savedUsername
        }

        if !savedEmail.isEmpty {
            accountEmail = savedEmail
        }
    }

    static func preferredUserID(currentUserID: String?, persistedUserID: String?, fallbackUserID: String) -> String {
        if let currentUserID, !currentUserID.isEmpty {
            return currentUserID
        }
        if let persistedUserID, !persistedUserID.isEmpty {
            return persistedUserID
        }
        return fallbackUserID
    }

    static func shouldRestoreSavedAccount(accountSignedIn: Bool, savedEmail: String, savedPassword: String) -> Bool {
        guard accountSignedIn else { return false }
        return !savedEmail.isEmpty && !savedPassword.isEmpty
    }

    private func resolveAuthenticatedUserID() async -> String {
        if let authenticatedID = try? FirebaseSpotService.shared.currentUserID(), !authenticatedID.isEmpty {
            persistResolvedUserID(authenticatedID)
            return authenticatedID
        }

        let accountSignedIn = UserDefaults.standard.bool(forKey: accountSignedInDefaultsKey)
        let savedEmail = UserDefaults.standard.string(forKey: accountEmailDefaultsKey) ?? ""
        let savedPassword = UserDefaults.standard.string(forKey: accountPasswordDefaultsKey) ?? ""

        if Self.shouldRestoreSavedAccount(accountSignedIn: accountSignedIn, savedEmail: savedEmail, savedPassword: savedPassword) {
            do {
                let user = try await FirebaseSpotService.shared.signIn(email: savedEmail, password: savedPassword)
                persistResolvedUserID(user.uid)
                await MainActor.run {
                    hydratePersistedIdentity()
                    if let profileFromUser = UserDefaults.standard.string(forKey: profileNameDefaultsKey), !profileFromUser.isEmpty {
                        profileName = profileFromUser
                    }
                    if let usernameFromUser = UserDefaults.standard.string(forKey: accountUsernameDefaultsKey), !usernameFromUser.isEmpty {
                        profileUsername = usernameFromUser
                        accountUsername = usernameFromUser
                    }
                }
                return user.uid
            } catch {
                print("Spot restored account sign-in failed: \(error)")
            }
        }

        return ""
    }

    private func uploadDraftMedia(postID: Int) async -> [String] {
        var uploadedURLs: [String] = []

        if let photo = draftPhotoImage,
           let imageData = photo.jpegData(compressionQuality: 0.8) {
            let fileName = "photo_\(UUID().uuidString).jpg"
            if let url = try? await FirebaseSpotService.shared.uploadMedia(data: imageData, folder: "posts/\(postID)/photos", fileName: fileName) {
                uploadedURLs.append(url)
            }
        }

        if let recordedURL = draftRecordedAudioURL,
           let audioData = try? Data(contentsOf: recordedURL) {
            let fileName = "audio_\(UUID().uuidString).m4a"
            if let url = try? await FirebaseSpotService.shared.uploadMedia(data: audioData, folder: "posts/\(postID)/audio", fileName: fileName) {
                uploadedURLs.append(url)
            }
        }

        if selectedPostType == "Song", let songURL = draftSongFileURL {
            let preparedSongURL = copyVideoToTemporaryLocation(sourceURL: songURL) ?? songURL
            let songExt = preparedSongURL.pathExtension.isEmpty ? "mp3" : preparedSongURL.pathExtension
            let fileName = "song_\(UUID().uuidString).\(songExt)"

            if let uploadedSongURL = try? await FirebaseSpotService.shared.uploadMediaFile(fileURL: preparedSongURL, folder: "posts/\(postID)/songs", fileName: fileName) {
                uploadedURLs.append(uploadedSongURL)
            } else if let songData = try? Data(contentsOf: preparedSongURL),
                      let fallbackURL = try? await FirebaseSpotService.shared.uploadMedia(data: songData, folder: "posts/\(postID)/songs", fileName: fileName) {
                uploadedURLs.append(fallbackURL)
            }
        }

        if let videoURL = draftVideoURL {
            let preparedVideoURL = copyVideoToTemporaryLocation(sourceURL: videoURL) ?? videoURL
            let extensionHint = preparedVideoURL.pathExtension.isEmpty ? "mp4" : preparedVideoURL.pathExtension
            let fileName = "video_\(UUID().uuidString).\(extensionHint)"

            if let url = try? await FirebaseSpotService.shared.uploadMediaFile(fileURL: preparedVideoURL, folder: "posts/\(postID)/videos", fileName: fileName) {
                uploadedURLs.append(url)
            } else if let videoData = try? Data(contentsOf: preparedVideoURL),
                      let fallbackURL = try? await FirebaseSpotService.shared.uploadMedia(data: videoData, folder: "posts/\(postID)/videos", fileName: fileName) {
                uploadedURLs.append(fallbackURL)
            }
        }

        let cleanedDraftURL = draftUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldCarrySourceURL = selectedPostType == "Link"
            || ((selectedPostType == "Audio" || selectedPostType == "Song" || selectedPostType == "Video")
                && uploadedURLs.isEmpty
                && Self.isRemoteURLString(cleanedDraftURL))

        if shouldCarrySourceURL, !cleanedDraftURL.isEmpty {
            uploadedURLs.append(cleanedDraftURL)
        }

        return uploadedURLs
    }

    private func copyVideoToTemporaryLocation(sourceURL: URL) -> URL? {
        guard sourceURL.isFileURL else {
            return sourceURL
        }

        let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension)

        let didAccessScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            return nil
        }
    }

    private func fallbackDraftMediaURLs(for post: MockPost) -> [String] {
        switch post.type {
        case "Photo", "Photo/Video":
            // Photo bytes are cached locally by post ID, so a stable local token keeps rendering functional.
            return draftPhotoImage == nil ? [] : ["local-photo://\(post.id)"]
        case "Video":
            let localOrRemoteVideo = (draftVideoURL?.absoluteString ?? draftUrl).trimmingCharacters(in: .whitespacesAndNewlines)
            return localOrRemoteVideo.isEmpty ? [] : [localOrRemoteVideo]
        case "Audio":
            let localOrRemoteAudio = Self.audioPostSourceURL(draftUrl: draftUrl, recordedAudioURL: draftRecordedAudioURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return localOrRemoteAudio.isEmpty ? [] : [localOrRemoteAudio]
        case "Song":
            let localOrRemoteSong = (draftSongFileURL?.absoluteString ?? draftUrl).trimmingCharacters(in: .whitespacesAndNewlines)
            return localOrRemoteSong.isEmpty ? [] : [localOrRemoteSong]
        default:
            return []
        }
    }

    private func firebasePayload(for post: MockPost, authorID: String, mediaURLs: [String] = []) -> FirebasePostPayload {
        let fallbackMediaURLs: [String]
        if mediaURLs.isEmpty {
            let cleanedURL = post.url.trimmingCharacters(in: .whitespacesAndNewlines)
            fallbackMediaURLs = cleanedURL.isEmpty ? [] : [cleanedURL]
        } else {
            fallbackMediaURLs = mediaURLs
        }
        let resolvedSourceURL: String?
        if post.type == "Link" {
            let cleanedURL = post.url.trimmingCharacters(in: .whitespacesAndNewlines)
            resolvedSourceURL = cleanedURL.isEmpty ? nil : cleanedURL
        } else if post.type == "Audio" || post.type == "Song" {
            let remoteAudioURL = fallbackMediaURLs.first { Self.isRemoteURLString($0) }
            if let remoteAudioURL, !remoteAudioURL.isEmpty {
                resolvedSourceURL = remoteAudioURL
            } else {
                let cleanedURL = post.url.trimmingCharacters(in: .whitespacesAndNewlines)
                resolvedSourceURL = Self.isRemoteURLString(cleanedURL) ? cleanedURL : nil
            }
        } else {
            resolvedSourceURL = Self.isRemoteURLString(post.url) ? post.url : nil
        }
        let postedRealms = Self.resolvedPostedRealms(location: post.location, postedInLocations: post.postedInLocations)
        let payloadAuthorUsername = post.isAnonymous
            ? Self.anonymousHandle
            : displayUsername(profileUsername.isEmpty ? "you" : profileUsername)
        let payloadAuthorDisplayName = post.isAnonymous
            ? Self.anonymousDisplayName
            : (profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "You" : profileName)
        let rawPayloadTags = [
            post.tag,
            post.isAnonymous ? Self.anonymousTagMarker : nil,
            post.isBoosted ? Self.boostedTagMarker : nil
        ].compactMap { $0 }
        var seenPayloadTags: Set<String> = []
        let payloadTags = rawPayloadTags.filter { tag in
            let cleanedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedTag.isEmpty else { return false }
            if seenPayloadTags.contains(cleanedTag) { return false }
            seenPayloadTags.insert(cleanedTag)
            return true
        }

        return FirebasePostPayload(
            id: String(post.id),
            authorID: authorID,
            authorUsername: payloadAuthorUsername,
            authorDisplayName: payloadAuthorDisplayName,
            authorProfilePhotoURL: post.isAnonymous ? nil : (profilePhotoRemoteURL.isEmpty ? nil : profilePhotoRemoteURL),
            contentType: post.type,
            title: post.title,
            body: post.body,
            sourceURL: resolvedSourceURL,
            mediaURLs: fallbackMediaURLs,
            pollOptions: post.pollOptions,
            pollVotes: post.pollVotes,
            accentHex: post.accent,
            locationName: post.location,
            feedInsertionIndex: 0,
            postedInLocations: postedRealms,
            poiID: nil,
            latitude: 0,
            longitude: 0,
            city: post.location,
            country: nil,
            geohash: nil,
            createdAt: post.createdAt.timeIntervalSince1970,
            updatedAt: Date().timeIntervalSince1970,
            isVideo: post.type == "Video" || post.type == "Photo/Video",
            visibilityScope: "nearby",
            tags: payloadTags,
            likesCount: post.likes,
            commentsCount: post.comments.count,
            viewCount: post.viewCount,
            totalViewDurationSeconds: post.timeViewedSeconds,
            savedCount: post.savedCount,
            shareCount: post.shareCount,
            score: post.engagementScore
        )
    }

    static func postsAfterSyncAttempt(currentPosts: [MockPost], persistedPosts: [FirebasePostPayload], syncError: Error?, ownerHandle: String = "you", ownerName: String = "You") -> [MockPost] {
        if let syncError {
            return currentPosts
        }

        let currentByID = Dictionary(uniqueKeysWithValues: currentPosts.map { ($0.id, $0) })

        let mapped = persistedPosts.map { payload in
            let numericID = Int(payload.id.filter { $0.isNumber }) ?? abs(payload.id.hashValue)
            let cachedImage = payload.mediaURLs.first.flatMap { _ in
                let key = Self.postPhotoCacheKey(forPostID: numericID)
                return Self.cachedImage(forKey: key)
            }
            let resolvedHandle = FirebaseSpotService.normalizeUsername(payload.authorUsername)
            let resolvedAuthor = payload.authorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ownerName : payload.authorDisplayName
            let resolvedURL = persistedPostURL(contentType: payload.contentType, sourceURL: payload.sourceURL, mediaURLs: payload.mediaURLs)
            let resolvedAccent = payload.accentHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "#DCE7FF" : payload.accentHex
            let resolvedRealms = resolvedPostedRealms(location: payload.locationName, postedInLocations: payload.postedInLocations)
            let normalizedPayloadUsername = FirebaseSpotService.normalizeUsername(payload.authorUsername)
            let isAnonymousPost = payload.tags.contains(Self.anonymousTagMarker)
                || normalizedPayloadUsername == Self.anonymousHandle
            let isBoostedPost = payload.tags.contains(Self.boostedTagMarker)
            let visibleTag = payload.tags.first(where: { !$0.hasPrefix("spot:") }) ?? payload.locationName

            return MockPost(
                id: numericID,
                author: isAnonymousPost ? Self.anonymousDisplayName : resolvedAuthor,
                handle: isAnonymousPost ? Self.anonymousHandle : (resolvedHandle.isEmpty ? ownerHandle : resolvedHandle),
                authorUserID: payload.authorID,
                authorProfilePhotoURL: isAnonymousPost ? nil : payload.authorProfilePhotoURL,
                type: payload.contentType,
                location: payload.locationName,
                title: payload.title ?? "",
                body: payload.body ?? "",
                url: resolvedURL,
                accent: resolvedAccent,
                tag: visibleTag,
                likes: payload.likesCount,
                viewCount: payload.viewCount,
                timeViewedSeconds: payload.totalViewDurationSeconds,
                savedCount: payload.savedCount,
                shareCount: payload.shareCount,
                peakEngagementScore: payload.score,
                isLiked: false,
                comments: [],
                sentTo: [],
                pollOptions: payload.pollOptions,
                pollVotes: payload.pollVotes,
                mediaImage: cachedImage,
                mediaURLs: payload.mediaURLs,
                sourceURL: payload.sourceURL,
                tags: payload.tags,
                isBoosted: isBoostedPost,
                postedInLocations: resolvedRealms,
                createdAt: Date(timeIntervalSince1970: payload.createdAt),
                firestoreID: payload.id,
                isAnonymous: isAnonymousPost
            )
        }

        let merged = mapped.map { persisted in
            guard let current = currentByID[persisted.id] else {
                return persisted
            }

            var next = persisted
            next.viewCount = max(current.viewCount, persisted.viewCount)
            next.timeViewedSeconds = max(current.timeViewedSeconds, persisted.timeViewedSeconds)
            next.savedCount = max(current.savedCount, persisted.savedCount)
            next.shareCount = max(current.shareCount, persisted.shareCount)
            next.likes = max(current.likes, persisted.likes)
            next.isBoosted = current.isBoosted || persisted.isBoosted
            next.peakEngagementScore = max(current.peakEngagementScore, persisted.peakEngagementScore, next.realEngagementScore)

            // Keep the richer local media when backend hydration is still catching up.
            if next.mediaImage == nil, let currentImage = current.mediaImage {
                next.mediaImage = currentImage
            }

            return next
        }

        let ordered = merged.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id > rhs.id
        }

        return ordered
    }

    static func isPostOwnedByUser(_ post: MockPost, currentUserID: String, currentUsername: String) -> Bool {
        let trimmedUserID = currentUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedUserID.isEmpty, !post.authorUserID.isEmpty {
            return post.authorUserID == trimmedUserID
        }

        let normalizedUser = FirebaseSpotService.normalizeUsername(currentUsername)
        let normalizedHandle = FirebaseSpotService.normalizeUsername(post.handle)
        return !normalizedUser.isEmpty && !normalizedHandle.isEmpty && normalizedUser == normalizedHandle
    }

    static func shouldIncludePostInViewedProfile(
        _ post: MockPost,
        viewedUsername: String,
        signedInUsername: String,
        currentUserID: String
    ) -> Bool {
        guard !post.isAnonymous else { return false }

        let normalizedViewed = FirebaseSpotService.normalizeUsername(viewedUsername)
        let normalizedSignedIn = FirebaseSpotService.normalizeUsername(signedInUsername)
        let normalizedHandle = FirebaseSpotService.normalizeUsername(post.handle)

        let handleMatchesViewedUser = !normalizedViewed.isEmpty
            && !normalizedHandle.isEmpty
            && normalizedHandle == normalizedViewed

        // Only use current-user ownership fallback when the viewed profile is the signed-in profile.
        let viewingOwnProfile = !normalizedViewed.isEmpty && normalizedViewed == normalizedSignedIn
        if viewingOwnProfile {
            let ownedBySignedInUser = isPostOwnedByUser(post, currentUserID: currentUserID, currentUsername: signedInUsername)
            return handleMatchesViewedUser || ownedBySignedInUser
        }

        return handleMatchesViewedUser
    }

    static func postsWithSavedState(_ posts: [MockPost], savedPostIDs: [String]) -> [MockPost] {
        let savedSet = Set(savedPostIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })

        return posts.map { post in
            var updated = post
            let numericIDString = String(post.id)
            let digitsOnlyIDString = String(post.id.description.filter { $0.isNumber })
            updated.isSaved = savedSet.contains(numericIDString)
                || savedSet.contains(digitsOnlyIDString)
                || savedSet.contains(String(post.id))
            return updated
        }
    }

    static func deleteCandidatePostIDs(firestoreID: String, localPostID: Int) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for candidate in [firestoreID, String(localPostID)] {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            ordered.append(trimmed)
        }

        return ordered
    }

    private func ensureAuthenticatedUserRecord() async -> String {
        if let authenticatedID = try? FirebaseSpotService.shared.currentUserID(), !authenticatedID.isEmpty {
            persistResolvedUserID(authenticatedID)
            return authenticatedID
        }

        let accountSignedIn = UserDefaults.standard.bool(forKey: accountSignedInDefaultsKey)
        let savedEmail = UserDefaults.standard.string(forKey: accountEmailDefaultsKey) ?? ""
        let savedPassword = UserDefaults.standard.string(forKey: accountPasswordDefaultsKey) ?? ""

        if Self.shouldRestoreSavedAccount(accountSignedIn: accountSignedIn, savedEmail: savedEmail, savedPassword: savedPassword) {
            do {
                let user = try await FirebaseSpotService.shared.signIn(email: savedEmail, password: savedPassword)
                persistResolvedUserID(user.uid)
                await MainActor.run {
                    hydratePersistedIdentity()
                }
                return user.uid
            } catch {
                print("Spot restored auth sign-in failed: \(error)")
            }
        }

        currentUserID = ""
        UserDefaults.standard.removeObject(forKey: "spot_firebase_user_id")
        return ""
    }

    private func persistCurrentUsername() async {
        guard isSignedInToAccount else {
            usernameAvailabilityMessage = "Sign up first to claim a username"
            usernameAvailabilityIsAvailable = false
            return
        }

        let cleanedUsername = profileUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUsername = FirebaseSpotService.normalizeUsername(cleanedUsername)
        let currentSavedUsername = FirebaseSpotService.normalizeUsername(accountUsername)

        guard !normalizedUsername.isEmpty else {
            usernameAvailabilityMessage = "Choose a username"
            usernameAvailabilityIsAvailable = false
            return
        }

        guard FirebaseSpotService.isAllowedUsername(normalizedUsername, reservedAgainst: currentSavedUsername) else {
            usernameAvailabilityMessage = "Taken or invalid"
            usernameAvailabilityIsAvailable = false
            return
        }

        do {
            let userID = await ensureAuthenticatedUserRecord()
            guard !userID.isEmpty else {
                usernameAvailabilityMessage = "Save your account first"
                usernameAvailabilityIsAvailable = false
                return
            }

            let existingAccount = try await FirebaseSpotService.shared.fetchUserAccount(userID: userID)
            let displayName = profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? normalizedUsername : profileName
            try await FirebaseSpotService.shared.saveUserProfile(
                userID: userID,
                username: normalizedUsername,
                displayName: displayName,
                bio: existingAccount.bio,
                photoURL: existingAccount.profilePhotoURL
            )

            profileUsername = normalizedUsername
            accountUsername = normalizedUsername
            usernameAvailabilityMessage = "Saved"
            usernameAvailabilityIsAvailable = true
            UserDefaults.standard.set(normalizedUsername, forKey: accountUsernameDefaultsKey)
            applyUserProfileToOwnPosts(username: normalizedUsername, displayName: profileName)
            activeSettingsEditor = nil
        } catch {
            usernameAvailabilityMessage = "Taken or invalid"
            usernameAvailabilityIsAvailable = false
            print("Spot username save error: \(error)")
        }
    }

    private func resolveUserIDForPosting() async -> String? {
        if let authenticatedID = try? FirebaseSpotService.shared.currentUserID(), !authenticatedID.isEmpty {
            persistResolvedUserID(authenticatedID)
            return authenticatedID
        }

        let accountSignedIn = UserDefaults.standard.bool(forKey: accountSignedInDefaultsKey)
        let savedEmail = UserDefaults.standard.string(forKey: accountEmailDefaultsKey) ?? ""
        let savedPassword = UserDefaults.standard.string(forKey: accountPasswordDefaultsKey) ?? ""

        if Self.shouldRestoreSavedAccount(accountSignedIn: accountSignedIn, savedEmail: savedEmail, savedPassword: savedPassword) {
            do {
                let user = try await FirebaseSpotService.shared.signIn(email: savedEmail, password: savedPassword)
                persistResolvedUserID(user.uid)
                return user.uid
            } catch {
                print("Spot post auth restore failed: \(error)")
            }
        }

        do {
            let anonymousUser = try await FirebaseSpotService.shared.signInAnonymously()
            persistResolvedUserID(anonymousUser.uid)
            return anonymousUser.uid
        } catch {
            print("Spot anonymous posting auth failed: \(error)")
            let fallbackID = FirebaseSpotService.makeStableDeviceUserID()
            persistResolvedUserID(fallbackID)
            return fallbackID
        }
    }

    private func persistCurrentProfileName(expectedDisplayName: String? = nil) async {
        let cleanedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let expectedDisplayName {
            let expected = expectedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard expected == cleanedName else {
                return
            }
        }

        let usernameToPersist = profileUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUsername = FirebaseSpotService.normalizeUsername(usernameToPersist.isEmpty ? "user" : usernameToPersist)
        let resolvedDisplayName = cleanedName.isEmpty ? (normalizedUsername.isEmpty ? "User" : normalizedUsername) : cleanedName

        guard FirebaseSpotService.isAllowedDisplayName(cleanedName.isEmpty ? normalizedUsername : cleanedName) else {
            await MainActor.run {
                profileNameSaveMessage = "Name contains a blocked term"
                isProfileNameSavePending = false
            }
            return
        }

        let userID = await ensureAuthenticatedUserRecord()
        guard !userID.isEmpty else {
            await MainActor.run {
                profileNameSaveMessage = "Sign in to save name"
                isProfileNameSavePending = false
            }
            print("Spot profile name save error: No authenticated userID available")
            return
        }

        await MainActor.run {
            isProfileNameSavePending = true
            profileNameSaveMessage = "Saving..."
        }

        do {
            let existingAccount = try await FirebaseSpotService.shared.fetchUserAccount(userID: userID)
            try await FirebaseSpotService.shared.saveUserProfile(
                userID: userID,
                username: normalizedUsername,
                displayName: resolvedDisplayName,
                bio: nil,
                photoURL: existingAccount.profilePhotoURL
            )
            UserDefaults.standard.set(cleanedName, forKey: profileNameDefaultsKey)
            applyUserProfileToOwnPosts(username: normalizedUsername, displayName: resolvedDisplayName)
            
            await MainActor.run {
                profileNameSaveMessage = "Saved"
                isProfileNameSavePending = false
            }
        } catch {
            print("Spot profile name save error: \(error)")
            await MainActor.run {
                profileNameSaveMessage = "Failed to save"
                isProfileNameSavePending = false
            }
        }
    }

    private func requireSavedAuthenticatedUserID() async -> String? {
        if let authenticatedID = try? FirebaseSpotService.shared.currentUserID(), !authenticatedID.isEmpty {
            persistResolvedUserID(authenticatedID)
            return authenticatedID
        }

        let accountSignedIn = UserDefaults.standard.bool(forKey: accountSignedInDefaultsKey)
        let savedEmail = UserDefaults.standard.string(forKey: accountEmailDefaultsKey) ?? ""
        let savedPassword = UserDefaults.standard.string(forKey: accountPasswordDefaultsKey) ?? ""

        if Self.shouldRestoreSavedAccount(accountSignedIn: accountSignedIn, savedEmail: savedEmail, savedPassword: savedPassword) {
            do {
                let user = try await FirebaseSpotService.shared.signIn(email: savedEmail, password: savedPassword)
                persistResolvedUserID(user.uid)
                return user.uid
            } catch {
                print("Spot saved account restoration failed before profile photo upload: \(error)")
            }
        }

        return nil
    }

    private func persistCurrentProfilePhoto() async {
        let imageToSave = profilePhotoPreviewImage ?? profilePhotoImage
        guard let image = imageToSave,
              let imageData = image.jpegData(compressionQuality: 0.85) else {
            return
        }

        // Persist locally first so the selected photo survives restarts even if remote sync fails.
        Self.persistImage(image, forKey: profilePhotoDefaultsKey)
        await MainActor.run {
            UserDefaults.standard.set(imageData, forKey: profilePhotoDefaultsKey)
            UserDefaults.standard.set(true, forKey: profilePhotoPendingSyncDefaultsKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: profilePhotoLastWriteAtDefaultsKey)
            profilePhotoImage = image
            profilePhotoPreviewImage = image
            pendingProfilePhotoSelection = image
            profilePhotoText = ""
        }

        guard let userID = await requireSavedAuthenticatedUserID() else {
            await MainActor.run {
                accountAuthMessage = "Save your account first so the profile photo can attach to the correct user."
            }
            return
        }

        isProfilePhotoUploadPending = true
        let fileName = "profile_\(UUID().uuidString).jpg"

        do {
            let photoURL = try await FirebaseSpotService.shared.uploadMedia(data: imageData, folder: "profilePhotos", fileName: fileName)
            let validUsername = await resolvedUsernameForProfileSave(userID: userID)
            let displayName = profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "User" : profileName
            try await FirebaseSpotService.shared.saveUserProfile(
                userID: userID,
                username: validUsername,
                displayName: displayName,
                bio: nil,
                photoURL: photoURL
            )
            Self.persistImage(image, forKey: profilePhotoDefaultsKey)
            await MainActor.run {
                profilePhotoRemoteURL = photoURL
                profilePhotoImage = image
                profilePhotoPreviewImage = image
                pendingProfilePhotoSelection = nil
                profilePhotoText = ""
                UserDefaults.standard.set(imageData, forKey: profilePhotoDefaultsKey)
                UserDefaults.standard.set(false, forKey: profilePhotoPendingSyncDefaultsKey)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: profilePhotoLastWriteAtDefaultsKey)
                applyProfilePhotoURLToOwnPosts(photoURL)
            }
            isProfilePhotoUploadPending = false
        } catch {
            await MainActor.run {
                accountAuthMessage = "Saved on this device. Cloud profile photo sync failed; retry when connected."
            }
            isProfilePhotoUploadPending = false
            print("Spot profile photo save error: \(error)")
        }
    }

    private func removeCurrentProfilePhoto() async {
        guard let userID = await requireSavedAuthenticatedUserID() else {
            await MainActor.run {
                accountAuthMessage = "Sign in or save your account before removing the profile photo."
            }
            return
        }

        let validUsername = await resolvedUsernameForProfileSave(userID: userID)
        let displayName = profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "User" : profileName

        do {
            try await FirebaseSpotService.shared.saveUserProfile(
                userID: userID,
                username: validUsername,
                displayName: displayName,
                bio: nil,
                photoURL: nil
            )
            await MainActor.run {
                profilePhotoRemoteURL = ""
                profilePhotoImage = nil
                profilePhotoPreviewImage = nil
                pendingProfilePhotoSelection = nil
                profilePhotoText = "YO"
                profilePhotoItem = nil
                profilePhotoCropScale = 1.0
                profilePhotoCropOffset = .zero
                UserDefaults.standard.removeObject(forKey: profilePhotoDefaultsKey)
                UserDefaults.standard.set(false, forKey: profilePhotoPendingSyncDefaultsKey)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: profilePhotoLastWriteAtDefaultsKey)
                applyProfilePhotoURLToOwnPosts(nil)
            }
        } catch {
            print("Spot profile photo removal error: \(error)")
        }
    }

    private func loadCurrentUserProfileFromRecord() async {
        if isProfilePhotoUploadPending || pendingProfilePhotoSelection != nil {
            return
        }

        let userID = await ensureAuthenticatedUserRecord()
        guard !userID.isEmpty else {
            return
        }

        do {
            let account = try await FirebaseSpotService.shared.fetchUserAccount(userID: userID)
            let liveCounts = try? await FirebaseSpotService.shared.fetchUserFollowCounts(userID: userID)
            let resolvedFollowerCount = liveCounts?.followers ?? account.followerCount
            let resolvedFollowingCount = liveCounts?.following ?? account.followingCount
            await MainActor.run {
                startCurrentUserProfileLiveListener(for: userID)
                let normalizedUsername = FirebaseSpotService.normalizeUsername(account.username)
                if !normalizedUsername.isEmpty {
                    profileUsername = normalizedUsername
                    accountUsername = normalizedUsername
                    UserDefaults.standard.set(normalizedUsername, forKey: accountUsernameDefaultsKey)
                }

                let savedDisplayName = UserDefaults.standard.string(forKey: profileNameDefaultsKey) ?? ""
                let firebaseDisplayName = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !savedDisplayName.isEmpty {
                    // Keep local UserDefaults value (it was saved immediately when user typed)
                    profileName = savedDisplayName
                    // If Firebase differs, queue a sync to update it
                    if firebaseDisplayName != savedDisplayName {
                        Task {
                            await persistCurrentProfileName(expectedDisplayName: savedDisplayName)
                        }
                    }
                } else if !firebaseDisplayName.isEmpty {
                    // Only use Firebase value if UserDefaults is empty
                    profileName = firebaseDisplayName
                    UserDefaults.standard.set(firebaseDisplayName, forKey: profileNameDefaultsKey)
                }

                let normalizedSavedUsername = FirebaseSpotService.normalizeUsername(account.username)
                if !normalizedSavedUsername.isEmpty {
                    profileUsername = normalizedSavedUsername
                    accountUsername = normalizedSavedUsername
                    UserDefaults.standard.set(normalizedSavedUsername, forKey: accountUsernameDefaultsKey)
                }

                let fetchedPhotoURL = (account.profilePhotoURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let currentPhotoURL = profilePhotoRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasPendingLocalPhotoSync = UserDefaults.standard.bool(forKey: profilePhotoPendingSyncDefaultsKey)
                let cachedLocalPhoto = Self.cachedImage(forKey: profilePhotoDefaultsKey)
                let lastLocalPhotoWriteAt = UserDefaults.standard.double(forKey: profilePhotoLastWriteAtDefaultsKey)
                let writeIsRecent = Date().timeIntervalSince1970 - lastLocalPhotoWriteAt < 20
                let shouldProtectRecentPhotoSelection = writeIsRecent
                    && !currentPhotoURL.isEmpty
                    && !fetchedPhotoURL.isEmpty
                    && currentPhotoURL != fetchedPhotoURL
                let shouldProtectPendingLocalPhoto = hasPendingLocalPhotoSync && cachedLocalPhoto != nil
                let shouldProtectLocalPhoto = shouldProtectRecentPhotoSelection || shouldProtectPendingLocalPhoto

                if shouldProtectLocalPhoto {
                    // Avoid replacing a freshly selected local photo with a stale server response.
                    applyProfilePhotoURLToOwnPosts(currentPhotoURL)
                } else {
                    profilePhotoRemoteURL = fetchedPhotoURL
                }

                if !shouldProtectLocalPhoto,
                   let photoURL = account.profilePhotoURL,
                   let url = URL(string: photoURL),
                   let imageData = try? Data(contentsOf: url),
                   let image = UIImage(data: imageData) {
                    profilePhotoImage = image
                    profilePhotoPreviewImage = image
                    pendingProfilePhotoSelection = nil
                    profilePhotoText = ""
                    Self.persistImage(image, forKey: profilePhotoDefaultsKey)
                } else if shouldProtectPendingLocalPhoto, let localImage = cachedLocalPhoto {
                    profilePhotoImage = localImage
                    profilePhotoPreviewImage = localImage
                    pendingProfilePhotoSelection = nil
                    profilePhotoText = ""
                } else if !shouldProtectLocalPhoto, profilePhotoImage == nil {
                    if let cachedImage = Self.cachedImage(forKey: profilePhotoDefaultsKey) {
                        profilePhotoImage = cachedImage
                        profilePhotoPreviewImage = cachedImage
                        pendingProfilePhotoSelection = nil
                        profilePhotoText = ""
                    } else {
                        profilePhotoImage = nil
                        profilePhotoPreviewImage = nil
                        pendingProfilePhotoSelection = nil
                        profilePhotoText = "YO"
                    }
                }

                let resolvedPostPhotoURL: String?
                if shouldProtectLocalPhoto {
                    resolvedPostPhotoURL = currentPhotoURL.isEmpty ? nil : currentPhotoURL
                } else {
                    resolvedPostPhotoURL = fetchedPhotoURL.isEmpty ? nil : fetchedPhotoURL
                }
                applyProfilePhotoURLToOwnPosts(resolvedPostPhotoURL)
                currentUserFollowerCount = max(0, resolvedFollowerCount)
                currentUserFollowingCount = max(0, resolvedFollowingCount)

                posts = Self.postsWithSavedState(posts, savedPostIDs: account.savedPostIDs)
            }
        } catch {
            print("Spot profile hydrate error: \(error)")
        }
    }

    @MainActor
    private func applyProfilePhotoURLToOwnPosts(_ photoURL: String?) {
        applyProfilePhotoURLToPosts(
            authorUserID: currentUserID,
            username: profileUsername,
            photoURL: photoURL
        )
    }

    @MainActor
    private func applyUserProfileToOwnPosts(username: String, displayName: String) {
        let resolvedAuthorID = currentUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedUsername = FirebaseSpotService.normalizeUsername(username)
        let resolvedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalDisplayName = resolvedDisplayName.isEmpty ? resolvedUsername : resolvedDisplayName
        
        guard !resolvedUsername.isEmpty else { return }

        func shouldUpdateAuthor(for post: MockPost) -> Bool {
            guard !post.isAnonymous else { return false }

            let postAuthorID = post.authorUserID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !resolvedAuthorID.isEmpty, postAuthorID == resolvedAuthorID {
                return true
            }

            let postUsername = FirebaseSpotService.normalizeUsername(post.handle)
            return !postUsername.isEmpty && postUsername == resolvedUsername
        }

        posts = posts.map { post in
            guard shouldUpdateAuthor(for: post) else { return post }

            var updatedPost = post
            updatedPost.handle = resolvedUsername
            updatedPost.author = finalDisplayName
            return updatedPost
        }

        if let selected = selectedProfilePost, !selected.isAnonymous {
            if shouldUpdateAuthor(for: selected) {
                var updatedSelected = selected
                updatedSelected.handle = resolvedUsername
                updatedSelected.author = finalDisplayName
                selectedProfilePost = updatedSelected
            }
        }

        if let pending = pendingSharePost, !pending.isAnonymous {
            if shouldUpdateAuthor(for: pending) {
                var updatedPending = pending
                updatedPending.handle = resolvedUsername
                updatedPending.author = finalDisplayName
                pendingSharePost = updatedPending
            }
        }
    }

    @MainActor
    private func refreshedProfileWithPhoto(_ profile: FakeUserProfile, photoURL: String?) -> FakeUserProfile {
        FakeUserProfile(
            id: profile.id,
            userID: profile.userID,
            username: profile.username,
            name: profile.name,
            city: profile.city,
            bio: profile.bio,
            followerCount: profile.followerCount,
            followingCount: profile.followingCount,
            profilePhotoText: profile.profilePhotoText,
            profilePhotoURL: photoURL
        )
    }

    @MainActor
    private func applyProfilePhotoURLToPosts(authorUserID: String, username: String?, photoURL: String?) {
        let resolvedAuthorID = authorUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedUsername = FirebaseSpotService.normalizeUsername(username ?? "")
        let trimmedURL = photoURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedURL = (trimmedURL?.isEmpty == false) ? trimmedURL : nil

        func shouldUpdate(_ post: MockPost) -> Bool {
            guard !post.isAnonymous else { return false }

            let postAuthorID = post.authorUserID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !resolvedAuthorID.isEmpty, postAuthorID == resolvedAuthorID {
                return true
            }

            guard !resolvedUsername.isEmpty else { return false }
            let postUsername = FirebaseSpotService.normalizeUsername(post.handle)
            return postUsername == resolvedUsername
        }

        posts = posts.map { post in
            guard shouldUpdate(post) else { return post }

            var updatedPost = post
            updatedPost.authorProfilePhotoURL = resolvedURL
            return updatedPost
        }

        if let selected = selectedProfilePost, shouldUpdate(selected) {
            var updatedSelected = selected
            updatedSelected.authorProfilePhotoURL = resolvedURL
            selectedProfilePost = updatedSelected
        }

        if let pending = pendingSharePost, shouldUpdate(pending) {
            var updatedPending = pending
            updatedPending.authorProfilePhotoURL = resolvedURL
            pendingSharePost = updatedPending
        }

        if let selectedProfile = selectedUserProfile {
            let selectedMatchesByID = !resolvedAuthorID.isEmpty
                && selectedProfile.userID.trimmingCharacters(in: .whitespacesAndNewlines) == resolvedAuthorID
            let selectedMatchesByUsername = !resolvedUsername.isEmpty
                && FirebaseSpotService.normalizeUsername(selectedProfile.username) == resolvedUsername

            if selectedMatchesByID || selectedMatchesByUsername {
                selectedUserProfile = refreshedProfileWithPhoto(selectedProfile, photoURL: resolvedURL)
            }
        }

        fakeUserProfiles = fakeUserProfiles.map { profile in
            let matchesByID = !resolvedAuthorID.isEmpty
                && profile.userID.trimmingCharacters(in: .whitespacesAndNewlines) == resolvedAuthorID
            let matchesByUsername = !resolvedUsername.isEmpty
                && FirebaseSpotService.normalizeUsername(profile.username) == resolvedUsername

            if matchesByID || matchesByUsername {
                return refreshedProfileWithPhoto(profile, photoURL: resolvedURL)
            }
            return profile
        }
    }

    private func refreshActivePostAuthorPhotos(force: Bool = false) async {
        let snapshot = await MainActor.run { () -> (authorIDs: [String], currentPhotoByAuthorID: [String: String], now: TimeInterval)? in
            let now = Date().timeIntervalSince1970
            if isActiveAuthorPhotoRefreshInFlight { return nil }
            if !force && (now - lastActiveAuthorPhotoRefreshAt) < 6 { return nil }

            let activePosts = posts.filter { !$0.isAnonymous }
            guard !activePosts.isEmpty else { return nil }

            var currentPhotoByAuthorID: [String: String] = [:]
            for post in activePosts {
                let authorID = post.authorUserID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !authorID.isEmpty else { continue }

                let currentURL = (post.authorProfilePhotoURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                currentPhotoByAuthorID[authorID] = currentURL
            }

            let authorIDs = Array(currentPhotoByAuthorID.keys)
            guard !authorIDs.isEmpty else { return nil }

            isActiveAuthorPhotoRefreshInFlight = true
            return (authorIDs, currentPhotoByAuthorID, now)
        }

        guard let snapshot else { return }

        let resolvedPhotoUpdates = await withTaskGroup(of: (String, String?)?.self, returning: [(String, String?)].self) { group in
            for authorID in snapshot.authorIDs {
                group.addTask {
                    do {
                        let account = try await FirebaseSpotService.shared.fetchUserAccount(userID: authorID)
                        let fetchedURL = (account.profilePhotoURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let existingURL = snapshot.currentPhotoByAuthorID[authorID] ?? ""

                        if fetchedURL != existingURL {
                            return (authorID, fetchedURL.isEmpty ? nil : fetchedURL)
                        }
                    } catch {
                        return nil
                    }

                    return nil
                }
            }

            var updates: [(String, String?)] = []
            for await result in group {
                guard let result else { continue }
                updates.append(result)
            }
            return updates
        }

        await MainActor.run {
            for update in resolvedPhotoUpdates {
                applyProfilePhotoURLToPosts(authorUserID: update.0, username: nil, photoURL: update.1)
                prefetchRemoteAvatarIfNeeded(update.1)
            }

            lastActiveAuthorPhotoRefreshAt = snapshot.now
            isActiveAuthorPhotoRefreshInFlight = false
        }
    }

    @MainActor
    private func loadCurrentUserPosts() async {
        let userID = await ensureAuthenticatedUserRecord()
        let currentHandle = FirebaseSpotService.normalizeUsername(profileUsername.isEmpty ? "you" : profileUsername)
        let displayName = profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "You" : profileName
        var ownPostsFetchError: Error?
        var feedPostsFetchError: Error?

        var ownPosts: [FirebasePostPayload] = []
        if !userID.isEmpty {
            do {
                ownPosts = try await FirebaseSpotService.shared.fetchPostsForUser(userID: userID)
            } catch {
                ownPostsFetchError = error
                print("Spot own posts fetch failed: \(error)")
            }
        }

        var feedPosts: [FirebasePostPayload] = []
        do {
            feedPosts = try await FirebaseSpotService.shared.fetchPosts(
                near: 0,
                longitude: 0,
                radiusMeters: 40_000_000,
                limit: 500
            )
        } catch {
            feedPostsFetchError = error
            print("Spot feed posts fetch failed: \(error)")
        }

        var mergedByID: [String: FirebasePostPayload] = [:]
        for payload in feedPosts + ownPosts {
            mergedByID[payload.id] = payload
        }

        let merged = mergedByID.values.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id > rhs.id
        }
        let syncError: Error?
        if merged.isEmpty, ownPostsFetchError != nil || feedPostsFetchError != nil {
            syncError = ownPostsFetchError ?? feedPostsFetchError
        } else {
            syncError = nil
        }

        let hydrated = Self.postsAfterSyncAttempt(
            currentPosts: posts,
            persistedPosts: merged,
            syncError: syncError,
            ownerHandle: currentHandle,
            ownerName: displayName
        )

        if userID.isEmpty {
            posts = hydrated
            prefetchProfilesForVisiblePostAuthors()
            Task {
                await refreshActivePostAuthorPhotos(force: true)
            }
            return
        }

        do {
            let account = try await FirebaseSpotService.shared.fetchUserAccount(userID: userID)
            posts = Self.postsWithSavedState(hydrated, savedPostIDs: account.savedPostIDs)
        } catch {
            posts = hydrated
            print("Spot account hydrate failed while loading posts: \(error)")
        }

        prefetchProfilesForVisiblePostAuthors()
        Task {
            await refreshActivePostAuthorPhotos(force: true)
        }
    }

    @MainActor
    private func mergeRealtimeFeedPayloads(_ persistedPosts: [FirebasePostPayload]) {
        let currentHandle = FirebaseSpotService.normalizeUsername(profileUsername.isEmpty ? "you" : profileUsername)
        let displayName = profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "You" : profileName
        let hydrated = Self.postsAfterSyncAttempt(
            currentPosts: posts,
            persistedPosts: persistedPosts,
            syncError: nil,
            ownerHandle: currentHandle,
            ownerName: displayName
        )
        posts = hydrated
        prefetchProfilesForVisiblePostAuthors()
        Task {
            await refreshActivePostAuthorPhotos(force: true)
        }
    }

    private func startRealtimeFeedListener() {
        guard realtimeFeedListener == nil else { return }

        realtimeFeedListener = FirebaseSpotService.shared.listenToRecentPosts(
            limit: 500,
            onUpdate: { payloads in
                Task { @MainActor in
                    mergeRealtimeFeedPayloads(payloads)
                }
            },
            onError: { error in
                print("Spot realtime feed listener error: \(error)")
            }
        )
    }

    private func stopRealtimeFeedListener() {
        realtimeFeedListener?.remove()
        realtimeFeedListener = nil
    }

    private func persistUserAccountActivity(for post: MockPost, saved: Bool? = nil, flagged: Bool? = nil, locationName: String? = nil) {
        Task {
            let userID = await ensureAuthenticatedUserRecord()

            do {
                if let saved {
                    try await FirebaseSpotService.shared.saveUserSavedPost(userID: userID, postID: String(post.id), saved: saved)
                }

                if let flagged {
                    try await FirebaseSpotService.shared.saveUserFlaggedPost(userID: userID, postID: String(post.id), flagged: flagged)
                }

                if let locationName {
                    try await FirebaseSpotService.shared.saveUserLocationHistory(userID: userID, locationName: locationName)
                }
            } catch {
                print("Spot user activity save error: \(error)")
            }
        }
    }

    private func toggleSavedState(for post: MockPost) {
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index].isSaved.toggle()
            if posts[index].isSaved {
                posts[index].savedCount += 1
            } else {
                posts[index].savedCount = max(0, posts[index].savedCount - 1)
            }
            pendingSharePost = posts[index].isSaved ? posts[index] : nil
            persistUserAccountActivity(for: posts[index], saved: posts[index].isSaved)

            let postIDForEngagement = posts[index].firestoreID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(posts[index].id)
                : posts[index].firestoreID
            let updatedSavedCount = posts[index].savedCount
            Task {
                try? await FirebaseSpotService.shared.updatePostEngagement(
                    postID: postIDForEngagement,
                    savedCount: updatedSavedCount
                )
            }
        } else {
            pendingSharePost = nil
        }
    }

    private func applyTrackedPostViewUpdate(_ updatedPost: MockPost) {
        if viewedPostIDs.insert(updatedPost.id).inserted {
            persistViewedPostIDs()
        }

        if let index = posts.firstIndex(where: { $0.id == updatedPost.id }) {
            var next = updatedPost
            if next.firestoreID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                next.firestoreID = posts[index].firestoreID
            }
            posts[index] = next
        }

        if let selected = selectedProfilePost, selected.id == updatedPost.id {
            var next = selected
            next.viewCount = updatedPost.viewCount
            next.timeViewedSeconds = updatedPost.timeViewedSeconds
            if !updatedPost.firestoreID.isEmpty {
                next.firestoreID = updatedPost.firestoreID
            }
            selectedProfilePost = next
        }

        if let pending = pendingSharePost, pending.id == updatedPost.id {
            var next = pending
            next.viewCount = updatedPost.viewCount
            next.timeViewedSeconds = updatedPost.timeViewedSeconds
            if !updatedPost.firestoreID.isEmpty {
                next.firestoreID = updatedPost.firestoreID
            }
            pendingSharePost = next
        }
    }

    private func deletePost(_ post: MockPost) {
        let deletedPostID = post.id
        let removedIndices = posts.indices.filter { posts[$0].id == deletedPostID }
        let reinsertIndex = removedIndices.min() ?? posts.count
        let removedPosts = posts.filter { $0.id == deletedPostID }

        posts.removeAll { $0.id == deletedPostID }
        reportedPostIds.remove(post.id)
        let userID = post.authorUserID.isEmpty ? activeUserID() : post.authorUserID
        let candidatePostIDs = Self.deleteCandidatePostIDs(firestoreID: post.firestoreID, localPostID: deletedPostID)
        Task {
            var deletedRemotely = false

            for candidatePostID in candidatePostIDs {
                do {
                    try await FirebaseSpotService.shared.deletePost(postID: candidatePostID, authorID: userID)
                    deletedRemotely = true
                    break
                } catch {
                    print("Spot delete failed for post id \(candidatePostID): \(error)")
                }
            }

            if deletedRemotely {
                await loadCurrentUserPosts()
                return
            }

            await MainActor.run {
                if !removedPosts.isEmpty {
                    let safeIndex = max(0, min(reinsertIndex, posts.count))
                    posts.insert(contentsOf: removedPosts, at: safeIndex)
                }
                lastSentMessage = "Could not delete this post. Please try again."
            }
        }
        if selectedProfilePost?.id == post.id {
            selectedProfilePost = nil
        }
        if pendingSharePost?.id == post.id {
            pendingSharePost = nil
        }
        if currentScreen == .postDetail {
            currentScreen = .profile
        }
    }

    private func reportPost(_ post: MockPost) {
        reportedPostIds.insert(post.id)
        persistUserAccountActivity(for: post, flagged: true)
    }

    private func reportUser(_ user: FakeUserProfile) {
        reportedUsers.insert(user.username.lowercased())
        if let thread = messages.first(where: { $0.username.lowercased() == user.username.lowercased() || $0.participant.lowercased() == user.name.lowercased() }) {
            selectedChatThread = thread
            currentScreen = .chatDetail
        }
    }

    private func togglePinThread(_ thread: DirectMessageThread) {
        guard let index = messages.firstIndex(where: { $0.id == thread.id }) else { return }
        messages[index].isPinned.toggle()
        selectedChatThread = messages[index]
    }

    private func deleteChatThread(_ thread: DirectMessageThread) {
        messages.removeAll { $0.id == thread.id }
        if selectedChatThread?.id == thread.id {
            selectedChatThread = nil
        }
        currentScreen = .messages
    }

    private func sharePostToFriends(_ post: MockPost) {
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index].recordShare()
            let updatedShareCount = posts[index].shareCount
            Task {
                try? await FirebaseSpotService.shared.updatePostEngagement(postID: String(post.id), shareCount: updatedShareCount)
            }
        }

        pendingSharePost = post
        selectedUserProfile = nil
        currentScreen = .messages
    }

    private func addSharedPostToThread(_ thread: DirectMessageThread, post: MockPost, isMine: Bool = true) {
        var updatedMessages = chatMessages[thread.id] ?? []
        updatedMessages.append(
            ChatMessage(
                id: (updatedMessages.last?.id ?? 0) + 1,
                text: "",
                isMine: isMine,
                time: "now",
                sharedPost: post
            )
        )
        chatMessages[thread.id] = updatedMessages
        pendingSharePost = nil
        chatComposerText = ""
    }

    private func shareTextFor(_ post: MockPost) -> String {
        let title = post.title.isEmpty ? "a post" : post.title
        let location = post.location.isEmpty ? "this place" : post.location
        return "I wanted to share this with you: \(title) — \(location)\n\(post.body)"
    }

    private func openDM(with user: FakeUserProfile) {
        if let existingIndex = messages.firstIndex(where: { $0.username.lowercased() == user.username.lowercased() || $0.participant.lowercased() == user.name.lowercased() }) {
            selectedChatThread = messages[existingIndex]
        } else {
            let created = DirectMessageThread(
                id: Int.random(in: 100...9999),
                participant: user.name,
                username: user.username,
                preview: pendingSharePost != nil ? shareTextFor(pendingSharePost!) : "Hey, I wanted to say hi.",
                time: "Now",
                unread: 0,
                isIncoming: false
            )
            messages.insert(created, at: 0)
            selectedChatThread = created
        }

        if let post = pendingSharePost {
            if let thread = selectedChatThread {
                addSharedPostToThread(thread, post: post, isMine: true)
            }
        } else {
            chatComposerText = ""
        }

        selectedUserProfile = user
        currentScreen = .chatDetail
    }
}

struct AnimatedLoadingFieldsPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Loading content…")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                loadingBar(width: 210, height: 14)
                loadingBar(width: 170, height: 12)
                loadingBar(width: 190, height: 12)
                loadingBar(width: 120, height: 12)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
        .modifier(ShimmerModifier())
    }

    private func loadingBar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.gray.opacity(0.18))
            .frame(width: width, height: height)
    }
}

struct PollEditorPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Loading poll response areas…")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(ContentView.appPrimaryThemeColor.opacity(0.12))
                    .frame(height: 50)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.gray.opacity(0.18))
                            .frame(width: 130, height: 12)
                            .modifier(ShimmerModifier())
                    )

                RoundedRectangle(cornerRadius: 14)
                    .fill(ContentView.appSecondaryThemeColor.opacity(0.12))
                    .frame(height: 50)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.gray.opacity(0.18))
                            .frame(width: 130, height: 12)
                            .modifier(ShimmerModifier())
                    )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var isAnimating = false

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [Color.clear, Color.white.opacity(0.5), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: isAnimating ? geo.size.width * 0.7 : -geo.size.width * 0.7)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false), value: isAnimating)
                    .onAppear { isAnimating = true }
                }
            )
            .mask(content)
    }
}

enum PollVoteLogic {
    static func updatedVotes(
        currentVotes: [Int],
        previousSelection: Int?,
        nextSelection: Int
    ) -> (votes: [Int], selected: Int?) {
        let safeVotes = currentVotes.count >= 2 ? currentVotes : [0, 0]
        guard nextSelection >= 0, nextSelection < safeVotes.count else {
            return (safeVotes, previousSelection)
        }

        var updated = safeVotes
        if updated.indices.contains(nextSelection) {
            updated[nextSelection] = min(Int.max, max(0, updated[nextSelection]) + 1)
        }
        return (updated, nextSelection)
    }
}

struct PollVoteButton: View {
    let label: String
    let count: Int
    let totalVotes: Int
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    private var percent: Double {
        let total = max(totalVotes, 1)
        return Double(count) / Double(total) * 100
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(count) votes • \(String(format: "%.0f", percent))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? tint : .secondary)
                    .frame(width: 18, height: 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background(isSelected ? tint.opacity(0.14) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PieChartView: View {
    let votes: [Int]
    let colorSeed: Int

    static func legacyPalette() -> [Color] {
        [
            Color(red: 0.12, green: 0.43, blue: 0.87),
            Color(red: 0.54, green: 0.31, blue: 0.85),
            Color(red: 0.20, green: 0.58, blue: 0.47),
            Color(red: 0.90, green: 0.33, blue: 0.62)
        ]
    }

    private var palette: [Color] {
        Self.legacyPalette()
    }

    private var total: Int {
        max(votes.reduce(0, +), 1)
    }

    private var segments: [(value: Int, color: Color, start: Double, end: Double)] {
        let totalValue = Double(total)
        let availableColors = palette

        var runningStart = 0.0
        var results: [(Int, Color, Double, Double)] = []

        for (index, value) in votes.enumerated() {
            let ratio = totalValue == 0 ? 0.0 : Double(value) / totalValue
            let color = availableColors.indices.contains(index) ? availableColors[index] : availableColors[index % max(availableColors.count, 1)]
            let segment = (value: value, color: color, start: runningStart, end: runningStart + ratio * 360.0)
            results.append(segment)
            runningStart = segment.end
        }

        return results
    }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = min(geometry.size.width, geometry.size.height) / 2

            ZStack {
                if votes.isEmpty || total == 0 {
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                } else {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        Path { path in
                            path.move(to: center)
                            path.addArc(
                                center: center,
                                radius: radius,
                                startAngle: .degrees(segment.start - 90),
                                endAngle: .degrees(segment.end - 90),
                                clockwise: false
                            )
                            path.closeSubpath()
                        }
                        .fill(segment.color)
                    }

                    Circle()
                        .fill(Color.white)
                        .frame(width: max(radius * 0.52, 12), height: max(radius * 0.52, 12))
                }
            }
        }
        .frame(width: 96, height: 96)
    }
}

struct LocationSearchSuggestion: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let value: String

    init(title: String, subtitle: String = "", value: String? = nil) {
        self.id = title
        self.title = title
        self.subtitle = subtitle
        self.value = value ?? title
    }
}

struct LocationField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let suggestions: [LocationSearchSuggestion]
    let onSuggestionSelected: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(suggestions.prefix(5).enumerated()), id: \ .element.id) { _, suggestion in
                        Button {
                            text = suggestion.value
                            onSuggestionSelected?(suggestion.value)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(suggestion.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LinkPreviewCardData {
    let title: String
    let host: String
    let description: String?
    let image: UIImage?
}

private struct LinkPreviewCard: View {
    let urlString: String
    let fallbackTitle: String
    let fallbackDescription: String?
    let accentColor: Color

    @State private var preview: LinkPreviewCardData?

    private var resolvedURL: URL? {
        URL(string: urlString) ?? URL(string: "https://\(urlString)")
    }

    private var currentTitle: String {
        preview?.title ?? fallbackTitle
    }

    private var currentHost: String {
        preview?.host ?? resolvedURL?.host ?? urlString
    }

    private func loadPreview() {
        guard let url = resolvedURL else {
            preview = LinkPreviewCardData(title: fallbackTitle, host: urlString, description: fallbackDescription, image: nil)
            return
        }

        let provider = LPMetadataProvider()
        provider.startFetchingMetadata(for: url) { metadata, _ in
            guard let metadata else {
                DispatchQueue.main.async {
                    self.preview = LinkPreviewCardData(title: self.fallbackTitle, host: url.host ?? self.urlString, description: self.fallbackDescription, image: nil)
                }
                return
            }

            let titleText = metadata.title ?? ""
            let title = !titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? titleText : self.fallbackTitle
            let host = metadata.originalURL?.host ?? url.host ?? self.urlString
            let descriptionText = metadata.description ?? ""
            let description = !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? descriptionText : self.fallbackDescription

            if let imageProvider = metadata.imageProvider {
                imageProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    let image = object as? UIImage
                    DispatchQueue.main.async {
                        self.preview = LinkPreviewCardData(
                            title: title,
                            host: host,
                            description: description,
                            image: image
                        )
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.preview = LinkPreviewCardData(
                        title: title,
                        host: host,
                        description: description,
                        image: nil
                    )
                }
            }
        }
    }

    var body: some View {
        Group {
            if urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.clear)
                    .frame(maxWidth: .infinity)
                    .frame(height: 0)
            } else if let destinationURL = resolvedURL {
                Link(destination: destinationURL) {
                    linkPreviewContent
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            } else {
                linkPreviewContent
            }
        }
        .onAppear { loadPreview() }
        .onChange(of: urlString) { _ in preview = nil; loadPreview() }
    }

    private var linkPreviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = preview?.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipped()
                    .background(Color(.secondarySystemBackground))
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.systemGray5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .overlay(
                        VStack(spacing: 10) {
                            Image(systemName: "link")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("Link preview")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(currentTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(currentHost)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let description = preview?.description ?? fallbackDescription, !description.isEmpty, description != currentTitle {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemBackground).opacity(0.7))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct UserProfile: Identifiable {
    let id = UUID()
    let username: String
    let name: String
    var isFollowing: Bool

    var initials: String {
        let components = name.split(separator: " ")
        let letters = components.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

struct FakeUserProfile: Identifiable {
    let id: UUID
    let userID: String
    let username: String
    let name: String
    let city: String
    let bio: String
    let followerCount: Int
    let followingCount: Int
    let profilePhotoText: String
    let profilePhotoURL: String?

    init(
        id: UUID = UUID(),
        userID: String = "",
        username: String,
        name: String,
        city: String,
        bio: String,
        followerCount: Int,
        followingCount: Int,
        profilePhotoText: String,
        profilePhotoURL: String? = nil
    ) {
        self.id = id
        self.userID = userID
        self.username = username
        self.name = name
        self.city = city
        self.bio = bio
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.profilePhotoText = profilePhotoText
        self.profilePhotoURL = profilePhotoURL
    }
}

struct DirectMessageThread: Identifiable {
    let id: Int
    let participant: String
    let username: String
    var preview: String
    var time: String
    let unread: Int
    let isIncoming: Bool
    var isPinned: Bool = false

    var initials: String {
        let components = participant.split(separator: " ")
        let letters = components.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

struct ChatMessage: Identifiable {
    let id: Int
    let text: String
    let isMine: Bool
    let time: String
    var sharedPost: MockPost? = nil
}

struct MockPost: Identifiable {
    let id: Int
    var author: String
    var handle: String
    let authorUserID: String
    var authorProfilePhotoURL: String?
    let type: String
    let location: String
    let title: String
    let body: String
    let url: String
    let accent: String
    let tag: String
    var likes: Int
    var isLiked: Bool
    var comments: [String]
    var sentTo: [String]
    var isSaved: Bool = false
    var pollOptions: [String] = []
    var pollVotes: [Int] = []
    var mediaImage: UIImage? = nil
    var mediaURLs: [String] = []
    var sourceURL: String? = nil
    var tags: [String] = []
    var isBoosted: Bool = false
    var postedInLocations: [String] = []
    var viewCount: Int
    var timeViewedSeconds: Int
    var savedCount: Int
    var shareCount: Int
    var createdAt: Date
    var firestoreID: String = ""
    var isAnonymous: Bool = false

    var peakEngagementScore: Double = 0

    var realEngagementScore: Double {
        FirebaseSpotService.engagementScore(
            views: viewCount,
            totalViewDurationSeconds: timeViewedSeconds,
            saves: savedCount,
            likes: likes,
            comments: comments.count,
            shares: shareCount,
            locationBreadth: max(1, Set(postedInLocations.map { $0.lowercased() }).count),
            isBoosted: isBoosted
        )
    }

    var engagementScore: Double {
        get {
            return max(peakEngagementScore, realEngagementScore)
        }
        set {
            peakEngagementScore = max(peakEngagementScore, newValue)
        }
    }

    var relativeTimestampText: String {
        let interval = Date().timeIntervalSince(createdAt)
        if interval < 60 {
            return "now"
        }

        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = Int(minutes / 60)
        if hours < 24 {
            return "\(hours)h"
        }

        let days = Int(hours / 24)
        if days < 7 {
            return "\(days)d"
        }

        let weeks = Int(days / 7)
        return "\(weeks)w"
    }

    mutating func recordView(durationSeconds: Int = 8) {
        viewCount += 1
        timeViewedSeconds += max(0, durationSeconds)
        engagementScore = realEngagementScore
    }

    mutating func recordShare(_ count: Int = 1) {
        shareCount += max(0, count)
        engagementScore = realEngagementScore
    }

    init(
        id: Int,
        author: String,
        handle: String,
        authorUserID: String = "",
        authorProfilePhotoURL: String? = nil,
        type: String,
        location: String,
        title: String,
        body: String,
        url: String,
        accent: String,
        tag: String,
        likes: Int,
        viewCount: Int? = nil,
        timeViewedSeconds: Int = 0,
        savedCount: Int = 0,
        shareCount: Int = 0,
        peakEngagementScore: Double = 0,
        isLiked: Bool,
        comments: [String],
        sentTo: [String],
        isSaved: Bool = false,
        pollOptions: [String] = [],
        pollVotes: [Int] = [],
        mediaImage: UIImage? = nil,
        mediaURLs: [String] = [],
        sourceURL: String? = nil,
        tags: [String] = [],
        isBoosted: Bool = false,
        postedInLocations: [String] = [],
        createdAt: Date = Date(),
        firestoreID: String = "",
        isAnonymous: Bool = false
    ) {
        self.id = id
        self.author = author
        self.handle = handle
        self.authorUserID = authorUserID
        self.authorProfilePhotoURL = authorProfilePhotoURL
        self.type = type
        self.location = location
        self.title = title
        self.body = body
        self.url = url
        self.accent = accent
        self.tag = tag
        self.likes = likes
        self.isLiked = isLiked
        self.comments = comments
        self.sentTo = sentTo
        self.isSaved = isSaved
        self.pollOptions = pollOptions
        self.pollVotes = pollVotes
        self.mediaImage = mediaImage
        self.mediaURLs = mediaURLs
        self.sourceURL = sourceURL
        self.tags = tags
        self.isBoosted = isBoosted
        self.postedInLocations = postedInLocations
        self.viewCount = viewCount ?? 0
        self.timeViewedSeconds = timeViewedSeconds
        self.savedCount = savedCount
        self.shareCount = shareCount
        self.createdAt = createdAt
        self.firestoreID = firestoreID
        self.isAnonymous = isAnonymous
        self.peakEngagementScore = max(peakEngagementScore, self.realEngagementScore)
    }
}

private struct LoopingVideoPlayer: UIViewRepresentable {
    let url: URL
    let isMuted: Bool
    let isActive: Bool
    let restartToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.backgroundColor = .secondarySystemBackground
        container.layer.masksToBounds = true
        let player = AVPlayer()
        player.isMuted = isMuted
        player.automaticallyWaitsToMinimizeStalling = true

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.contentsScale = UIScreen.main.scale
        playerLayer.frame = container.bounds
        playerLayer.backgroundColor = UIColor.black.cgColor
        playerLayer.needsDisplayOnBoundsChange = true
        container.layer.addSublayer(playerLayer)

        let loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.color = .white
        loadingIndicator.hidesWhenStopped = true
        container.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        loadingIndicator.startAnimating()

        context.coordinator.player = player
        context.coordinator.playerLayer = playerLayer
        context.coordinator.item = item
        context.coordinator.loadingIndicator = loadingIndicator
        context.coordinator.lastURL = url
        context.coordinator.lastRestartToken = restartToken
        context.coordinator.isActive = isActive
        context.coordinator.attachPlaybackLoopObserver(for: item)
        context.coordinator.attachBufferObservers(for: item)
        context.coordinator.timeControlObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { observedPlayer, _ in
            DispatchQueue.main.async {
                guard let observedItem = observedPlayer.currentItem else {
                    context.coordinator.setLoadingVisible(true)
                    return
                }
                context.coordinator.updateLoadingState(player: observedPlayer, item: observedItem)
            }
        }
        context.coordinator.statusObserver = item.observe(\.status, options: [.initial, .new]) { observedItem, _ in
            DispatchQueue.main.async {
                guard context.coordinator.isActive else {
                    context.coordinator.setLoadingVisible(false)
                    return
                }
                context.coordinator.attemptPlaybackIfReady(player: player, item: observedItem)
                context.coordinator.updateLoadingState(player: player, item: observedItem)
            }
        }

        if isActive {
            DispatchQueue.main.async {
                player.seek(to: .zero)
                context.coordinator.attemptPlaybackIfReady(player: player, item: item)
                context.coordinator.updateLoadingState(player: player, item: item)
            }
        }

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let playerLayer = context.coordinator.playerLayer {
            playerLayer.frame = uiView.bounds
            playerLayer.contentsScale = UIScreen.main.scale
        }

        guard let player = context.coordinator.player else { return }
        player.isMuted = isMuted
        player.actionAtItemEnd = .none
        context.coordinator.isActive = isActive

        if !isActive {
            player.pause()
            context.coordinator.setLoadingVisible(false)
            return
        }

        if context.coordinator.lastURL != url || context.coordinator.lastRestartToken != restartToken {
            let replacementItem = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: replacementItem)
            context.coordinator.item = replacementItem
            context.coordinator.lastURL = url
            context.coordinator.lastRestartToken = restartToken
            context.coordinator.attachPlaybackLoopObserver(for: replacementItem)
            context.coordinator.attachBufferObservers(for: replacementItem)
            context.coordinator.statusObserver = replacementItem.observe(\.status, options: [.initial, .new]) { observedItem, _ in
                DispatchQueue.main.async {
                    guard context.coordinator.isActive else {
                        context.coordinator.setLoadingVisible(false)
                        return
                    }
                    context.coordinator.attemptPlaybackIfReady(player: player, item: observedItem)
                    context.coordinator.updateLoadingState(player: player, item: observedItem)
                }
            }

            DispatchQueue.main.async {
                player.seek(to: .zero)
                context.coordinator.attemptPlaybackIfReady(player: player, item: replacementItem)
                context.coordinator.updateLoadingState(player: player, item: replacementItem)
            }
            return
        }

        if player.timeControlStatus != .playing {
            if let item = player.currentItem {
                DispatchQueue.main.async {
                    player.seek(to: .zero)
                    context.coordinator.attemptPlaybackIfReady(player: player, item: item)
                    context.coordinator.updateLoadingState(player: player, item: item)
                }
            }
        }

        if let item = player.currentItem {
            context.coordinator.updateLoadingState(player: player, item: item)
        }
    }

    func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.player?.pause()
        coordinator.detachPlaybackLoopObserver()
        coordinator.detachBufferObservers()
        coordinator.statusObserver = nil
        coordinator.timeControlObserver = nil
        coordinator.playerLayer?.removeFromSuperlayer()
        coordinator.loadingIndicator?.removeFromSuperview()
        coordinator.player = nil
        coordinator.item = nil
        coordinator.playerLayer = nil
        coordinator.loadingIndicator = nil
    }

    final class Coordinator {
        var player: AVPlayer?
        var playerLayer: AVPlayerLayer?
        var item: AVPlayerItem?
        var loadingIndicator: UIActivityIndicatorView?
        var lastURL: URL?
        var lastRestartToken: Int = 0
        var isActive: Bool = false
        var statusObserver: NSKeyValueObservation?
        var timeControlObserver: NSKeyValueObservation?
        var likelyToKeepUpObserver: NSKeyValueObservation?
        var bufferFullObserver: NSKeyValueObservation?
        var loopObserver: NSObjectProtocol?

        func attemptPlaybackIfReady(player: AVPlayer, item: AVPlayerItem) {
            guard item.status == .readyToPlay else { return }
            guard item.isPlaybackLikelyToKeepUp || item.isPlaybackBufferFull else { return }
            guard isActive else { return }
            player.play()
        }

        func setLoadingVisible(_ visible: Bool) {
            guard let loadingIndicator else { return }
            if visible {
                loadingIndicator.startAnimating()
            } else {
                loadingIndicator.stopAnimating()
            }
        }

        func updateLoadingState(player: AVPlayer, item: AVPlayerItem) {
            guard isActive else {
                setLoadingVisible(false)
                return
            }

            let hasPlayableBuffer = item.isPlaybackLikelyToKeepUp || item.isPlaybackBufferFull
            let isPlaying = player.timeControlStatus == .playing
            let isReady = item.status == .readyToPlay
            setLoadingVisible(!(isReady && (hasPlayableBuffer || isPlaying)))
        }

        func attachBufferObservers(for item: AVPlayerItem) {
            detachBufferObservers()

            likelyToKeepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self] observedItem, _ in
                guard let self, let player = self.player else { return }
                DispatchQueue.main.async {
                    self.attemptPlaybackIfReady(player: player, item: observedItem)
                    self.updateLoadingState(player: player, item: observedItem)
                }
            }

            bufferFullObserver = item.observe(\.isPlaybackBufferFull, options: [.initial, .new]) { [weak self] observedItem, _ in
                guard let self, let player = self.player else { return }
                DispatchQueue.main.async {
                    self.attemptPlaybackIfReady(player: player, item: observedItem)
                    self.updateLoadingState(player: player, item: observedItem)
                }
            }
        }

        func detachBufferObservers() {
            likelyToKeepUpObserver = nil
            bufferFullObserver = nil
        }

        func attachPlaybackLoopObserver(for item: AVPlayerItem) {
            detachPlaybackLoopObserver()
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                guard let self, let player = self.player, self.isActive else { return }
                player.seek(to: .zero)
                player.play()
            }
        }

        func detachPlaybackLoopObserver() {
            if let loopObserver {
                NotificationCenter.default.removeObserver(loopObserver)
                self.loopObserver = nil
            }
        }
    }
}

struct PostCardView: View {
    @Binding var post: MockPost
    var isOwnPost: Bool = false
    var currentUserProfilePhotoImage: UIImage? = nil
    var showsAuthorLine: Bool = true
    var videoPlaybackEnabled: Bool? = nil
    var showProfileLocationBadge: Bool = false
    var isReported: Bool = false
    var onSend: () -> Void = {}
    var onSave: (MockPost) -> Void = { _ in }
    var onDelete: (() -> Void)? = nil
    var onReport: (() -> Void)? = nil
    var onProfileTap: () -> Void = {}
    var onMessageTap: () -> Void = {}
    var onViewTracked: (MockPost) -> Void = { _ in }

    @State private var selectedPollIndex: Int? = nil
    @State private var audioPlaybackPlayer: AVAudioPlayer? = nil

    private var currentSelectedPollIndex: Int? {
        selectedPollIndex ?? post.pollVotes.firstIndex(where: { $0 > 0 })
    }
    @State private var isAudioPostPlaying = false
    @State private var audioPlaybackDotCount = 1
    @State private var audioDotsAnimationTask: Task<Void, Never>? = nil
    @State private var audioPlaybackStopTask: Task<Void, Never>? = nil
    @State private var viewStartedAt: Date? = nil
    @State private var liveViewElapsedSeconds: Int = 0
    @State private var liveViewSessionElapsedSeconds: Int = 0
    @State private var liveViewSessionBaseDurationSeconds: Int = 0
    @State private var liveScoreTickerTask: Task<Void, Never>? = nil
    @State private var boostedShimmerOffset: CGFloat = -1.0
    @State private var showDeleteConfirmation = false
    @State private var guideVisibleStepCount = 1
    @State private var showHiringContactOptions = false
    @State private var isExpandedListingImagePresented = false
    @State private var isVideoPlaybackActive = false
    @State private var videoPlaybackRestartToken = 0
    @State private var showAdminPinCodePrompt = false
    @State private var adminPinCodeInput = ""
    @State private var adminPinErrorMessage = ""
    @Environment(\.openURL) private var openURL

    private static let liveViewRegistrationIntervalSeconds = 4

    private var pollChoices: [String] {
        post.pollOptions.count >= 2 ? Array(post.pollOptions.prefix(2)) : ["Yes", "No"]
    }

    private var pollVotes: [Int] {
        post.pollVotes.count >= 2 ? Array(post.pollVotes.prefix(2)) : [0, 0]
    }

    private var profileLocationBadgeText: String? {
        let postedRealm = post.postedInLocations
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        if let postedRealm {
            return postedRealm
        }

        let fallback = post.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? nil : fallback
    }

    private func voteForPoll(index: Int) {
        let result = PollVoteLogic.updatedVotes(
            currentVotes: post.pollVotes.count >= 2 ? post.pollVotes : [0, 0],
            previousSelection: selectedPollIndex ?? post.pollVotes.firstIndex(where: { $0 > 0 }),
            nextSelection: index
        )

        // Update local UI immediately with optimistic update
        post.pollVotes = result.votes
        selectedPollIndex = result.selected
        onViewTracked(post)

        let postIDForVote = post.firestoreID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(post.id)
            : post.firestoreID

        Task {
            do {
                let updatedVotes = try await FirebaseSpotService.shared.registerPollVote(postID: postIDForVote, optionIndex: index)
                await MainActor.run {
                    // Update with server response to ensure consistency
                    post.pollVotes = updatedVotes
                    selectedPollIndex = index
                    onViewTracked(post)
                }
            } catch {
                print("Spot poll vote save error: \(error)")
                // On error, revert the local vote by restoring previous state
                let previousSelection = selectedPollIndex ?? post.pollVotes.firstIndex(where: { $0 > 0 })
                selectedPollIndex = previousSelection
            }
        }
    }

    static func shouldCountView(isOwnPost: Bool, showsAuthorLine: Bool) -> Bool {
        // Suppress self-views while browsing your own profile posts.
        return !(isOwnPost && !showsAuthorLine)
    }

    static func shouldExpandMediaOnTap(forType type: String, hasMediaImage: Bool) -> Bool {
        return type == "For Sale" && hasMediaImage
    }

    static func mediaFrameSize(for image: UIImage?, availableWidth: CGFloat = UIScreen.main.bounds.width - 54, maxHeight: CGFloat = 760) -> CGSize {
        if let image {
            let width = max(1.0, image.size.width)
            let height = max(1.0, image.size.height)
            let aspectRatio = width / height
            let preferredWidth = min(max(240.0, availableWidth), 440.0)
            let resolvedHeight = min(maxHeight, max(260.0, preferredWidth / max(aspectRatio, 0.45)))
            let resolvedWidth = min(preferredWidth, resolvedHeight * aspectRatio)
            return CGSize(width: resolvedWidth, height: resolvedHeight)
        }

        return CGSize(width: min(max(240.0, availableWidth), 440.0), height: 420.0)
    }

    private var mediaCardSize: CGSize {
        Self.mediaFrameSize(for: post.mediaImage, availableWidth: UIScreen.main.bounds.width - 54)
    }

    private var isVideoPost: Bool {
        post.type == "Video" || post.type == "Photo/Video"
    }

    private var shouldAutoplayVideo: Bool {
        videoPlaybackEnabled ?? true
    }

    private var effectiveVideoCardSize: CGSize {
        if isVideoPost, showsAuthorLine {
            // Keep the card inside feed padding so parent layout width doesn't inflate.
            let desiredWidth = max(300.0, UIScreen.main.bounds.width - 16.0)
            let desiredHeight = min(760.0, max(540.0, UIScreen.main.bounds.height * 0.72))
            return CGSize(width: desiredWidth, height: desiredHeight)
        }
        return mediaCardSize
    }

    private var resolvedAudioPlaybackSource: String? {
        let candidates = (post.mediaURLs + [post.sourceURL ?? "", post.url])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for candidate in candidates {
            if candidate.hasPrefix("http://") || candidate.hasPrefix("https://") || candidate.hasPrefix("file://") || candidate.hasPrefix("/") || candidate.hasPrefix("~/") {
                return candidate
            }
        }

        return candidates.first
    }

    private var resolvedVideoPlaybackURL: URL? {
        let rawCandidates = (post.mediaURLs + [post.sourceURL ?? "", post.url])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rawCandidates.isEmpty else { return nil }

        let prioritized = rawCandidates.filter { isLikelyVideoReference($0) } + rawCandidates
        var seen: Set<String> = []

        for candidate in prioritized {
            if !seen.insert(candidate).inserted {
                continue
            }

            if let playable = playableVideoURL(from: candidate) {
                return playable
            }
        }

        return nil
    }

    private func isLikelyVideoReference(_ value: String) -> Bool {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered.hasPrefix("file://") || lowered.hasPrefix("/") {
            return true
        }

        let knownVideoHints = [".mp4", ".mov", ".m4v", ".webm", ".m3u8"]
        return knownVideoHints.contains { lowered.contains($0) }
    }

    private func playableVideoURL(from raw: String) -> URL? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        if cleaned.hasPrefix("http://") || cleaned.hasPrefix("https://") {
            let escaped = cleaned.replacingOccurrences(of: " ", with: "%20")
            if let remoteURL = URL(string: escaped),
               let scheme = remoteURL.scheme?.lowercased(),
               (scheme == "http" || scheme == "https") {
                return remoteURL
            }
        }

        if let directURL = URL(string: cleaned), directURL.isFileURL {
            return safeLocalVideoURL(from: directURL)
        }

        if cleaned.hasPrefix("/") {
            let fileURL = URL(fileURLWithPath: cleaned)
            return safeLocalVideoURL(from: fileURL)
        }

        if cleaned.hasPrefix("~/") {
            let expanded = NSString(string: cleaned).expandingTildeInPath
            let fileURL = URL(fileURLWithPath: expanded)
            return safeLocalVideoURL(from: fileURL)
        }

        if let legacyLocalURL = URL(string: cleaned), legacyLocalURL.scheme == "file" {
            return safeLocalVideoURL(from: legacyLocalURL)
        }

        return nil
    }

    private func copyVideoToTemporaryLocation(sourceURL: URL) -> URL? {
        guard sourceURL.isFileURL else {
            return sourceURL
        }

        let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension)

        let didAccessScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            return nil
        }
    }

    private func safeLocalVideoURL(from sourceURL: URL) -> URL? {
        guard sourceURL.isFileURL || sourceURL.path.starts(with: "/") else {
            return nil
        }

        let didAccessScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        let copiedURL = copyVideoToTemporaryLocation(sourceURL: sourceURL)
        return copiedURL ?? sourceURL
    }

    private var displayedEngagementScore: Double {
        guard Self.shouldCountView(isOwnPost: isOwnPost, showsAuthorLine: showsAuthorLine), viewStartedAt != nil else {
            return post.engagementScore
        }

        // Keep score moving for the full visible session, even between persisted engagement writes.
        let sessionDurationSeconds = liveViewSessionBaseDurationSeconds + max(0, liveViewSessionElapsedSeconds)
        let liveDurationSeconds = max(post.timeViewedSeconds, sessionDurationSeconds)
        let interval = max(1, Self.liveViewRegistrationIntervalSeconds)
        let liveViewProgress = min(max(Double(liveViewElapsedSeconds) / Double(interval), 0), 1)
        let currentScore = FirebaseSpotService.engagementScore(
            views: post.viewCount,
            totalViewDurationSeconds: liveDurationSeconds,
            saves: post.savedCount,
            likes: post.likes,
            comments: post.comments.count,
            shares: post.shareCount,
            viewProgress: liveViewProgress,
            locationBreadth: max(1, Set(post.postedInLocations.map { $0.lowercased() }).count),
            isBoosted: post.isBoosted
        )
        return max(post.engagementScore, currentScore)
    }

    private func persistEngagement(_ trackedPost: MockPost) {
        let postIDForEngagement = trackedPost.firestoreID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(trackedPost.id)
            : trackedPost.firestoreID

        Task {
            try? await FirebaseSpotService.shared.updatePostEngagement(
                postID: postIDForEngagement,
                viewCount: trackedPost.viewCount,
                totalViewDurationSeconds: trackedPost.timeViewedSeconds
            )
        }
    }

    private func registerLiveViewBatch(viewsToAdd: Int, durationSeconds: Int) {
        guard viewsToAdd > 0 || durationSeconds > 0 else { return }

        var trackedPost = post
        trackedPost.viewCount += max(0, viewsToAdd)
        trackedPost.timeViewedSeconds += max(0, durationSeconds)
        post = trackedPost
        onViewTracked(trackedPost)
        persistEngagement(trackedPost)
    }

    private func playAudioFile(_ audioURL: URL) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: audioURL)
            audioPlaybackStopTask?.cancel()
            audioPlaybackPlayer?.stop()
            player.prepareToPlay()
            guard player.play() else {
                stopAudioPlaybackDotsAnimation()
                return
            }
            audioPlaybackPlayer = player
            startAudioPlaybackDotsAnimation()

            audioPlaybackStopTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        guard let activePlayer = audioPlaybackPlayer else {
                            stopAudioPlaybackDotsAnimation()
                            return
                        }

                        let reachedPlaybackEnd = activePlayer.duration > 0
                            && activePlayer.currentTime >= (activePlayer.duration - 0.05)

                        if activePlayer === player && reachedPlaybackEnd {
                            stopAudioPlaybackDotsAnimation()
                        }
                    }
                }
            }
        } catch {
            // Ignore playback failures for the placeholder/mock audio posts.
            stopAudioPlaybackDotsAnimation()
        }
    }

    private func startAudioPlaybackDotsAnimation() {
        isAudioPostPlaying = true
        audioPlaybackDotCount = 1

        audioDotsAnimationTask?.cancel()
        audioDotsAnimationTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled else { break }

                await MainActor.run {
                    guard isAudioPostPlaying else { return }
                    audioPlaybackDotCount = audioPlaybackDotCount % 3 + 1
                }
            }
        }
    }

    private func stopAudioPlaybackDotsAnimation() {
        isAudioPostPlaying = false
        audioPlaybackDotCount = 1
        audioPlaybackPlayer?.stop()
        audioPlaybackPlayer = nil
        audioDotsAnimationTask?.cancel()
        audioDotsAnimationTask = nil
        audioPlaybackStopTask?.cancel()
        audioPlaybackStopTask = nil
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.duckOthers])
        } catch {
            print("Spot audio session reset failed: \(error)")
        }
    }

    private func playAudioPost(from urlString: String) {
        guard !urlString.isEmpty else { return }

        let audioURL = URL(string: urlString) ?? URL(fileURLWithPath: urlString)

        if audioURL.isFileURL {
            playAudioFile(audioURL)
            return
        }

        Task {
            do {
                let (downloadedURL, _) = try await URLSession.shared.download(from: audioURL)
                let fileExtension = audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("spot-audio-\(UUID().uuidString).\(fileExtension)")

                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try? FileManager.default.removeItem(at: tempURL)
                }
                try FileManager.default.moveItem(at: downloadedURL, to: tempURL)

                await MainActor.run {
                    playAudioFile(tempURL)
                }
            } catch {
                print("Audio playback fetch failed: \(error)")
            }
        }
    }

    private func mediaCardImageView() -> some View {
        let resolvedView: AnyView

        if let mediaImage = post.mediaImage {
            resolvedView = AnyView(
                Image(uiImage: mediaImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: mediaCardSize.width, height: mediaCardSize.height)
                    .contentShape(Rectangle())
                    .clipped()
            )
        } else if let remoteImageURL = ContentView.photoDisplayURL(for: post) {
            resolvedView = AnyView(
                AsyncImage(url: remoteImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: mediaCardSize.width, height: mediaCardSize.height)
                            .contentShape(Rectangle())
                            .clipped()
                    case .empty, .failure:
                        fallbackPhotoPlaceholder()
                    @unknown default:
                        fallbackPhotoPlaceholder()
                    }
                }
            )
        } else {
            resolvedView = AnyView(fallbackPhotoPlaceholder())
        }

        return resolvedView
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func fallbackPhotoPlaceholder() -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color(hex: post.accent), ContentView.appPrimaryThemeColor.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: mediaCardSize.width, height: mediaCardSize.height)
            .overlay(
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if post.type != "Video" {
                            Image(systemName: "photo.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(16)
            )
    }

    private func resolvedAdminPinCode() -> String {
        let saved = (UserDefaults.standard.string(forKey: "spot_admin_pin_code") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return saved.isEmpty ? "0420" : saved
    }

    private func resolvedAdminGlobalPinCode() -> String {
        let saved = (UserDefaults.standard.string(forKey: "spot_admin_global_pin_code") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return saved.isEmpty ? "2626" : saved
    }

    private func resolvedAdminUnpinCode() -> String {
        let saved = (UserDefaults.standard.string(forKey: "spot_admin_unpin_code") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return saved.isEmpty ? "0007" : saved
    }

    private func adminPinStorageKey(for post: MockPost) -> String {
        let trimmedFirestoreID = post.firestoreID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFirestoreID.isEmpty {
            return "f:\(trimmedFirestoreID)"
        }
        return "l:\(post.id)"
    }

    private func syncAdminPinStateToSharedStore(realm: String?, pinnedAt: TimeInterval?) {
        let postID = post.firestoreID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !postID.isEmpty else { return }

        Task {
            do {
                try await FirebaseSpotService.shared.setAdminPinState(
                    postID: postID,
                    realm: realm,
                    pinnedAt: pinnedAt
                )
            } catch {
                print("Spot admin pin sync failed: \(error)")
            }
        }
    }

    private func persistAdminPinForCurrentPost(applyToAllNonMetricFeeds: Bool = false) {
        let key = adminPinStorageKey(for: post)
        var realmMap = UserDefaults.standard.dictionary(forKey: "spot_admin_pinned_posts_by_realm") as? [String: String] ?? [:]
        var timestampMap = UserDefaults.standard.dictionary(forKey: "spot_admin_pinned_posts_at") as? [String: Double] ?? [:]

        let metricRealm = ContentView.normalizedLocationRealm("Metric")
        let targetRealm = applyToAllNonMetricFeeds ? "spot:all-non-metric" : metricRealm

        realmMap[key] = targetRealm
        let pinnedAt = Date().timeIntervalSince1970
        timestampMap[key] = pinnedAt

        UserDefaults.standard.set(realmMap, forKey: "spot_admin_pinned_posts_by_realm")
        UserDefaults.standard.set(timestampMap, forKey: "spot_admin_pinned_posts_at")

        syncAdminPinStateToSharedStore(realm: targetRealm, pinnedAt: pinnedAt)

        adminPinErrorMessage = applyToAllNonMetricFeeds ? "Pinned to all non-Metric feeds" : "Pinned to Metric top"
        onViewTracked(post)
    }

    private func removeAdminPinForCurrentPost() {
        let key = adminPinStorageKey(for: post)
        var realmMap = UserDefaults.standard.dictionary(forKey: "spot_admin_pinned_posts_by_realm") as? [String: String] ?? [:]
        var timestampMap = UserDefaults.standard.dictionary(forKey: "spot_admin_pinned_posts_at") as? [String: Double] ?? [:]

        realmMap.removeValue(forKey: key)
        timestampMap.removeValue(forKey: key)

        UserDefaults.standard.set(realmMap, forKey: "spot_admin_pinned_posts_by_realm")
        UserDefaults.standard.set(timestampMap, forKey: "spot_admin_pinned_posts_at")

        syncAdminPinStateToSharedStore(realm: nil, pinnedAt: nil)

        adminPinErrorMessage = "Pin removed"
        onViewTracked(post)
    }

    private func submitAdminPinCode() {
        let entered = adminPinCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entered.isEmpty else {
            adminPinErrorMessage = "Enter admin code"
            return
        }

        if entered == resolvedAdminPinCode() {
            persistAdminPinForCurrentPost(applyToAllNonMetricFeeds: false)
            adminPinCodeInput = ""
            showAdminPinCodePrompt = false
            return
        }

        if entered == resolvedAdminGlobalPinCode() {
            persistAdminPinForCurrentPost(applyToAllNonMetricFeeds: true)
            adminPinCodeInput = ""
            showAdminPinCodePrompt = false
            return
        }

        if entered == resolvedAdminUnpinCode() {
            removeAdminPinForCurrentPost()
            adminPinCodeInput = ""
            showAdminPinCodePrompt = false
            return
        }

        adminPinErrorMessage = "Invalid admin code"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                if showsAuthorLine {
                    HStack(alignment: .center, spacing: 10) {
                        ZStack {
                            if !post.isAnonymous,
                               isOwnPost,
                               let localProfilePhoto = currentUserProfilePhotoImage {
                                Image(uiImage: localProfilePhoto)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 34, height: 34)
                                    .clipShape(Circle())
                            } else if let rawURL = post.authorProfilePhotoURL,
                               let avatarURL = URL(string: rawURL),
                               !rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                AsyncImage(url: avatarURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 34, height: 34)
                                            .clipShape(Circle())
                                    default:
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 34, height: 34)
                                            .overlay(
                                                Text(String(post.author.prefix(2)).uppercased())
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(.black)
                                            )
                                    }
                                }
                            } else {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [ContentView.appPrimaryThemeColor, ContentView.appSecondaryThemeColor],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Text(String(post.author.prefix(2)).uppercased())
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.black)
                                    )
                            }
                        }
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.13), lineWidth: 0.8)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.72), lineWidth: 0.5)
                                .padding(0.6)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                        .blur(radius: post.isAnonymous ? 8 : 0)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.isAnonymous ? "Anonymous" : post.author)
                                .font(.headline)
                            Text(post.isAnonymous ? "Identity hidden" : (post.handle.hasPrefix("@") ? post.handle : "@\(post.handle)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .blur(radius: post.isAnonymous ? 8 : 0)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
                }

                if post.type == "Photo" || post.type == "Photo/Video" {
                    VStack(alignment: .leading, spacing: 10) {
                        ZStack(alignment: .bottomLeading) {
                            mediaCardImageView()
                        }
                        .frame(maxWidth: .infinity)

                        if !post.body.isEmpty {
                            Text(post.body)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 8)
                        }
                    }
                } else if isVideoPost {
                    VStack(alignment: .leading, spacing: 10) {
                        ZStack(alignment: .bottomLeading) {
                            if let videoURL = resolvedVideoPlaybackURL {
                                LoopingVideoPlayer(
                                    url: videoURL,
                                    isMuted: true,
                                    isActive: isVideoPlaybackActive,
                                    restartToken: videoPlaybackRestartToken
                                )
                                    .frame(width: effectiveVideoCardSize.width, height: effectiveVideoCardSize.height)
                                    .clipped()
                                    .contentShape(Rectangle())
                            } else {
                                mediaCardImageView()
                            }
                        }
                        .frame(maxWidth: .infinity)

                        if !post.body.isEmpty {
                            Text(post.body)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 8)
                        }
                    }
                } else if post.type == "Live Route" {
                    let route = LiveRouteCodec.decode(post.url)
                    let start = route?.start ?? "Start"
                    let end = route?.end ?? "Destination"
                    let routeBrandingLabel = (route?.isRunBranding ?? false) ? "run" : "trip"

                    VStack(alignment: .leading, spacing: 10) {
                        Text(post.title.isEmpty ? "\(post.author)'s \(routeBrandingLabel)" : post.title)
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)

                        LiveRouteMiniMapView(
                            startName: start,
                            endName: end,
                            nearbyPlaces: [],
                            height: showsAuthorLine ? 240 : 190
                        )

                        HStack(spacing: 8) {
                            Label(start, systemImage: "flag.fill")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.14))
                                .clipShape(Capsule())

                            Label(end, systemImage: "mappin.and.ellipse")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.14))
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 8)

                        if !post.body.isEmpty {
                            Text(post.body)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 8)
                        }
                    }
                } else if post.type == "Guide" {
                    let steps = GuidePostCodec.decode(post.url)
                    let totalSteps = max(1, steps.count)
                    let visibleCount = min(max(guideVisibleStepCount, 1), totalSteps)

                    VStack(alignment: .leading, spacing: 12) {
                        if !post.title.isEmpty {
                            Text(post.title)
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                        }

                        if !post.body.isEmpty {
                            Text(post.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 8)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(steps.prefix(visibleCount).enumerated()), id: \.offset) { pair in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(pair.offset + 1)")
                                        .font(.caption.weight(.bold))
                                        .frame(width: 22, height: 22)
                                        .background(Color.black)
                                        .foregroundStyle(.white)
                                        .clipShape(Circle())

                                    Text(pair.element)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        .padding(.horizontal, 8)

                        if visibleCount < totalSteps {
                            Button {
                                guideVisibleStepCount = min(totalSteps, guideVisibleStepCount + 1)
                            } label: {
                                Text("Next step (\(visibleCount + 1)/\(totalSteps))")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.black)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                        }
                    }
                } else if post.type == "Work" || post.type == "Hiring" {
                    let details = WorkPostCodec.decode(post.url)
                    let listings = details?.listings ?? []
                    let phone = details?.phone ?? ""
                    let email = details?.email ?? ""
                    let phoneDigits = WorkPostCodec.sanitizedPhoneDigits(phone)
                    let primaryListing = listings.first ?? ""

                    VStack(alignment: .leading, spacing: 12) {
                        if !primaryListing.isEmpty {
                            Text(primaryListing)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                        }

                        HStack(spacing: 8) {
                            Spacer(minLength: 0)

                            if !phoneDigits.isEmpty || !email.isEmpty {
                                Button {
                                    showHiringContactOptions = true
                                } label: {
                                    Text("Contact")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color(.secondarySystemBackground))
                                        .foregroundStyle(.primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .confirmationDialog("Contact", isPresented: $showHiringContactOptions, titleVisibility: .visible) {
                                    if !phoneDigits.isEmpty,
                                       let callURL = URL(string: "tel://\(phoneDigits)") {
                                        Button("Phone") {
                                            openURL(callURL)
                                        }
                                    }

                                    if !email.isEmpty,
                                       let mailtoURL = URL(string: "mailto:\(email)") {
                                        Button("Email") {
                                            openURL(mailtoURL)
                                        }
                                    }

                                    Button("Cancel", role: .cancel) {}
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                } else if post.type == "For Sale" {
                    let details = SalePostCodec.decode(post.url)
                    let items = details?.items ?? []
                    let price = details?.price ?? ""
                    let formattedPrice = price.isEmpty ? "Offer" : (price.hasPrefix("$") ? price : "$\(price)")
                    let phone = details?.phone ?? ""
                    let email = details?.email ?? ""
                    let phoneDigits = WorkPostCodec.sanitizedPhoneDigits(phone)
                    let primaryItem = items.first ?? ""

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Spacer(minLength: 0)
                            Text(formattedPrice)
                                .font(.headline.weight(.bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 8)

                        HStack(alignment: .center, spacing: 12) {
                            Group {
                                if let image = post.mediaImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 88, height: 88)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .onTapGesture {
                                            if Self.shouldExpandMediaOnTap(forType: post.type, hasMediaImage: post.mediaImage != nil) {
                                                isExpandedListingImagePresented = true
                                            }
                                        }
                                } else {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.secondarySystemBackground))
                                        .frame(width: 88, height: 88)
                                        .overlay(
                                            Image(systemName: "photo")
                                                .foregroundStyle(.secondary)
                                        )
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                if !primaryItem.isEmpty {
                                    Text(primaryItem)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .lineLimit(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 8)

                        if !phoneDigits.isEmpty,
                           let callURL = URL(string: "tel://\(phoneDigits)") {
                            Link(destination: callURL) {
                                Text("Contact seller")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color(.systemGray5))
                                    .foregroundStyle(.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                        }
                    }
                } else if post.type == "Poll" {
                    VStack(alignment: .leading, spacing: 16) {
                        if !post.title.isEmpty {
                            Text(post.title)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 8)
                                .padding(.top, 6)
                        }

                        HStack(alignment: .center, spacing: 14) {
                            VStack(alignment: .leading, spacing: 10) {
                                PollVoteButton(
                                    label: pollChoices[0],
                                    count: pollVotes[0],
                                    totalVotes: pollVotes.reduce(0, +),
                                    isSelected: currentSelectedPollIndex == 0,
                                    tint: Color(red: 0.12, green: 0.43, blue: 0.87)
                                ) {
                                    voteForPoll(index: 0)
                                }

                                PollVoteButton(
                                    label: pollChoices[1],
                                    count: pollVotes[1],
                                    totalVotes: pollVotes.reduce(0, +),
                                    isSelected: currentSelectedPollIndex == 1,
                                    tint: Color(red: 0.54, green: 0.31, blue: 0.85)
                                ) {
                                    voteForPoll(index: 1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, 2)

                            PieChartView(votes: pollVotes, colorSeed: post.id)
                                .frame(width: 96, height: 96)
                                .fixedSize()
                                .padding(.trailing, 2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)
                } else if post.type == "Audio" {
                    let audioBlockMinHeight = showsAuthorLine ? 52.0 : 80.0
                    let audioBlockPadding: CGFloat = showsAuthorLine ? 2.0 : 8.0

                    VStack(alignment: .center, spacing: 0) {
                        Spacer(minLength: 0)

                        HStack(alignment: .center, spacing: 12) {
                            Button {
                                if let audioSource = resolvedAudioPlaybackSource {
                                    playAudioPost(from: audioSource)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                        .font(.caption.weight(.bold))
                                    if isAudioPostPlaying {
                                        Text("Playing audio")
                                            .font(.caption.weight(.semibold))
                                    } else {
                                        Text("Play audio")
                                            .font(.caption.weight(.semibold))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .foregroundStyle(.black)
                                .background(Color.white)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.black, lineWidth: 1.2)
                                )
                                .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }
                        .padding(.leading, 8)
                        .frame(maxWidth: .infinity, alignment: .center)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: audioBlockMinHeight, alignment: .center)
                    .padding(.vertical, audioBlockPadding)
                } else if post.type == "Song" {
                    let hasSongArtwork = post.mediaImage != nil
                    let hasSongDescription = !post.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                    if !hasSongArtwork && !hasSongDescription {
                        VStack(alignment: .center, spacing: 6) {
                            HStack(alignment: .center, spacing: 12) {
                                Button {
                                    if let audioSource = resolvedAudioPlaybackSource {
                                        playAudioPost(from: audioSource)
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "play.fill")
                                            .font(.caption.weight(.bold))
                                        Text(isAudioPostPlaying ? "Playing song" : "Play song")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(.black)
                                    .background(Color.white)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.black, lineWidth: 1.2)
                                    )
                                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                                }
                                .buttonStyle(.plain)

                                Spacer()
                            }
                            .padding(.leading, 8)
                            .frame(maxWidth: .infinity, alignment: .center)

                            Spacer(minLength: 3)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
                        .padding(.bottom, 2)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            if let artwork = post.mediaImage {
                                Image(uiImage: artwork)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .padding(.horizontal, 8)
                            }

                            if hasSongDescription {
                                Text(post.body)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 8)
                            }

                            Button {
                                if let audioSource = resolvedAudioPlaybackSource {
                                    playAudioPost(from: audioSource)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                        .font(.caption.weight(.bold))
                                    Text(isAudioPostPlaying ? "Playing song" : "Play song")
                                        .font(.caption.weight(.semibold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .foregroundStyle(.black)
                                .background(Color.white)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.black, lineWidth: 1.2)
                                )
                                .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                        .padding(.bottom, 4)
                    }
                } else if post.type == "Text" {
                    if showsAuthorLine {
                        // Feed view: text posts are naturally sized
                        Text(post.body)
                            .font(.body)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                            .padding(.bottom, 6)
                            .padding(.leading, 8)
                    } else {
                        // Profile view: left-aligned text, vertically centered within post container
                        VStack {
                            Spacer()
                            Text(post.body)
                                .font(.body)
                                .lineSpacing(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 8)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 70)
                    }
                } else if post.type == "Link" {
                    VStack(alignment: .leading, spacing: 12) {
                        LinkPreviewCard(
                            urlString: post.url,
                            fallbackTitle: post.title.isEmpty ? post.handle : post.title,
                            fallbackDescription: post.body,
                            accentColor: Color(hex: post.accent)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)

                        if !post.body.isEmpty {
                            Text(post.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack {
                        if post.type != "Video" {
                            Image(systemName: post.type == "Photo/Video" ? "photo.on.rectangle.angled" : "waveform")
                                .font(.title2)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(post.title.isEmpty ? post.handle : post.title)
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if !post.body.isEmpty {
                                Text(post.body)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !post.isAnonymous else { return }
                if Self.shouldExpandMediaOnTap(forType: post.type, hasMediaImage: post.mediaImage != nil) {
                    isExpandedListingImagePresented = true
                    return
                }
                onProfileTap()
            }
            .onLongPressGesture(minimumDuration: 0.55) {
                adminPinErrorMessage = ""
                adminPinCodeInput = ""
                showAdminPinCodePrompt = true
            }

            postActionRow
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(Color(red: 0.972, green: 0.982, blue: 0.995))
        .overlay(
            Rectangle()
                .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.09))
                .frame(height: 0.6)
                .padding(.horizontal, 8)
        }
        .clipShape(Rectangle())
        .sheet(isPresented: $isExpandedListingImagePresented) {
            if let expandedImage = post.mediaImage {
                ZStack {
                    Color.black.opacity(0.8)
                        .ignoresSafeArea()

                    Image(uiImage: expandedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.9,
                               maxHeight: UIScreen.main.bounds.height * 0.8)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.9), lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 8)

                    Button {
                        isExpandedListingImagePresented = false
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.95))
                                .frame(width: 36, height: 36)
                                .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.black)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 24)
                    .padding(.trailing, 20)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                if showProfileLocationBadge, let locationTag = profileLocationBadgeText {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption2)
                        Text(locationTag)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.black.opacity(0.18), lineWidth: 1)
                    )
                }

            }
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
        .confirmationDialog("Delete this post?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                effectiveDeleteAction?()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Pin Post", isPresented: $showAdminPinCodePrompt) {
            TextField("Admin code", text: $adminPinCodeInput)
            Button("Pin") {
                submitAdminPinCode()
            }
            Button("Cancel", role: .cancel) {
                adminPinCodeInput = ""
            }
        } message: {
            if adminPinErrorMessage.isEmpty {
                Text("Enter code: 0420 pins Metric top, 2626 pins all non-Metric feeds, 0007 unpins.")
            } else {
                Text(adminPinErrorMessage)
            }
        }
        .onAppear {
            if isVideoPost && shouldAutoplayVideo {
                DispatchQueue.main.async {
                    isVideoPlaybackActive = true
                    videoPlaybackRestartToken += 1
                }
            } else if isVideoPost {
                isVideoPlaybackActive = false
            }
            viewStartedAt = Date()
            liveViewElapsedSeconds = 0
            liveViewSessionElapsedSeconds = 0
            liveViewSessionBaseDurationSeconds = post.timeViewedSeconds
            guideVisibleStepCount = 1
            liveScoreTickerTask?.cancel()
            liveScoreTickerTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard Self.shouldCountView(isOwnPost: isOwnPost, showsAuthorLine: showsAuthorLine) else {
                            return
                        }

                        liveViewElapsedSeconds += 1
                        liveViewSessionElapsedSeconds += 1
                        let interval = max(1, Self.liveViewRegistrationIntervalSeconds)
                        if liveViewElapsedSeconds >= interval {
                            let completedViews = liveViewElapsedSeconds / interval
                            let committedSeconds = completedViews * interval
                            liveViewElapsedSeconds -= committedSeconds
                            registerLiveViewBatch(viewsToAdd: completedViews, durationSeconds: committedSeconds)
                        }
                    }
                }
            }
        }
        .onDisappear {
            isVideoPlaybackActive = false
            audioDotsAnimationTask?.cancel()
            audioDotsAnimationTask = nil
            liveScoreTickerTask?.cancel()
            liveScoreTickerTask = nil
            guideVisibleStepCount = 1

            if viewStartedAt != nil {
                if Self.shouldCountView(isOwnPost: isOwnPost, showsAuthorLine: showsAuthorLine), liveViewElapsedSeconds > 0 {
                    // Keep legacy behavior: if the user viewed for any remaining time, count one final view.
                    registerLiveViewBatch(viewsToAdd: 1, durationSeconds: liveViewElapsedSeconds)
                }
                viewStartedAt = nil
                liveViewElapsedSeconds = 0
                liveViewSessionElapsedSeconds = 0
                liveViewSessionBaseDurationSeconds = 0
            }
        }
        .onChange(of: post.id) { _, _ in
            guideVisibleStepCount = 1
            if isVideoPost && shouldAutoplayVideo {
                DispatchQueue.main.async {
                    isVideoPlaybackActive = true
                    videoPlaybackRestartToken += 1
                }
            } else if isVideoPost {
                isVideoPlaybackActive = false
            }
        }
        .onChange(of: videoPlaybackEnabled) { _, enabled in
            guard isVideoPost else { return }
            let shouldPlay = enabled ?? true
            if shouldPlay {
                DispatchQueue.main.async {
                    isVideoPlaybackActive = true
                    videoPlaybackRestartToken += 1
                }
            } else {
                isVideoPlaybackActive = false
            }
        }
    }

    private var effectiveDeleteAction: (() -> Void)? {
        (isOwnPost && !showsAuthorLine) ? onDelete : nil
    }

    private var postActionRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    onSave(post)
                } label: {
                    Circle()
                        .strokeBorder(Color(.systemGray4), lineWidth: 1.2)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(post.isSaved ? Color(.systemGray4) : Color.clear)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    onSend()
                } label: {
                    Image(systemName: "arrowshape.turn.up.right.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if isOwnPost && !showsAuthorLine {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Text("Delete")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(.systemGray))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        onReport?()
                    } label: {
                        Image(systemName: "flag")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isReported ? Color.secondary : Color.black.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 8)

            Spacer()

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text(formatCompactNumber(displayedEngagementScore))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(.systemGray))
                    TrendLineView()
                        .frame(width: 18, height: 10)
                }

                Text(post.relativeTimestampText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color(.systemGray2))
            }
            .frame(alignment: .trailing)
            .padding(.trailing, 8)
        }
    }
}

func formatCompactNumber(_ value: Double) -> String {
    if value >= 10000 {
        return String(format: "%.1fK", value / 1000.0)
    }

    let rounded = (value * 100).rounded() / 100
    let wholeValue = rounded.rounded()
    if abs(rounded - wholeValue) < 0.0001 {
        return String(Int(wholeValue))
    }

    return String(format: "%.2f", rounded)
}

func formatFollowerCount(_ value: Int) -> String {
    if value >= 100000 {
        return String(format: "%.1fK", Double(value) / 1000.0)
    }
    return String(value)
}

private struct TrendLineView: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 8))
            path.addLine(to: CGPoint(x: 4, y: 6))
            path.addLine(to: CGPoint(x: 8, y: 4))
            path.addLine(to: CGPoint(x: 12, y: 5))
            path.addLine(to: CGPoint(x: 18, y: 2))
        }
        .stroke(Color.green, lineWidth: 1.5)
        .frame(width: 18, height: 10)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let hexString = cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned

        var rgb: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255

        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    ContentView()
}
