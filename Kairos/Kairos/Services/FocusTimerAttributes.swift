import ActivityKit
import Foundation

/// Shared ActivityKit contract compiled into both the app and WidgetKit extension.
struct FocusTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isRunning: Bool
        var elapsedSeconds: Int
    }

    var startedAt: Date
}
