import SwiftUI

struct OccurrenceDetailsView: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(\.dismiss) private var dismiss
    let occurrence: KairosRecurringOccurrence
    let calendar: Calendar

    // A one-time editor baseline: live snapshots must not replace unsaved steps.
    @State private var items: [KairosChecklistItem]
    @State private var status: String
    @State private var scheduledDate: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var timed: Bool
    @State private var saving = false
    @State private var error: String?

    init(occurrence: KairosRecurringOccurrence, calendar: Calendar = .current) {
        self.occurrence = occurrence
        self.calendar = calendar
        _items = State(initialValue: occurrence.task.checklist ?? [])
        _status = State(initialValue: occurrence.status)
        let day = KairosScheduleDates.parse(occurrence.displayDate, calendar: calendar) ?? Date()
        let a = KairosScheduleProjection.minutes(occurrence.startTime) ?? 9 * 60
        let b = KairosScheduleProjection.minutes(occurrence.endTime) ?? min(1439, a + 60)
        _scheduledDate = State(initialValue: day)
        _startTime = State(initialValue: calendar.date(bySettingHour: a / 60, minute: a % 60, second: 0, of: day) ?? day)
        _endTime = State(initialValue: calendar.date(bySettingHour: b / 60, minute: b % 60, second: 0, of: day) ?? day)
        _timed = State(initialValue: occurrence.startTime != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    details
                    Picker("Status", selection: $status) {
                        Text("Pending").tag("pending")
                        Text("Completed").tag("completed")
                        Text("Skipped").tag("skipped")
                    }.pickerStyle(.segmented)
                    VStack(spacing: 12) {
                        DatePicker("Occurrence date", selection: $scheduledDate, displayedComponents: .date)
                        Toggle("Set time", isOn: $timed)
                        if timed {
                            DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                            DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                        }
                    }.padding(18).kairosCard(cornerRadius: 22)
                    KairosChecklistEditor(items: $items, allowsCompletion: true)
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    if saving { ProgressView("Saving…") }
                }
                .padding(20)
                .disabled(saving)
            }
            .kairosBackground()
            .navigationTitle("Occurrence details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(saving || planRepo.isSaving)
                }
            }
            .interactiveDismissDisabled()
        }.environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(occurrence.task.title).font(.title2.weight(.bold))
            Text("Checklist changes apply only to this occurrence.")
                .font(.subheadline).foregroundStyle(.secondary)
            LabeledContent("Date", value: occurrence.displayDate)
            LabeledContent("Status", value: occurrence.status.capitalized)
            LabeledContent("Time", value: timeLabel)
            if occurrence.occurrenceDate != occurrence.displayDate {
                LabeledContent("Original date", value: occurrence.occurrenceDate)
            }
            if let notes = occurrence.task.notes, !notes.isEmpty {
                Text("Notes").font(.subheadline.weight(.semibold))
                Text(notes).font(.subheadline).textSelection(.enabled)
            }
            if let priority = occurrence.task.priority {
                LabeledContent("Priority", value: priority.capitalized)
            }
            if let minutes = occurrence.task.estimatedMinutes {
                LabeledContent("Estimate", value: "\(minutes) minutes")
            }
        }
        .padding(18).kairosCard(cornerRadius: 22)
    }

    private var timeLabel: String {
        guard let start = occurrence.startTime else { return "Flexible time" }
        if let end = occurrence.endTime { return "\(start)–\(end)" }
        return start
    }

    private func save() {
        guard !saving, !planRepo.isSaving else { return }
        do { try KairosChecklist.validate(items) }
        catch {
            self.error = "Give each step a title of 1–180 characters, with no more than 100 steps."
            return
        }
        let schedule = KairosOccurrenceSchedule(date: KairosDate.dayKey(for: scheduledDate, timeZone: calendar.timeZone), startTime: timed ? clock(startTime) : nil, endTime: timed ? clock(endTime) : nil)
        let original = KairosOccurrenceSchedule(date: occurrence.displayDate, startTime: occurrence.startTime, endTime: occurrence.endTime)
        guard items != (occurrence.task.checklist ?? []) || status != occurrence.status || schedule != original else { dismiss(); return }
        saving = true
        error = nil
        Task {
            let saved = await planRepo.saveOccurrenceDetails(occurrence, items: items, status: status, schedule: schedule == original ? nil : schedule)
            saving = false
            if saved { dismiss() }
            else { error = planRepo.errorMessage ?? "Could not save. Your checklist edits are still here." }
        }
    }
    private func clock(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return KairosScheduleProjection.clock((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }
}
