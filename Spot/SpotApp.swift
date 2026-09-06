//
//  SpotApp.swift
//  Spot
//
//  Created by Francis Black on 8/18/26.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import CoreLocation
import UserNotifications

struct TidingPolicyView: View {
    @AppStorage("tiding_permissions_prompted") private var permissionsPrompted = false
    @State private var isRequestingPermissions = false
    @State private var permissionStatusText = ""
    var onAgree: () -> Void

    private func requestInitialPermissions() {
        guard !permissionsPrompted else { return }
        isRequestingPermissions = true

        Task {
            let notificationCenter = UNUserNotificationCenter.current()
            let granted = (try? await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            permissionsPrompted = true

            await MainActor.run {
                isRequestingPermissions = false
                permissionStatusText = granted ? "Notifications enabled" : "Notifications can be enabled later in iOS Settings"
                onAgree()
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("By creating an account and using Tiding, you agree to use the service lawfully and respectfully. You may not use Tiding to harass, deceive, abuse, or disrupt other users or the platform.")
                        .font(.footnote.weight(.medium))

                    Text("You are responsible for the content you share, including text, photographs, audio, videos, location information, and messages. You must have the rights to post what you share and must not upload content that infringes the rights of others.")
                        .font(.footnote.weight(.medium))

                    Text("Tiding may review, remove, limit, or restrict content or accounts that violate these terms, applicable law, or community safety standards. We may also suspend or terminate access to the service for misuse or repeated policy violations.")
                        .font(.footnote.weight(.medium))

                    Text("We use location, account, and activity data to provide local discovery, moderation, and safety features. By using Tiding, you understand that your activity and location-related information may be processed to operate the service.")
                        .font(.footnote.weight(.medium))

                    Text("We may update this agreement from time to time. Continued use of Tiding after changes are posted means you accept the updated terms.")
                        .font(.footnote.weight(.medium))

                    Text("By tapping I agree, you confirm that you have read and accepted this agreement.")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 10)
            }
            .frame(maxHeight: .infinity)
            .layoutPriority(1)

            if !permissionStatusText.isEmpty {
                Text(permissionStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                if permissionsPrompted {
                    onAgree()
                } else {
                    requestInitialPermissions()
                }
            } label: {
                Text(isRequestingPermissions ? "Preparing access..." : "I agree")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isRequestingPermissions)
            .opacity(isRequestingPermissions ? 0.65 : 1)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(Color(.systemBackground))
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private let cachedAPNSTokenDefaultsKey = "spot_cached_apns_token"
    private let postAgreementLocalNotificationID = "spot-post-agreement-local-test"

    func registerForRemoteNotificationsIfAuthorized() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                    print("[Push] registerForRemoteNotifications() called (authorized).")
                }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    guard granted else {
                        print("[Push] Notification permission denied during APNs registration request.")
                        return
                    }
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                        print("[Push] registerForRemoteNotifications() called after permission grant.")
                    }
                }
            case .denied:
                print("[Push] Notifications are denied in iOS Settings; APNs registration skipped.")
            @unknown default:
                print("[Push] Unknown notification authorization status; APNs registration skipped.")
            }
        }
    }

    func sendPostAgreementLocalTestNotification() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            func enqueue() {
                let locationName = self.launchNotificationLocationName()
                center.removePendingNotificationRequests(withIdentifiers: [self.postAgreementLocalNotificationID])

                let content = UNMutableNotificationContent()
                content.title = "\(locationName) has a new post"
                content.body = "Open Tiding to see what's new."
                content.sound = .default

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.2, repeats: false)
                let request = UNNotificationRequest(
                    identifier: self.postAgreementLocalNotificationID,
                    content: content,
                    trigger: trigger
                )
                center.add(request) { error in
                    if let error {
                        print("[Push] Failed to queue post-agreement local notification: \(error.localizedDescription)")
                    } else {
                        print("[Push] Queued post-agreement local notification.")
                    }
                }
            }

            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                enqueue()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    guard granted else { return }
                    enqueue()
                }
            default:
                break
            }
        }
    }

    private func awaitRegisteredAPNSToken(maxAttempts: Int = 8) async -> String? {
        for _ in 0..<maxAttempts {
            if let token = UserDefaults.standard.string(forKey: cachedAPNSTokenDefaultsKey), !token.isEmpty {
                return token
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return nil
    }

    private func launchNotificationLocationName() -> String {
        let defaults = UserDefaults.standard

        if let saved = (defaults.array(forKey: "spot_saved_locations") as? [String])?
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return saved.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let recent = (defaults.array(forKey: "spot_recent_locations") as? [String])?
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return recent.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let active = defaults.string(forKey: "spot_feed_location")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !active.isEmpty {
            return active
        }

        return "Metric"
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseConfig.configureIfNeeded()
        UNUserNotificationCenter.current().delegate = self
        print("[Push] didFinishLaunching: notification center delegate set")
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content
        print("[Push] willPresent foreground notification: title='\(content.title)' body='\(content.body)'")
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        UserDefaults.standard.set(token, forKey: cachedAPNSTokenDefaultsKey)
        print("[Push] APNs registration succeeded. Device token: \(token)")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[Push] APNs registration failed: \(error.localizedDescription)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        completionHandler(.newData)
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if Auth.auth().canHandle(url) {
            return true
        }
        return false
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let incomingURL = userActivity.webpageURL,
           Auth.auth().canHandle(incomingURL) {
            return true
        }
        return false
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main
struct SpotApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("has_agreed_to_tiding_policy") private var hasAgreedToPolicy = false

    init() {
        FirebaseConfig.configureIfNeeded()
        FirebaseSpotService.shared.bootstrap()
        Task.detached(priority: .userInitiated) {
            NearbyPlaceLoader.initializeSearchIndexIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            if !hasAgreedToPolicy {
                TidingPolicyView {
                    hasAgreedToPolicy = true
                    appDelegate.registerForRemoteNotificationsIfAuthorized()
                    appDelegate.sendPostAgreementLocalTestNotification()
                }
            } else {
                ContentView()
            }
        }
    }
}
