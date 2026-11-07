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
    @State private var busy = false
    @State private var error: String?
    @State private var preview: KairosRecurringEditPreview?
    @State private var reviewed: KairosRecurringEditRequest?
    private var request: KairosRecurringEditRequest { .init(scope: "create", day: rule.startDate, rule: rule, title: title, startTime: nil, endTime: nil) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Task title", text: $title).textFieldStyle(.roundedBorder)
                    Toggle("Repeat", isOn: $repeats)
                    if repeats {
                        KairosRepeatFields(rule: $rule, calendar: calendar)
                        Text("You can set the series time from task details after creation.").font(.caption).foregroundStyle(.secondary)
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
                ownerScope = planRepo.searchScope
            }
    }
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
            let saved = repeats ? await planRepo.createRecurringTask(sectionID: sectionID, title: title, rule: rule, scope: ownerScope) : await planRepo.addTask(sectionID: sectionID, title: title)
            guard ownerScope == planRepo.searchScope else { return }
            if saved { dismiss() } else { error = planRepo.errorMessage ?? "Could not save. Your draft is still here." }
        }
    }
}
