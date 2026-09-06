import Foundation
import FirebaseCore
import FirebaseAppCheck

public enum FirebaseConfig {
    public static let projectID = "tiding-506722"
    public static let storageBucket = "tiding-506722.firebasestorage.app"
    public static let storageBucketURL = "gs://tiding-506722.firebasestorage.app"

    private static func logConfigMismatchIfNeeded() {
        guard let app = FirebaseApp.app() else { return }
        let options = app.options
        let resolvedProjectID = options.projectID
        let resolvedStorageBucket = options.storageBucket

        if resolvedProjectID != projectID || resolvedStorageBucket != storageBucket {
            print(
                "Firebase project mismatch detected. " +
                "Expected project='\(projectID)' bucket='\(storageBucket)', " +
                "got project='\(resolvedProjectID ?? "nil")' bucket='\(resolvedStorageBucket ?? "nil")'."
            )
        }
    }

    private static func configureAppCheckIfNeeded() {
        // App Check is intentionally disabled for now.
        // Re-enable with an explicit provider once backend enforcement is ready.
    }

    public static func configureIfNeeded() {
        if FirebaseApp.app() == nil {
            configureAppCheckIfNeeded()
            FirebaseApp.configure()
        }
        logConfigMismatchIfNeeded()
    }
}
