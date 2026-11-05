import SwiftUI

struct MobileTaskScheduler: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(\.dismiss) private var dismiss
    let entry: ScheduleTaskEntry
    let calendar: Calendar
    @State private var date: Date
    @State private var time: Date
    @State private var duration: Int
    @State private var timed: Bool
    @State private var saving = false
    @State private var error: String?
    init(entry: ScheduleTaskEntry, selectedDate: Date, calendar: Calendar) {
        self.entry = entry; self.calendar = calendar
        let day = entry.task.date.flatMap { KairosScheduleDates.parse($0, calendar: calendar) } ?? selectedDate
        _date = State(initialValue: day)
        let minutes = KairosScheduleProjection.minutes(entry.task.startTime) ?? 9 * 60
        _time = State(initialValue: calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day)
        _duration = State(initialValue: KairosScheduleProjection.duration(entry.task))
        _timed = State(initialValue: entry.task.startTime != nil || entry.task.date == nil)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(entry.task.title).font(.headline); DatePicker("Date", selection: $date, displayedComponents: .date); Toggle("Set time", isOn: $timed) }
                if timed { DatePicker("Start", selection: $time, displayedComponents: .hourAndMinute); Stepper("Duration: \(duration) min", value: $duration, in: 1...1440, step: 5) }
                Button("Remove from schedule", role: .destructive) { save(removing: true) }
                if let error { Text(error).foregroundStyle(.red) }
            }.disabled(saving).interactiveDismissDisabled()
            .navigationTitle("Schedule task").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(removing: false) }.disabled(saving) }
            }
        }.environment(\.timeZone, calendar.timeZone).environment(\.calendar, calendar)
    }
    private func save(removing: Bool) {
        guard !saving else { return }
        let parts = calendar.dateComponents([.hour, .minute], from: time), start = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
        guard removing || !timed || start + duration <= 1440 else { error = "Choose a duration that ends by midnight."; return }
        var patch = KairosTaskPatch()
        patch.date = .set(removing ? nil : KairosDate.dayKey(for: date, timeZone: calendar.timeZone))
        patch.startTime = .set(removing || !timed ? nil : KairosScheduleProjection.clock(start))
        patch.endTime = .set(removing || !timed ? nil : KairosScheduleProjection.clock(start + duration))
        saving = true
        Task { let saved = await planRepo.updateTask(taskID: entry.id, patch: patch, expected: entry.task); saving = false; if saved { dismiss() } else { error = planRepo.errorMessage } }
    }
}

struct MobileScheduleCreator: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(\.dismiss) private var dismiss
    let calendar: Calendar
    @State private var date: Date
    @State private var time: Date
    @State private var title = ""
    @State private var sectionID = ""
    @State private var timed = true
    @State private var duration = 60
    @State private var saving = false
    @State private var error: String?
    init(selectedDate: Date, calendar: Calendar) {
        self.calendar = calendar; _date = State(initialValue: selectedDate)
        _time = State(initialValue: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate)
    }
    private var sections: [(id: String, title: String)] {
        (planRepo.currentPlan?.boards ?? []).filter { !$0.archived }.flatMap { board in board.sections.filter { !$0.archived }.map { (id: $0.id, title: "\(board.title) / \($0.title)") } }
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Task name", text: $title)
                if sections.isEmpty { Text("Create a board and section in Boards before adding a task.").foregroundStyle(.secondary) }
                Picker("Section", selection: $sectionID) { ForEach(sections, id: \.id) { Text($0.title).tag($0.id) } }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Toggle("Set time", isOn: $timed)
                if timed { DatePicker("Start", selection: $time, displayedComponents: .hourAndMinute); Stepper("Duration: \(duration) min", value: $duration, in: 5...1440, step: 5) }
                if let error { Text(error).foregroundStyle(.red) }
            }.disabled(saving).interactiveDismissDisabled()
            .navigationTitle("New task").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { save() }.disabled(saving || sectionID.isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.onAppear { sectionID = sections.first?.id ?? "" }
        }.environment(\.timeZone, calendar.timeZone).environment(\.calendar, calendar)
    }
    private func save() {
        guard !saving else { return }
        let parts = calendar.dateComponents([.hour, .minute], from: time), start = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
        guard !timed || start + duration <= 1440 else { error = "Choose a duration that ends by midnight."; return }
        saving = true
        Task {
            let saved = await planRepo.addScheduledTask(sectionID: sectionID, title: title, day: KairosDate.dayKey(for: date, timeZone: calendar.timeZone), start: timed ? KairosScheduleProjection.clock(start) : nil, end: timed ? KairosScheduleProjection.clock(start + duration) : nil)
            saving = false; if saved { dismiss() } else { error = planRepo.errorMessage }
        }
    }
}

struct MobileEventDetails: View {
    let event: KairosEventSegment
    let calendar: Calendar
    @Environment(\.dismiss) private var dismiss
    @State private var calendarManager = KairosCalendarManager()
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(event.title).font(.headline); LabeledContent("Date", value: event.date); LabeledContent("Time", value: "\(KairosScheduleProjection.clock(event.startMin))–\(KairosScheduleProjection.clock(event.endMin))"); LabeledContent("Category", value: event.category) }
                if event.readOnly { Text("This event is managed by its connected calendar.").font(.footnote).foregroundStyle(.secondary) }
                Button("Export to Apple Calendar", systemImage: "calendar.badge.plus") {
                    Task {
                        guard await calendarManager.requestAccess() else { message = "Allow Calendar access in iOS Settings to export."; return }
                        guard let day = KairosScheduleDates.parse(event.date, calendar: calendar), let start = calendar.date(byAdding: .minute, value: event.startMin, to: day), let end = calendar.date(byAdding: .minute, value: event.endMin, to: day) else { return }
                        do { let added = try calendarManager.addEventIfNeeded(title: event.title, start: start, end: end, notes: "Exported from Kairos"); message = added ? "Saved to Apple Calendar." : "Already in Apple Calendar." } catch { message = error.localizedDescription }
                    }
                }
                if let message { Text(message).font(.footnote) }
            }.navigationTitle("Event details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

enum KairosScheduleDates {
    static func parse(_ key: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: key), formatter.string(from: date) == key else { return nil }
        return date
    }
}
