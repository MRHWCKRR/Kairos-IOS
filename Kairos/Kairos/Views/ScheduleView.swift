import SwiftUI

struct ScheduleView: View {
    @Environment(StudyPlanRepository.self) private var planRepo

    private var events: [KairosScheduleEvent] {
        (planRepo.currentPlan?.scheduleEvents ?? []).sorted {
            if $0.day != $1.day { return $0.day < $1.day }
            return $0.start < $1.start
        }
    }

    private var groupedEvents: [(day: Int, events: [KairosScheduleEvent])] {
        Dictionary(grouping: events, by: \.day)
            .keys.sorted()
            .map { day in
                (day: day, events: events.filter { $0.day == day })
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    header

                    if groupedEvents.isEmpty {
                        emptyState
                    } else {
                        ForEach(groupedEvents, id: \.day) { group in
                            daySection(group.day, events: group.events)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .kairosBackground()
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2.weight(.semibold))
                .foregroundStyle(KairosColors.accent)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Study schedule")
                    .font(.headline)
                Text(events.isEmpty ? "Generate a plan with Kairos AI to fill your week." : "Your plan, organised by study day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .kairosCard()
    }

    private func daySection(_ day: Int, events: [KairosScheduleEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dayTitle(day))
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    scheduleRow(event)
                    if index < events.count - 1 {
                        Divider().padding(.leading, 68)
                    }
                }
            }
            .kairosCard()
        }
    }

    private func scheduleRow(_ event: KairosScheduleEvent) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 3) {
                Text(event.start)
                    .font(.caption.weight(.bold))
                Text(event.end)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 52, alignment: .leading)

            Capsule()
                .fill(KairosColors.accent.opacity(0.8))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 5) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(event.category.capitalized)
                    .font(.caption)
                    .foregroundStyle(KairosColors.accent)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(KairosColors.accent)
            Text("Nothing scheduled yet")
                .font(.headline)
            Text("Use the AI Helper to create a study plan. Its scheduled sessions will appear here automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
        .kairosCard()
    }

    private func dayTitle(_ day: Int) -> String {
        switch day {
        case 1: return "Day 1"
        case 2: return "Day 2"
        case 3: return "Day 3"
        case 4: return "Day 4"
        case 5: return "Day 5"
        case 6: return "Day 6"
        case 7: return "Day 7"
        default: return "Day \(day)"
        }
    }
}

#Preview {
    ScheduleView()
        .environment(StudyPlanRepository())
}
