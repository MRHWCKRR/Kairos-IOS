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
            HStack(spacing: 12) {
                Image(systemName: context.state.isRunning ? "timer" : "pause.circle")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kairos Focus")
                        .font(.headline)
                    Text(timerText(context))
                        .font(.system(.title3, design: .monospaced))
                        .monospacedDigit()
                }
                Spacer()
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer")
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(timerText(context))
                        .font(.system(.headline, design: .monospaced))
                        .monospacedDigit()
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                Text(timerText(context))
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }

    private func timerText(_ context: ActivityViewContext<FocusTimerAttributes>) -> String {
        if context.state.isRunning {
            return context.state.elapsedSeconds.formatted(.number.precision(.integerLength(2)))
        }
        return context.state.elapsedSeconds.formatted(.number.precision(.integerLength(2)))
    }
}

struct KairosHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KairosHomeWidget", provider: Provider()) { entry in
            VStack(alignment: .leading, spacing: 6) {
                Text("Kairos")
                    .font(.headline)
                Text("Focus Timer")
                    .font(.subheadline)
                Text(entry.date, style: .time)
                    .font(.title2.monospacedDigit())
            }
            .padding()
        }
        .configurationDisplayName("Kairos")
        .description("Quick access to your Kairos focus timer.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    struct Entry: TimelineEntry {
        let date: Date
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: .now) }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(Entry(date: .now))
        }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            let entry = Entry(date: .now)
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(900))))
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
