import SwiftUI
import UIKit

struct CalendarView: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(\.scenePhase) private var scenePhase
    @State private var calendarManager = KairosCalendarManager()
    @State private var selectedDate = Date()
    @State private var message: String?
    @State private var showingMessage = false

    private var events: [KairosScheduleEvent] {
        (planRepo.currentPlan?.scheduleEvents ?? []).sorted { $0.day == $1.day ? $0.start < $1.start : $0.day < $1.day }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    DatePicker("Schedule start", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding(14)
                        .kairosCard(cornerRadius: 24)
                    calendarAccessCard
                    if events.isEmpty { emptyState } else { scheduleList }
                }
                .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 30)
            }
            .kairosBackground()
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Calendar", isPresented: $showingMessage) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
            .onAppear { calendarManager.refreshAuthorizationState() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                calendarManager.refreshAuthorizationState()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Plan your time").font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Turn your Kairos study schedule into real calendar events.").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var calendarAccessCard: some View {
        HStack(spacing: 12) {
            Image(systemName: calendarManager.authorizationState == .authorized ? "checkmark.circle.fill" : "calendar.badge.plus")
                .font(.title2).foregroundStyle(KairosColors.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(calendarManager.authorizationState == .authorized ? "Apple Calendar connected" : "Connect Apple Calendar").font(.subheadline.weight(.semibold))
                Text(calendarManager.authorizationState == .authorized ? "You can add Kairos sessions to your calendar." : "Kairos only asks when you choose to export a session.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if calendarManager.authorizationState == .notDetermined {
                Button("Allow") { requestCalendarAccess() }.buttonStyle(.glassProminent).tint(KairosColors.accent)
            } else if calendarManager.authorizationState == .denied {
                Button("Settings", systemImage: "gear") { openSystemSettings() }.buttonStyle(.glass)
            }
        }
        .padding(16).kairosCard(cornerRadius: 22)
    }

    private var scheduleList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Study sessions").font(.headline)
                Spacer()
                if calendarManager.authorizationState == .authorized {
                    Button("Add all") { exportAll() }.buttonStyle(.glass).tint(KairosColors.accent)
                }
            }
            ForEach(Array(events.enumerated()), id: \.element.id) { _, event in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title).font(.subheadline.weight(.semibold))
                        Text("Day \(event.day) · \(event.start)–\(event.end) · \(event.category)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if calendarManager.authorizationState == .authorized {
                        Button { export(event) } label: { Image(systemName: "calendar.badge.plus") }
                            .buttonStyle(.glass).accessibilityLabel("Add \(event.title) to Calendar")
                    }
                }
                .padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock").font(.system(size: 34)).foregroundStyle(KairosColors.accent)
            Text("No scheduled sessions").font(.headline)
            Text("Ask the AI Helper to create a study plan and its schedule will appear here.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(30).kairosCard(cornerRadius: 24)
    }

    private func requestCalendarAccess() {
        Task {
            let granted = await calendarManager.requestAccess()
            if !granted { show("Calendar access was not granted. You can enable it later in iOS Settings.") }
        }
    }

    private func export(_ event: KairosScheduleEvent) {
        guard let dates = dates(for: event) else { show("This session has an invalid time format."); return }
        do { _ = try calendarManager.addEvent(title: event.title, start: dates.start, end: dates.end, notes: "Created from Kairos · \(event.category)"); show("Added “\(event.title)” to Apple Calendar.") }
        catch { show(error.localizedDescription) }
    }

    private func exportAll() {
        var added = 0
        for event in events {
            guard let dates = dates(for: event) else { continue }
            do { _ = try calendarManager.addEvent(title: event.title, start: dates.start, end: dates.end, notes: "Created from Kairos · \(event.category)"); added += 1 } catch { break }
        }
        show(added == events.count ? "Added \(added) Kairos sessions to Apple Calendar." : "Added \(added) of \(events.count) sessions. Some could not be exported.")
    }

    private func dates(for event: KairosScheduleEvent) -> (start: Date, end: Date)? {
        let partsStart = event.start.split(separator: ":").compactMap { Int($0) }
        let partsEnd = event.end.split(separator: ":").compactMap { Int($0) }
        guard partsStart.count == 2, partsEnd.count == 2,
              (0...23).contains(partsStart[0]), (0...59).contains(partsStart[1]),
              (0...23).contains(partsEnd[0]), (0...59).contains(partsEnd[1]) else { return nil }
        let dayOffset = max(event.day - 1, 0)
        let base = Calendar.current.date(byAdding: .day, value: dayOffset, to: Calendar.current.startOfDay(for: selectedDate)) ?? selectedDate
        let start = Calendar.current.date(bySettingHour: partsStart[0], minute: partsStart[1], second: 0, of: base)
        let end = Calendar.current.date(bySettingHour: partsEnd[0], minute: partsEnd[1], second: 0, of: base)
        guard let start, let end, end > start else { return nil }
        return (start, end)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func show(_ text: String) { message = text; showingMessage = true }
}

#Preview { CalendarView().environment(StudyPlanRepository()) }
