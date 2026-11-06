import SwiftUI

struct PlanningAccessibilityView: View {
    @Environment(UserProfileRepository.self) private var profileRepo
    @State private var seed: (stamp: String, value: KairosPlanningSettings)?
    var body: some View {
        Group {
            if let stamp = profileRepo.planningSettingsOwnerStamp, let seed, seed.stamp == stamp {
                PlanningSettingsEditor(initial: seed.value, ownerStamp: stamp).id(stamp)
            } else if profileRepo.isLoading { ProgressView("Loading settings.") }
            else {
                ContentUnavailableView { Label("Settings unavailable", sharedIcon: "exclamationmark.triangle") }
                description: { Text(profileRepo.planningSettingsError ?? profileRepo.errorMessage ?? "Wait for your verified account's settings to load.") }
                actions: { Button("Retry") { profileRepo.retryPlanningSettings() } }
            }
        }.navigationTitle("Accessibility")
            .onChange(of: profileRepo.planningSettingsOwnerStamp, initial: true) { _, stamp in
                seed = stamp.flatMap { owner in profileRepo.planningSettings.map { (owner, $0) } }
            }
            .onChange(of: profileRepo.planningSettings) { _, value in
                if seed == nil, let stamp = profileRepo.planningSettingsOwnerStamp, let value { seed = (stamp, value) }
            }
    }
}

private struct WorkWindowDraft: Identifiable {
    let id = UUID()
    var start: String
    var end: String
}
private struct WorkDayDraft: Identifiable {
    let id: Int
    var windows: [WorkWindowDraft]
}
private struct PlanningSettingsEditor: View {
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(\.dismiss) private var dismiss
    let ownerStamp: String
    // One-time baseline and local fields: live snapshots must not replace drafts.
    @State private var baseline: KairosPlanningSettings
    @State private var timezone: String
    @State private var timeFormat: String
    @State private var dailyLimit: String
    @State private var gap: Int
    @State private var rescheduleCompleted: Bool
    @State private var useWeekly: Bool
    @State private var days: [WorkDayDraft]
    @State private var error: String?
    @State private var showingZones = false
    @State private var confirmingDiscard = false
    @State private var confirmingReload = false

    init(initial: KairosPlanningSettings, ownerStamp: String) {
        self.ownerStamp = ownerStamp
        _baseline = State(initialValue: initial)
        _timezone = State(initialValue: initial.timezone); _timeFormat = State(initialValue: initial.timeFormat)
        _dailyLimit = State(initialValue: String(initial.dailyLimitMinutes)); _gap = State(initialValue: initial.gapMinutes)
        _rescheduleCompleted = State(initialValue: initial.rescheduleCompleted)
        _useWeekly = State(initialValue: initial.weeklyAvailability != nil)
        _days = State(initialValue: [1, 2, 3, 4, 5, 6, 0].map { day in
            WorkDayDraft(id: day, windows: (initial.weeklyAvailability?[String(day)] ?? (initial.weeklyAvailability == nil ? [.init(start: "07:00", end: "22:00")] : [])).map { WorkWindowDraft(start: $0.start, end: $0.end) })
        })
    }
    private var draft: KairosPlanningSettings {
        .init(timezone: timezone, timeFormat: timeFormat, dailyLimitMinutes: Int(dailyLimit) ?? -1, gapMinutes: gap,
              rescheduleCompleted: rescheduleCompleted,
              weeklyAvailability: useWeekly ? Dictionary(uniqueKeysWithValues: days.map { (String($0.id), $0.windows.map { KairosWorkWindow(start: $0.start, end: $0.end) }) }) : nil)
    }
    private var dirty: Bool { draft != baseline }
    private var saving: Bool { profileRepo.isSavingPlanningSettings || profileRepo.isReloadingPlanningSettings }
    var body: some View {
        Form {
            Section("Time") {
                Button { showingZones = true } label: { LabeledContent("Profile timezone", value: timezone.replacingOccurrences(of: "_", with: " ")) }
                Picker("Time format", selection: $timeFormat) {
                    Text("12-hour").tag("12"); Text("24-hour").tag("24")
                }
            }
            Section {
                LabeledContent("Daily task work limit (minutes)") {
                    TextField("0", text: $dailyLimit).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(minWidth: 60)
                        .accessibilityLabel("Daily task work limit in minutes")
                }
                Text("0 means no limit. Otherwise use 15–1440 minutes. Counts dated assignment sessions, including completed and locked work; gaps do not count.").font(.footnote).foregroundStyle(.secondary)
                Picker("Gap between planned sessions", selection: $gap) {
                    ForEach([0, 5, 10, 15], id: \.self) { Text($0 == 0 ? "None" : "\($0) minutes").tag($0) }
                }
                Toggle("Rescheduling completed tasks", isOn: $rescheduleCompleted)
            } header: { Text("Planning defaults") }
            footer: { Text("Completed-task rescheduling is off by default. Saving these preferences does not move tasks or change existing reviewed previews.") }
            Section {
                Toggle("Use saved weekly hours for planning", isOn: $useWeekly)
                Text(useWeekly ? "Times use \(timezone). Empty days are unavailable. Use up to four separate windows per day, ending on the same day." : "Without saved hours, planning uses 07:00–22:00 unless you choose custom hours.")
                    .font(.footnote).foregroundStyle(.secondary)
                if useWeekly, days.allSatisfy({ $0.windows.isEmpty }) {
                    Text("All days are unavailable. New plans will need custom hours.").font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text("Weekly availability") }
            if useWeekly {
                ForEach($days) { $day in
                    Section(dayName(day.id)) {
                        ForEach($day.windows) { $window in
                            let windowID = window.id
                            VStack(alignment: .leading) {
                                WorkWindowEditor(start: $window.start, end: $window.end, format: timeFormat)
                                Button("Remove window", role: .destructive) { day.windows.removeAll { $0.id == windowID } }
                            }
                        }
                        if day.windows.isEmpty { Text("Unavailable").foregroundStyle(.secondary) }
                        Button("Add window", sharedIcon: "plus") { day.windows.append(.init(start: "09:00", end: "17:00")) }
                            .disabled(day.windows.count >= 4)
                    }
                }
            }
            if let error {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("Reload saved values") { confirmingReload = true }
                }
            }
            if let error = profileRepo.planningReloadError { Text(error).foregroundStyle(.red) }
        }
        .disabled(saving)
        .navigationTitle("Accessibility").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true).interactiveDismissDisabled(dirty || saving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { confirmingDiscard = true } else { dismiss() } }.disabled(saving) }
            ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : "Save") { save() }.disabled(saving || !dirty) }
        }
        .confirmationDialog("Discard unsaved settings?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) { }
        }
        .sheet(isPresented: $showingZones) { PlanningTimezonePicker(selection: $timezone) }
        .confirmationDialog("Reload saved settings and discard this draft?", isPresented: $confirmingReload, titleVisibility: .visible) {
            Button("Reload saved values", role: .destructive) { profileRepo.retryPlanningSettings() }
            Button("Keep editing", role: .cancel) { }
        }
    }
    private func dayName(_ day: Int) -> String { ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][day] }
    private func save() {
        guard !saving else { return }; error = nil
        let current = draft
        do { try KairosPlanningSettingsStore.validate(current) }
        catch { self.error = error.localizedDescription; return }
        Task {
            let saved = await profileRepo.savePlanningSettings(expected: baseline, draft: current, ownerStamp: ownerStamp)
            if saved { dismiss() } else { error = profileRepo.errorMessage ?? "Could not save. Your edits are still here." }
        }
    }
}

private struct WorkWindowEditor: View {
    @Binding var start: String
    @Binding var end: String
    let format: String
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private func time(_ value: Binding<String>) -> Binding<Date> {
        Binding(get: { Date(timeIntervalSince1970: Double(KairosScheduleProjection.minutes(value.wrappedValue) ?? 0) * 60) }, set: { date in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            value.wrappedValue = KairosScheduleProjection.clock((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        })
    }
    var body: some View {
        VStack {
            DatePicker("Start", selection: time($start), displayedComponents: .hourAndMinute)
            DatePicker("End", selection: time($end), displayedComponents: .hourAndMinute)
        }.environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone).environment(\.locale, KairosTimeDisplay.locale(format: format))
    }
}
private struct PlanningTimezonePicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var zones: [String] {
        Array(Set(TimeZone.knownTimeZoneIdentifiers + ["UTC", selection])).sorted().filter { query.isEmpty || $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        NavigationStack {
            List(zones, id: \.self) { zone in
                Button { selection = zone; dismiss() } label: {
                    HStack { Text(zone.replacingOccurrences(of: "_", with: " ")); Spacer(); if selection == zone { KairosIcon("checkmark") } }
                }
            }.searchable(text: $query, prompt: "Search timezones")
                .navigationTitle("Profile timezone").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

