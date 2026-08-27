import Foundation
import FirebaseCore

public enum FirebaseConfig {
    public static func configureIfNeeded() {
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
    }
}
