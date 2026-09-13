import Foundation

/// Centralizes the lightweight URL contract used by Siri, widgets, and notifications.
enum KairosDeepLink {
    static let scheme = "kairos"
    static let focusTimerPath = "focus"

    static var focusTimerURL: URL? {
        URL(string: "\(scheme)://\(focusTimerPath)")
    }
}
