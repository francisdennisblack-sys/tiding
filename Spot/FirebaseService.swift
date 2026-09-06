import Foundation
import CoreLocation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage

public enum FirebaseSpotError: Error {
    case appNotConfigured
    case userNotAuthenticated
    case invalidPayload
    case uploadFailed
    case writeFailed
    case readFailed
    case invalidUsername
    case usernameTaken
    case emailNotVerified
    case invalidEmail
    case weakPassword
}

public struct PollVoteResult {
    public let votes: [Int]
    public let selectedIndex: Int
    public let wasRecorded: Bool

    public init(votes: [Int], selectedIndex: Int, wasRecorded: Bool) {
        self.votes = votes
        self.selectedIndex = selectedIndex
        self.wasRecorded = wasRecorded
    }
}

public struct FirebasePostPayload: Codable {
    public let id: String
    public let authorID: String
    public let authorUsername: String
    public let authorDisplayName: String
    public let authorProfilePhotoURL: String?
    public let contentType: String
    public let title: String?
    public let body: String?
    public let sourceURL: String?
    public let mediaURLs: [String]
    public let pollOptions: [String]
    public let pollVotes: [Int]
    public let currentUserPollSelection: Int?
    public let accentHex: String
    public let locationName: String
    public let feedInsertionIndex: Int
    public let postedInLocations: [String]
    public let poiID: String?
    public let latitude: Double
    public let longitude: Double
    public let city: String?
    public let country: String?
    public let geohash: String?
    public let createdAt: TimeInterval
    public let updatedAt: TimeInterval
    public let isVideo: Bool
    public let visibilityScope: String
    public let tags: [String]
    public let likesCount: Int
    public let commentsCount: Int
    public let viewCount: Int
    public let totalViewDurationSeconds: Int
    public let savedCount: Int
    public let shareCount: Int
    public let score: Double

    public init(
        id: String,
        authorID: String,
        authorUsername: String = "",
        authorDisplayName: String = "",
        authorProfilePhotoURL: String? = nil,
        contentType: String,
        title: String? = nil,
        body: String? = nil,
        sourceURL: String? = nil,
        mediaURLs: [String] = [],
        pollOptions: [String] = [],
        pollVotes: [Int] = [],
        currentUserPollSelection: Int? = nil,
        accentHex: String = "#DCE7FF",
        locationName: String,
        feedInsertionIndex: Int = 0,
        postedInLocations: [String] = [],
        poiID: String? = nil,
        latitude: Double,
        longitude: Double,
        city: String? = nil,
        country: String? = nil,
        geohash: String? = nil,
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        updatedAt: TimeInterval = Date().timeIntervalSince1970,
        isVideo: Bool = false,
        visibilityScope: String = "nearby",
        tags: [String] = [],
        likesCount: Int = 0,
        commentsCount: Int = 0,
        viewCount: Int = 0,
        totalViewDurationSeconds: Int = 0,
        savedCount: Int = 0,
        shareCount: Int = 0,
        score: Double = 0
    ) {
        self.id = id
        self.authorID = authorID
        self.authorUsername = authorUsername
        self.authorDisplayName = authorDisplayName
        self.authorProfilePhotoURL = authorProfilePhotoURL
        self.contentType = contentType
        self.title = title
        self.body = body
        self.sourceURL = sourceURL
        self.mediaURLs = mediaURLs
        self.pollOptions = pollOptions
        self.pollVotes = pollVotes
        self.currentUserPollSelection = currentUserPollSelection
        self.accentHex = accentHex
        self.locationName = locationName
        self.feedInsertionIndex = feedInsertionIndex
        self.postedInLocations = postedInLocations
        self.poiID = poiID
        self.latitude = latitude
        self.longitude = longitude
        self.city = city
        self.country = country
        self.geohash = geohash
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isVideo = isVideo
        self.visibilityScope = visibilityScope
        self.tags = tags
        self.likesCount = likesCount
        self.commentsCount = commentsCount
        self.viewCount = viewCount
        self.totalViewDurationSeconds = totalViewDurationSeconds
        self.savedCount = savedCount
        self.shareCount = shareCount
        self.score = score
    }
}

public struct FirebasePOIRecord: Codable {
    public let id: String
    public let name: String
    public let category: String
    public let latitude: Double
    public let longitude: Double
    public let neighborhood: String?
    public let subregion: String?
    public let city: String?
    public let country: String?
    public let geohash: String?
    public let updatedAt: TimeInterval

    public init(
        id: String,
        name: String,
        category: String,
        latitude: Double,
        longitude: Double,
        neighborhood: String? = nil,
        subregion: String? = nil,
        city: String? = nil,
        country: String? = nil,
        geohash: String? = nil,
        updatedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
        self.neighborhood = neighborhood
        self.subregion = subregion
        self.city = city
        self.country = country
        self.geohash = geohash
        self.updatedAt = updatedAt
    }
}

public struct FirebaseUserAccountRecord: Codable {
    public let uid: String
    public let username: String
    public let displayName: String
    public let phoneNumber: String?
    public let bio: String?
    public let profilePhotoURL: String?
    public let createdAt: TimeInterval
    public let updatedAt: TimeInterval
    public let savedPostIDs: [String]
    public let flaggedPostIDs: [String]
    public let postedPostIDs: [String]
    public let areaHistory: [String]
    public let followerCount: Int
    public let followingCount: Int
    public let remainingBoosts: Int

    public init(
        uid: String,
        username: String,
        displayName: String,
        phoneNumber: String? = nil,
        bio: String? = nil,
        profilePhotoURL: String? = nil,
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        updatedAt: TimeInterval = Date().timeIntervalSince1970,
        savedPostIDs: [String] = [],
        flaggedPostIDs: [String] = [],
        postedPostIDs: [String] = [],
        areaHistory: [String] = [],
        followerCount: Int = 0,
        followingCount: Int = 0,
        remainingBoosts: Int = 0
    ) {
        self.uid = uid
        self.username = username
        self.displayName = displayName
        self.phoneNumber = phoneNumber
        self.bio = bio
        self.profilePhotoURL = profilePhotoURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.savedPostIDs = savedPostIDs
        self.flaggedPostIDs = flaggedPostIDs
        self.postedPostIDs = postedPostIDs
        self.areaHistory = areaHistory
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.remainingBoosts = max(0, remainingBoosts)
    }
}

public struct FirebaseUserPostLogEntry: Codable {
    public let id: String
    public let userID: String
    public let postID: String
    public let locationName: String
    public let locationKey: String
    public let contentType: String
    public let feedInsertionIndex: Int
    public let createdAt: TimeInterval
    public let updatedAt: TimeInterval

    public init(
        id: String,
        userID: String,
        postID: String,
        locationName: String,
        locationKey: String = "",
        contentType: String = "",
        feedInsertionIndex: Int = 0,
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        updatedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.userID = userID
        self.postID = postID
        self.locationName = locationName
        self.locationKey = locationKey
        self.contentType = contentType
        self.feedInsertionIndex = feedInsertionIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct FirebaseModeratedPostResult: Codable {
    public let approved: Bool
    public let posted: Bool
    public let status: String
    public let message: String
    public let reasonCodes: [String]
    public let scores: [String: Double]
    public let postID: String?

    public var isApproved: Bool {
        approved || status == "approved"
    }
}

public struct FirebaseChatMessage: Codable, Identifiable {
    public let id: String
    public let senderID: String
    public let text: String
    public let sharedPostID: String?
    public let createdAt: TimeInterval

    public init(id: String, senderID: String, text: String, sharedPostID: String? = nil, createdAt: TimeInterval = Date().timeIntervalSince1970) {
        self.id = id
        self.senderID = senderID
        self.text = text
        self.sharedPostID = sharedPostID
        self.createdAt = createdAt
    }
}

public final class FirebaseSpotService {
    public static let shared = FirebaseSpotService()

    public enum PasswordResetDeliveryMode {
        case branded
        case standardFallback
    }

    private lazy var db = Firestore.firestore()
    private lazy var storage = Storage.storage(url: FirebaseConfig.storageBucketURL)

    private init() {}

    public func bootstrap() {
        FirebaseConfig.configureIfNeeded()
    }

    public static func isValidEmail(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let range = trimmed.range(of: pattern, options: .regularExpression)
        return range != nil
    }

    public static func passwordRequirementsText() -> String {
        "Password must be at least 6 characters."
    }

    public static func isStrongPassword(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 6
    }

    public func signIn(email: String, password: String) async throws -> User {
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(cleanedEmail) else { throw FirebaseSpotError.invalidEmail }
        guard !cleanedPassword.isEmpty else { throw FirebaseSpotError.invalidPayload }

        let result = try await Auth.auth().signIn(withEmail: cleanedEmail, password: cleanedPassword)
        return result.user
    }

    public func signUp(email: String, password: String, username: String, displayName: String? = nil, bio: String? = nil, photoURL: String? = nil) async throws -> User {
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(cleanedEmail) else {
            throw FirebaseSpotError.invalidEmail
        }
        guard Self.isStrongPassword(cleanedPassword) else {
            throw FirebaseSpotError.weakPassword
        }

        let result = try await Auth.auth().createUser(withEmail: cleanedEmail, password: cleanedPassword)
        let uid = result.user.uid
        let normalizedUsername = Self.normalizeUsername(username)
        let resolvedDisplayName = (displayName ?? "User").trimmingCharacters(in: .whitespacesAndNewlines)

        try await saveUserProfile(
            userID: uid,
            username: normalizedUsername.isEmpty ? "user" : normalizedUsername,
            displayName: resolvedDisplayName.isEmpty ? "User" : resolvedDisplayName,
            bio: bio,
            photoURL: photoURL
        )

        try await result.user.sendEmailVerification()

        return result.user
    }

    public func sendEmailVerification() async throws {
        guard let user = Auth.auth().currentUser else {
            throw FirebaseSpotError.userNotAuthenticated
        }
        try await user.sendEmailVerification()
    }

    private func ensurePushAuthenticatedUserID() async throws -> String {
        if let existingUID = Auth.auth().currentUser?.uid, !existingUID.isEmpty {
            return existingUID
        }

        let user = try await signInAnonymously()
        return user.uid
    }

    private func sanitizedAPNSToken(_ raw: String) -> String {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()

        let validCharacterSet = CharacterSet(charactersIn: "0123456789abcdef")
        guard cleaned.count >= 64, cleaned.rangeOfCharacter(from: validCharacterSet.inverted) == nil else {
            return ""
        }
        return cleaned
    }

    public func registerDevicePushTokenForCurrentUser(apnsToken: String) async throws {
        let token = sanitizedAPNSToken(apnsToken)
        guard !token.isEmpty else {
            throw FirebaseSpotError.invalidPayload
        }

        _ = try await ensurePushAuthenticatedUserID()
        let callable = Functions.functions().httpsCallable("registerDevicePushToken")
        _ = try await callable.call([
            "apnsToken": token,
            "platform": "ios"
        ])
    }

    public func sendPostAgreementRemoteTestPush(apnsToken: String, locationName: String) async throws {
        let token = sanitizedAPNSToken(apnsToken)
        guard !token.isEmpty else {
            throw FirebaseSpotError.invalidPayload
        }

        _ = try await ensurePushAuthenticatedUserID()
        let callable = Functions.functions().httpsCallable("sendPostAgreementRemoteTestPush")
        _ = try await callable.call([
            "apnsToken": token,
            "locationName": locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
    }

    public func sendPasswordReset(email: String) async throws -> PasswordResetDeliveryMode {
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(cleanedEmail) else {
            throw FirebaseSpotError.invalidEmail
        }

        // Send through Firebase Auth directly so the Firebase password-reset template
        // in Console is always the source of truth for delivery and branding.
        try await Auth.auth().sendPasswordReset(withEmail: cleanedEmail)
        return .standardFallback
    }

    public func signInAnonymously() async throws -> User {
        do {
            print("FirebaseSpotService.signInAnonymously: Starting anonymous auth...")
            let result = try await Auth.auth().signInAnonymously()
            print("FirebaseSpotService.signInAnonymously: Success! UID=\(result.user.uid)")
            return result.user
        } catch {
            print("FirebaseSpotService.signInAnonymously: FAILED")
            print("  Error domain: \(NSError(domain: "", code: 0).domain)")
            print("  Error code: \((error as NSError).code)")
            print("  Error message: \(error.localizedDescription)")
            print("  Full error: \(error)")
            throw error
        }
    }

    public func sendPhoneCode(to phoneNumber: String) async throws -> String {
        let cleaned = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw FirebaseSpotError.invalidPayload
        }

        let verificationID = try await PhoneAuthProvider.provider().verifyPhoneNumber(cleaned, uiDelegate: nil)
        guard !verificationID.isEmpty else {
            throw FirebaseSpotError.invalidPayload
        }
        return verificationID
    }

    public func linkOrSignInPhoneNumber(phoneNumber: String, verificationID: String, verificationCode: String) async throws -> User {
        let cleanedNumber = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCode = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedNumber.isEmpty, !cleanedCode.isEmpty, !verificationID.isEmpty else {
            throw FirebaseSpotError.invalidPayload
        }

        let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationID, verificationCode: cleanedCode)

        let currentUser: User
        if let existingUser = Auth.auth().currentUser {
            currentUser = existingUser
            let hasPhoneProvider = existingUser.providerData.contains { $0.providerID == PhoneAuthProviderID }
            if hasPhoneProvider {
                try await existingUser.updatePhoneNumber(credential)
            } else {
                _ = try await existingUser.link(with: credential)
            }
        } else {
            let result = try await Auth.auth().signIn(with: credential)
            currentUser = result.user
        }

        if Auth.auth().currentUser?.uid == currentUser.uid {
            let profileRef = Firestore.firestore().collection("users").document(currentUser.uid)
            let verifiedAt = Date().timeIntervalSince1970
            let data: [String: Any] = [
                "uid": currentUser.uid,
                "phoneNumber": cleanedNumber,
                "phoneVerifiedAt": verifiedAt,
                "updatedAt": verifiedAt
            ]
            try await profileRef.setData(data, merge: true)
        }

        return currentUser
    }

    public func updatePhoneNumberForCurrentUser(phoneNumber: String, verificationID: String, verificationCode: String) async throws -> User {
        let cleanedNumber = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCode = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedNumber.isEmpty, !cleanedCode.isEmpty, !verificationID.isEmpty else {
            throw FirebaseSpotError.invalidPayload
        }

        guard let currentUser = Auth.auth().currentUser else {
            throw FirebaseSpotError.userNotAuthenticated
        }

        let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationID, verificationCode: cleanedCode)
        let hasPhoneProvider = currentUser.providerData.contains { $0.providerID == PhoneAuthProviderID }
        if hasPhoneProvider {
            try await currentUser.updatePhoneNumber(credential)
        } else {
            _ = try await currentUser.link(with: credential)
        }

        let verifiedAt = Date().timeIntervalSince1970
        try await Firestore.firestore().collection("users").document(currentUser.uid).setData([
            "uid": currentUser.uid,
            "phoneNumber": cleanedNumber,
            "phoneVerifiedAt": verifiedAt,
            "updatedAt": verifiedAt
        ], merge: true)

        return currentUser
    }

    public func ensureAuthenticatedUser(username: String, displayName: String = "User", bio: String? = nil, photoURL: String? = nil) async throws -> User {
        let currentUser: User
        if let existingUser = Auth.auth().currentUser {
            currentUser = existingUser
        } else {
            currentUser = try await signInAnonymously()
        }

        let normalized = Self.normalizeUsername(username)
        guard Self.isValidUsername(normalized) else {
            throw FirebaseSpotError.invalidUsername
        }

        try await saveUserProfile(userID: currentUser.uid, username: normalized, displayName: displayName, bio: bio, photoURL: photoURL)
        return currentUser
    }

    public func signOut() throws {
        try Auth.auth().signOut()
    }

    public func currentUserID() throws -> String {
        guard let userID = Auth.auth().currentUser?.uid else {
            throw FirebaseSpotError.userNotAuthenticated
        }
        return userID
    }

    public func uploadMedia(data: Data, folder: String, fileName: String) async throws -> String {
        let userID = try currentUserID()
        let storageRef = storage.reference()
            .child(folder)
            .child(userID)
            .child(fileName)

        _ = try await storageRef.putDataAsync(data)
        let url = try await storageRef.downloadURL()
        return url.absoluteString
    }

    public func uploadMediaFallback(data: Data, folder: String, fileName: String, contentType: String, ownerID: String? = nil) async throws -> String {
        guard data.count <= 7 * 1024 * 1024 else {
            throw FirebaseSpotError.uploadFailed
        }

        let callable = Functions.functions().httpsCallable("uploadMediaFallback")
        let payload: [String: Any] = [
            "base64Data": data.base64EncodedString(),
            "folder": folder,
            "fileName": fileName,
            "contentType": contentType,
            "ownerID": ownerID ?? ""
        ]

        let result = try await callable.call(payload)
        guard let data = result.data as? [String: Any],
              let url = data["url"] as? String,
              !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FirebaseSpotError.uploadFailed
        }

        return url
    }

    public func uploadMediaFile(fileURL: URL, folder: String, fileName: String) async throws -> String {
        let userID = try currentUserID()
        let storageRef = storage.reference()
            .child(folder)
            .child(userID)
            .child(fileName)

        _ = try await storageRef.putFileAsync(from: fileURL)
        let url = try await storageRef.downloadURL()
        return url.absoluteString
    }

    public static func sanitizeFirestoreDocumentID(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = cleaned.map { character in
            let scalar = character.unicodeScalars.first
            if scalar != nil && (character.isLetter || character.isNumber || character == "_" || character == "-") {
                return String(character)
            }
            return "_"
        }.joined()

        return safe.isEmpty ? "poi" : safe
    }

    public static func canonicalPostDocumentID(fieldID: String?, documentID: String) -> String {
        let trimmedDocumentID = documentID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDocumentID.isEmpty {
            return trimmedDocumentID
        }

        return (fieldID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedPostReference(for postID: String) async throws -> DocumentReference {
        let cleanedPostID = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPostID.isEmpty else {
            throw FirebaseSpotError.invalidPayload
        }

        let directRef = db.collection("posts").document(cleanedPostID)
        let directSnapshot = try await directRef.getDocument()
        if directSnapshot.exists {
            return directRef
        }

        let byFieldID = try await db.collection("posts")
            .whereField("id", isEqualTo: cleanedPostID)
            .limit(to: 1)
            .getDocuments()

        if let matched = byFieldID.documents.first {
            return matched.reference
        }

        throw FirebaseSpotError.readFailed
    }

    private static func decodedString(_ raw: Any?) -> String? {
        guard let value = raw as? String else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func decodedDouble(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty { return nil }
            return Double(cleaned)
        }
        return nil
    }

    private static func milesDistance(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> Double {
        let src = CLLocation(latitude: source.latitude, longitude: source.longitude)
        let dst = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        return src.distance(from: dst) / 1609.344
    }

    private func decodePOI(from document: DocumentSnapshot) -> FirebasePOIRecord? {
        let data = document.data()

        let id = Self.decodedString(data?["id"])
            ?? Self.decodedString(data?["sourceID"])
            ?? document.documentID
        let name = Self.decodedString(data?["name"])
            ?? Self.decodedString(data?["displayName"])
        let category = Self.decodedString(data?["category"])
            ?? Self.decodedString(data?["type"])
            ?? Self.decodedString(data?["class"])
            ?? "poi"
        let latitude = Self.decodedDouble(data?["latitude"])
            ?? Self.decodedDouble(data?["lat"])
        let longitude = Self.decodedDouble(data?["longitude"])
            ?? Self.decodedDouble(data?["lng"])
            ?? Self.decodedDouble(data?["lon"])

        guard let name, let latitude, let longitude else {
            return nil
        }

        let neighborhood = Self.decodedString(data?["neighborhood"])
            ?? Self.decodedString(data?["neighbourhood"])
            ?? Self.decodedString(data?["district"])
            ?? Self.decodedString(data?["borough"])
            ?? Self.decodedString(data?["subregion"])
            ?? Self.decodedString(data?["area"])

        let subregion = Self.decodedString(data?["subregion"])
            ?? Self.decodedString(data?["neighbourhood"])
            ?? Self.decodedString(data?["district"])

        return FirebasePOIRecord(
            id: id,
            name: name,
            category: category,
            latitude: latitude,
            longitude: longitude,
            neighborhood: neighborhood,
            subregion: subregion,
            city: Self.decodedString(data?["city"]),
            country: Self.decodedString(data?["country"]),
            geohash: Self.decodedString(data?["geohash"]),
            updatedAt: Self.decodedDouble(data?["updatedAt"]) ?? Date().timeIntervalSince1970
        )
    }

    private func poiCollections() -> [CollectionReference] {
        [db.collection("pois"), db.collection("osm_places")]
    }

    private func prefixSearchPOIs(field: String, query: String, limit: Int) async throws -> [FirebasePOIRecord] {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else { return [] }

        var results: [FirebasePOIRecord] = []
        var seen = Set<String>()

        let candidates = [
            cleanedQuery,
            cleanedQuery.lowercased(),
            cleanedQuery.capitalized
        ]

        for candidate in candidates {
            guard results.count < limit else { break }
            let end = candidate + "\u{f8ff}"
            for collectionRef in poiCollections() {
                guard results.count < limit else { break }
                do {
                    let snapshot = try await collectionRef
                        .order(by: field)
                        .start(at: [candidate])
                        .end(at: [end])
                        .limit(to: max(1, limit))
                        .getDocuments()

                    for document in snapshot.documents {
                        guard let poi = decodePOI(from: document) else { continue }
                        let key = "\(poi.id)|\(poi.latitude)|\(poi.longitude)"
                        guard !seen.contains(key) else { continue }
                        seen.insert(key)
                        results.append(poi)
                    }
                } catch {
                    continue
                }
            }
        }

        return results
    }

    private func searchTextFieldPOIs(query: String, limit: Int) async throws -> [FirebasePOIRecord] {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else { return [] }

        let normalizedQuery = Self.normalizeSearchText(cleanedQuery)
        let tokens = normalizedQuery.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }

        var combined: [FirebasePOIRecord] = []
        var seen = Set<String>()

        for collectionRef in poiCollections() {
            do {
                let snapshot = try await collectionRef
                    .limit(to: max(200, limit * 8))
                    .getDocuments()

                for document in snapshot.documents {
                    guard let poi = decodePOI(from: document) else { continue }
                    let key = "\(poi.id)|\(poi.latitude)|\(poi.longitude)"
                    guard !seen.contains(key) else { continue }

                    let searchableText = "\(poi.name) \(poi.category) \(poi.city ?? "") \(poi.country ?? "")"
                        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                        .lowercased()

                    if tokens.allSatisfy({ token in searchableText.contains(token) }) {
                        seen.insert(key)
                        combined.append(poi)
                    }
                }
            } catch {
                continue
            }
        }

        return combined
    }

    public static func makeStableDeviceUserID(storageKey: String = "spot_device_user_id") -> String {
        if let existing = UserDefaults.standard.string(forKey: storageKey), !existing.isEmpty {
            return existing
        }

        let generated = "device_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        UserDefaults.standard.set(generated, forKey: storageKey)
        return generated
    }

    public static func isDeviceFallbackUserID(_ userID: String) -> Bool {
        let cleaned = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }

        let stable = makeStableDeviceUserID().trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned == stable {
            return true
        }

        return cleaned.hasPrefix("device_") && cleaned.count > "device_".count
    }

    public func savePOIs(_ pois: [FirebasePOIRecord]) async throws {
        let batch = db.batch()
        for poi in pois {
            let safeID = Self.sanitizeFirestoreDocumentID(poi.id)
            let ref = db.collection("pois").document(safeID)
            let payload: [String: Any] = [
                "id": safeID,
                "sourceID": poi.id,
                "name": poi.name,
                "category": poi.category,
                "latitude": poi.latitude,
                "longitude": poi.longitude,
                "city": poi.city ?? "",
                "country": poi.country ?? "",
                "geohash": poi.geohash ?? "",
                "updatedAt": poi.updatedAt
            ]
            batch.setData(payload, forDocument: ref)
        }
        try await batch.commit()
    }

    public func fetchNearbyPOIs(limit: Int = 30) async throws -> [FirebasePOIRecord] {
        var merged: [FirebasePOIRecord] = []
        var seen = Set<String>()

        for collectionRef in poiCollections() {
            let snapshot = try await collectionRef
                .limit(to: limit)
                .getDocuments()

            for document in snapshot.documents {
                guard let poi = decodePOI(from: document) else { continue }
                let key = "\(poi.id)|\(poi.latitude)|\(poi.longitude)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                merged.append(poi)
            }
        }

        return merged
    }

    public func fetchNearbyPOIs(around center: CLLocationCoordinate2D, limit: Int = 30, scanLimit: Int = 1600) async throws -> [FirebasePOIRecord] {
        let safeLimit = max(1, limit)
        let safeScanLimit = max(safeLimit, scanLimit)
        let pageSize = min(300, max(80, safeLimit * 4))
        var scanned = 0
        var lastDocument: [DocumentSnapshot?] = [nil, nil]
        var buffer: [FirebasePOIRecord] = []
        var seen = Set<String>()

        while scanned < safeScanLimit {
            var advancedACollection = false

            for (index, collectionRef) in poiCollections().enumerated() {
                var queryRef = collectionRef.limit(to: pageSize)
                if let lastDoc = lastDocument[index] {
                    queryRef = queryRef.start(afterDocument: lastDoc)
                }

                let snapshot = try await queryRef.getDocuments()
                if snapshot.documents.isEmpty {
                    continue
                }

                advancedACollection = true
                for document in snapshot.documents {
                    guard let poi = decodePOI(from: document) else { continue }
                    let key = "\(poi.id)|\(poi.latitude)|\(poi.longitude)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    buffer.append(poi)
                }
                lastDocument[index] = snapshot.documents.last
                scanned += snapshot.documents.count
            }

            if !advancedACollection {
                break
            }

            if buffer.count >= safeLimit * 8 {
                break
            }
        }

        return buffer
            .sorted { lhs, rhs in
                let lhsDistance = Self.milesDistance(
                    from: center,
                    to: CLLocationCoordinate2D(latitude: lhs.latitude, longitude: lhs.longitude)
                )
                let rhsDistance = Self.milesDistance(
                    from: center,
                    to: CLLocationCoordinate2D(latitude: rhs.latitude, longitude: rhs.longitude)
                )
                if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(safeLimit)
            .map { $0 }
    }

    public func createPost(_ post: FirebasePostPayload) async throws {
        let payload = postPayloadDictionary(post)
        try await db.collection("posts").document(post.id).setData(payload)
    }

    public func submitPostWithModeration(_ post: FirebasePostPayload) async throws -> FirebaseModeratedPostResult {
        let callable = Functions.functions().httpsCallable("submitPostWithModeration")
        let result = try await callable.call([
            "post": postPayloadDictionary(post)
        ])

        guard let data = result.data as? [String: Any] else {
            print("Spot submitPostWithModeration: Invalid payload - result.data is not a dictionary")
            print("Spot submitPostWithModeration: result.data type = \(type(of: result.data))")
            print("Spot submitPostWithModeration: result.data = \(result.data)")
            throw FirebaseSpotError.invalidPayload
        }

        print("Spot submitPostWithModeration: Raw response data = \(data)")

        let status = (data["status"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "review_required"
        let message = (data["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? ((data["message"] as? String) ?? "")
            : "This post requires moderation review before it can be posted."
        let approved = data["approved"] as? Bool ?? (status == "approved")
        let posted = data["posted"] as? Bool ?? false
        let reasonCodes = data["reasonCodes"] as? [String] ?? []
        let postID = (data["postID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        var scores: [String: Double] = [:]
        if let rawScores = data["scores"] as? [String: Any] {
            for (key, value) in rawScores {
                if let asDouble = value as? Double {
                    scores[key] = asDouble
                } else if let asInt = value as? Int {
                    scores[key] = Double(asInt)
                }
            }
        }

        let result_obj = FirebaseModeratedPostResult(
            approved: approved,
            posted: posted,
            status: status,
            message: message,
            reasonCodes: reasonCodes,
            scores: scores,
            postID: postID?.isEmpty == true ? nil : postID
        )
        
        print("Spot submitPostWithModeration: Parsed result = approved:\(result_obj.approved) posted:\(result_obj.posted) status:\(result_obj.status) postID:\(result_obj.postID ?? "nil")")
        
        return result_obj
    }

    private func postPayloadDictionary(_ post: FirebasePostPayload) -> [String: Any] {
        [
            "id": post.id,
            "authorID": post.authorID,
            "authorUsername": post.authorUsername,
            "authorDisplayName": post.authorDisplayName,
            "authorProfilePhotoURL": post.authorProfilePhotoURL ?? "",
            "contentType": post.contentType,
            "title": post.title ?? "",
            "body": post.body ?? "",
            "sourceURL": post.sourceURL ?? "",
            "mediaURLs": post.mediaURLs,
            "pollOptions": post.pollOptions,
            "pollVotes": post.pollVotes,
            "accentHex": post.accentHex,
            "locationName": post.locationName,
            "feedInsertionIndex": post.feedInsertionIndex,
            "postedInLocations": post.postedInLocations,
            "poiID": post.poiID ?? "",
            "latitude": post.latitude,
            "longitude": post.longitude,
            "city": post.city ?? "",
            "country": post.country ?? "",
            "geohash": post.geohash ?? "",
            "createdAt": post.createdAt,
            "updatedAt": post.updatedAt,
            "isVideo": post.isVideo,
            "visibilityScope": post.visibilityScope,
            "tags": post.tags,
            "likesCount": post.likesCount,
            "commentsCount": post.commentsCount,
            "viewCount": post.viewCount,
            "totalViewDurationSeconds": post.totalViewDurationSeconds,
            "savedCount": post.savedCount,
            "shareCount": post.shareCount,
            "score": post.score
        ]
    }

    public func setAdminPinState(postID: String, realm: String?, pinnedAt: TimeInterval?) async throws {
        let trimmedPostID = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPostID.isEmpty else {
            throw FirebaseSpotError.invalidPayload
        }

        let realmTagPrefix = "spot:admin-pin:realm:"
        let pinnedAtTagPrefix = "spot:admin-pin:at:"
        let postRef = db.collection("posts").document(trimmedPostID)

        let updated = try await db.runTransaction { transaction, errorPointer in
            do {
                let existing = try transaction.getDocument(postRef)
                guard existing.exists else { return false }

                let data = existing.data() ?? [:]
                var tags = (data["tags"] as? [String] ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                tags.removeAll { tag in
                    tag.hasPrefix(realmTagPrefix) || tag.hasPrefix(pinnedAtTagPrefix)
                }

                if let realm {
                    let cleanedRealm = realm.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanedRealm.isEmpty {
                        tags.append("\(realmTagPrefix)\(cleanedRealm)")
                        let resolvedPinnedAt = pinnedAt ?? Date().timeIntervalSince1970
                        tags.append("\(pinnedAtTagPrefix)\(resolvedPinnedAt)")
                    }
                }

                var seenTags = Set<String>()
                let dedupedTags = tags.filter { seenTags.insert($0).inserted }

                transaction.updateData([
                    "tags": dedupedTags,
                    "updatedAt": Date().timeIntervalSince1970
                ], forDocument: postRef)
                return true
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }

        guard updated as? Bool == true else {
            throw FirebaseSpotError.writeFailed
        }
    }

    public func fetchPostsForUser(userID: String, limit: Int = 200) async throws -> [FirebasePostPayload] {
        let documents: QuerySnapshot
        do {
            documents = try await db.collection("posts")
                .whereField("authorID", isEqualTo: userID)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
                .getDocuments()
        } catch {
            documents = try await db.collection("posts")
                .whereField("authorID", isEqualTo: userID)
                .limit(to: limit)
                .getDocuments()
        }

        return documents.documents.compactMap { decodePostPayload(from: $0) }
        .sorted { $0.createdAt > $1.createdAt }
    }

    public func deletePost(postID: String, authorID: String, adminDeleteCode: String? = nil) async throws {
        let trimmedPostID = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPostID.isEmpty else { return }

        let trimmedAuthorID = authorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAuthorID.isEmpty else { return }

        let callable = Functions.functions().httpsCallable("deletePost")
        var payload: [String: Any] = [
            "postID": trimmedPostID,
            "authorID": trimmedAuthorID
        ]

        let trimmedAdminDeleteCode = (adminDeleteCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAdminDeleteCode.isEmpty {
            payload["adminDeleteCode"] = trimmedAdminDeleteCode
        }

        let result = try await callable.call(payload)
        
        guard let data = result.data as? [String: Any], let deleted = data["deleted"] as? Bool, deleted else {
            throw NSError(domain: "FirebaseSpotService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to delete post"])
        }
    }

    public func deletePostsForUser(userID: String) async throws {
        let snapshot = try await db.collection("posts")
            .whereField("authorID", isEqualTo: userID)
            .getDocuments()

        for document in snapshot.documents {
            try await db.collection("posts").document(document.documentID).delete()
        }

        let profileRef = db.collection("users").document(userID)
        try await profileRef.updateData([
            "postedPostIDs": [],
            "updatedAt": Date().timeIntervalSince1970
        ])
    }

    public func deleteAllPosts() async throws {
        let functions = Functions.functions()
        let callable = functions.httpsCallable("deleteAllPlatformPosts")
        _ = try await callable.call(["requestedBy": "ios-app"])
    }

    public func fetchPosts(near latitude: Double, longitude: Double, radiusMeters: Double, limit: Int) async throws -> [FirebasePostPayload] {
        let documents: QuerySnapshot
        do {
            documents = try await db.collection("posts")
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
                .getDocuments()
        } catch {
            documents = try await db.collection("posts")
                .limit(to: limit)
                .getDocuments()
        }

        return documents.documents.compactMap { decodePostPayload(from: $0) }
    }

    public func fetchVideoPosts(near latitude: Double, longitude: Double, radiusMeters: Double, limit: Int) async throws -> [FirebasePostPayload] {
        let posts = try await fetchPosts(near: latitude, longitude: longitude, radiusMeters: radiusMeters, limit: limit)
        return posts.filter { $0.isVideo }
    }

    @discardableResult
    public func listenToRecentPosts(
        limit: Int = 500,
        onUpdate: @escaping ([FirebasePostPayload]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        let safeLimit = max(1, limit)
        let query = db.collection("posts")
            .order(by: "createdAt", descending: true)
            .limit(to: safeLimit)

        return query.addSnapshotListener { snapshot, error in
            if let error {
                onError(error)
                return
            }

            guard let snapshot else {
                return
            }

            let decoded = snapshot.documents
                .compactMap { self.decodePostPayload(from: $0) }
                .sorted { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt {
                        return lhs.createdAt > rhs.createdAt
                    }
                    return lhs.id > rhs.id
                }
            onUpdate(decoded)
        }
    }

    public func updatePostEngagement(postID: String, likesCount: Int? = nil, commentsCount: Int? = nil, viewCount: Int? = nil, totalViewDurationSeconds: Int? = nil, savedCount: Int? = nil, shareCount: Int? = nil) async throws {
        // Keep engagement growth available for signed-out sessions.
        // If there is no active Firebase auth user, establish an anonymous session first.
        if Auth.auth().currentUser == nil {
            _ = try await signInAnonymously()
        }

        let postRef = try await resolvedPostReference(for: postID)
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let existing = try transaction.getDocument(postRef)
                guard existing.exists else { return nil }

                let data = existing.data() ?? [:]
                let existingLikes = max(0, data["likesCount"] as? Int ?? 0)
                let existingComments = max(0, data["commentsCount"] as? Int ?? 0)
                let existingViews = max(0, data["viewCount"] as? Int ?? 0)
                let existingViewDuration = max(0, data["totalViewDurationSeconds"] as? Int ?? 0)
                let existingSaves = max(0, data["savedCount"] as? Int ?? 0)
                let existingShares = max(0, data["shareCount"] as? Int ?? 0)
                let existingScore = max(
                    Self.firestoreNumericDouble(data["score"]),
                    Self.firestoreNumericDouble(data["engagementScore"])
                )
                let locationNames = (data["postedInLocations"] as? [String] ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
                let locationBreadth = max(1, Set(locationNames).count)
                let isBoosted = (data["tags"] as? [String] ?? []).contains("spot:boosted")

                // Multiple feed surfaces may report engagement for the same post concurrently.
                // Use monotonic merges so stale/lower payloads never reduce aggregate counts.
                let resolvedLikes = max(existingLikes, max(0, likesCount ?? existingLikes))
                let resolvedComments = max(existingComments, max(0, commentsCount ?? existingComments))
                let resolvedViews = max(existingViews, max(0, viewCount ?? existingViews))
                let resolvedViewDuration = max(existingViewDuration, max(0, totalViewDurationSeconds ?? existingViewDuration))
                let resolvedSaves = max(existingSaves, max(0, savedCount ?? existingSaves))
                let resolvedShares = max(existingShares, max(0, shareCount ?? existingShares))

                let computedScore = Self.engagementScore(
                    views: resolvedViews,
                    totalViewDurationSeconds: resolvedViewDuration,
                    saves: resolvedSaves,
                    likes: resolvedLikes,
                    comments: resolvedComments,
                    shares: resolvedShares,
                    locationBreadth: locationBreadth,
                    isBoosted: isBoosted
                )
                let resolvedScore = max(existingScore, computedScore)

                transaction.updateData([
                    "likesCount": resolvedLikes,
                    "commentsCount": resolvedComments,
                    "viewCount": resolvedViews,
                    "totalViewDurationSeconds": resolvedViewDuration,
                    "savedCount": resolvedSaves,
                    "shareCount": resolvedShares,
                    "score": resolvedScore,
                    "engagementScore": resolvedScore,
                    "updatedAt": Date().timeIntervalSince1970
                ], forDocument: postRef)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    private static func pollVoteSelections(from raw: Any?) -> [String: Int] {
        guard let dictionary = raw as? [String: Any] else { return [:] }
        var resolved: [String: Int] = [:]

        for (key, value) in dictionary {
            let cleanedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedKey.isEmpty else { continue }

            if let intValue = value as? Int {
                resolved[cleanedKey] = intValue
            } else if let numberValue = value as? NSNumber {
                resolved[cleanedKey] = numberValue.intValue
            } else if let stringValue = value as? String, let intValue = Int(stringValue) {
                resolved[cleanedKey] = intValue
            }
        }

        return resolved
    }

    public func registerPollVote(postID: String, optionIndex: Int) async throws -> PollVoteResult {
        let cleanedPostID = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPostID.isEmpty, optionIndex >= 0, optionIndex < 2 else {
            throw FirebaseSpotError.invalidPayload
        }

        guard let currentUser = Auth.auth().currentUser else {
            throw FirebaseSpotError.userNotAuthenticated
        }
        let currentUserID = currentUser.uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentUserID.isEmpty else {
            throw FirebaseSpotError.userNotAuthenticated
        }

        let postRef = try await resolvedPostReference(for: cleanedPostID)

        let transactionResult = try await db.runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(postRef)
                guard snapshot.exists else {
                    throw FirebaseSpotError.readFailed
                }

                let storedVotes = snapshot.data()?["pollVotes"] as? [Int] ?? []
                var votes = Array(storedVotes.prefix(2))
                if votes.count < 2 {
                    votes.append(contentsOf: Array(repeating: 0, count: 2 - votes.count))
                }

                var voteSelections = Self.pollVoteSelections(from: snapshot.data()?["pollVoteSelectionsByUser"])
                if let existingSelection = voteSelections[currentUserID], existingSelection >= 0, existingSelection < votes.count {
                    return PollVoteResult(
                        votes: votes,
                        selectedIndex: existingSelection,
                        wasRecorded: false
                    )
                }

                let currentValue = max(0, votes[optionIndex])
                votes[optionIndex] = currentValue == Int.max ? Int.max : currentValue + 1
                voteSelections[currentUserID] = optionIndex

                transaction.updateData([
                    "pollVotes": votes,
                    "pollVoteSelectionsByUser": voteSelections,
                    "updatedAt": Date().timeIntervalSince1970
                ], forDocument: postRef)

                return PollVoteResult(
                    votes: votes,
                    selectedIndex: optionIndex,
                    wasRecorded: true
                )
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }

        guard let resolvedResult = transactionResult as? PollVoteResult, resolvedResult.votes.count >= 2 else {
            throw FirebaseSpotError.writeFailed
        }

        return PollVoteResult(
            votes: Array(resolvedResult.votes.prefix(2)),
            selectedIndex: resolvedResult.selectedIndex,
            wasRecorded: resolvedResult.wasRecorded
        )
    }

    public func updateAuthorProfilePhotoForPosts(authorID: String, photoURL: String?) async throws {
        let cleanedAuthorID = authorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedAuthorID.isEmpty else { return }

        let normalizedURL = (photoURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedAt = Date().timeIntervalSince1970
        var lastDocument: DocumentSnapshot?

        repeat {
            var query = db.collection("posts")
                .whereField("authorID", isEqualTo: cleanedAuthorID)
                .order(by: "createdAt", descending: true)
                .limit(to: 200)

            if let lastDocument {
                query = query.start(afterDocument: lastDocument)
            }

            let snapshot = try await query.getDocuments()
            guard !snapshot.documents.isEmpty else { break }

            var batch = db.batch()
            var writeCount = 0

            for document in snapshot.documents {
                let data = document.data()
                let tags = data["tags"] as? [String] ?? []
                let normalizedAuthorUsername = Self.normalizeUsername(data["authorUsername"] as? String ?? "")
                let isAnonymousPost = tags.contains("spot:anonymous") || normalizedAuthorUsername == "anonymous"
                if isAnonymousPost {
                    continue
                }

                batch.updateData([
                    "authorProfilePhotoURL": normalizedURL,
                    "updatedAt": updatedAt
                ], forDocument: document.reference)
                writeCount += 1

                if writeCount == 450 {
                    try await batch.commit()
                    batch = db.batch()
                    writeCount = 0
                }
            }

            if writeCount > 0 {
                try await batch.commit()
            }

            lastDocument = snapshot.documents.last
        } while lastDocument != nil
    }

    public func updateAuthorDisplayNameForPosts(authorID: String, displayName: String) async throws {
        let cleanedAuthorID = authorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedAuthorID.isEmpty else { return }

        let cleanedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedDisplayName.isEmpty else { return }

        let updatedAt = Date().timeIntervalSince1970
        var lastDocument: DocumentSnapshot?

        repeat {
            var query = db.collection("posts")
                .whereField("authorID", isEqualTo: cleanedAuthorID)
                .order(by: "createdAt", descending: true)
                .limit(to: 200)

            if let lastDocument {
                query = query.start(afterDocument: lastDocument)
            }

            let snapshot = try await query.getDocuments()
            guard !snapshot.documents.isEmpty else { break }

            var batch = db.batch()
            var writeCount = 0

            for document in snapshot.documents {
                let data = document.data()
                let tags = data["tags"] as? [String] ?? []
                let normalizedAuthorUsername = Self.normalizeUsername(data["authorUsername"] as? String ?? "")
                let isAnonymousPost = tags.contains("spot:anonymous") || normalizedAuthorUsername == "anonymous"
                if isAnonymousPost {
                    continue
                }

                batch.updateData([
                    "authorDisplayName": cleanedDisplayName,
                    "updatedAt": updatedAt
                ], forDocument: document.reference)
                writeCount += 1

                if writeCount == 450 {
                    try await batch.commit()
                    batch = db.batch()
                    writeCount = 0
                }
            }

            if writeCount > 0 {
                try await batch.commit()
            }

            lastDocument = snapshot.documents.last
        } while lastDocument != nil
    }

    public func updateAuthorAgeForPosts(authorID: String, age: String?) async throws {
        let cleanedAuthorID = authorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedAuthorID.isEmpty else { return }

        let cleanedAge = age?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ageTagPrefix = "spot:age:"
        let updatedAt = Date().timeIntervalSince1970
        var lastDocument: DocumentSnapshot?

        repeat {
            var query = db.collection("posts")
                .whereField("authorID", isEqualTo: cleanedAuthorID)
                .order(by: "createdAt", descending: true)
                .limit(to: 200)

            if let lastDocument {
                query = query.start(afterDocument: lastDocument)
            }

            let snapshot = try await query.getDocuments()
            guard !snapshot.documents.isEmpty else { break }

            var batch = db.batch()
            var writeCount = 0

            for document in snapshot.documents {
                let data = document.data()
                var tags = data["tags"] as? [String] ?? []
                let normalizedAuthorUsername = Self.normalizeUsername(data["authorUsername"] as? String ?? "")
                let isAnonymousPost = tags.contains("spot:anonymous") || normalizedAuthorUsername == "anonymous"
                if isAnonymousPost {
                    continue
                }

                // Strip any existing spot:age: tag
                tags.removeAll(where: { $0.hasPrefix(ageTagPrefix) })

                // Add new age tag if age is non-empty
                if !cleanedAge.isEmpty {
                    tags.append("\(ageTagPrefix)\(cleanedAge)")
                }

                batch.updateData([
                    "tags": tags,
                    "updatedAt": updatedAt
                ], forDocument: document.reference)
                writeCount += 1

                if writeCount == 450 {
                    try await batch.commit()
                    batch = db.batch()
                    writeCount = 0
                }
            }

            if writeCount > 0 {
                try await batch.commit()
            }

            lastDocument = snapshot.documents.last
        } while lastDocument != nil
    }

    public func updateAuthorPositionForPosts(authorID: String, position: String?) async throws {
        let cleanedAuthorID = authorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedAuthorID.isEmpty else { return }

        let cleanedPosition = position?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let positionTagPrefix = "spot:position:"
        let updatedAt = Date().timeIntervalSince1970
        var lastDocument: DocumentSnapshot?

        repeat {
            var query = db.collection("posts")
                .whereField("authorID", isEqualTo: cleanedAuthorID)
                .order(by: "createdAt", descending: true)
                .limit(to: 200)

            if let lastDocument {
                query = query.start(afterDocument: lastDocument)
            }

            let snapshot = try await query.getDocuments()
            guard !snapshot.documents.isEmpty else { break }

            var batch = db.batch()
            var writeCount = 0

            for document in snapshot.documents {
                let data = document.data()
                var tags = data["tags"] as? [String] ?? []
                let normalizedAuthorUsername = Self.normalizeUsername(data["authorUsername"] as? String ?? "")
                let isAnonymousPost = tags.contains("spot:anonymous") || normalizedAuthorUsername == "anonymous"
                if isAnonymousPost {
                    continue
                }

                // Strip any existing spot:position: tag
                tags.removeAll(where: { $0.hasPrefix(positionTagPrefix) })

                // Add new position tag if position is non-empty
                if !cleanedPosition.isEmpty {
                    tags.append("\(positionTagPrefix)\(cleanedPosition)")
                }

                batch.updateData([
                    "tags": tags,
                    "updatedAt": updatedAt
                ], forDocument: document.reference)
                writeCount += 1

                if writeCount == 450 {
                    try await batch.commit()
                    batch = db.batch()
                    writeCount = 0
                }
            }

            if writeCount > 0 {
                try await batch.commit()
            }

            lastDocument = snapshot.documents.last
        } while lastDocument != nil
    }

    public static func normalizeUsername(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutAt = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        let lowered = withoutAt.lowercased()
        let allowed = lowered.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
        return String(String(allowed).prefix(15))
    }

    private static func hasBlockedIdentityTerm(_ value: String) -> Bool {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return false }

        if lowered == "tiding" {
            return false
        }

        return lowered.contains("tiding") || lowered.contains("tidings")
    }

    private static func hasBlockedUsernameBrandTerm(_ rawUsername: String) -> Bool {
        let cleaned = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutAt = cleaned.hasPrefix("@") ? String(cleaned.dropFirst()) : cleaned
        guard !withoutAt.isEmpty else { return false }

        let normalized = withoutAt.lowercased()

        // Only the exact username "tiding" is allowed.
        if normalized == "tiding" {
            return false
        }

        return normalized.hasPrefix("tiding")
    }

    public static func isAllowedDisplayName(_ value: String, reservedAgainst: String? = nil) -> Bool {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }

        let lowered = cleaned.lowercased()
        if let reserved = reservedAgainst?.trimmingCharacters(in: .whitespacesAndNewlines), !reserved.isEmpty {
            if lowered == reserved.lowercased() {
                return false
            }
        }

        return !hasBlockedIdentityTerm(lowered)
    }

    public static func isAllowedUsername(_ username: String, reservedAgainst: String? = nil) -> Bool {
        let normalized = normalizeUsername(username)
        guard !normalized.isEmpty else { return false }
        guard normalized.count >= 3, normalized.count <= 15 else { return false }

        let range = normalized.range(of: "^[a-z0-9._]+$", options: .regularExpression)
        guard range != nil && range == normalized.startIndex..<normalized.endIndex else { return false }

        if let reserved = reservedAgainst?.trimmingCharacters(in: .whitespacesAndNewlines), !reserved.isEmpty {
            let normalizedReserved = normalizeUsername(reserved)
            if !normalizedReserved.isEmpty && normalized == normalizedReserved {
                return true
            }
        }

        return !hasBlockedUsernameBrandTerm(username)
    }

    public static func normalizedOptionalString(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func firestoreNumericDouble(_ value: Any?) -> Double {
        if let doubleValue = value as? Double {
            return doubleValue
        }
        if let intValue = value as? Int {
            return Double(intValue)
        }
        if let numberValue = value as? NSNumber {
            return numberValue.doubleValue
        }
        return 0
    }

    private static func firestoreNumericInt(_ value: Any?) -> Int {
        if let intValue = value as? Int {
            return intValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.intValue
        }
        if let doubleValue = value as? Double {
            return Int(doubleValue)
        }
        if let stringValue = value as? String,
           let intValue = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return intValue
        }
        return 0
    }

    public static func engagementScore(
        views: Int,
        totalViewDurationSeconds: Int,
        saves: Int,
        likes: Int,
        comments: Int,
        shares: Int,
        viewProgress: Double = 0,
        locationBreadth: Int = 1,
        isBoosted: Bool = false
    ) -> Double {
        let safeViews = max(0, views)
        let safeSaves = max(0, saves)
        let safeLikes = max(0, likes)
        let safeComments = max(0, comments)
        let safeShares = max(0, shares)
        let safeLocationBreadth = max(1, locationBreadth)
        let safeViewProgress = min(max(viewProgress, 0), 1)
        let safeTotalViewDurationSeconds = max(0, totalViewDurationSeconds)
        let effectiveViews = Double(safeViews) + safeViewProgress

        let viewPoints = effectiveViews * (0.42 / 3.0)
        // Keep long watch sessions climbing even when it's the same viewer on one post.
        let dwellPoints = Double(safeTotalViewDurationSeconds) * 0.009
        let savePoints = Double(safeSaves) * (0.75 / 3.0)
        let sharePoints = Double(safeShares) * (1.10 / 3.0)
        let likePoints = Double(safeLikes) * 0.10
        let commentPoints = Double(safeComments) * 0.18

        let baseScore = viewPoints + dwellPoints + savePoints + sharePoints + likePoints + commentPoints
        let viewMomentumMultiplier = 1.0 + min(0.45, log10(Double(safeViews) + 1.0) * 0.15)
        let locationBreadthMultiplier = 1.0 + min(0.60, Double(max(0, safeLocationBreadth - 1)) * 0.12)
        let boostMultiplier = isBoosted ? 1.18 : 1.0
        let qualityFactor: Double = {
            guard safeViews > 0 else { return 1.0 }
            let avgWatchSeconds = Double(safeTotalViewDurationSeconds) / Double(safeViews)
            // Small quality nudge for stickier views without dominating growth.
            return 1.0 + min(0.10, max(0.0, avgWatchSeconds - 4.0) * 0.008)
        }()

        return baseScore * viewMomentumMultiplier * locationBreadthMultiplier * boostMultiplier * qualityFactor
    }

    public static func monotonicEngagementScore(
        previousScore: Double,
        views: Int,
        totalViewDurationSeconds: Int,
        saves: Int,
        likes: Int,
        comments: Int,
        shares: Int,
        viewProgress: Double = 0,
        locationBreadth: Int = 1,
        isBoosted: Bool = false
    ) -> Double {
        let computed = engagementScore(
            views: views,
            totalViewDurationSeconds: totalViewDurationSeconds,
            saves: saves,
            likes: likes,
            comments: comments,
            shares: shares,
            viewProgress: viewProgress,
            locationBreadth: locationBreadth,
            isBoosted: isBoosted
        )
        return max(previousScore, computed)
    }

    private func decodePostPayload(from document: DocumentSnapshot) -> FirebasePostPayload? {
        let data = document.data() ?? [:]
        let id = Self.canonicalPostDocumentID(fieldID: data["id"] as? String, documentID: document.documentID)
        let authorID = (data["authorID"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let contentType = (data["contentType"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !id.isEmpty, !authorID.isEmpty, !contentType.isEmpty else {
            return nil
        }

        let locationName = Self.normalizedOptionalString(data["locationName"] as? String)
            ?? Self.normalizedOptionalString(data["location"] as? String)
            ?? Self.normalizedOptionalString(data["city"] as? String)
            ?? "Metric"

        let currentUserID = Auth.auth().currentUser?.uid.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let voteSelections = Self.pollVoteSelections(from: data["pollVoteSelectionsByUser"])
        let currentUserPollSelection: Int?
        if let selection = voteSelections[currentUserID], selection >= 0, selection < 2 {
            currentUserPollSelection = selection
        } else {
            currentUserPollSelection = nil
        }

        return FirebasePostPayload(
            id: id,
            authorID: authorID,
            authorUsername: data["authorUsername"] as? String ?? "",
            authorDisplayName: data["authorDisplayName"] as? String ?? "",
            authorProfilePhotoURL: Self.normalizedOptionalString(data["authorProfilePhotoURL"] as? String),
            contentType: contentType,
            title: data["title"] as? String,
            body: data["body"] as? String,
            sourceURL: Self.normalizedOptionalString(data["sourceURL"] as? String),
            mediaURLs: data["mediaURLs"] as? [String] ?? [],
            pollOptions: data["pollOptions"] as? [String] ?? [],
            pollVotes: data["pollVotes"] as? [Int] ?? [],
            currentUserPollSelection: currentUserPollSelection,
            accentHex: data["accentHex"] as? String ?? "#DCE7FF",
            locationName: locationName,
            feedInsertionIndex: Self.firestoreNumericInt(data["feedInsertionIndex"]),
            postedInLocations: data["postedInLocations"] as? [String] ?? [],
            poiID: data["poiID"] as? String,
            latitude: Self.firestoreNumericDouble(data["latitude"]),
            longitude: Self.firestoreNumericDouble(data["longitude"]),
            city: data["city"] as? String,
            country: data["country"] as? String,
            geohash: data["geohash"] as? String,
            createdAt: Self.firestoreNumericDouble(data["createdAt"]),
            updatedAt: Self.firestoreNumericDouble(data["updatedAt"]),
            isVideo: data["isVideo"] as? Bool ?? false,
            visibilityScope: data["visibilityScope"] as? String ?? "nearby",
            tags: data["tags"] as? [String] ?? [],
            likesCount: Self.firestoreNumericInt(data["likesCount"]),
            commentsCount: Self.firestoreNumericInt(data["commentsCount"]),
            viewCount: Self.firestoreNumericInt(data["viewCount"]),
            totalViewDurationSeconds: Self.firestoreNumericInt(data["totalViewDurationSeconds"]),
            savedCount: Self.firestoreNumericInt(data["savedCount"]),
            shareCount: Self.firestoreNumericInt(data["shareCount"]),
            score: max(
                Self.firestoreNumericDouble(data["score"]),
                Self.firestoreNumericDouble(data["engagementScore"])
            )
        )
    }

    public static func userSearchMatches(query: String, account: FirebaseUserAccountRecord) -> Bool {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else { return true }

        let normalizedQuery = normalizeUsername(cleanedQuery).lowercased()
        let username = normalizeUsername(account.username).lowercased()
        let displayName = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fullSignature = "\(account.username) \(account.displayName)".lowercased()

        return normalizedQuery.isEmpty
            ? true
            : username.contains(normalizedQuery)
                || displayName.contains(normalizedQuery)
                || fullSignature.contains(normalizedQuery)
    }

    public static func poiSearchMatches(query: String, poi: FirebasePOIRecord) -> Bool {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else { return true }

        let normalizedQuery = normalizeSearchText(cleanedQuery)
        guard !normalizedQuery.isEmpty else { return true }

        let name = normalizeSearchText(poi.name)
        let category = normalizeSearchText(poi.category)
        let city = normalizeSearchText(poi.city ?? "")
        let country = normalizeSearchText(poi.country ?? "")
        let signature = normalizeSearchText("\(poi.name) \(poi.category) \(poi.city ?? "") \(poi.country ?? "")")

        if name.contains(normalizedQuery)
            || category.contains(normalizedQuery)
            || city.contains(normalizedQuery)
            || country.contains(normalizedQuery)
            || signature.contains(normalizedQuery) {
            return true
        }

        let queryTokens = normalizedQuery
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !queryTokens.isEmpty else { return true }
        return queryTokens.allSatisfy { signature.contains($0) }
    }

    public static func poiSearchScore(query: String, poi: FirebasePOIRecord) -> Double {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else { return 1 }

        let normalizedQuery = normalizeSearchText(cleanedQuery)
        guard !normalizedQuery.isEmpty else { return 1 }

        let name = normalizeSearchText(poi.name)
        let category = normalizeSearchText(poi.category)
        let city = normalizeSearchText(poi.city ?? "")
        let country = normalizeSearchText(poi.country ?? "")
        let signature = normalizeSearchText("\(poi.name) \(poi.category) \(poi.city ?? "") \(poi.country ?? "")")

        // Specific POI Boost: A non-city/macro category (like school, park, museum, restaurant, venue) gets a +1,500 point boost over generic city matches
        let isMacroCategory = category.contains("city") || category.contains("town") || category.contains("suburb") || category.contains("district") || category.contains("county") || category == "city"
        let poiPriorityBonus: Double = isMacroCategory ? 0 : 1500

        if name == normalizedQuery { return 10000 + poiPriorityBonus }
        if name.hasPrefix(normalizedQuery) { return 6000 + poiPriorityBonus }
        if name.contains(normalizedQuery) { return 4000 + poiPriorityBonus }
        if category == normalizedQuery { return 2500 + poiPriorityBonus }
        if category.hasPrefix(normalizedQuery) { return 2000 + poiPriorityBonus }
        if category.contains(normalizedQuery) { return 1500 + poiPriorityBonus }
        if city == normalizedQuery { return 820 }
        if country == normalizedQuery { return 760 }
        if city.hasPrefix(normalizedQuery) { return 560 }
        if country.hasPrefix(normalizedQuery) { return 520 }
        if city.contains(normalizedQuery) { return 370 }
        if country.contains(normalizedQuery) { return 340 }
        if signature.contains(normalizedQuery) { return 260 + poiPriorityBonus }

        let queryTokens = normalizedQuery
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !queryTokens.isEmpty else { return 0 }

        var tokenMatches = 0
        var tokenScore = 0.0
        for token in queryTokens {
            if name.hasPrefix(token) {
                tokenMatches += 1
                tokenScore += 180
            } else if name.contains(token) {
                tokenMatches += 1
                tokenScore += 140
            } else if category.contains(token) {
                tokenMatches += 1
                tokenScore += 100
            } else if city.hasPrefix(token) {
                tokenMatches += 1
                tokenScore += 50
            } else if city.contains(token) {
                tokenMatches += 1
                tokenScore += 35
            } else if country.contains(token) {
                tokenMatches += 1
                tokenScore += 20
            }
        }

        if tokenMatches == 0 { return 0 }
        if tokenMatches == queryTokens.count {
            return 210 + tokenScore + poiPriorityBonus
        }
        return tokenScore + poiPriorityBonus
    }

    public static func normalizeSearchText(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let cleaned = folded.replacingOccurrences(of: "[^a-zA-Z0-9]+", with: " ", options: .regularExpression)
        let normalizedSpaces = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return normalizedSpaces.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func isValidUsername(_ username: String) -> Bool {
        isAllowedUsername(username)
    }

    public func checkUsernameAvailability(username: String, currentUserID: String? = nil) async throws -> Bool {
        let normalized = Self.normalizeUsername(username)
        guard Self.isAllowedUsername(normalized, reservedAgainst: username) else { return false }

        let snapshot = try await db.collection("usernames").document(normalized).getDocument()
        guard snapshot.exists else {
            return true
        }

        let existingUserID = (snapshot.data()?["userID"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if existingUserID.isEmpty {
            return true
        }

        if let currentUserID = currentUserID?.trimmingCharacters(in: .whitespacesAndNewlines), !currentUserID.isEmpty {
            return existingUserID == currentUserID
        }

        let activeUID = (Auth.auth().currentUser?.uid ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !activeUID.isEmpty {
            return existingUserID == activeUID
        }

        return false
    }

    public func resolveUserID(username: String) async throws -> String? {
        let normalized = Self.normalizeUsername(username)
        guard !normalized.isEmpty else { return nil }

        let snapshot = try await db.collection("usernames").document(normalized).getDocument()
        guard snapshot.exists else { return nil }

        let userID = (snapshot.data()? ["userID"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return userID.isEmpty ? nil : userID
    }

    public func fetchUserAccount(username: String) async throws -> FirebaseUserAccountRecord? {
        guard let userID = try await resolveUserID(username: username) else {
            return nil
        }
        return try await fetchUserAccount(userID: userID)
    }

    public static func normalizedSearchTokens(_ query: String) -> [String] {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        return cleaned
            .lowercased()
            .split(whereSeparator: { character in
                !character.isLetter && !character.isNumber && character != "/" && character != "@" && character != "#"
            })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    public static func postSearchMatches(query: String, post: FirebasePostPayload) -> Bool {
        let tokens = normalizedSearchTokens(query)
        guard !tokens.isEmpty else { return true }

        let searchableText = [
            post.authorDisplayName,
            post.authorUsername,
            post.contentType,
            post.title ?? "",
            post.body ?? "",
            post.locationName,
            post.city ?? "",
            post.country ?? "",
            post.postedInLocations.joined(separator: " "),
            post.tags.joined(separator: " "),
            post.sourceURL ?? "",
            post.mediaURLs.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()

        return tokens.allSatisfy { token in
            searchableText.contains(token)
        }
    }

    public static func postSearchScore(query: String, post: FirebasePostPayload) -> Double {
        let tokens = normalizedSearchTokens(query)
        guard !tokens.isEmpty else { return 1 }

        var totalScore: Double = 0

        for token in tokens {
            let exactSearchFields = [
                post.title ?? "",
                post.body ?? "",
                post.authorDisplayName,
                post.authorUsername,
                post.locationName,
                post.city ?? "",
                post.country ?? "",
                post.contentType,
                post.tags.joined(separator: " "),
                post.postedInLocations.joined(separator: " ")
            ]

            for field in exactSearchFields {
                let lowerField = field.lowercased()
                if lowerField == token { totalScore += 80 }
                else if lowerField.hasPrefix(token) { totalScore += 35 }
                else if lowerField.contains(token) { totalScore += 15 }
            }

            if (post.title ?? "").lowercased().contains(token) { totalScore += 25 }
            if (post.body ?? "").lowercased().contains(token) { totalScore += 20 }
            if post.authorUsername.lowercased().contains(token) { totalScore += 30 }
            if post.locationName.lowercased().contains(token) { totalScore += 30 }
            if post.tags.contains(where: { $0.lowercased() == token || $0.lowercased().contains(token) }) { totalScore += 25 }
        }

        if let title = post.title?.lowercased(), title.contains(query.lowercased()) { totalScore += 30 }
        if let body = post.body?.lowercased(), body.contains(query.lowercased()) { totalScore += 25 }

        return totalScore
    }

    public func searchPosts(query: String, limit: Int = 20, center: CLLocationCoordinate2D? = nil) async throws -> [FirebasePostPayload] {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pageLimit = max(40, min(300, limit * 12))

        let snapshot = try await db.collection("posts")
            .order(by: "createdAt", descending: true)
            .limit(to: pageLimit)
            .getDocuments()

        let posts = snapshot.documents.compactMap { self.decodePostPayload(from: $0) }

        if cleanedQuery.isEmpty {
            return posts
                .sorted { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                    return lhs.id > rhs.id
                }
                .prefix(limit)
                .map { $0 }
        }

        let matches = posts.filter { Self.postSearchMatches(query: cleanedQuery, post: $0) }
            .sorted { lhs, rhs in
                let lhsScore = Self.postSearchScore(query: cleanedQuery, post: lhs)
                let rhsScore = Self.postSearchScore(query: cleanedQuery, post: rhs)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id > rhs.id
            }

        return Array(matches.prefix(limit))
    }

    public func searchUsers(query: String, limit: Int = 20) async throws -> [FirebaseUserAccountRecord] {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = try await db.collection("users")
            .limit(to: limit)
            .getDocuments()

        let accounts = snapshot.documents.compactMap { document -> FirebaseUserAccountRecord? in
            let data = document.data()
            guard let uid = data["uid"] as? String else { return nil }
            return FirebaseUserAccountRecord(
                uid: uid,
                username: data["username"] as? String ?? "@user",
                displayName: data["displayName"] as? String ?? "User",
                phoneNumber: Self.normalizedOptionalString(data["phoneNumber"] as? String),
                bio: data["bio"] as? String,
                profilePhotoURL: data["profilePhotoURL"] as? String,
                createdAt: data["createdAt"] as? TimeInterval ?? Date().timeIntervalSince1970,
                updatedAt: data["updatedAt"] as? TimeInterval ?? Date().timeIntervalSince1970,
                savedPostIDs: data["savedPostIDs"] as? [String] ?? [],
                flaggedPostIDs: data["flaggedPostIDs"] as? [String] ?? [],
                postedPostIDs: data["postedPostIDs"] as? [String] ?? [],
                areaHistory: data["areaHistory"] as? [String] ?? [],
                remainingBoosts: max(0, data["remainingBoosts"] as? Int ?? 0)
            )
        }

        if cleanedQuery.isEmpty {
            return accounts.sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
        }

        return accounts.filter { account in
            Self.userSearchMatches(query: cleanedQuery, account: account)
        }
        .sorted { lhs, rhs in
            let lhsScore = Self.userSearchScore(query: cleanedQuery, account: lhs)
            let rhsScore = Self.userSearchScore(query: cleanedQuery, account: rhs)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    public func searchPOIs(query: String, limit: Int = 20, center: CLLocationCoordinate2D? = nil) async throws -> [FirebasePOIRecord] {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeLimit = max(1, limit)

        var fastMatches: [FirebasePOIRecord] = []
        var seenFast = Set<String>()
        let fastLimit = min(max(40, safeLimit), 240)

        if !cleanedQuery.isEmpty {
            if let prefixMatches = try? await prefixSearchPOIs(field: "name", query: cleanedQuery, limit: fastLimit) {
                for poi in prefixMatches {
                    let key = "\(poi.id)|\(poi.latitude)|\(poi.longitude)"
                    guard !seenFast.contains(key) else { continue }
                    seenFast.insert(key)
                    fastMatches.append(poi)
                }
            }
            if fastMatches.count < fastLimit, let cityPrefixMatches = try? await prefixSearchPOIs(field: "city", query: cleanedQuery, limit: fastLimit) {
                for poi in cityPrefixMatches {
                    let key = "\(poi.id)|\(poi.latitude)|\(poi.longitude)"
                    guard !seenFast.contains(key) else { continue }
                    seenFast.insert(key)
                    fastMatches.append(poi)
                }
            }
            if fastMatches.count < fastLimit, let textMatches = try? await searchTextFieldPOIs(query: cleanedQuery, limit: fastLimit) {
                for poi in textMatches {
                    let key = "\(poi.id)|\(poi.latitude)|\(poi.longitude)"
                    guard !seenFast.contains(key) else { continue }
                    seenFast.insert(key)
                    fastMatches.append(poi)
                }
            }
        }

        if !fastMatches.isEmpty {
            return fastMatches
                .filter { Self.poiSearchMatches(query: cleanedQuery, poi: $0) }
                .sorted { lhs, rhs in
                    Self.poiSearchScore(query: cleanedQuery, poi: lhs) > Self.poiSearchScore(query: cleanedQuery, poi: rhs)
                }
                .prefix(safeLimit)
                .map { $0 }
        }

        let pageSize = 350
        var lastDocument: [DocumentSnapshot?] = [nil, nil]
        var allPOIs: [FirebasePOIRecord] = []
        var seen = Set<String>()

        for (index, collectionRef) in poiCollections().enumerated() {
            while true {
                var queryRef = collectionRef.limit(to: pageSize)

                if let lastDoc = lastDocument[index] {
                    queryRef = queryRef.start(afterDocument: lastDoc)
                }

                let snapshot = try await queryRef.getDocuments()
                if snapshot.documents.isEmpty {
                    break
                }

                for document in snapshot.documents {
                    guard let poi = decodePOI(from: document) else {
                        continue
                    }

                    let key = "\(poi.id)|\(poi.latitude)|\(poi.longitude)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)

                    if cleanedQuery.isEmpty {
                        allPOIs.append(poi)
                    } else if Self.poiSearchMatches(query: cleanedQuery, poi: poi) {
                        allPOIs.append(poi)
                    }
                }

                lastDocument[index] = snapshot.documents.last
                if snapshot.documents.count < pageSize {
                    break
                }
            }
        }

        var combined: [FirebasePOIRecord] = []
        var seenCombined = Set<String>()

        for poi in fastMatches + allPOIs {
            let key = "\(poi.id)|\(poi.latitude)|\(poi.longitude)"
            guard !seenCombined.contains(key) else { continue }
            seenCombined.insert(key)
            combined.append(poi)
        }

        if cleanedQuery.isEmpty {
            return combined
                .sorted { lhs, rhs in
                    lhs.updatedAt > rhs.updatedAt
                }
                .prefix(safeLimit)
                .map { $0 }
        }

        return combined
            .filter { Self.poiSearchMatches(query: cleanedQuery, poi: $0) }
            .sorted { lhs, rhs in
                let lhsScore = Self.poiSearchScore(query: cleanedQuery, poi: lhs)
                let rhsScore = Self.poiSearchScore(query: cleanedQuery, poi: rhs)
                let lhsDistance = center.map {
                    Self.milesDistance(from: $0, to: CLLocationCoordinate2D(latitude: lhs.latitude, longitude: lhs.longitude))
                } ?? 0
                let rhsDistance = center.map {
                    Self.milesDistance(from: $0, to: CLLocationCoordinate2D(latitude: rhs.latitude, longitude: rhs.longitude))
                } ?? 0
                let lhsCombined = lhsScore + max(0.0, 4000.0 - (lhsDistance * 120.0))
                let rhsCombined = rhsScore + max(0.0, 4000.0 - (rhsDistance * 120.0))
                if lhsCombined != rhsCombined { return lhsCombined > rhsCombined }
                if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(safeLimit)
            .map { $0 }
    }

    public static func userSearchScore(query: String, account: FirebaseUserAccountRecord) -> Double {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else { return 1 }

        let normalizedQuery = normalizeUsername(cleanedQuery).lowercased()
        let username = normalizeUsername(account.username).lowercased()
        let displayName = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if username == normalizedQuery { return 1000 }
        if username.hasPrefix(normalizedQuery) { return 500 }
        if displayName == normalizedQuery { return 400 }
        if displayName.hasPrefix(normalizedQuery) { return 250 }
        if username.contains(normalizedQuery) { return 200 }
        if displayName.contains(normalizedQuery) { return 150 }
        return 0
    }

    static func poiDistancePriorityScore(
        query: String,
        candidateName: String,
        nearbyPlaces: [NearbyPlace],
        userCoordinate: CLLocationCoordinate2D
    ) -> Double {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = trimmedQuery.lowercased()
        let normalizedName = candidateName.lowercased()

        let textScore: Double
        if normalizedQuery.isEmpty {
            textScore = 1
        } else if normalizedName == normalizedQuery {
            textScore = 100000
        } else if normalizedName.hasPrefix(normalizedQuery) {
            textScore = 60000
        } else if normalizedName.contains(normalizedQuery) {
            textScore = 25000
        } else {
            textScore = 0
        }

        let distanceMiles = nearbyPlaces
            .first { $0.name.caseInsensitiveCompare(candidateName) == .orderedSame }
            .map {
                Self.milesDistance(
                    from: userCoordinate,
                    to: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                )
            } ?? Double.greatestFiniteMagnitude

        let proximityScore = max(0.0, 4000.0 - (distanceMiles * 120.0))
        return textScore + proximityScore
    }

    public func reserveUsername(userID: String, username: String, previousUsername: String? = nil) async throws -> Bool {
        let normalized = Self.normalizeUsername(username)
        guard Self.isAllowedUsername(normalized, reservedAgainst: previousUsername) else { throw FirebaseSpotError.invalidUsername }

        let usernameRef = db.collection("usernames").document(normalized)
        let previousNormalized = previousUsername.flatMap { Self.normalizeUsername($0) }

        let reserved = try await db.runTransaction { transaction, errorPointer in
            do {
                let usernameDoc = try transaction.getDocument(usernameRef)
                if usernameDoc.exists {
                    let existingUserID = usernameDoc.data()?["userID"] as? String
                    if existingUserID != nil && existingUserID != userID {
                        throw FirebaseSpotError.usernameTaken
                    }
                }

                if let previousNormalized, !previousNormalized.isEmpty, previousNormalized != normalized {
                    let previousRef = self.db.collection("usernames").document(previousNormalized)
                    let previousDoc = try transaction.getDocument(previousRef)
                    let previousUserID = previousDoc.data()?["userID"] as? String
                    if previousDoc.exists && previousUserID == userID {
                        transaction.deleteDocument(previousRef)
                    }
                }

                transaction.setData([
                    "userID": userID,
                    "username": "@\(normalized)",
                    "updatedAt": Date().timeIntervalSince1970
                ], forDocument: usernameRef)
                return true
            } catch {
                let nsError = error as NSError
                errorPointer?.pointee = nsError
                return nil
            }
        }

        guard let reserved = reserved as? Bool else {
            let existingDoc = try? await usernameRef.getDocument()
            let existingUserID = (existingDoc?.data()?["userID"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if existingDoc?.exists == true && !existingUserID.isEmpty && existingUserID != userID {
                throw FirebaseSpotError.usernameTaken
            }
            try await usernameRef.setData([
                "userID": userID,
                "username": "@\(normalized)",
                "updatedAt": Date().timeIntervalSince1970
            ], merge: true)
            return true
        }

        return reserved
    }

    public static func makeUserProfileUpsertPayload(
        userID: String,
        username: String,
        displayName: String,
        bio: String?,
        photoURL: String?,
        existingData: [String: Any],
        previousUsername: String?
    ) -> [String: Any] {
        let normalizedUsername = Self.normalizeUsername(username)
        let safePhotoURL = Self.normalizedOptionalString(photoURL) ?? ""
        let existingAliases = (existingData["usernameAliases"] as? [String] ?? [])
            .map { Self.normalizeUsername($0) }
            .filter { !$0.isEmpty }
        let normalizedPrevious = Self.normalizeUsername(previousUsername ?? "")
        let mergedAliases = Array(Set(existingAliases + [normalizedUsername, normalizedPrevious].filter { !$0.isEmpty })).sorted()

        return [
            "uid": userID,
            "username": "@\(normalizedUsername)",
            "displayName": displayName,
            "bio": bio ?? "",
            "profilePhotoURL": safePhotoURL,
            "createdAt": existingData["createdAt"] as? TimeInterval ?? Date().timeIntervalSince1970,
            "updatedAt": Date().timeIntervalSince1970,
            "savedPostIDs": existingData["savedPostIDs"] as? [String] ?? [],
            "flaggedPostIDs": existingData["flaggedPostIDs"] as? [String] ?? [],
            "postedPostIDs": existingData["postedPostIDs"] as? [String] ?? [],
            "usernameAliases": mergedAliases,
            "areaHistory": existingData["areaHistory"] as? [String] ?? [],
            "followerCount": existingData["followerCount"] as? Int ?? 0,
            "followingCount": existingData["followingCount"] as? Int ?? 0,
            "remainingBoosts": max(0, existingData["remainingBoosts"] as? Int ?? 0)
        ]
    }

    public static func migratedPostUpdatePayload(
        authorID: String,
        username: String,
        displayName: String,
        photoURL: String?
    ) -> [String: Any] {
        let normalizedUsername = Self.normalizeUsername(username)
        let sanitizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalDisplayName = sanitizedDisplayName.isEmpty ? (normalizedUsername.isEmpty ? "You" : normalizedUsername.capitalized) : sanitizedDisplayName
        let authorUsername = normalizedUsername.isEmpty ? "@you" : "@\(normalizedUsername)"
        let safePhotoURL = Self.normalizedOptionalString(photoURL) ?? ""

        return [
            "authorID": authorID,
            "authorUsername": authorUsername,
            "authorDisplayName": finalDisplayName,
            "authorProfilePhotoURL": safePhotoURL,
            "updatedAt": Date().timeIntervalSince1970
        ]
    }

    public func migrateLegacyPostsForUser(
        userID: String,
        username: String,
        displayName: String,
        photoURL: String?,
        preferredLegacyAuthorIDs: [String] = []
    ) async throws {
        let cleanedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedUserID.isEmpty else { return }

        let persistedLegacyID = UserDefaults.standard.string(forKey: "spot_firebase_user_id") ?? ""
        let stableDeviceID = Self.makeStableDeviceUserID()
        let currentAuthID = (try? Auth.auth().currentUser?.uid) ?? ""
        let preferred = preferredLegacyAuthorIDs.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let legacyIDs = Array(Set((preferred + [persistedLegacyID, stableDeviceID, currentAuthID]).filter { !$0.isEmpty && $0 != cleanedUserID }))
        guard !legacyIDs.isEmpty else { return }

        let updatePayload = Self.migratedPostUpdatePayload(
            authorID: cleanedUserID,
            username: username,
            displayName: displayName,
            photoURL: photoURL
        )

        var migratedPostIDs: [String] = []
        for legacyID in legacyIDs {
            let snapshot = try await db.collection("posts")
                .whereField("authorID", isEqualTo: legacyID)
                .getDocuments()

            for document in snapshot.documents {
                let data = document.data()
                let storedID = (data["id"] as? String ?? document.documentID).trimmingCharacters(in: .whitespacesAndNewlines)
                if !storedID.isEmpty {
                    migratedPostIDs.append(storedID)
                }
                try await document.reference.setData(updatePayload, merge: true)
            }
        }

        guard !migratedPostIDs.isEmpty else { return }

        let profileRef = db.collection("users").document(cleanedUserID)
        let existing = try await profileRef.getDocument()
        let current = (existing.data()? ["postedPostIDs"] as? [String]) ?? []
        let merged = Array(Set(current + migratedPostIDs))
        try await profileRef.setData([
            "postedPostIDs": merged,
            "updatedAt": Date().timeIntervalSince1970
        ], merge: true)
    }

    public func saveUserProfile(userID: String, username: String, displayName: String, bio: String?, photoURL: String?) async throws {
        let profileRef = db.collection("users").document(userID)
        let existing = try? await profileRef.getDocument()
        let existingData = existing?.data() ?? [:]
        let previousUsername = existingData["username"] as? String
        let normalizedUsername = Self.normalizeUsername(username)
        let cleanedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard Self.isAllowedUsername(normalizedUsername, reservedAgainst: previousUsername) else {
            throw FirebaseSpotError.invalidUsername
        }

        guard Self.isAllowedDisplayName(cleanedDisplayName) else {
            throw FirebaseSpotError.invalidPayload
        }

        _ = try await reserveUsername(userID: userID, username: normalizedUsername, previousUsername: previousUsername)

        let payload = Self.makeUserProfileUpsertPayload(
            userID: userID,
            username: normalizedUsername,
            displayName: displayName,
            bio: bio,
            photoURL: photoURL,
            existingData: existingData,
            previousUsername: previousUsername
        )

        let historicalAliases = (existingData["usernameAliases"] as? [String] ?? [])

        try await profileRef.setData(payload, merge: true)
        try await updateAuthorProfilePhotoForPosts(
            authorID: userID,
            photoURL: Self.normalizedOptionalString(photoURL)
        )
        try await syncAuthorIdentityForPosts(
            authorID: userID,
            username: normalizedUsername,
            previousUsername: previousUsername,
            usernameAliases: historicalAliases,
            displayName: displayName,
            photoURL: photoURL
        )
    }

    public func syncAuthorIdentityForPosts(
        authorID: String,
        username: String,
        previousUsername: String? = nil,
        usernameAliases: [String] = [],
        displayName: String,
        photoURL: String?
    ) async throws {
        let cleanedAuthorID = authorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedAuthorID.isEmpty else { return }

        let updatePayload = Self.migratedPostUpdatePayload(
            authorID: cleanedAuthorID,
            username: username,
            displayName: displayName,
            photoURL: photoURL
        )

        let persistedLegacyID = (UserDefaults.standard.string(forKey: "spot_firebase_user_id") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stableDeviceID = Self.makeStableDeviceUserID().trimmingCharacters(in: .whitespacesAndNewlines)
        let currentAuthID = (Auth.auth().currentUser?.uid ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let authorIDsToSync = Array(Set([cleanedAuthorID, persistedLegacyID, stableDeviceID, currentAuthID].filter { !$0.isEmpty }))

        let normalizedCurrentUsername = Self.normalizeUsername(username)
        let normalizedPreviousUsername = Self.normalizeUsername(previousUsername ?? "")
        var usernamesToSync: Set<String> = []
        if !normalizedCurrentUsername.isEmpty {
            usernamesToSync.insert(normalizedCurrentUsername)
            usernamesToSync.insert("@\(normalizedCurrentUsername)")
        }
        if !normalizedPreviousUsername.isEmpty {
            usernamesToSync.insert(normalizedPreviousUsername)
            usernamesToSync.insert("@\(normalizedPreviousUsername)")
        }
        for alias in usernameAliases {
            let normalizedAlias = Self.normalizeUsername(alias)
            guard !normalizedAlias.isEmpty else { continue }
            usernamesToSync.insert(normalizedAlias)
            usernamesToSync.insert("@\(normalizedAlias)")
        }

        let normalizedAuthorIDSet = Set(authorIDsToSync.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })

        for candidateAuthorID in authorIDsToSync {
            var lastDocument: DocumentSnapshot?

            repeat {
                var query = db.collection("posts")
                    .whereField("authorID", isEqualTo: candidateAuthorID)
                    .order(by: "createdAt", descending: true)
                    .limit(to: 220)

                if let lastDocument {
                    query = query.start(afterDocument: lastDocument)
                }

                let snapshot = try await query.getDocuments()
                guard !snapshot.documents.isEmpty else { break }

                var batch = db.batch()
                var writesInBatch = 0

                for document in snapshot.documents {
                    batch.setData(updatePayload, forDocument: document.reference, merge: true)
                    writesInBatch += 1

                    if writesInBatch >= 440 {
                        try await batch.commit()
                        batch = db.batch()
                        writesInBatch = 0
                    }
                }

                if writesInBatch > 0 {
                    try await batch.commit()
                }

                lastDocument = snapshot.documents.last
            } while lastDocument != nil
        }

        for usernameCandidate in usernamesToSync {
            var lastDocument: DocumentSnapshot?

            repeat {
                var query = db.collection("posts")
                    .whereField("authorUsername", isEqualTo: usernameCandidate)
                    .order(by: "createdAt", descending: true)
                    .limit(to: 220)

                if let lastDocument {
                    query = query.start(afterDocument: lastDocument)
                }

                let snapshot = try await query.getDocuments()
                guard !snapshot.documents.isEmpty else { break }

                var batch = db.batch()
                var writesInBatch = 0

                for document in snapshot.documents {
                    let data = document.data()
                    let storedAuthorID = (data["authorID"] as? String ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    // Only migrate username-keyed legacy posts when they are unclaimed,
                    // or already owned by one of this user's known IDs.
                    if !storedAuthorID.isEmpty && !normalizedAuthorIDSet.contains(storedAuthorID) {
                        continue
                    }

                    batch.setData(updatePayload, forDocument: document.reference, merge: true)
                    writesInBatch += 1

                    if writesInBatch >= 440 {
                        try await batch.commit()
                        batch = db.batch()
                        writesInBatch = 0
                    }
                }

                if writesInBatch > 0 {
                    try await batch.commit()
                }

                lastDocument = snapshot.documents.last
            } while lastDocument != nil
        }
    }

    public func setFollowState(followerUserID: String, followedUserID: String, isFollowing: Bool) async throws {
        guard !followerUserID.isEmpty, !followedUserID.isEmpty, followerUserID != followedUserID else {
            return
        }

        let callable = Functions.functions().httpsCallable("setFollowState")
        _ = try await callable.call([
            "followerUserID": followerUserID,
            "followedUserID": followedUserID,
            "isFollowing": isFollowing
        ])
    }

    public func fetchUserFollowCounts(userID: String) async throws -> (followers: Int, following: Int) {
        let followerSnapshot = try await db.collection("follows")
            .whereField("followedUserID", isEqualTo: userID)
            .getDocuments()

        let followingSnapshot = try await db.collection("follows")
            .whereField("followerUserID", isEqualTo: userID)
            .getDocuments()

        return (followers: followerSnapshot.documents.count, following: followingSnapshot.documents.count)
    }

    public func fetchFollowedUserIDs(followerUserID: String, limit: Int = 500) async throws -> [String] {
        guard !followerUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let snapshot = try await db.collection("follows")
            .whereField("followerUserID", isEqualTo: followerUserID)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap { document in
            let followed = (document.data()["followedUserID"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return followed.isEmpty ? nil : followed
        }
    }

    public func fetchFollowerUserIDs(followedUserID: String, limit: Int = 500) async throws -> [String] {
        guard !followedUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let snapshot = try await db.collection("follows")
            .whereField("followedUserID", isEqualTo: followedUserID)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap { document in
            let follower = (document.data()["followerUserID"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return follower.isEmpty ? nil : follower
        }
    }

    private func updateFollowCounts(for userID: String) async throws {
        let cleanedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedUserID.isEmpty else { return }

        let profileRef = db.collection("users").document(cleanedUserID)
        let followerSnapshot = try await db.collection("follows")
            .whereField("followedUserID", isEqualTo: cleanedUserID)
            .getDocuments()
        let followingSnapshot = try await db.collection("follows")
            .whereField("followerUserID", isEqualTo: cleanedUserID)
            .getDocuments()

        let counts: [String: Any] = [
            "uid": cleanedUserID,
            "followerCount": followerSnapshot.documents.count,
            "followingCount": followingSnapshot.documents.count,
            "updatedAt": Date().timeIntervalSince1970
        ]

        try await profileRef.setData(counts, merge: true)
    }

    public func saveUserPostReference(userID: String, postID: String, locationName: String, contentType: String = "", feedInsertionIndex: Int = 0, createdAt: TimeInterval = Date().timeIntervalSince1970) async throws {
        let profileRef = db.collection("users").document(userID)
        let now = Date().timeIntervalSince1970

        let safeLocation = Self.sanitizeFirestoreDocumentID(locationName)
        let entryID = "post_\(postID)_\(safeLocation)_\(userID)"
        let locationKey = ContentView.cooldownKeyForLocation(locationName)
        let logRef = db.collection("users").document(userID).collection("postLog").document(entryID)
        try await logRef.setData([
            "id": entryID,
            "userID": userID,
            "postID": postID,
            "locationName": locationName,
            "locationKey": locationKey,
            "contentType": contentType,
            "feedInsertionIndex": feedInsertionIndex,
            "createdAt": createdAt,
            "updatedAt": now
        ])

        let existing = try await profileRef.getDocument()
        let currentPostIDs = (existing.data()? ["postedPostIDs"] as? [String]) ?? []
        let uniquePostIDs = Array(Set(currentPostIDs + [postID]))
        try await profileRef.setData([
            "postedPostIDs": uniquePostIDs,
            "updatedAt": now
        ], merge: true)
    }

    public func saveUserSavedPost(userID: String, postID: String, saved: Bool) async throws {
        let cleanedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedPostID = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedUserID.isEmpty, !cleanedPostID.isEmpty else { return }
        guard !Self.isDeviceFallbackUserID(cleanedUserID) else {
            return
        }

        let profileRef = db.collection("users").document(cleanedUserID)
        let existing = try await profileRef.getDocument()
        let current = (existing.data()? ["savedPostIDs"] as? [String]) ?? []
        let next = saved ? Array(Set(current + [cleanedPostID])) : current.filter { $0 != cleanedPostID }
        try await profileRef.setData([
            "savedPostIDs": next,
            "updatedAt": Date().timeIntervalSince1970
        ], merge: true)
    }

    public func saveUserFlaggedPost(userID: String, postID: String, flagged: Bool) async throws {
        let cleanedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedPostID = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedUserID.isEmpty, !cleanedPostID.isEmpty else { return }
        guard !Self.isDeviceFallbackUserID(cleanedUserID) else {
            return
        }

        let profileRef = db.collection("users").document(cleanedUserID)
        let existing = try await profileRef.getDocument()
        let current = (existing.data()? ["flaggedPostIDs"] as? [String]) ?? []
        let next = flagged ? Array(Set(current + [cleanedPostID])) : current.filter { $0 != cleanedPostID }
        try await profileRef.setData([
            "flaggedPostIDs": next,
            "updatedAt": Date().timeIntervalSince1970
        ], merge: true)
    }

    public func recentUserPostCountForLocation(userID: String, locationName: String, withinLastSeconds: TimeInterval = 3600) async throws -> Int {
        let cleaned = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return 0 }

        let locationKey = ContentView.cooldownKeyForLocation(cleaned)
        let cutoff = Date().timeIntervalSince1970 - withinLastSeconds

        let snapshot = try await db.collection("users")
            .document(userID)
            .collection("postLog")
            .whereField("locationKey", isEqualTo: locationKey)
            .whereField("createdAt", isGreaterThanOrEqualTo: cutoff)
            .getDocuments()

        return snapshot.documents.count
    }

    public func saveUserLocationHistory(userID: String, locationName: String) async throws {
        let cleaned = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let profileRef = db.collection("users").document(userID)
        let existing = try await profileRef.getDocument()
        let current = (existing.data()? ["areaHistory"] as? [String]) ?? []
        var next = current.filter { $0.lowercased() != cleaned.lowercased() }
        next.insert(cleaned, at: 0)
        if next.count > 12 { next = Array(next.prefix(12)) }

        try await profileRef.setData([
            "areaHistory": next,
            "updatedAt": Date().timeIntervalSince1970
        ], merge: true)
    }

    public func saveUserBoostBalance(userID: String, remainingBoosts: Int) async throws {
        let cleanedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedUserID.isEmpty else { return }

        try await db.collection("users").document(cleanedUserID).setData([
            "remainingBoosts": max(0, remainingBoosts),
            "updatedAt": Date().timeIntervalSince1970
        ], merge: true)
    }

    public func fetchUserAccount(userID: String) async throws -> FirebaseUserAccountRecord {
        let snapshot = try await db.collection("users").document(userID).getDocument()
        let data = snapshot.data() ?? [:]

        let rawUsername = data["username"] as? String ?? ""
        let cleanedUsername = (rawUsername == "user" || rawUsername == "@user") ? "" : rawUsername

        return FirebaseUserAccountRecord(
            uid: data["uid"] as? String ?? userID,
            username: cleanedUsername,
            displayName: data["displayName"] as? String ?? "",
            phoneNumber: Self.normalizedOptionalString(data["phoneNumber"] as? String),
            bio: data["bio"] as? String,
            profilePhotoURL: Self.normalizedOptionalString(data["profilePhotoURL"] as? String),
            createdAt: data["createdAt"] as? TimeInterval ?? Date().timeIntervalSince1970,
            updatedAt: data["updatedAt"] as? TimeInterval ?? Date().timeIntervalSince1970,
            savedPostIDs: data["savedPostIDs"] as? [String] ?? [],
            flaggedPostIDs: data["flaggedPostIDs"] as? [String] ?? [],
            postedPostIDs: data["postedPostIDs"] as? [String] ?? [],
            areaHistory: data["areaHistory"] as? [String] ?? [],
            followerCount: data["followerCount"] as? Int ?? 0,
            followingCount: data["followingCount"] as? Int ?? 0,
            remainingBoosts: max(0, data["remainingBoosts"] as? Int ?? 0)
        )
    }

    public static func chatID(for userIDs: [String], isAnonymous: Bool = false) -> String {
        let base = userIDs.sorted().joined(separator: "_")
        return isAnonymous ? "anon_\(base)" : base
    }

    public func createOrGetChat(participantIDs: [String], isAnonymous: Bool = false) async throws -> String {
        let cleanedIDs = Array(Set(participantIDs.filter { !$0.isEmpty }))
        guard cleanedIDs.count >= 2 else { throw FirebaseSpotError.invalidPayload }

        let chatID = Self.chatID(for: cleanedIDs, isAnonymous: isAnonymous)
        let chatRef = db.collection("chats").document(chatID)
        let existing = try await chatRef.getDocument()

        if !existing.exists {
            try await chatRef.setData([
                "id": chatID,
                "participantIDs": cleanedIDs,
                "isAnonymous": isAnonymous,
                "createdAt": Date().timeIntervalSince1970,
                "updatedAt": Date().timeIntervalSince1970,
                "lastMessage": ""
            ])
        }

        return chatID
    }

    public func sendChatMessage(chatID: String, senderID: String, text: String, sharedPostID: String? = nil) async throws {
        let now = Date().timeIntervalSince1970
        let messageID = UUID().uuidString
        let chatRef = db.collection("chats").document(chatID)
        let messageRef = chatRef.collection("messages").document(messageID)

        try await messageRef.setData([
            "id": messageID,
            "senderID": senderID,
            "text": text,
            "sharedPostID": sharedPostID ?? "",
            "createdAt": now
        ])

        try await chatRef.updateData([
            "lastMessage": text,
            "updatedAt": now
        ])
    }

    public func fetchChatMessages(chatID: String, limit: Int = 200) async throws -> [FirebaseChatMessage] {
        let snapshot = try await db.collection("chats").document(chatID).collection("messages")
            .order(by: "createdAt", descending: false)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap { document in
            let data = document.data()
            guard let id = data["id"] as? String,
                  let senderID = data["senderID"] as? String else {
                return nil
            }

            return FirebaseChatMessage(
                id: id,
                senderID: senderID,
                text: data["text"] as? String ?? "",
                sharedPostID: Self.normalizedOptionalString(data["sharedPostID"] as? String),
                createdAt: data["createdAt"] as? TimeInterval ?? Date().timeIntervalSince1970
            )
        }
    }

    public func listenToUserChats(userID: String, completion: @escaping ([String: Any]) -> Void) -> ListenerRegistration? {
        guard !userID.isEmpty else { return nil }
        return db.collection("chats")
            .whereField("participantIDs", arrayContains: userID)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents, error == nil else { return }
                for doc in documents {
                    completion(doc.data())
                }
            }
    }

    public func fetchUserChats(userID: String) async throws -> [[String: Any]] {
        guard !userID.isEmpty else { return [] }
        let snapshot = try await db.collection("chats")
            .whereField("participantIDs", arrayContains: userID)
            .getDocuments()
        return snapshot.documents.map { $0.data() }
    }

    public func listenToChatMessages(chatID: String, completion: @escaping ([FirebaseChatMessage]) -> Void) -> ListenerRegistration? {
        guard !chatID.isEmpty else { return nil }
        return db.collection("chats").document(chatID).collection("messages")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents, error == nil else { return }
                let messages = documents.compactMap { document -> FirebaseChatMessage? in
                    let data = document.data()
                    guard let id = data["id"] as? String,
                          let senderID = data["senderID"] as? String else {
                        return nil
                    }
                    return FirebaseChatMessage(
                        id: id,
                        senderID: senderID,
                        text: data["text"] as? String ?? "",
                        sharedPostID: Self.normalizedOptionalString(data["sharedPostID"] as? String),
                        createdAt: data["createdAt"] as? TimeInterval ?? Date().timeIntervalSince1970
                    )
                }
                completion(messages)
            }
    }
}
