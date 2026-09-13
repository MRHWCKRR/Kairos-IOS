import SwiftUI

struct ScheduleView: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @State private var calendarManager = KairosCalendarManager()
    @State private var showingCalendarAccess = false

    private var events: [KairosScheduleEvent] {
        (planRepo.currentPlan?.scheduleEvents ?? []).sorted {
            if $0.day != $1.day { return $0.day < $1.day }
            return $0.start < $1.start
        }
    }

    private var groupedEvents: [(day: Int, events: [KairosScheduleEvent])] {
        Dictionary(grouping: events, by: \.day)
            .keys.sorted()
            .map { day in (day: day, events: events.filter { $0.day == day }) }
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
            .toolbar {
                if !events.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingCalendarAccess = true } label: {
                            Image(systemName: "calendar.badge.plus")
                        }
                        .accessibilityLabel("Add schedule to Apple Calendar")
                    }
                }
            }
            .sheet(isPresented: $showingCalendarAccess) {
                CalendarAccessSheet(calendarManager: calendarManager, events: events)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .task { calendarManager.refreshAuthorizationState() }
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
                Text("Study schedule").font(.headline)
                Text(events.isEmpty ? "Generate a plan with Kairos AI to fill your week." : "Your plan, organised by study day.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .kairosCard()
    }

    private func daySection(_ day: Int, events: [KairosScheduleEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dayTitle(day)).font(.headline.weight(.semibold)).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    scheduleRow(event)
                    if index < events.count - 1 { Divider().padding(.leading, 68) }
                }
            }
            .kairosCard()
        }
    }

    private func scheduleRow(_ event: KairosScheduleEvent) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 3) {
                Text(event.start).font(.caption.weight(.bold))
                Text(event.end).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 52, alignment: .leading)
            Capsule().fill(KairosColors.accent.opacity(0.8)).frame(width: 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(event.title).font(.subheadline.weight(.semibold))
                Text(event.category.capitalized).font(.caption).foregroundStyle(KairosColors.accent)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus").font(.system(size: 36)).foregroundStyle(KairosColors.accent)
            Text("Nothing scheduled yet").font(.headline)
            Text("Use the AI Helper to create a study plan. Its scheduled sessions will appear here automatically.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 330)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 52).kairosCard()
    }

    private func dayTitle(_ day: Int) -> String { "Day \(day)" }
}

private struct CalendarAccessSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var calendarManager: KairosCalendarManager
    let events: [KairosScheduleEvent]
    @State private var exportError: String?
    @State private var exportedCount = 0

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "calendar.badge.plus").font(.system(size: 42)).foregroundStyle(KairosColors.accent)
                Text("Apple Calendar").font(.title2.weight(.bold))
                Text("Add your Kairos study sessions to Apple Calendar. Day 1 starts today, with later days following automatically.")
                    .font(.body).foregroundStyle(.secondary)

                switch calendarManager.authorizationState {
                case .authorized:
                    Label("Calendar access is enabled", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Add \(events.count) Sessions to Calendar") { exportEvents() }
                        .buttonStyle(.glassProminent).tint(KairosColors.accent)
                    if exportedCount > 0 {
                        Text("Added \(exportedCount) sessions.").font(.subheadline).foregroundStyle(.secondary)
                    }
                case .denied, .restricted:
                    Label("Calendar access is unavailable", systemImage: "xmark.circle").foregroundStyle(.secondary)
                case .notDetermined:
                    Button("Allow Calendar Access") {
                        Task { _ = await calendarManager.requestAccess() }
                    }
                    .buttonStyle(.glassProminent).tint(KairosColors.accent)
                }

                if let exportError {
                    Text(exportError).font(.footnote).foregroundStyle(.red)
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Calendar").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private func exportEvents() {
        exportError = nil
        var added = 0
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: .now)

        do {
            for event in events {
                guard let start = date(for: event.start, day: event.day, base: base),
                      let end = date(for: event.end, day: event.day, base: base), end > start else { continue }
                _ = try calendarManager.addEvent(
                    title: event.title,
                    start: start,
                    end: end,
                    notes: "Added from Kairos • \(event.category.capitalized)"
                )
                added += 1
            }
            exportedCount = added
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func date(for time: String, day: Int, base: Date) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, day > 0, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        guard let targetDay = Calendar.current.date(byAdding: .day, value: day - 1, to: base) else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: targetDay)
    }
}

#Preview {
    ScheduleView().environment(StudyPlanRepository())
}
