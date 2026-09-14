import ActivityKit
import SwiftUI
import WidgetKit

struct FocusTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var isRunning: Bool
        var elapsedSeconds: Int
    }

    var startedAt: Date
}

struct KairosFocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusTimerAttributes.self) { context in
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.secondary.opacity(0.14))
                    Image(systemName: context.state.isRunning ? "timer" : "pause.fill")
                        .font(.headline.weight(.semibold))
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.isRunning ? "Focus session" : "Focus paused")
                        .font(.headline)
                    Text(timerText(context))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                }

                Spacer()

                Text(context.state.isRunning ? "FOCUS" : "PAUSED")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(context.state.isRunning ? .primary : .secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .activityBackgroundTint(.black.opacity(0.06))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isRunning ? "timer" : "pause.fill")
                        .font(.title3.weight(.semibold))
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.isRunning ? "Focus session" : "Focus paused")
                            .font(.caption.weight(.semibold))
                        Text(timerText(context))
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isRunning ? "FOCUS" : "PAUSED")
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                }
            } compactLeading: {
                Image(systemName: context.state.isRunning ? "timer" : "pause.fill")
            } compactTrailing: {
                Text(timerText(context))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: context.state.isRunning ? "timer" : "pause.fill")
            }
        }
    }

    private func timerText(_ context: ActivityViewContext<FocusTimerAttributes>) -> String {
        let totalSeconds = max(0, context.state.elapsedSeconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct KairosHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KairosHomeWidget", provider: Provider()) { entry in
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("KAIROS")
                            .font(.caption.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(.secondary)
                        Text("Ready to focus?")
                            .font(.title3.weight(.bold))
                    }

                    Spacer()

                    Image(systemName: "timer")
                        .font(.title3.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(.thinMaterial, in: Circle())
                }

                Spacer(minLength: 12)

                HStack(alignment: .lastTextBaseline) {
                    Text("Start Focus")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Text(entry.date, style: .time)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(16)
            .containerBackground(for: .widget) {
                Color.clear
            }
            .widgetURL(URL(string: "kairos://focus-timer"))
        }
        .configurationDisplayName("Kairos Focus")
        .description("Jump straight into a Kairos focus session.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    struct Entry: TimelineEntry {
        let date: Date
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry {
            Entry(date: .now)
        }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(Entry(date: .now))
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            let now = Date()
            let entries = (0..<4).map { offset in
                Entry(date: now.addingTimeInterval(Double(offset) * 900))
            }
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }
}

@main
struct KairosWidgetsBundle: WidgetBundle {
    var body: some Widget {
        KairosFocusLiveActivity()
        KairosHomeWidget()
    }
}
