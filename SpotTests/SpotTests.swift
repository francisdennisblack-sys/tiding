//
//  SpotTests.swift
//  SpotTests
//
//  Created by Francis Black on 8/18/26.
//

import Testing
import CoreLocation
import SwiftUI
@testable import Spot

struct SpotTests {

    @Test func emptyProfilePhotoURLsAreTreatedAsMissing() async throws {
        #expect(FirebaseSpotService.normalizedOptionalString(nil) == nil)
        #expect(FirebaseSpotService.normalizedOptionalString("   ") == nil)
        #expect(FirebaseSpotService.normalizedOptionalString("https://cdn.example.com/avatar.jpg") == "https://cdn.example.com/avatar.jpg")
    }

    @Test func nearbyPlaceMatchesRankAboveGenericFallbackSuggestions() async throws {
        let nearby = [
            NearbyPlace(id: "1", name: "Temple Square", category: "landmark", latitude: 40.7707, longitude: -111.8910),
            NearbyPlace(id: "2", name: "City Creek Center", category: "shopping", latitude: 40.7675, longitude: -111.8897),
            NearbyPlace(id: "3", name: "Liberty Park", category: "park", latitude: 40.7362, longitude: -111.8597)
        ]

        let suggestions = LocationSuggestionRanker.rankedSuggestions(
            query: "temple",
            nearbyPlaces: nearby,
            fallback: ["Salt Lake City", "Utah", "Temple Square"],
            userCoordinate: CLLocationCoordinate2D(latitude: 40.7608, longitude: -111.8910)
        )

        #expect(suggestions.first == "Temple Square")
        #expect(suggestions.contains("Salt Lake City"))
    }

    @Test func emptyQueryStillKeepsNearbyPlacesUpFront() async throws {
        let nearby = [
            NearbyPlace(id: "1", name: "Temple Square", category: "landmark", latitude: 40.7707, longitude: -111.8910),
            NearbyPlace(id: "2", name: "City Creek Center", category: "shopping", latitude: 40.7675, longitude: -111.8897)
        ]

        let suggestions = LocationSuggestionRanker.rankedSuggestions(
            query: "",
            nearbyPlaces: nearby,
            fallback: ["Salt Lake City", "Denver"],
            userCoordinate: CLLocationCoordinate2D(latitude: 40.7608, longitude: -111.8910)
        )

        #expect(suggestions.prefix(2).contains("Temple Square"))
        #expect(suggestions.prefix(2).contains("City Creek Center"))
    }

    @Test func proximityWeightedResultsRankCloserMatchesHigher() async throws {
        let nearby = [
            NearbyPlace(id: "near", name: "Museum of Art", category: "museum", latitude: 40.7608, longitude: -111.8910),
            NearbyPlace(id: "far", name: "Museum", category: "museum", latitude: 41.5000, longitude: -111.9000)
        ]

        let suggestions = LocationSuggestionRanker.rankedSuggestions(
            query: "museum",
            nearbyPlaces: nearby,
            fallback: [],
            userCoordinate: CLLocationCoordinate2D(latitude: 40.7608, longitude: -111.8910)
        )

        #expect(!suggestions.isEmpty)
        #expect(suggestions.first == "Museum of Art")
    }

    @Test func pollVoteSwitchingRebalancesVoteCounts() async throws {
        let first = PollVoteLogic.updatedVotes(currentVotes: [0, 0], previousSelection: nil, nextSelection: 0)
        #expect(first.votes == [1, 0])
        #expect(first.selected == 0)

        let switched = PollVoteLogic.updatedVotes(currentVotes: first.votes, previousSelection: 0, nextSelection: 1)
        #expect(switched.votes == [0, 1])
        #expect(switched.selected == 1)

        let toggledOff = PollVoteLogic.updatedVotes(currentVotes: switched.votes, previousSelection: 1, nextSelection: 1)
        #expect(toggledOff.votes == [0, 0])
        #expect(toggledOff.selected == nil)

        let accumulated = PollVoteLogic.updatedVotes(currentVotes: [4, 2], previousSelection: nil, nextSelection: 0)
        #expect(accumulated.votes == [5, 2])
    }

    @Test func audioPostSourcePrefersRecordedAudioWhenAvailable() async throws {
        let recordedURL = URL(fileURLWithPath: "/tmp/recorded-audio.m4a")

        #expect(ContentView.audioPostSourceURL(draftUrl: "https://example.com/audio.mp3", recordedAudioURL: recordedURL) == recordedURL.absoluteString)
        #expect(ContentView.audioPostSourceURL(draftUrl: "https://example.com/audio.mp3", recordedAudioURL: nil) == "https://example.com/audio.mp3")
    }

    @Test func audioPostsPreferRemoteSourceURLForPersistentPlayback() async throws {
        let remoteSource = "https://cdn.example.com/audio.mp3"
        #expect(ContentView.persistedPostURL(contentType: "Audio", sourceURL: remoteSource, mediaURLs: ["local://stale"]) == remoteSource)
        #expect(ContentView.persistedPostURL(contentType: "Audio", sourceURL: nil, mediaURLs: [remoteSource]) == remoteSource)
    }

    @Test func mediaCaptionsCapAtFiftyCharacters() async throws {
        let input = "1234567890ABCDEFGHIJ1234567890ABCDEFGHIJ1234567890ABCDEFGHIJ"
        let capped = ContentView.cappedCaptionText(input, maxLength: 50)
        #expect(capped.count == 50)
        #expect(capped == String(input.prefix(50)))
    }

    @Test func postSearchRankingRewardsExactTextMatches() async throws {
        let matching = FirebasePostPayload(
            id: "match-1",
            authorID: "user-1",
            authorUsername: "@sunsetgirl",
            authorDisplayName: "Sunset Girl",
            authorProfilePhotoURL: nil,
            contentType: "Photo",
            title: "Sunset over Tokyo",
            body: "Golden hour with friends and ramen.",
            sourceURL: nil,
            mediaURLs: [],
            accentHex: "#DCE7FF",
            locationName: "Tokyo, Japan",
            feedInsertionIndex: 0,
            postedInLocations: ["Tokyo, Japan"],
            poiID: nil,
            latitude: 35.6762,
            longitude: 139.6503,
            city: "Tokyo",
            country: "Japan",
            geohash: nil,
            createdAt: Date().timeIntervalSince1970,
            updatedAt: Date().timeIntervalSince1970,
            isVideo: false,
            visibilityScope: "nearby",
            tags: ["sunset", "travel"],
            likesCount: 10,
            commentsCount: 2,
            viewCount: 28,
            totalViewDurationSeconds: 90,
            savedCount: 4,
            shareCount: 3,
            score: 10
        )

        let nonMatching = FirebasePostPayload(
            id: "match-2",
            authorID: "user-2",
            authorUsername: "@coffeeclub",
            authorDisplayName: "Coffee Club",
            authorProfilePhotoURL: nil,
            contentType: "Photo",
            title: "Coffee in Seattle",
            body: "A rainy cafe afternoon.",
            sourceURL: nil,
            mediaURLs: [],
            accentHex: "#DCE7FF",
            locationName: "Seattle, WA",
            feedInsertionIndex: 0,
            postedInLocations: ["Seattle, WA"],
            poiID: nil,
            latitude: 47.6062,
            longitude: -122.3321,
            city: "Seattle",
            country: "USA",
            geohash: nil,
            createdAt: Date().timeIntervalSince1970,
            updatedAt: Date().timeIntervalSince1970,
            isVideo: false,
            visibilityScope: "nearby",
            tags: ["coffee", "rain"],
            likesCount: 4,
            commentsCount: 1,
            viewCount: 9,
            totalViewDurationSeconds: 35,
            savedCount: 1,
            shareCount: 1,
            score: 3
        )

        #expect(FirebaseSpotService.postSearchMatches(query: "sunset tokyo", post: matching))
        #expect(!FirebaseSpotService.postSearchMatches(query: "sunset tokyo", post: nonMatching))
        #expect(FirebaseSpotService.postSearchScore(query: "sunset tokyo", post: matching) > FirebaseSpotService.postSearchScore(query: "sunset tokyo", post: nonMatching))
    }

    @Test func photoPostsResolveRemoteMediaURLWhenLocalCacheIsMissing() async throws {
        var post = MockPost(
            id: 99,
            author: "Sam",
            handle: "@sam",
            authorUserID: "u9",
            type: "Photo",
            location: "Metric",
            title: "Photo",
            body: "",
            url: "https://example.com/old-photo.jpg",
            accent: "#DCE7FF",
            tag: "Photo",
            likes: 0,
            viewCount: 0,
            isLiked: false,
            comments: [],
            sentTo: [],
            isSaved: false,
            pollOptions: [],
            pollVotes: [],
            mediaImage: nil,
            isBoosted: false,
            postedInLocations: ["Metric"],
            isAnonymous: false
        )
        post.mediaURLs = ["https://cdn.example.com/uploaded-photo.jpg"]
        post.sourceURL = "https://example.com/old-photo.jpg"

        let resolvedURL = ContentView.photoDisplayURL(for: post)
        #expect(resolvedURL?.absoluteString == "https://cdn.example.com/uploaded-photo.jpg")
    }

    @Test func videoPostPlaybackPrefersUploadedMediaURLOverStaleDraftURL() async throws {
        let remoteMedia = "https://cdn.example.com/uploaded-video.mp4"
        let staleURL = "/tmp/old-local-video.mp4"
        var post = MockPost(
            id: 42,
            author: "Francis",
            handle: "@francis",
            authorUserID: "u1",
            type: "Video",
            location: "Metric",
            title: "Video",
            body: "",
            url: staleURL,
            accent: "#DCE7FF",
            tag: "Video",
            likes: 0,
            viewCount: 0,
            isLiked: false,
            comments: [],
            sentTo: [],
            isSaved: false,
            pollOptions: [],
            pollVotes: [],
            mediaImage: nil,
            isBoosted: false,
            postedInLocations: ["Metric"],
            isAnonymous: false
        )
        post.mediaURLs = [remoteMedia]
        post.sourceURL = staleURL

        let playbackURL = await MainActor.run {
            let view = PostCardView(post: .constant(post))
            return view
        }
        _ = playbackURL
        #expect(ContentView.persistedPostURL(contentType: "Video", sourceURL: staleURL, mediaURLs: [remoteMedia]) == remoteMedia)
    }

    @Test func videoPostsResolveRemoteMediaURLWhenLocalCacheIsMissing() async throws {
        var post = MockPost(
            id: 42,
            author: "Alex",
            handle: "@alex",
            authorUserID: "u42",
            type: "Video",
            location: "Metric",
            title: "Video",
            body: "",
            url: "",
            accent: "#DCE7FF",
            tag: "Video",
            likes: 0,
            viewCount: 0,
            isLiked: false,
            comments: [],
            sentTo: [],
            isSaved: false,
            pollOptions: [],
            pollVotes: [],
            mediaImage: nil,
            isBoosted: false,
            postedInLocations: ["Metric"],
            isAnonymous: false
        )
        post.mediaURLs = ["https://cdn.example.com/uploaded-video.mp4"]
        post.sourceURL = nil

        let resolvedURL = ContentView.videoDisplayURL(for: post)
        #expect(resolvedURL?.absoluteString == "https://cdn.example.com/uploaded-video.mp4")
    }

    @Test func videoDisplayURLPrefersMediaURLsOverSourceURL() async throws {
        let primaryMedia = "https://storage.example.com/video.mp4"
        let fallbackSource = "https://example.com/old-video.mp4"
        var post = MockPost(
            id: 43,
            author: "Bob",
            handle: "@bob",
            authorUserID: "u43",
            type: "Video",
            location: "Metric",
            title: "Video",
            body: "",
            url: fallbackSource,
            accent: "#DCE7FF",
            tag: "Video",
            likes: 0,
            viewCount: 0,
            isLiked: false,
            comments: [],
            sentTo: [],
            isSaved: false,
            pollOptions: [],
            pollVotes: [],
            mediaImage: nil,
            isBoosted: false,
            postedInLocations: ["Metric"],
            isAnonymous: false
        )
        post.mediaURLs = [primaryMedia]
        post.sourceURL = fallbackSource

        let resolvedURL = ContentView.videoDisplayURL(for: post)
        #expect(resolvedURL?.absoluteString == primaryMedia)
    }

    @Test func ensureMediaURLsPopulatedBackfillsFromSourceURL() async throws {
        var post = MockPost(
            id: 44,
            author: "Charlie",
            handle: "@charlie",
            authorUserID: "u44",
            type: "Audio",
            location: "Metric",
            title: "Audio",
            body: "",
            url: "local-uuid-12345",
            accent: "#DCE7FF",
            tag: "Audio",
            likes: 0,
            viewCount: 0,
            isLiked: false,
            comments: [],
            sentTo: [],
            isSaved: false,
            pollOptions: [],
            pollVotes: [],
            mediaImage: nil,
            isBoosted: false,
            postedInLocations: ["Metric"],
            isAnonymous: false
        )
        post.mediaURLs = []
        post.sourceURL = "https://firebase-storage.example.com/audio.mp3"

        ContentView.ensureMediaURLsPopulated(for: &post)
        #expect(post.mediaURLs == ["https://firebase-storage.example.com/audio.mp3"])
    }

    @Test func photoAndVideoURLResolutionHandlesEmptySourceURLGracefully() async throws {
        var post = MockPost(
            id: 45,
            author: "Dave",
            handle: "@dave",
            authorUserID: "u45",
            type: "Photo",
            location: "Metric",
            title: "Photo",
            body: "",
            url: "",
            accent: "#DCE7FF",
            tag: "Photo",
            likes: 0,
            viewCount: 0,
            isLiked: false,
            comments: [],
            sentTo: [],
            isSaved: false,
            pollOptions: [],
            pollVotes: [],
            mediaImage: nil,
            isBoosted: false,
            postedInLocations: ["Metric"],
            isAnonymous: false
        )
        post.mediaURLs = ["https://cdn.example.com/photo.jpg"]
        post.sourceURL = nil

        let photoURL = ContentView.photoDisplayURL(for: post)
        let videoURL = ContentView.videoDisplayURL(for: post)

        #expect(photoURL?.absoluteString == "https://cdn.example.com/photo.jpg")
        #expect(videoURL?.absoluteString == "https://cdn.example.com/photo.jpg")
    }

    @Test func cooldownKeysRemainSeparateAcrossLocations() async throws {
        let tokyo = ContentView.cooldownKeyForLocation("Tokyo, Japan")
        let paris = ContentView.cooldownKeyForLocation("Paris, France")
        let spacedTokyo = ContentView.cooldownKeyForLocation("  Tokyo, Japan  ")
        let punctuationVariant = ContentView.cooldownKeyForLocation("Tokyo Japan")

        #expect(tokyo == spacedTokyo)
        #expect(tokyo == punctuationVariant)
        #expect(tokyo != paris)
    }

    @Test func legacyGlobalCooldownHistoryIsDiscarded() async throws {
        let key = "spot_location_post_cooldown_history"
        UserDefaults.standard.set(["global": [1700000000.0, 1700000001.0, 1700000002.0]], forKey: key)

        let restored = ContentView.loadLocationPostCooldownHistory()

        #expect(restored.isEmpty)
        #expect(UserDefaults.standard.dictionary(forKey: key) == nil)

        UserDefaults.standard.removeObject(forKey: key)
    }

    @Test func salePostCodecSupportsEmailAndRejectsLegacyConditionFields() async throws {
        let encoded = SalePostCodec.encode(items: ["Bike"], price: "150", phone: "5551234567", email: "seller@example.com")
        let decoded = SalePostCodec.decode(encoded)

        #expect(decoded != nil)
        #expect(decoded?.items == ["Bike"])
        #expect(decoded?.price == "150")
        #expect(decoded?.phone == "5551234567")
        #expect(decoded?.email == "seller@example.com")
        #expect(!encoded.lowercased().contains("condition"))
        #expect(!encoded.lowercased().contains("pickup"))
    }

    @Test func persistedDraftAudioRecordingURLRoundTrips() async throws {
        let key = "spot_draft_recorded_audio_url"
        UserDefaults.standard.removeObject(forKey: key)

        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("spot_draft_audio_roundtrip_\(UUID().uuidString).m4a")
        try "test-audio-data".write(to: fileURL, atomically: true, encoding: .utf8)

        ContentView.saveDraftAudioRecordingURL(fileURL)
        let restored = ContentView.loadDraftAudioRecordingURL()

        #expect(restored != nil)
        #expect(restored?.absoluteString == fileURL.absoluteString)

        ContentView.saveDraftAudioRecordingURL(nil)
        #expect(ContentView.loadDraftAudioRecordingURL() == nil)

        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test func postMediaFrameMatchesPhotoAspectRatio() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800)).image { _ in
            UIColor.red.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: 1200, height: 800)).fill()
        }

        let frame = PostCardView.mediaFrameSize(for: image, availableWidth: 360)

        #expect(frame.width <= 360)
        #expect(frame.height > 0)
        #expect(abs(frame.width / frame.height - 1.5) < 0.05)
    }

    @Test func savedAccountRestoreRequiresExplicitSignedInState() async throws {
        #expect(!ContentView.shouldRestoreSavedAccount(accountSignedIn: false, savedEmail: "legacy@example.com", savedPassword: "Password123"))
        #expect(ContentView.shouldRestoreSavedAccount(accountSignedIn: true, savedEmail: "legacy@example.com", savedPassword: "Password123"))
    }

    @Test func listingPhotosOpenInExpandedViewInsteadOfProfile() async throws {
        #expect(PostCardView.shouldExpandMediaOnTap(forType: "For Sale", hasMediaImage: true))
        #expect(!PostCardView.shouldExpandMediaOnTap(forType: "For Sale", hasMediaImage: false))
        #expect(!PostCardView.shouldExpandMediaOnTap(forType: "Photo", hasMediaImage: true))
    }

    @Test func audioComposerPrimaryLabelTransitionsThroughStates() async throws {
        #expect(ContentView.audioComposerPrimaryLabel(isRecording: true, hasRecording: false, hasPlayedRecording: false) == "Stop recording")
        #expect(ContentView.audioComposerPrimaryLabel(isRecording: false, hasRecording: false, hasPlayedRecording: false) == "Record audio")
        #expect(ContentView.audioComposerPrimaryLabel(isRecording: false, hasRecording: true, hasPlayedRecording: false) == "Play audio")
        #expect(ContentView.audioComposerPrimaryLabel(isRecording: false, hasRecording: true, hasPlayedRecording: true) == "Record again")
    }

    @Test func pollOptionsNormalizeToTwoToFourChoices() async throws {
        #expect(ContentView.normalizedPollOptions(["A", "B", "C", "D"]) == ["A", "B", "C", "D"])
        #expect(ContentView.normalizedPollOptions(["A", "B", "", ""]) == ["A", "B"])
        #expect(ContentView.normalizedPollOptions(["", "B", "C", ""]) == ["B", "C"])
        #expect(ContentView.normalizedPollOptions(["A", "", "", "D"]) == ["A", "D"])
        #expect(ContentView.normalizedPollOptions([""]) == ["Yes", "No"])
        #expect(ContentView.normalizedPollOptions(["Only"]) == ["Only", "No"])
    }

    @Test func customPollLabelsAndZeroVotesStayVisibleUntilAUserVotes() async throws {
        #expect(ContentView.normalizedPollOptions(["Left", "Right"]) == ["Left", "Right"])

        let draft = MockPost(
            id: 1,
            author: "You",
            handle: "@you",
            type: "Poll",
            location: "Tokyo, Japan",
            title: "Which way should we go?",
            body: "",
            url: "",
            accent: "#DCE7FF",
            tag: "Tokyo, Japan",
            likes: 0,
            isLiked: false,
            comments: [],
            sentTo: [],
            pollOptions: ["Left", "Right"],
            pollVotes: [0, 0]
        )

        #expect(draft.pollOptions == ["Left", "Right"])
        #expect(draft.pollVotes == [0, 0])
        #expect(draft.pollVotes.reduce(0, +) == 0)
    }

    @Test func pollChartUsesOriginalBrandPaletteForLeftAndRightSegments() async throws {
        let palette = PieChartView.legacyPalette()

        #expect(palette.count >= 2)
        #expect(palette[0] == Color(red: 0.12, green: 0.43, blue: 0.87))
        #expect(palette[1] == Color(red: 0.54, green: 0.31, blue: 0.85))
    }

    @Test func draftSubmissionIsAlwaysAvailableForAnyPostType() async throws {
        #expect(ContentView.canSubmitDraft(type: "Text", title: "", body: "", url: "", pollQuestion: "", pollOptionA: "", pollOptionB: "", hasPhoto: false, hasRecordedAudio: false))
        #expect(ContentView.canSubmitDraft(type: "Photo/Video", title: "", body: "", url: "", pollQuestion: "", pollOptionA: "", pollOptionB: "", hasPhoto: false, hasRecordedAudio: false))
        #expect(ContentView.canSubmitDraft(type: "Poll", title: "", body: "", url: "", pollQuestion: "", pollOptionA: "", pollOptionB: "", hasPhoto: false, hasRecordedAudio: false))
    }

    @Test func postSubmissionIsSingleFlightWhenAlreadySubmitting() async throws {
        #expect(ContentView.canStartDraftSubmission(isSubmitting: false))
        #expect(!ContentView.canStartDraftSubmission(isSubmitting: true))
    }

    @Test func ownProfileViewsDoNotCountButOwnFeedViewsDo() async throws {
        #expect(!PostCardView.shouldCountView(isOwnPost: true, showsAuthorLine: false))
        #expect(PostCardView.shouldCountView(isOwnPost: true, showsAuthorLine: true))
        #expect(PostCardView.shouldCountView(isOwnPost: false, showsAuthorLine: false))
    }

    @Test func usernameNormalizationKeepsCanonicalDatabaseFormat() async throws {
        #expect(FirebaseSpotService.normalizeUsername("@FrA_ncis!!") == "francis")
        #expect(FirebaseSpotService.normalizeUsername("  @maya_01  ") == "maya_01")
        #expect(FirebaseSpotService.isValidUsername("maya_01"))
        #expect(!FirebaseSpotService.isValidUsername("ab"))
        #expect(!FirebaseSpotService.isValidUsername("bad username"))
    }

    @Test func legacyPostIdentityMigrationUpdatesAuthorAndHandle() async throws {
        let payload = FirebaseSpotService.migratedPostUpdatePayload(
            authorID: "auth_456",
            username: "francis",
            displayName: "Francis Black",
            photoURL: "https://cdn.example.com/avatar.jpg"
        )

        #expect(payload["authorID"] as? String == "auth_456")
        #expect(payload["authorUsername"] as? String == "@francis")
        #expect(payload["authorDisplayName"] as? String == "Francis Black")
        #expect(payload["authorProfilePhotoURL"] as? String == "https://cdn.example.com/avatar.jpg")
    }

    @Test func blockedBrandTermsAreRejectedForUsernamesAndNames() async throws {
        #expect(!FirebaseSpotService.isAllowedUsername("tidingreal", reservedAgainst: "francis"))
        #expect(!FirebaseSpotService.isAllowedUsername("tidings", reservedAgainst: "francis"))
        #expect(!FirebaseSpotService.isAllowedUsername("ceo", reservedAgainst: "francis"))
        #expect(!FirebaseSpotService.isAllowedUsername("ceo123", reservedAgainst: "francis"))
        #expect(!FirebaseSpotService.isAllowedUsername("francis", reservedAgainst: "francis"))
        #expect(FirebaseSpotService.isAllowedUsername("frankly", reservedAgainst: "francis"))

        #expect(!FirebaseSpotService.isAllowedDisplayName("Tiding Real", reservedAgainst: "Sam"))
        #expect(!FirebaseSpotService.isAllowedDisplayName("CEO", reservedAgainst: "Sam"))
    }

    @Test func requestedTemporaryTidingHandleIsTemporarilyAllowed() async throws {
        #expect(FirebaseSpotService.isAllowedUsername("tiding", reservedAgainst: "francis"))
        #expect(FirebaseSpotService.isAllowedDisplayName("Tiding", reservedAgainst: "Sam"))
        #expect(!FirebaseSpotService.isAllowedDisplayName("Tidings", reservedAgainst: "Sam"))
        #expect(FirebaseSpotService.isAllowedDisplayName("Lena Moore", reservedAgainst: "Sam"))
    }

    @Test func activeAuthUserIDWinsOverStalePersistedID() async throws {
        let currentUserID = "auth_user_456"
        let persistedUserID = "stale_user_123"
        let fallbackUserID = "device_user_789"

        let resolved = ContentView.preferredUserID(
            currentUserID: currentUserID,
            persistedUserID: persistedUserID,
            fallbackUserID: fallbackUserID
        )

        #expect(resolved == currentUserID)
        #expect(ContentView.preferredUserID(currentUserID: nil, persistedUserID: persistedUserID, fallbackUserID: fallbackUserID) == persistedUserID)
        #expect(ContentView.preferredUserID(currentUserID: nil, persistedUserID: nil, fallbackUserID: fallbackUserID) == fallbackUserID)
    }

    @Test func locationPickerReturnsToVideoFeedWhenVideoContextIsSelected() async throws {
        #expect(ContentView.closeScreenAfterLocationSelection(context: .video, currentScreen: .locationPicker) == .locationFeed)
        #expect(ContentView.closeScreenAfterLocationSelection(context: .feed, currentScreen: .locationPicker) == .home)
        #expect(ContentView.closeScreenAfterLocationSelection(context: .post, currentScreen: .postLocationPicker) == .home)
    }

    @Test func metricLocationIsPreservedWhenSubmittingPosts() async throws {
        #expect(ContentView.resolvedPostingLocation(postLocation: "Metric", feedLocation: "Tokyo, Japan", nearbyPlaceName: "Shibuya") == "Metric")
        #expect(ContentView.resolvedPostingLocation(postLocation: "", feedLocation: "Metric", nearbyPlaceName: "Shibuya") == "Metric")
        #expect(ContentView.resolvedPostingLocation(postLocation: "", feedLocation: "Tokyo, Japan", nearbyPlaceName: "Shibuya") == "Tokyo, Japan")
    }

    @Test func postOwnershipFollowsUIDEvenWhenUsernameChanges() async throws {
        let original = MockPost(
            id: 1,
            author: "Francis Black",
            handle: "@francis",
            authorUserID: "user_123",
            type: "Text",
            location: "Tokyo, Japan",
            title: "First",
            body: "Body",
            url: "",
            accent: "#DCE7FF",
            tag: "Tokyo, Japan",
            likes: 0,
            isLiked: false,
            comments: [],
            sentTo: []
        )

        let renamed = original
        let updatedHandle = "@frank"
        let renamedPost = MockPost(
            id: original.id,
            author: original.author,
            handle: updatedHandle,
            authorUserID: original.authorUserID,
            type: original.type,
            location: original.location,
            title: original.title,
            body: original.body,
            url: original.url,
            accent: original.accent,
            tag: original.tag,
            likes: original.likes,
            isLiked: original.isLiked,
            comments: original.comments,
            sentTo: original.sentTo
        )

        #expect(ContentView.isPostOwnedByUser(renamedPost, currentUserID: "user_123", currentUsername: "@frank"))
        #expect(!ContentView.isPostOwnedByUser(renamedPost, currentUserID: "user_999", currentUsername: "@frank"))
        #expect(!ContentView.isPostOwnedByUser(renamedPost, currentUserID: "", currentUsername: "@other"))
    }

    @Test func osmStylePoiIdentifiersAreSanitizedForFirestorePaths() async throws {
        #expect(FirebaseSpotService.sanitizeFirestoreDocumentID("way/1455306847") == "way_1455306847")
        #expect(FirebaseSpotService.sanitizeFirestoreDocumentID("node/123") == "node_123")
        #expect(FirebaseSpotService.sanitizeFirestoreDocumentID("  south-station  ") == "south-station")
    }

    @Test func canonicalPostDocumentIDPrefersFirestoreDocumentID() async throws {
        #expect(FirebaseSpotService.canonicalPostDocumentID(fieldID: "legacy_123", documentID: "doc_789") == "doc_789")
        #expect(FirebaseSpotService.canonicalPostDocumentID(fieldID: "legacy_123", documentID: "   ") == "legacy_123")
        #expect(FirebaseSpotService.canonicalPostDocumentID(fieldID: nil, documentID: "doc_789") == "doc_789")
    }

    @Test func deleteCandidatePostIDsUseCanonicalThenFallbackWithoutDuplicates() async throws {
        #expect(ContentView.deleteCandidatePostIDs(firestoreID: "doc_789", localPostID: 123) == ["doc_789", "123"])
        #expect(ContentView.deleteCandidatePostIDs(firestoreID: "123", localPostID: 123) == ["123"])
        #expect(ContentView.deleteCandidatePostIDs(firestoreID: "", localPostID: 123) == ["123"])
    }

    @Test func viewedOtherProfileDoesNotReuseSignedInOwnership() async throws {
        let myPost = MockPost(
            id: 42,
            author: "Me",
            handle: "@me",
            authorUserID: "user_me",
            type: "Text",
            location: "Tokyo, Japan",
            title: "Mine",
            body: "owned by me",
            url: "",
            accent: "#DCE7FF",
            tag: "Tokyo, Japan",
            likes: 0,
            isLiked: false,
            comments: [],
            sentTo: []
        )

        let includeOnOtherProfile = ContentView.shouldIncludePostInViewedProfile(
            myPost,
            viewedUsername: "@other",
            signedInUsername: "@me",
            currentUserID: "user_me"
        )

        let includeOnOwnProfile = ContentView.shouldIncludePostInViewedProfile(
            myPost,
            viewedUsername: "@me",
            signedInUsername: "@me",
            currentUserID: "user_me"
        )

        #expect(!includeOnOtherProfile)
        #expect(includeOnOwnProfile)
    }

    @Test func anonymousPostsAreExcludedFromProfileViews() async throws {
        let anonymousPost = MockPost(
            id: 99,
            author: "Anonymous",
            handle: "anonymous",
            authorUserID: "user_me",
            type: "Text",
            location: "Tokyo, Japan",
            title: "Hidden",
            body: "anonymous content",
            url: "",
            accent: "#DCE7FF",
            tag: "Tokyo, Japan",
            likes: 0,
            isLiked: false,
            comments: [],
            sentTo: [],
            isAnonymous: true
        )

        let includeOnOwnProfile = ContentView.shouldIncludePostInViewedProfile(
            anonymousPost,
            viewedUsername: "@me",
            signedInUsername: "@me",
            currentUserID: "user_me"
        )

        #expect(!includeOnOwnProfile)
    }

    @Test func missingUserProfileWritesUseMergeSafePayload() async throws {
        let payload = FirebaseSpotService.makeUserProfileUpsertPayload(
            userID: "uid_123",
            username: "@francis",
            displayName: "Francis",
            bio: nil,
            photoURL: nil,
            existingData: [:]
        )

        #expect(payload["uid"] as? String == "uid_123")
        #expect(payload["username"] as? String == "@francis")
        #expect(payload["savedPostIDs"] as? [String] == [])
        #expect(payload["postedPostIDs"] as? [String] == [])
        #expect(payload["areaHistory"] as? [String] == [])
    }

    @Test func stableDeviceUserIDPersistsAcrossAppRestarts() async throws {
        let key = "spot_device_user_id_test"
        UserDefaults.standard.removeObject(forKey: key)

        let first = FirebaseSpotService.makeStableDeviceUserID(storageKey: key)
        let second = FirebaseSpotService.makeStableDeviceUserID(storageKey: key)

        #expect(first == second)
        #expect(!first.isEmpty)
        #expect(UserDefaults.standard.string(forKey: key) == first)
    }

    @Test func localPostsStayVisibleWhenFirebaseSyncFails() async throws {
        let local = [
            MockPost(id: 1, author: "You", handle: "@you", type: "Text", location: "Tokyo, Japan", title: "Still here", body: "This should stay visible", url: "", accent: "#DCE7FF", tag: "Tokyo, Japan", likes: 0, viewCount: 0, timeViewedSeconds: 0, shareCount: 0, isLiked: false, comments: [], sentTo: [])
        ]

        let persisted = [
            FirebasePostPayload(
                id: "1",
                authorID: "uid-123",
                contentType: "Text",
                title: "Still here",
                body: "This should stay visible",
                mediaURLs: [],
                locationName: "Tokyo, Japan",
                latitude: 0,
                longitude: 0,
                city: "Tokyo, Japan",
                createdAt: Date().timeIntervalSince1970,
                isVideo: false,
                visibilityScope: "nearby",
                tags: ["Tokyo, Japan"]
            )
        ]

        let kept = ContentView.postsAfterSyncAttempt(currentPosts: local, persistedPosts: [], syncError: FirebaseSpotError.readFailed)
        #expect(kept.count == 1)
        #expect(kept.first?.id == 1)

        let replaced = ContentView.postsAfterSyncAttempt(currentPosts: local, persistedPosts: persisted, syncError: nil)
        #expect(replaced.count == 1)
        #expect(replaced.first?.title == "Still here")
    }

    @Test func legacyFirestorePostIDsArePreservedForExactDeletion() async throws {
        let payloads = [
            FirebasePostPayload(
                id: "post_legacy_7f3a9c",
                authorID: "uid-123",
                authorUsername: "@you",
                authorDisplayName: "You",
                contentType: "Text",
                title: "Old one",
                body: "Delete me",
                mediaURLs: [],
                locationName: "Tokyo, Japan",
                latitude: 35.6762,
                longitude: 139.6503,
                city: "Tokyo, Japan",
                createdAt: Date().timeIntervalSince1970,
                isVideo: false,
                visibilityScope: "nearby",
                tags: ["Tokyo, Japan"]
            )
        ]

        let hydrated = ContentView.postsAfterSyncAttempt(currentPosts: [], persistedPosts: payloads, syncError: nil)

        #expect(hydrated.count == 1)
        #expect(hydrated.first?.firestoreID == "post_legacy_7f3a9c")
        #expect(hydrated.first?.id != 0)
    }

    @Test func savedPostsHydrateFromUserRecord() async throws {
        let posts = [
            MockPost(id: 1, author: "You", handle: "@you", type: "Text", location: "Tokyo, Japan", title: "First", body: "A", url: "", accent: "#DCE7FF", tag: "Tokyo, Japan", likes: 0, isLiked: false, comments: [], sentTo: []),
            MockPost(id: 2, author: "You", handle: "@you", type: "Text", location: "Tokyo, Japan", title: "Second", body: "B", url: "", accent: "#DCE7FF", tag: "Tokyo, Japan", likes: 0, isLiked: false, comments: [], sentTo: [])
        ]

        let hydrated = ContentView.postsWithSavedState(posts, savedPostIDs: ["2"])
        #expect(hydrated[0].isSaved == false)
        #expect(hydrated[1].isSaved == true)

        let ownSaved = ContentView.postsWithSavedState(posts, savedPostIDs: ["1", "2"])
        #expect(ownSaved[0].isSaved == true)
        #expect(ownSaved[1].isSaved == true)
    }

    @Test func selfUserIsNeverEligibleForDMSearchOrSelfChats() async throws {
        let me = FakeUserProfile(username: "@francis", name: "Francis Black", city: "", bio: "", followerCount: 0, followingCount: 0, profilePhotoText: "FB")
        let friend = FakeUserProfile(username: "@maya", name: "Maya Chen", city: "", bio: "", followerCount: 0, followingCount: 0, profilePhotoText: "MC")

        #expect(ContentView.isCurrentUserDMProfile(me, currentUsername: "francis"))
        #expect(!ContentView.isCurrentUserDMProfile(friend, currentUsername: "francis"))
    }

    @Test func userSearchMatchesUsernameAndDisplayNameWithoutCaseSensitivity() async throws {
        let account = FirebaseUserAccountRecord(
            uid: "abc123",
            username: "@Maya_01",
            displayName: "Maya Chen",
            bio: nil,
            profilePhotoURL: nil
        )

        #expect(FirebaseSpotService.userSearchMatches(query: "maya", account: account))
        #expect(FirebaseSpotService.userSearchMatches(query: "chen", account: account))
        #expect(!FirebaseSpotService.userSearchMatches(query: "francis", account: account))
    }

    @Test func poiSearchMatchesNameAndCategoryWithoutCaseSensitivity() async throws {
        let record = FirebasePOIRecord(
            id: "south-station",
            name: "South Station",
            category: "transportation",
            latitude: 42.3522,
            longitude: -71.0552,
            city: "Boston",
            country: "United States"
        )

        #expect(FirebaseSpotService.poiSearchMatches(query: "south", poi: record))
        #expect(FirebaseSpotService.poiSearchMatches(query: "station", poi: record))
        #expect(FirebaseSpotService.poiSearchMatches(query: "transport", poi: record))
        #expect(!FirebaseSpotService.poiSearchMatches(query: "harvard", poi: record))
        #expect(FirebaseSpotService.poiSearchScore(query: "south", poi: record) > FirebaseSpotService.poiSearchScore(query: "transport", poi: record))
    }

    @Test func postEngagementScoreRisesWithDwellTime() async throws {
        var post = MockPost(
            id: 1,
            author: "You",
            handle: "@you",
            type: "Photo",
            location: "Tokyo, Japan",
            title: "Testing score",
            body: "Testing score behavior",
            url: "https://example.com",
            accent: "#DCE7FF",
            tag: "Photo",
            likes: 0,
            viewCount: 14,
            timeViewedSeconds: 42,
            shareCount: 1,
            isLiked: false,
            comments: [],
            sentTo: []
        )

        let before = post.engagementScore
        post.recordView(durationSeconds: 18)

        #expect(post.viewCount >= 15)
        #expect(post.engagementScore > before)
        #expect(post.engagementScore == 30)
    }

    @Test func engagementScoreNeverDropsBelowItsBestHistoricValue() async throws {
        let previousPeak = FirebaseSpotService.engagementScore(
            views: 120,
            totalViewDurationSeconds: 420,
            saves: 10,
            likes: 16,
            comments: 12,
            shares: 5,
            locationBreadth: 4,
            isBoosted: true
        )

        let laterScore = FirebaseSpotService.monotonicEngagementScore(
            previousScore: previousPeak,
            views: 40,
            totalViewDurationSeconds: 90,
            saves: 1,
            likes: 0,
            comments: 0,
            shares: 0,
            locationBreadth: 1,
            isBoosted: false
        )

        #expect(laterScore >= previousPeak)
    }

    @Test func persistedPayloadKeepsLinkAndPollFieldsWhenHydrated() async throws {
        let createdAt = Date().timeIntervalSince1970
        let persisted = [
            FirebasePostPayload(
                id: "12345",
                authorID: "uid-1",
                authorUsername: "@you",
                authorDisplayName: "You",
                contentType: "Poll",
                title: "Which route?",
                body: "Vote below",
                sourceURL: "https://example.com/poll-context",
                mediaURLs: [],
                pollOptions: ["Left", "Right"],
                pollVotes: [7, 3],
                accentHex: "#FFAA33",
                locationName: "Tokyo, Japan",
                feedInsertionIndex: 0,
                postedInLocations: ["Tokyo, Japan"],
                latitude: 0,
                longitude: 0,
                createdAt: createdAt
            )
        ]

        let hydrated = ContentView.postsAfterSyncAttempt(currentPosts: [], persistedPosts: persisted, syncError: nil)
        #expect(hydrated.count == 1)
        #expect(hydrated[0].type == "Poll")
        #expect(hydrated[0].url == "https://example.com/poll-context")
        #expect(hydrated[0].pollOptions == ["Left", "Right"])
        #expect(hydrated[0].pollVotes == [7, 3])
        #expect(hydrated[0].accent == "#FFAA33")
    }

    @Test func hydratedPostsPreserveNewestFirstFeedOrderByTimestamp() async throws {
        let now = Date().timeIntervalSince1970
        let older = FirebasePostPayload(
            id: "100",
            authorID: "uid-1",
            contentType: "Text",
            title: "Older",
            body: "First",
            sourceURL: nil,
            mediaURLs: [],
            locationName: "Tokyo, Japan",
            postedInLocations: ["Tokyo, Japan"],
            latitude: 0,
            longitude: 0,
            createdAt: now - 120
        )
        let newer = FirebasePostPayload(
            id: "101",
            authorID: "uid-1",
            contentType: "Text",
            title: "Newer",
            body: "Second",
            sourceURL: nil,
            mediaURLs: [],
            locationName: "Tokyo, Japan",
            postedInLocations: ["Tokyo, Japan"],
            latitude: 0,
            longitude: 0,
            createdAt: now
        )

        let hydrated = ContentView.postsAfterSyncAttempt(currentPosts: [], persistedPosts: [older, newer], syncError: nil)
        #expect(hydrated.count == 2)
        #expect(hydrated[0].title == "Newer")
        #expect(hydrated[1].title == "Older")
    }

}
