import SwiftUI

enum MobileScheduleView: String, CaseIterable, Identifiable {
    case day = "Day", threeDays = "3 days", week = "Week", month = "Month"
    var id: String { rawValue }
}
struct ScheduleTaskEntry: Identifiable {
    let task: KairosTask
    let boardID: String
    let sectionID: String
    let boardTitle: String
    var id: String { task.id }
    var context: TaskDetailContext { .init(taskID: task.id, boardID: boardID, sectionID: sectionID) }
}
private struct ScheduleDay: Identifiable {
    let date: Date
    let key: String
    let tasks: [ScheduleTaskEntry]
    let occurrences: [KairosRecurringOccurrence]
    let events: [KairosEventSegment]
    var id: String { key }
    var count: Int { tasks.count + occurrences.count + events.count }
}
private struct ScheduleBlock: Identifiable {
    let id: String
    let title: String
    let start: Int
    let end: Int
    let kind: Int
    let completed: Bool
    var column = 0
    var columns = 1
}
private struct ScheduleTouchInteraction {
    let draft: KairosTouchDraft
    let blockID: String
    let sourceDate: String
    let mode: ScheduleTouchMode
    var placement: KairosSchedulePlacement?
}
private struct PendingScheduleTouch {
    let draft: KairosTouchDraft
    let placement: KairosSchedulePlacement
}

struct CalendarView: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDate = Date()
    @State private var mode: MobileScheduleView = .day
    @State private var days: [ScheduleDay] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var selectedTask: TaskDetailContext?
    @State private var selectedOccurrence: KairosRecurringOccurrence?
    @State private var scheduleTarget: ScheduleTaskEntry?
    @State private var selectedEvent: KairosEventSegment?
    @State private var showingBacklog = false
    @State private var creatingTask = false
    @State private var creatingEvent = false
    @State private var showCompleted = true
    @State private var showEvents = true
    @State private var showSkipped = false
    @State private var interaction: ScheduleTouchInteraction?
    @State private var columnFrames: [String: CGRect] = [:]
    @State private var viewportFrame: CGRect = .zero
    @State private var savingTouch = false
    @State private var undoingTouch = false
    @State private var touchUndo: KairosTouchUndo?
    @State private var pendingTouch: PendingScheduleTouch?
    @State private var touchMessage: String?
    @State private var suppressTapUntil = Date.distantPast

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = profileRepo.profile.flatMap { TimeZone(identifier: $0.timezone) } ?? .current
        return value
    }
    private func key(_ date: Date) -> String { KairosDate.dayKey(for: date, timeZone: calendar.timeZone) }
    private var entries: [ScheduleTaskEntry] {
        (planRepo.currentPlan?.boards ?? []).filter { !$0.archived }.flatMap { board in
            board.sections.filter { !$0.archived }.flatMap { section in
                section.tasks.filter { !$0.archived && $0.recurrence?.enabled != true }.map { ScheduleTaskEntry(task: $0, boardID: board.id, sectionID: section.id, boardTitle: board.title) }
            }
        }
    }
    private var backlog: [ScheduleTaskEntry] { entries.filter { !$0.task.completed && ($0.task.date == nil || $0.task.startTime == nil || ($0.task.date ?? "") < key(Date())) } }
    private var dateRange: [Date] {
        var start = calendar.startOfDay(for: selectedDate)
        var count = mode == .day ? 1 : mode == .threeDays ? 3 : 7
        if mode == .week { start = calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: start), to: start) ?? start }
        if mode == .month {
            let first = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
            start = calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: first), to: first) ?? first
            count = 42
        }
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    private var loadID: String { "\(dateRange.first.map(key) ?? "")-\(mode.rawValue)-\(planRepo.plannerRevision)-\(showCompleted)-\(showEvents)-\(showSkipped)-\(calendar.timeZone.identifier)" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controls
                if planRepo.isLoading { ProgressView("Loading schedule…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if planRepo.plannerIsUnavailable {
                    ContentUnavailableView { Label("Schedule unavailable", systemImage: "exclamationmark.triangle") } description: { Text(planRepo.errorMessage ?? "Could not read your planner.") } actions: { Button("Retry") { planRepo.retryLoading() } }
                } else {
                    if let loadError { Text(loadError).font(.caption).foregroundStyle(.red).padding(.horizontal) }
                    if loading { ProgressView().controlSize(.small).padding(4) }
                    if mode == .month { monthView }
                    else if showingDayDetails {
                        ScrollView { VStack(alignment: .leading, spacing: 16) { ForEach(days) { day in Text(day.date.formatted(date: .complete, time: .omitted)).font(.headline); agenda(day) }; insight }.padding(16) }
                    } else { timeline }
                }
            }
            .kairosBackground().navigationTitle("Schedule").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) { touchBar }
            .onPreferenceChange(ScheduleColumnFrames.self) { columnFrames = $0 }
            .onPreferenceChange(ScheduleViewportFrame.self) { viewportFrame = $0 }
            .onChange(of: loadID) { _, _ in interaction = nil }
            .onChange(of: showingDayDetails) { _, _ in interaction = nil }
            .onChange(of: scenePhase) { _, phase in if phase != .active { interaction = nil } }
            .onDisappear { interaction = nil }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Backlog", systemImage: "tray") { showingBacklog = true } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(showingDayDetails ? "Timeline" : "Agenda", systemImage: showingDayDetails ? "clock" : "list.bullet") { showingDayDetails.toggle() }.labelStyle(.iconOnly)
                    Menu { Toggle("Completed tasks", isOn: $showCompleted); Toggle("Skipped occurrences", isOn: $showSkipped); Toggle("Fixed events", isOn: $showEvents) } label: { Image(systemName: "line.3.horizontal.decrease") }.accessibilityLabel("Schedule filters")
                    Menu {
                        Button("Task", systemImage: "checkmark.circle") { creatingTask = true }
                        Button("Fixed event", systemImage: "calendar.badge.plus") { creatingEvent = true }
                    } label: { Image(systemName: "plus") }.accessibilityLabel("Add to schedule").disabled(planRepo.isLoading || planRepo.plannerIsUnavailable)
                }
            }
            .sheet(item: $selectedTask) { TaskDetailView(context: $0).environment(planRepo) }
            .sheet(item: $selectedOccurrence) { OccurrenceDetailsView(occurrence: $0, calendar: calendar).environment(planRepo).presentationDetents([.medium, .large]) }
            .sheet(item: $scheduleTarget) { entry in MobileTaskScheduler(entry: entry, selectedDate: selectedDate, calendar: calendar).environment(planRepo) }
            .sheet(item: $selectedEvent) { event in MobileEventDetails(event: event, selectedDate: selectedDate, calendar: calendar, revision: planRepo.plannerRevision).environment(planRepo) }
            .sheet(isPresented: $creatingEvent) { MobileEventDetails(event: nil, selectedDate: selectedDate, calendar: calendar, revision: planRepo.plannerRevision).environment(planRepo) }
            .sheet(isPresented: $creatingTask) { MobileScheduleCreator(selectedDate: selectedDate, calendar: calendar).environment(planRepo) }
            .sheet(isPresented: $showingBacklog, onDismiss: { if let backlogSelection { scheduleTarget = backlogSelection; self.backlogSelection = nil } }) { backlogSheet }
            .task(id: loadID) { await loadDays() }
        }.environment(\.timeZone, calendar.timeZone).environment(\.calendar, calendar)
    }
    @State private var backlogSelection: ScheduleTaskEntry?

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date).labelsHidden()
                Spacer()
                Button("Today") { selectedDate = Date() }.font(.subheadline.weight(.medium))
                Button("Previous", systemImage: "chevron.left") { navigate(-1) }.labelStyle(.iconOnly).frame(minWidth: 34, minHeight: 44)
                Button("Next", systemImage: "chevron.right") { navigate(1) }.labelStyle(.iconOnly).frame(minWidth: 34, minHeight: 44)
            }
            Picker("Schedule view", selection: $mode) { ForEach(MobileScheduleView.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
        }.padding(.horizontal, 16).padding(.bottom, 10)
    }
    private var timeline: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 126)
                            ForEach(0..<24, id: \.self) { hour in
                                Text(KairosScheduleProjection.clock(hour * 60)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 46, height: 56, alignment: .topTrailing).padding(.trailing, 6).id("hour-\(hour)")
                            }
                        }
                        ForEach(days) { day in dayColumn(day, width: mode == .day ? max(220, geometry.size.width - 54) : 200) }
                    }
                }
                .scrollDisabled(interaction != nil)
                .task { proxy.scrollTo("hour-8", anchor: .top) }
            }
            .preference(key: ScheduleViewportFrame.self, value: geometry.frame(in: .global))
        }
    }
    private func dayColumn(_ day: ScheduleDay, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).font(.subheadline.weight(.semibold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(day.tasks.filter { KairosScheduleProjection.minutes($0.task.startTime) == nil }) { entry in
                            Button(entry.task.title) { selectedTask = entry.context }.font(.caption).lineLimit(1).padding(8).background(KairosColors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        }
                        ForEach(day.occurrences.filter { $0.startTime == nil }) { occurrence in Button(occurrence.task.title) { selectedOccurrence = occurrence }.font(.caption).lineLimit(1) }
                    }
                }
                Button("Day details") { selectedDate = day.date; showingDayDetails = true }.font(.caption)
            }.padding(8).frame(width: width, height: 126, alignment: .topLeading)
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) { ForEach(0..<24, id: \.self) { _ in Rectangle().fill(Color.secondary.opacity(0.13)).frame(height: 0.5).frame(height: 56, alignment: .top) } }
                    ForEach(blocks(day)) { block in
                        timelineBlock(block, day: day)
                            .frame(width: max(44, geo.size.width / CGFloat(block.columns) - 6), height: max(44, CGFloat(block.end - block.start) * 56 / 60))
                            .offset(x: CGFloat(block.column) * geo.size.width / CGFloat(block.columns) + 3, y: CGFloat(block.start) * 56 / 60)
                            .accessibilityLabel("\(block.title), \(KairosScheduleProjection.clock(block.start)) to \(KairosScheduleProjection.clock(block.end))")
                    }
                    if let active = interaction, let placement = active.placement, placement.date == day.key || (mode == .day && active.sourceDate == day.key) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(active.draft.title).font(.caption.weight(.semibold)).lineLimit(2)
                            Text("\(placement.date) · \(KairosScheduleProjection.clock(placement.start))–\(KairosScheduleProjection.clock(placement.end))").font(.caption2).monospacedDigit()
                        }
                        .padding(8).frame(width: max(44, geo.size.width - 8), height: max(44, CGFloat(placement.duration) * 56 / 60), alignment: .topLeading)
                        .background(KairosColors.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(KairosColors.accent, lineWidth: 2) }
                        .offset(x: 4, y: CGFloat(placement.start) * 56 / 60)
                        .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .preference(key: ScheduleColumnFrames.self, value: [day.key: geo.frame(in: .global)])
            }.frame(height: 24 * 56)
        }.frame(width: width).overlay(alignment: .leading) { Rectangle().fill(Color.secondary.opacity(0.1)).frame(width: 0.5) }
    }
    @State private var showingDayDetails = false
    private var monthView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                    ForEach(0..<7, id: \.self) { index in Text(calendar.veryShortStandaloneWeekdaySymbols[index]).font(.caption).foregroundStyle(.secondary) }
                    ForEach(days) { day in
                        Button { selectedDate = day.date } label: {
                            VStack(spacing: 4) { Text("\(calendar.component(.day, from: day.date))").font(.subheadline.weight(.medium)); Text(day.count == 0 ? " " : "\(day.count)").font(.system(size: 9)) }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(day.key == key(selectedDate) ? Color.white : Color.primary)
                                .background(day.key == key(selectedDate) ? KairosColors.accent : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).accessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted)), \(day.count) items")
                    }
                }
                HStack { Text(selectedDate.formatted(.dateTime.month(.abbreviated).day())).font(.headline); Spacer(); Button("Open day") { mode = .day } }
                if let day = days.first(where: { $0.key == key(selectedDate) }) { agenda(day) }
                insight
            }.padding(16)
        }
    }
    private var insight: some View {
        Group {
            if let text = planRepo.currentPlan?.dayInsights?[key(selectedDate)], !text.isEmpty {
                Divider(); Text("Daily insight").font(.headline); Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
    private func agenda(_ day: ScheduleDay) -> some View {
        VStack(spacing: 0) {
            if day.count == 0 { Text("Nothing scheduled. Add a task or choose one from your backlog.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 20) }
            ForEach(day.tasks) { taskRow($0) }
            ForEach(day.occurrences) { occurrence in
                Button { selectedOccurrence = occurrence } label: { HStack { Image(systemName: "repeat"); Text(occurrence.task.title); Spacer(); Text(occurrence.startTime ?? occurrence.status).font(.caption) }.padding(.vertical, 12) }.buttonStyle(.plain)
            }
            ForEach(day.events) { event in
                Button { selectedEvent = event } label: { HStack { Image(systemName: "calendar"); Text(event.title); Spacer(); Text(KairosScheduleProjection.clock(event.startMin)).font(.caption) }.padding(.vertical, 12) }.buttonStyle(.plain)
            }
        }
    }
    private func taskRow(_ entry: ScheduleTaskEntry) -> some View {
        HStack(spacing: 8) {
            Button { complete(entry) } label: { Image(systemName: entry.task.completed ? "checkmark.circle.fill" : "circle").frame(minWidth: 34, minHeight: 44) }.disabled(planRepo.isSaving)
            Button { selectedTask = entry.context } label: { VStack(alignment: .leading, spacing: 4) { Text(entry.task.title).strikethrough(entry.task.completed); Text(entry.boardTitle).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
            Button("Schedule", systemImage: "calendar.badge.clock") { scheduleTarget = entry }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
        }.padding(.vertical, 6)
    }
    private var backlogSheet: some View {
        NavigationStack {
            List {
                Section("Unscheduled and overdue work") {
                    if backlog.isEmpty { Text("Your backlog is clear.").foregroundStyle(.secondary) }
                    ForEach(backlog) { entry in HStack { Text(entry.task.title).lineLimit(2); Spacer(); Button("Schedule") { backlogSelection = entry; showingBacklog = false } } }
                }
            }.navigationTitle("Backlog").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingBacklog = false } } }
        }
    }
    private func navigate(_ direction: Int) {
        selectedDate = calendar.date(byAdding: mode == .month ? .month : .day, value: direction * (mode == .threeDays ? 3 : mode == .week ? 7 : 1), to: selectedDate) ?? selectedDate
    }
    private func loadDays() async {
        loading = true; loadError = nil; days = []
        let dates = dateRange, tasks = entries
        var result: [ScheduleDay] = []
        do {
            let projected = try await planRepo.recurringOccurrences(onDays: dates.map(key))
            for date in dates {
                try Task.checkCancellation()
                let dateKey = key(date)
                let occurrences = (projected[dateKey] ?? []).filter { $0.status == "pending" || (showCompleted && $0.status == "completed") || (showSkipped && $0.status == "skipped") }
                result.append(.init(date: date, key: dateKey, tasks: tasks.filter { $0.task.date == dateKey && (showCompleted || !$0.task.completed) }, occurrences: occurrences, events: showEvents ? try planRepo.eventSegments(on: dateKey) : []))
            }
            try Task.checkCancellation(); days = result; loading = false
        } catch is CancellationError { }
        catch { guard !Task.isCancelled else { return }; days = []; loading = false; loadError = error.localizedDescription }
    }
    private func blocks(_ day: ScheduleDay) -> [ScheduleBlock] {
        var blocks = day.tasks.compactMap { entry -> ScheduleBlock? in
            guard let start = KairosScheduleProjection.minutes(entry.task.startTime) else { return nil }
            return .init(id: entry.id, title: entry.task.title, start: start, end: min(1440, start + KairosScheduleProjection.duration(entry.task)), kind: 0, completed: entry.task.completed)
        }
        blocks += day.occurrences.compactMap { occurrence in
            guard let start = KairosScheduleProjection.minutes(occurrence.startTime) else { return nil }
            return .init(id: occurrence.id, title: occurrence.task.title, start: start, end: min(1440, start + KairosScheduleProjection.duration(occurrence.task)), kind: 1, completed: occurrence.status == "completed")
        }
        blocks += day.events.map { .init(id: $0.id, title: $0.title, start: $0.startMin, end: $0.endMin, kind: 2, completed: false) }
        blocks.sort { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
        var ends: [Int] = [], groupStart = 0, groupEnd = 0
        for index in blocks.indices {
            if blocks[index].start >= groupEnd { for j in groupStart..<index { blocks[j].columns = max(1, ends.count) }; ends = []; groupStart = index }
            let lane = ends.firstIndex(where: { $0 <= blocks[index].start }) ?? ends.count
            let visualEnd = max(blocks[index].end, blocks[index].start + 48)
            if lane == ends.count { ends.append(visualEnd) } else { ends[lane] = visualEnd }
            blocks[index].column = lane; groupEnd = ends.max() ?? 0
        }
        for j in groupStart..<blocks.count { blocks[j].columns = max(1, ends.count) }
        return blocks
    }
    private func open(_ block: ScheduleBlock, day: ScheduleDay) {
        guard Date() > suppressTapUntil, !savingTouch, !undoingTouch else { return }
        if block.kind == 0 { selectedTask = day.tasks.first { $0.id == block.id }?.context }
        else if block.kind == 1 { selectedOccurrence = day.occurrences.first { $0.id == block.id } }
        else { selectedEvent = day.events.first { $0.id == block.id } }
    }
    private func complete(_ entry: ScheduleTaskEntry) {
        guard !planRepo.isSaving else { return }
        Task { let saved = await planRepo.toggleTask(boardID: entry.boardID, sectionID: entry.sectionID, taskID: entry.id); if saved && !entry.task.completed { await profileRepo.recordTaskCompletion(taskID: entry.id) }; if !saved { loadError = planRepo.errorMessage } }
    }

    @ViewBuilder private func timelineBlock(_ block: ScheduleBlock, day: ScheduleDay) -> some View {
        if block.kind == 2 {
            Button { open(block, day: day) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(block.title).font(.caption.weight(.semibold)).lineLimit(3)
                    Text("\(KairosScheduleProjection.clock(block.start))–\(KairosScheduleProjection.clock(block.end))").font(.system(size: 10)).monospacedDigit().lineLimit(1)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(6)
                    .background(Color.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain)
        } else {
            ScheduleInteractiveBlock(title: block.title, start: block.start, end: block.end, recurring: block.kind == 1, completed: block.completed,
                                     editable: canEdit(block, day: day), active: interaction?.blockID == block.id && interaction?.sourceDate == day.key,
                                     busy: savingTouch || undoingTouch || planRepo.isSaving,
                                     open: { open(block, day: day) }, editDetails: { openScheduleDetails(block, day: day) },
                                     begin: { beginTouch(block, day: day, mode: $0) },
                                     change: { updateTouch(mode: $0, translation: $1, point: $2) }, finish: finishTouch,
                                     cancel: { interaction = nil }, adjust: { adjustTouch(block, day: day, mode: $0, minutes: $1) })
        }
    }
    private func canEdit(_ block: ScheduleBlock, day: ScheduleDay) -> Bool {
        if let entry = day.tasks.first(where: { $0.id == block.id }) { return entry.task.scheduleLocked != true && (!entry.task.completed || profileRepo.allowsCompletedRescheduling) }
        if let occurrence = day.occurrences.first(where: { $0.id == block.id }) { return occurrence.task.scheduleLocked != true && (occurrence.status == "pending" || (occurrence.status == "completed" && profileRepo.allowsCompletedRescheduling)) }
        return false
    }
    private func openScheduleDetails(_ block: ScheduleBlock, day: ScheduleDay) {
        guard !savingTouch, !undoingTouch else { return }
        if let entry = day.tasks.first(where: { $0.id == block.id }) { scheduleTarget = entry }
        else { selectedOccurrence = day.occurrences.first { $0.id == block.id } }
    }
    private func beginTouch(_ block: ScheduleBlock, day: ScheduleDay, mode: ScheduleTouchMode) -> Bool {
        guard interaction == nil, !savingTouch, !undoingTouch, pendingTouch == nil, canEdit(block, day: day) else { return false }
        let target: KairosTouchTarget
        if let entry = day.tasks.first(where: { $0.id == block.id }) { target = .init(taskId: entry.id) }
        else if let occurrence = day.occurrences.first(where: { $0.id == block.id }) { target = .init(taskId: occurrence.seriesId, occurrenceDate: occurrence.occurrenceDate) }
        else { return false }
        do {
            let draft = try planRepo.beginTouchEdit(target: target, timezone: calendar.timeZone.identifier, allowCompleted: profileRepo.allowsCompletedRescheduling)
            interaction = .init(draft: draft, blockID: block.id, sourceDate: day.key, mode: mode, placement: draft.original)
            touchMessage = nil; suppressTapUntil = Date().addingTimeInterval(1)
            return true
        } catch { touchMessage = error.localizedDescription; return false }
    }
    private func updateTouch(mode: ScheduleTouchMode, translation: CGSize, point: CGPoint) {
        guard var active = interaction, active.mode == mode else { return }
        guard viewportFrame.contains(point) else { active.placement = nil; interaction = active; return }
        do {
            if mode == .resize {
                active.placement = try KairosTouchSchedule.resize(date: active.draft.original.date, start: active.draft.original.start, targetEnd: Double(active.draft.original.end) + Double(translation.height) * 60 / 56)
            } else {
                var date = columnFrames.first(where: { point.x >= $0.value.minX && point.x < $0.value.maxX })?.key
                if self.mode == .day, let original = KairosScheduleDates.parse(active.draft.original.date, calendar: calendar) {
                    if point.x < viewportFrame.minX + 32 { date = calendar.date(byAdding: .day, value: -1, to: original).map(key) }
                    if point.x > viewportFrame.maxX - 32 { date = calendar.date(byAdding: .day, value: 1, to: original).map(key) }
                }
                if let date { active.placement = try KairosTouchSchedule.move(date: date, targetStart: Double(active.draft.original.start) + Double(translation.height) * 60 / 56, duration: active.draft.original.duration) }
                else { active.placement = nil }
            }
            interaction = active
        } catch { active.placement = nil; interaction = active }
    }
    private func finishTouch() {
        guard let active = interaction else { return }
        interaction = nil; suppressTapUntil = Date().addingTimeInterval(0.4)
        guard let placement = active.placement, placement != active.draft.original else { return }
        saveTouch(.init(draft: active.draft, placement: placement))
    }
    private func saveTouch(_ pending: PendingScheduleTouch) {
        guard !savingTouch, !undoingTouch else { return }
        pendingTouch = pending; savingTouch = true; touchMessage = nil
        Task {
            let saved = await planRepo.saveTouchEdit(pending.draft, placement: pending.placement)
            savingTouch = false
            if let saved {
                touchUndo = saved; pendingTouch = nil; touchMessage = "Updated \(saved.title)"
                if mode == .day, let date = KairosScheduleDates.parse(pending.placement.date, calendar: calendar) { selectedDate = date }
            } else { touchMessage = planRepo.errorMessage ?? "Could not save. Retry this change when connected." }
        }
    }
    private func adjustTouch(_ block: ScheduleBlock, day: ScheduleDay, mode: ScheduleTouchMode, minutes: Int) {
        guard beginTouch(block, day: day, mode: mode), var active = interaction else { return }
        do {
            if mode == .move { active.placement = try KairosTouchSchedule.move(date: active.draft.original.date, targetStart: Double(active.draft.original.start + minutes), duration: active.draft.original.duration) }
            else { active.placement = try KairosTouchSchedule.resize(date: active.draft.original.date, start: active.draft.original.start, targetEnd: Double(active.draft.original.end + minutes)) }
            interaction = active; finishTouch()
        } catch { interaction = nil; touchMessage = error.localizedDescription }
    }
    @ViewBuilder private var touchBar: some View {
        if let active = interaction {
            VStack(alignment: .leading, spacing: 5) {
                Text(active.draft.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let placement = active.placement { Text("\(placement.date) · \(KairosScheduleProjection.clock(placement.start))–\(KairosScheduleProjection.clock(placement.end))").font(.subheadline).monospacedDigit() }
                else { Text("Release here to cancel").font(.subheadline) }
                Text(active.mode == .resize ? "Release to resize · 5-minute snapping" : (mode == .day ? "Release to move · Drag to a screen edge to change day" : "Release to move · Drag across visible day columns"))
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.bar)
        } else if savingTouch || undoingTouch {
            ProgressView(undoingTouch ? "Restoring schedule…" : "Saving schedule…").frame(maxWidth: .infinity).padding(12).background(.bar)
        } else if touchMessage != nil || touchUndo != nil || pendingTouch != nil {
            HStack(spacing: 10) {
                Text(touchMessage ?? "Schedule updated").font(.caption).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                if let pending = pendingTouch { Button("Retry") { saveTouch(pending) } }
                else if let undo = touchUndo {
                    Button("Undo") {
                        undoingTouch = true
                        Task { let saved = await planRepo.undoTouchEdit(undo); undoingTouch = false; if saved { touchUndo = nil; touchMessage = "Schedule restored" } else { touchMessage = planRepo.errorMessage ?? "Could not restore this schedule." } }
                    }.keyboardShortcut("z", modifiers: .command)
                }
                Button("Dismiss", systemImage: "xmark") { pendingTouch = nil; touchUndo = nil; touchMessage = nil }.labelStyle(.iconOnly).frame(minWidth: 34, minHeight: 44)
            }.padding(.horizontal, 14).padding(.vertical, 4).background(.bar)
        }
    }
}
