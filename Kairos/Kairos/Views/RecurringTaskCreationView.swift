import SwiftUI

struct RecurringTaskCreationView: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(\.dismiss) private var dismiss
    let sectionID: String
    @State private var title = ""
    @State private var repeats = false
    @State private var rule = KairosRepeatRule(startDate: "")
    @State private var calendar = Calendar(identifier: .gregorian)
    @State private var ownerScope: String?
    @State private var initialized = false
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var busy = false
    @State private var error: String?
    @State private var preview: KairosRecurringEditPreview?
    @State private var reviewed: KairosRecurringEditRequest?
    private var request: KairosRecurringEditRequest { .init(scope: "create", day: rule.startDate, rule: rule, title: title, startTime: rule.mode == "fixed" ? clock(startTime) : nil, endTime: rule.mode == "fixed" ? clock(endTime) : nil) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Task title", text: $title).textFieldStyle(.roundedBorder)
                    Toggle("Repeat", isOn: $repeats)
                    if repeats {
                        KairosRepeatFields(rule: $rule, calendar: calendar)
                        if rule.mode == "fixed" {
                            DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                            DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                        }
                        Button("Preview dates") { review() }.buttonStyle(.bordered)
                        if let preview, reviewed == request {
                            Text("First dates (up to five years)").font(.headline)
                            Text(preview.after.map(\.date).joined(separator: ", ").isEmpty ? "No dates in this sample" : preview.after.map(\.date).joined(separator: ", ")).font(.subheadline)
                        }
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    if busy { ProgressView("Saving…") }
                }.padding(20).disabled(busy)
            }.kairosBackground().navigationTitle("New task").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { save() }.disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ownerScope == nil || ownerScope != planRepo.searchScope || (repeats && reviewed != request))
                    }
                }.interactiveDismissDisabled()
        }.environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
            .task {
                guard !initialized else { return }; initialized = true
                calendar.timeZone = TimeZone(identifier: profileRepo.profile?.timezone ?? "") ?? .current
                let date = Date(); rule.startDate = KairosDate.dayKey(for: date, timeZone: calendar.timeZone)
                rule.weekdays = [calendar.component(.weekday, from: date) - 1]; rule.month = calendar.component(.month, from: date); rule.monthDay = calendar.component(.day, from: date)
                startTime = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
                endTime = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: date) ?? date
                ownerScope = planRepo.searchScope
            }
    }
    private func clock(_ date: Date) -> String { let p = calendar.dateComponents([.hour, .minute], from: date); return KairosScheduleProjection.clock((p.hour ?? 0) * 60 + (p.minute ?? 0)) }
    private func review() {
        guard !busy, ownerScope != nil, ownerScope == planRepo.searchScope else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: ["id": "new-preview", "title": title])
            let baseline = KairosSeriesBaseline(boardID: "preview", sectionID: sectionID, taskID: "new-preview", taskJSON: String(decoding: data, as: UTF8.self))
            preview = try KairosRecurringEdit.preview(baseline, request: request); reviewed = request; error = nil
        } catch { error = error.localizedDescription; reviewed = nil }
    }
    private func save() {
        guard !busy, let ownerScope, ownerScope == planRepo.searchScope, !repeats || reviewed == request else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            guard ownerScope == planRepo.searchScope else { return }
            let saved = repeats ? await planRepo.createRecurringTask(sectionID: sectionID, title: title, rule: rule, scope: ownerScope, startTime: request.startTime, endTime: request.endTime) : await planRepo.addTask(sectionID: sectionID, title: title)
            guard ownerScope == planRepo.searchScope else { return }
            if saved { dismiss() } else { error = planRepo.errorMessage ?? "Could not save. Your draft is still here." }
        }
    }
}
