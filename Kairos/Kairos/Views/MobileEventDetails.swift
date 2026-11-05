import SwiftUI

struct MobileEventDetails: View {
    let event: KairosEventSegment?
    let calendar: Calendar
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(\.dismiss) private var dismiss
    @State private var calendarManager = KairosCalendarManager()
    @State private var title: String
    @State private var date: Date
    @State private var start: Date
    @State private var end: Date
    @State private var category: String
    @State private var weekly = false
    @State private var saving = false
    @State private var message: String?
    @State private var confirmingDelete = false
    @State private var revision: UUID

    init(event: KairosEventSegment?, selectedDate: Date, calendar: Calendar, revision: UUID) {
        self.event = event; self.calendar = calendar
        let day = event.flatMap { KairosScheduleDates.parse($0.effectiveDate, calendar: calendar) } ?? selectedDate
        let a = KairosScheduleProjection.minutes(event?.startTime) ?? 9 * 60
        let b = KairosScheduleProjection.minutes(event?.endTime) ?? 10 * 60
        _title = State(initialValue: event?.title ?? ""); _category = State(initialValue: event?.category ?? "other")
        _date = State(initialValue: day)
        _start = State(initialValue: calendar.date(bySettingHour: a / 60, minute: a % 60, second: 0, of: day) ?? day)
        _end = State(initialValue: calendar.date(bySettingHour: b / 60, minute: b % 60, second: 0, of: day) ?? day)
        _revision = State(initialValue: revision)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Event name", text: $title)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
                    Picker("Category", selection: $category) {
                        ForEach(["sleep", "class", "tutoring", "training", "other"], id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    if event == nil { Toggle("Repeats weekly", isOn: $weekly) }
                }.disabled(event?.readOnly == true)
                if event?.occurrenceDate != nil { Text("Changes apply to this occurrence only.").font(.footnote).foregroundStyle(.secondary) }
                if event?.readOnly == true { Text("This event is managed by its connected calendar.").font(.footnote).foregroundStyle(.secondary) }
                if event != nil { Button("Export to Apple Calendar", systemImage: "calendar.badge.plus") { export() } }
                if event != nil && event?.readOnly != true { Button(event?.occurrenceDate == nil ? "Delete event" : "Skip this occurrence", role: .destructive) { confirmingDelete = true } }
                if let message { Text(message).font(.footnote) }
            }.disabled(saving).interactiveDismissDisabled()
            .navigationTitle(event == nil ? "New fixed event" : "Event details").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { PlannerSearchButton().disabled(saving) }
                ToolbarItem(placement: .cancellationAction) { Button(event?.readOnly == true ? "Done" : "Cancel") { dismiss() }.disabled(saving) }
                if event?.readOnly != true { ToolbarItem(placement: .confirmationAction) { Button("Save") { save(removing: false) }.disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
            }
            .confirmationDialog("Remove this event from the schedule?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { save(removing: true) }
            }
        }.environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
    }
    private func clock(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return KairosScheduleProjection.clock((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }
    private func save(removing: Bool) {
        guard !saving else { return }; saving = true; message = nil
        let edit = KairosEventEdit(eventID: event?.eventID, occurrenceDate: event?.occurrenceDate, title: title, date: KairosDate.dayKey(for: date, timeZone: calendar.timeZone), start: clock(start), end: clock(end), category: category, weeklyDay: weekly ? calendar.component(.weekday, from: date) - 1 : nil, removing: removing)
        Task { let saved = await planRepo.editScheduleEvent(edit, revision: revision); saving = false; if saved { dismiss() } else { message = planRepo.errorMessage ?? "Could not save. Your edits are still here." } }
    }
    private func export() {
        guard !saving, let event else { return }
        saving = true
        Task {
            defer { saving = false }
            guard await calendarManager.requestAccess() else { message = "Allow Calendar access in iOS Settings to export."; return }
            guard let dates = KairosScheduleProjection.eventDates(day: event.effectiveDate, start: event.startTime, end: event.endTime, calendar: calendar) else { message = "This event's times cannot be exported."; return }
            do { let added = try calendarManager.addEventIfNeeded(title: event.title, start: dates.start, end: dates.end, notes: "Exported from Kairos"); message = added ? "Saved to Apple Calendar." : "Already in Apple Calendar." } catch { message = error.localizedDescription }
        }
    }
}
