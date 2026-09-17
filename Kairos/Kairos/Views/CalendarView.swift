import SwiftUI
import UIKit

struct CalendarView: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(\.scenePhase) private var scenePhase
    @State private var calendarManager = KairosCalendarManager()
    @State private var selectedDate = Date()
    @State private var message: String?
    @State private var showingMessage = false

    private var selectedKey: String { Self.dateKey(selectedDate) }
    private var scheduledTasks: [KairosTask] {
        (planRepo.currentPlan?.boards ?? []).flatMap { $0.sections.filter { !$0.archived } }
            .flatMap { $0.tasks.filter { !$0.archived && !$0.completed && $0.date == selectedKey } }
            .sorted { ($0.dueTime ?? "99:99") < ($1.dueTime ?? "99:99") }
    }
    private var events: [KairosScheduleEvent] {
        (planRepo.currentPlan?.scheduleEvents ?? []).sorted { $0.day == $1.day ? $0.start < $1.start : $0.day < $1.day }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    DatePicker("Selected date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical).padding(14).kairosCard(cornerRadius: 24)
                    calendarAccessCard
                    if !scheduledTasks.isEmpty { taskScheduleList }
                    if !events.isEmpty { studySessionList }
                    if scheduledTasks.isEmpty && events.isEmpty { emptyState }
                }
                .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 30)
            }
            .kairosBackground()
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Calendar", isPresented: $showingMessage) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
            .onAppear { calendarManager.refreshAuthorizationState() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { calendarManager.refreshAuthorizationState() } }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Plan your time").font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Tasks with a due date automatically appear on that day.").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var calendarAccessCard: some View {
        HStack(spacing: 12) {
            Image(systemName: calendarManager.authorizationState == .authorized ? "checkmark.circle.fill" : "calendar.badge.plus")
                .font(.title2).foregroundStyle(KairosColors.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(calendarManager.authorizationState == .authorized ? "Apple Calendar connected" : "Connect Apple Calendar").font(.subheadline.weight(.semibold))
                Text(calendarManager.authorizationState == .authorized ? "Export a task or study session when you want it in Apple Calendar." : "Kairos keeps scheduling in-app until you choose to export.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if calendarManager.authorizationState == .notDetermined {
                Button("Allow") { requestCalendarAccess() }.buttonStyle(.glassProminent).tint(KairosColors.accent)
            } else if calendarManager.authorizationState == .denied {
                Button("Settings", systemImage: "gear") { openSystemSettings() }.buttonStyle(.glass)
            }
        }.padding(16).kairosCard(cornerRadius: 22)
    }

    private var taskScheduleList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tasks for \(selectedDate.formatted(.dateTime.month(.abbreviated).day()))").font(.headline)
                Spacer()
                Text("\(scheduledTasks.count)").font(.caption.weight(.bold)).foregroundStyle(KairosColors.accent)
            }
            ForEach(scheduledTasks) { task in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle").foregroundStyle(KairosColors.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title).font(.subheadline.weight(.semibold))
                        Text(task.dueTime.map { "Due \($0)" } ?? "Due today").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if calendarManager.authorizationState == .authorized {
                        Button { export(task) } label: { Image(systemName: "calendar.badge.plus") }.buttonStyle(.glass).accessibilityLabel("Add \(task.title) to Apple Calendar")
                    }
                }
                .padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var studySessionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Study sessions").font(.headline)
                Spacer()
                if calendarManager.authorizationState == .authorized { Button("Add all") { exportAll() }.buttonStyle(.glass).tint(KairosColors.accent) }
            }
            ForEach(Array(events.enumerated()), id: \.element.id) { _, event in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title).font(.subheadline.weight(.semibold))
                        Text("Day \(event.day) · \(event.start)–\(event.end) · \(event.category)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if calendarManager.authorizationState == .authorized { Button { export(event) } label: { Image(systemName: "calendar.badge.plus") }.buttonStyle(.glass) }
                }
                .padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock").font(.system(size: 34)).foregroundStyle(KairosColors.accent)
            Text("Nothing scheduled for this date").font(.headline)
            Text("Set a due date on any task and it will appear here automatically.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(30).kairosCard(cornerRadius: 24)
    }

    private func requestCalendarAccess() {
        Task { let granted = await calendarManager.requestAccess(); if !granted { show("Calendar access was not granted. You can enable it later in iOS Settings.") } }
    }

    private func export(_ task: KairosTask) {
        let start = taskDate(task)
        let end = start.addingTimeInterval(30 * 60)
        do {
            let created = try calendarManager.addEventIfNeeded(title: task.title, start: start, end: end, notes: "Created from Kairos · task")
            show(created ? "Added “\(task.title)” to Apple Calendar." : "“\(task.title)” is already in Apple Calendar.")
        } catch { show(error.localizedDescription) }
    }

    private func export(_ event: KairosScheduleEvent) {
        guard let dates = dates(for: event) else { show("This session has an invalid time format."); return }
        do {
            let created = try calendarManager.addEventIfNeeded(title: event.title, start: dates.start, end: dates.end, notes: "Created from Kairos · \(event.category)")
            show(created ? "Added “\(event.title)” to Apple Calendar." : "“\(event.title)” is already in Apple Calendar.")
        } catch { show(error.localizedDescription) }
    }

    private func exportAll() {
        var added = 0
        for event in events {
            guard let dates = dates(for: event) else { continue }
            if (try? calendarManager.addEventIfNeeded(title: event.title, start: dates.start, end: dates.end, notes: "Created from Kairos · \(event.category)")) == true { added += 1 }
        }
        show("Added \(added) Kairos study sessions to Apple Calendar.")
    }

    private func taskDate(_ task: KairosTask) -> Date {
        let f = DateFormatter(); f.calendar = .current; f.dateFormat = "yyyy-MM-dd"
        let base = task.date.flatMap { f.date(from: $0) } ?? selectedDate
        if let time = task.dueTime {
            let parts = time.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 { return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: base) ?? base }
        }
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? base
    }

    private func dates(for event: KairosScheduleEvent) -> (start: Date, end: Date)? {
        let a = event.start.split(separator: ":").compactMap { Int($0) }
        let b = event.end.split(separator: ":").compactMap { Int($0) }
        guard a.count == 2, b.count == 2, (0...23).contains(a[0]), (0...59).contains(a[1]), (0...23).contains(b[0]), (0...59).contains(b[1]) else { return nil }
        let base = Calendar.current.date(byAdding: .day, value: max(event.day - 1, 0), to: Calendar.current.startOfDay(for: selectedDate)) ?? selectedDate
        guard let start = Calendar.current.date(bySettingHour: a[0], minute: a[1], second: 0, of: base), let end = Calendar.current.date(bySettingHour: b[0], minute: b[1], second: 0, of: base), end > start else { return nil }
        return (start, end)
    }

    private static func dateKey(_ date: Date) -> String { let f = DateFormatter(); f.calendar = .current; f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    private func openSystemSettings() { guard let url = URL(string: UIApplication.openSettingsURLString) else { return }; UIApplication.shared.open(url) }
    private func show(_ text: String) { message = text; showingMessage = true }
}

#Preview { CalendarView().environment(StudyPlanRepository()) }
