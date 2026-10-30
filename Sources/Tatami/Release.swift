import Foundation

/// Version facts read from the app bundle, so the About text, footer and `tatami status` never fall behind the release.
enum Release {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    /// "alpha", "beta" or empty for a stable release. Set in Info.plist as TatamiReleaseStage.
    static var stage: String { Bundle.main.object(forInfoDictionaryKey: "TatamiReleaseStage") as? String ?? "" }
    /// "0.3.0 alpha", or just "0.3.0" once the stage is empty.
    static var label: String { stage.isEmpty ? version : "\(version) \(stage)" }
}
