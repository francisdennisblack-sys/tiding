//
//  SpotApp.swift
//  Spot
//
//  Created by Francis Black on 8/18/26.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth

struct TidingPolicyView: View {
    @AppStorage("tiding_terms_accepted") private var termsAccepted = false

    var body: some View {
        VStack(spacing: 12) {
            Image("Image 2")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .clipped()
                .padding(.top, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("By creating an account and using Tiding, you agree to use the service lawfully and respectfully. You may not use Tiding to harass, deceive, abuse, or disrupt other users or the platform.")
                        .font(.subheadline)

                    Text("You are responsible for the content you share, including text, photographs, audio, videos, location information, and messages. You must have the rights to post what you share and must not upload content that infringes the rights of others.")
                        .font(.subheadline)

                    Text("Tiding may review, remove, limit, or restrict content or accounts that violate these terms, applicable law, or community safety standards. We may also suspend or terminate access to the service for misuse or repeated policy violations.")
                        .font(.subheadline)

                    Text("We use location, account, and activity data to provide local discovery, moderation, and safety features. By using Tiding, you understand that your activity and location-related information may be processed to operate the service.")
                        .font(.subheadline)

                    Text("We may update this agreement from time to time. Continued use of Tiding after changes are posted means you accept the updated terms.")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
            }
            .frame(maxHeight: 228)

            Text("By tapping I agree, you confirm that you have read and accepted this agreement.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            Button {
                termsAccepted = true
            } label: {
                Text("I agree")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color(.systemGray5), Color(.systemGray4)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .padding(.top, 10)
        .background(Color(.systemBackground))
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseConfig.configureIfNeeded()
        return true
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
}

@main
struct SpotApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("tiding_terms_accepted") private var termsAccepted = false

    init() {
        FirebaseConfig.configureIfNeeded()
        FirebaseSpotService.shared.bootstrap()
        termsAccepted = false
    }

    var body: some Scene {
        WindowGroup {
            if termsAccepted {
                ContentView()
            } else {
                TidingPolicyView()
            }
        }
    }
}
