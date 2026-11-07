import SwiftUI

struct KairosRepeatFields: View {
    @Binding var rule: KairosRepeatRule
    let calendar: Calendar
    var startEditable = true
    private let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Repeats", selection: $rule.frequency) {
                Text("Daily").tag("daily"); Text("Weekly").tag("weekly")
                Text("Monthly").tag("monthly"); Text("Yearly").tag("yearly")
            }
            Stepper("Every \(rule.interval) \(unit)", value: $rule.interval, in: 1...999)
            if startEditable { DatePicker("Starts", selection: dateBinding(ending: false), displayedComponents: .date) }
            if rule.frequency == "weekly" {
                Button("Every weekday") { rule.weekdays = [1, 2, 3, 4, 5] }
                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                    Toggle(day, isOn: Binding(get: { rule.weekdays.contains(index) }, set: { selected in
                        if selected { rule.weekdays = Array(Set(rule.weekdays + [index])).sorted() }
                        else { rule.weekdays.removeAll { $0 == index } }
                    }))
                }
            }
            if rule.frequency == "monthly" {
                Picker("Pattern", selection: Binding(get: { rule.monthlyMode ?? "date" }, set: { rule.monthlyMode = $0 })) {
                    Text("Day of month").tag("date"); Text("Weekday position").tag("weekdayPosition")
                }
                if rule.monthlyMode == "weekdayPosition" {
                    Picker("Position", selection: Binding(get: { rule.weekdayPosition ?? "first" }, set: { rule.weekdayPosition = $0 })) {
                        ForEach(["first", "second", "third", "fourth", "last"], id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    Picker("Weekday", selection: Binding(get: { rule.weekday ?? 1 }, set: { rule.weekday = $0 })) {
                        ForEach(Array(days.enumerated()), id: \.element) { Text($0.element).tag($0.offset) }
                    }
                }
            }
            if rule.frequency == "yearly" {
                Picker("Month", selection: Binding(get: { rule.month ?? 1 }, set: { rule.month = $0 })) {
                    ForEach(1...12, id: \.self) { Text(calendar.monthSymbols[$0 - 1]).tag($0) }
                }
            }
            if rule.frequency == "yearly" || (rule.frequency == "monthly" && rule.monthlyMode != "weekdayPosition") {
                Stepper("Day \(rule.monthDay ?? 1)", value: Binding(get: { rule.monthDay ?? 1 }, set: { rule.monthDay = $0 }), in: 1...31)
                Text("Months without that date are skipped.").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Scheduling", selection: $rule.mode) {
                Text("Flexible time").tag("flexible"); Text("Fixed time").tag("fixed")
            }
            Picker("Ends", selection: $rule.endType) {
                Text("Never").tag("never"); Text("On date").tag("date"); Text("After occurrences").tag("count")
            }
            if rule.endType == "date" { DatePicker("End date", selection: dateBinding(ending: true), displayedComponents: .date) }
            if rule.endType == "count" { Stepper("\(rule.count ?? 10) occurrences", value: Binding(get: { rule.count ?? 10 }, set: { rule.count = $0 }), in: 1...10000) }
        }.onChange(of: rule.endType) { _, value in
            if value == "date", rule.endDate == nil { rule.endDate = rule.startDate }
            if value == "count", rule.count == nil { rule.count = 10 }
        }
    }
    private var unit: String { ["daily": "day(s)", "weekly": "week(s)", "monthly": "month(s)", "yearly": "year(s)"][rule.frequency] ?? "days" }
    private func dateBinding(ending: Bool) -> Binding<Date> {
        Binding(get: { KairosScheduleDates.parse((ending ? rule.endDate : rule.startDate) ?? rule.startDate, calendar: calendar) ?? Date() }, set: {
            let key = KairosDate.dayKey(for: $0, timeZone: calendar.timeZone)
            if ending { rule.endDate = key } else { rule.startDate = key }
        })
    }
}

struct RecurringTaskEditor: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(\.dismiss) private var dismiss
    let taskID: String
    let occurrenceDate: String?
    @State private var baseline: KairosSeriesBaseline?
    @State private var ownerScope: String?
    @State private var calendar = Calendar(identifier: .gregorian)
    @State private var rule = KairosRepeatRule(startDate: "")
    @State private var title = ""
    @State private var scope = "series"
    @State private var logicalDate = ""
    @State private var recurring = false
    @State private var timed = false
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var busy = false
    @State private var error: String?
    @State private var preview: KairosRecurringEditPreview?
    @State private var reviewed: KairosRecurringEditRequest?
    private var request: KairosRecurringEditRequest {
        .init(scope: recurring ? scope : "create", day: recurring ? logicalDate : rule.startDate, rule: rule, title: title, startTime: timed ? clock(startTime) : nil, endTime: timed ? clock(endTime) : nil, allowCompleted: profileRepo.allowsCompletedRescheduling)
    }
    private var available: Bool { ownerScope != nil && ownerScope == planRepo.searchScope && baseline != nil && (try? planRepo.recurringEditorBaseline(taskID: taskID)) == baseline }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if baseline != nil {
                        TextField("Task title", text: $title).textFieldStyle(.roundedBorder)
                        if recurring {
                            Picker("Apply changes to", selection: $scope) {
                                Text("This occurrence").tag("occurrence")
                                Text("This and future").tag("future")
                                Text("Entire series").tag("series")
                            }
                            if scope != "series" {
                                DatePicker("Original occurrence date", selection: logicalBinding, displayedComponents: .date)
                                Text("Choose the original date, even if an occurrence was moved.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if scope != "occurrence" || !recurring {
                            KairosRepeatFields(rule: $rule, calendar: calendar, startEditable: scope != "future")
                        } else { Text("A single-occurrence edit leaves the repeat rule unchanged.").font(.footnote).foregroundStyle(.secondary) }
                        Toggle("Set time", isOn: $timed)
                        if timed {
                            DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                            DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                        }
                        Text("Completed, moved and progress-bearing occurrences keep their individual dates, times and progress.").font(.footnote).foregroundStyle(.secondary)
                        if !available { Text("This task changed or became unavailable. Your draft is retained; reopen the editor to review its latest version.").font(.footnote).foregroundStyle(.secondary) }
                        Button("Preview changes") { review() }.buttonStyle(.bordered).disabled(!available || busy)
                        if let preview, reviewed == request { previewCard(preview) }
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    if busy { ProgressView("Working…") }
                }.padding(20).disabled(busy)
            }.kairosBackground()
                .navigationTitle(recurring ? "Edit repeat" : "Make recurring")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button("Apply") { apply() }.disabled(busy || !available || reviewed != request) }
                }
                .interactiveDismissDisabled()
        }.environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
            .task { load() }
    }
    private var logicalBinding: Binding<Date> {
        Binding(get: { KairosScheduleDates.parse(logicalDate, calendar: calendar) ?? Date() }, set: { logicalDate = KairosDate.dayKey(for: $0, timeZone: calendar.timeZone) })
    }
    private func previewCard(_ value: KairosRecurringEditPreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review changes").font(.headline)
            Text(value.description).font(.subheadline)
            Text("Date sample: up to four occurrences within five years").font(.caption).foregroundStyle(.secondary)
            Text("Before: \(placements(value.before))").font(.footnote)
            Text("After: \(placements(value.after))").font(.footnote)
            if value.preserved > 0 { Text("\(value.preserved) individually adjusted or resolved occurrences keep their dates, times and progress.").font(.footnote) }
            Text("Apply saves this reviewed change. Cancel keeps the planner unchanged.").font(.caption).foregroundStyle(.secondary)
        }.padding(18).kairosCard(cornerRadius: 22)
    }
    private func placements(_ rows: [KairosRecurringEditPreview.Placement]) -> String {
        let text = rows.map { row in
            let time = row.startTime.map { KairosTimeDisplay.time($0, format: profileRepo.accessibilitySettings?.timeFormat ?? "12") } ?? "Flexible"
            return "\(row.date) \(time)"
        }.joined(separator: "; ")
        return text.isEmpty ? "None" : text
    }
    private func load() {
        guard baseline == nil, ownerScope == nil else { return }
        do {
            let value = try planRepo.recurringEditorBaseline(taskID: taskID), seed = try KairosRecurringEdit.seed(value, on: occurrenceDate)
            var captured = Calendar(identifier: .gregorian); captured.timeZone = TimeZone(identifier: profileRepo.profile?.timezone ?? "") ?? .current
            calendar = captured; recurring = seed.recurring; rule = seed.rule; title = seed.title
            if rule.startDate.isEmpty { rule.startDate = KairosDate.dayKey(for: Date(), timeZone: captured.timeZone) }
            let date = KairosScheduleDates.parse(rule.startDate, calendar: captured) ?? Date()
            if !seed.recurring { rule.weekdays = [captured.component(.weekday, from: date) - 1]; rule.monthDay = captured.component(.day, from: date); rule.month = captured.component(.month, from: date) }
            logicalDate = occurrenceDate ?? rule.startDate
            scope = seed.recurring && occurrenceDate != nil ? "occurrence" : "series"
            let a = KairosScheduleProjection.minutes(seed.startTime) ?? 540, b = KairosScheduleProjection.minutes(seed.endTime) ?? 600
            startTime = captured.date(bySettingHour: a / 60, minute: a % 60, second: 0, of: date) ?? date
            endTime = captured.date(bySettingHour: b / 60, minute: b % 60, second: 0, of: date) ?? date
            timed = seed.startTime != nil; ownerScope = planRepo.searchScope; baseline = value
        } catch { self.error = error.localizedDescription }
    }
    private func clock(_ date: Date) -> String { let p = calendar.dateComponents([.hour, .minute], from: date); return KairosScheduleProjection.clock((p.hour ?? 0) * 60 + (p.minute ?? 0)) }
    private func review() {
        guard let baseline, available, !busy else { return }
        let draft = request; busy = true; error = nil; reviewed = nil
        Task {
            defer { busy = false }
            do {
                let value = try await Task.detached { try KairosRecurringEdit.preview(baseline, request: draft) }.value
                guard available, request == draft else { return }
                preview = value; reviewed = draft
            } catch { self.error = error.localizedDescription }
        }
    }
    private func apply() {
        guard let baseline, let ownerScope, let reviewed, reviewed == request, available, !busy else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            guard available, reviewed == request else { return }
            if await planRepo.saveRecurringEdit(baseline: baseline, request: reviewed, scope: ownerScope) { dismiss() }
            else { error = planRepo.errorMessage ?? "Could not save. Your draft is still here." }
        }
    }
}
