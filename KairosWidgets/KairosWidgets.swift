import ActivityKit
import SwiftUI
import WidgetKit

struct FocusTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isRunning: Bool
        var elapsedSeconds: Int
    }

    var startedAt: Date
}

@main
struct KairosWidgets: WidgetBundle {
    var body: some Widget {
        FocusTimerLiveActivity()
    }
}

struct FocusTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusTimerAttributes.self) { context in
            FocusTimerLockScreenView(context: context)
                .activityBackgroundTint(.clear)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isRunning ? "timer" : "pause.fill")
                        .foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.center) {
                    FocusElapsedText(context: context)
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isRunning ? "Focus" : "Paused")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label("Kairos", systemImage: "sparkles")
                        Spacer()
                        Text(context.state.isRunning ? "In progress" : "Paused")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                FocusElapsedText(context: context)
                    .monospacedDigit()
                    .font(.caption2)
            } minimal: {
                Image(systemName: "timer")
            }
            .widgetURL(URL(string: "kairos://focus"))
        }
    }
}

private struct FocusTimerLockScreenView: View {
    let context: ActivityViewContext<FocusTimerAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "timer")
                .font(.title2.weight(.semibold))
                .frame(width: 42, height: 42)
                .background(.thinMaterial, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Kairos Focus")
                    .font(.headline)
                Text(context.state.isRunning ? "Focus session in progress" : "Focus session paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            FocusElapsedText(context: context)
                .font(.title3.monospacedDigit().weight(.semibold))
        }
        .padding()
    }
}

private struct FocusElapsedText: View {
    let context: ActivityViewContext<FocusTimerAttributes>

    var body: some View {
        if context.state.isRunning {
            Text(timerInterval: context.attributes.startedAt...Date(), countsDown: false)
        } else {
            Text(context.state.elapsedSeconds.formattedElapsed)
        }
    }
}

private extension Int {
    var formattedElapsed: String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}
