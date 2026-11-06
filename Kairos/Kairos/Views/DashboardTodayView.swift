import SwiftUI

struct DashboardTodayView: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(UserProfileRepository.self) private var profileRepo
    let isActive: Bool
    let today: String
    let calendar: Calendar
    var onSchedule: () -> Void
    @State private var snapshot: KairosTodaySnapshot?
    @State private var snapshotKey = ""
    @State private var snapshotRevision = UUID()
    @State private var loading = false
    @State private var error: String?
    @State private var message: String?
    @State private var busy = false
    @State private var retry = 0
    @State private var visibleCounts = ["overdue": 5, "today": 5, "unscheduled": 5]
    @State private var selectedTask: TaskDetailContext?
    @State private var selectedOccurrence: KairosRecurringOccurrence?
    @State private var selectedEvent: KairosEventSegment?
    @State private var scheduler: ScheduleTaskEntry?
    @State private var creating = false

    private var scope: String? { planRepo.searchScope }
    private var loadKey: String { "\(scope ?? "loading")-\(planRepo.plannerRevision)-\(today)-\(calendar.timeZone.identifier)" }
    private var current: KairosTodaySnapshot? { snapshotKey == loadKey ? snapshot : nil }
    private var day: Date { KairosScheduleDates.parse(today, calendar: calendar) ?? Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today").font(.title2.weight(.bold))
                    Text("Overdue work, today's schedule and tasks to plan.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button { creating = true } label: { KairosIcon("plus").frame(width: 44, height: 44) }
                    .buttonStyle(.bordered).accessibilityLabel("New task for today").disabled(scope == nil)
            }
            if scope == nil {
                Text(planRepo.isLoading ? "Loading your planner." : planRepo.errorMessage ?? "Your planner is unavailable.").font(.subheadline).foregroundStyle(.secondary)
                if !planRepo.isLoading { Button("Retry") { planRepo.retryLoading() } }
            } else if let error {
                Text(error).font(.subheadline).foregroundStyle(.red)
                Button("Retry Today") { retry += 1 }
            } else if loading || current == nil {
                ProgressView("Loading Today.").frame(maxWidth: .infinity).padding(.vertical)
            } else if let current {
                group("Needs attention", id: "overdue", rows: current.overdue, empty: "No overdue work.")
                group("On today", id: "today", rows: current.today, empty: "No work or events planned for today.")
                group("To plan", id: "unscheduled", rows: current.unscheduled, empty: "No unscheduled tasks.")
            }
            if let message {
                HStack {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss", sharedIcon: "xmark") { self.message = nil }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }
            }
            Button("Open Schedule", sharedIcon: "calendar", action: onSchedule).font(.subheadline.weight(.semibold))
        }.padding(20).kairosCard(cornerRadius: 28)
            .task(id: "\(isActive)-\(loadKey)-\(retry)") { await refresh() }
            .onChange(of: scope) { _, _ in
                snapshot = nil; error = nil; message = nil; selectedTask = nil; selectedOccurrence = nil; selectedEvent = nil; scheduler = nil; creating = false; visibleCounts = ["overdue": 5, "today": 5, "unscheduled": 5]
            }
            .sheet(item: $selectedTask) { TaskDetailView(context: $0) }
            .sheet(item: $selectedOccurrence) { OccurrenceDetailsView(occurrence: $0, calendar: calendar) }
            .sheet(item: $selectedEvent) { MobileEventDetails(event: $0, selectedDate: day, calendar: calendar, revision: snapshotRevision) }
            .sheet(item: $scheduler) { MobileTaskScheduler(entry: $0, selectedDate: day, calendar: calendar) }
            .sheet(isPresented: $creating) { MobileScheduleCreator(selectedDate: day, calendar: calendar) }
            .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
    }
    private func group(_ title: String, id: String, rows: [KairosTodayRow], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(title).font(.headline); Spacer(); Text("\(rows.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            if rows.isEmpty { Text(empty).font(.subheadline).foregroundStyle(.secondary) }
            ForEach(Array(rows.prefix(visibleCounts[id] ?? 5)), id: \.key) { row in taskRow(row) }
            if rows.count > (visibleCounts[id] ?? 5) { Button("Show more") { visibleCounts[id, default: 5] += 10 }.font(.subheadline) }
        }.padding(.vertical, 8)
    }
    private func taskRow(_ row: KairosTodayRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Button { open(row, schedule: false) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        Text(row.path).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).frame(minHeight: 44)
                if row.canComplete {
                    Button { act(row, plan: false) } label: { KairosIcon("circle").frame(width: 44, height: 44) }
                        .buttonStyle(.plain).foregroundStyle(KairosColors.accent).accessibilityLabel("Complete \(row.title)")
                }
            }
            Text(when(row)).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                if row.kind == "task", row.occurrenceDate == nil, row.date != today {
                    Button("Plan today") { act(row, plan: true) }.font(.caption.weight(.semibold)).frame(minHeight: 44)
                }
                Button(row.kind == "event" ? "Event details" : row.occurrenceDate != nil ? "Open occurrence" : "Schedule") { open(row, schedule: true) }
                    .font(.caption.weight(.semibold)).frame(minHeight: 44)
            }
        }.disabled(busy || planRepo.isSaving).padding(.vertical, 8)
            .overlay(alignment: .bottom) { Divider().opacity(0.3) }
    }
    private func displayTime(_ value: String) -> String { KairosTimeDisplay.time(value, format: profileRepo.accessibilitySettings?.timeFormat ?? "12") }
    private func when(_ row: KairosTodayRow) -> String {
        if let start = row.start, !start.isEmpty { return "\(row.date ?? today) · \(displayTime(start))\(row.end.flatMap { $0.isEmpty ? nil : "–" + displayTime($0) } ?? "")" }
        if let due = row.dueDate { return due == today ? "Due today" : "Due \(due)" }
        return row.date ?? "No scheduled date"
    }
    private func refresh() async {
        guard isActive, scope != nil else { return }
        loading = true; error = nil
        let key = loadKey, revision = planRepo.plannerRevision, date = today
        do {
            let payload = try planRepo.todayInputJSON()
            let work = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let result = try KairosToday.build(planJSON: payload, today: date)
                try Task.checkCancellation()
                return result
            }
            let result = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
            try Task.checkCancellation()
            guard key == loadKey else { return }
            snapshot = result; snapshotKey = key; snapshotRevision = revision; loading = false
        } catch is CancellationError { }
        catch { guard !Task.isCancelled, key == loadKey else { return }; self.error = "Today could not load. \(error.localizedDescription)"; loading = false }
    }
    private func open(_ row: KairosTodayRow, schedule: Bool) {
        guard !busy, current != nil else { return }
        do {
            if row.kind == "event" {
                guard let event = try planRepo.eventSegments(on: today).first(where: { $0.eventID == row.id && $0.occurrenceDate == row.occurrenceDate && $0.continued == (row.continued ?? false) }) else { throw KairosPlannerSearch.Unavailable() }
                selectedEvent = event
            } else if row.occurrenceDate != nil {
                let key = loadKey; busy = true
                Task {
                    defer { busy = false }
                    do { let result = try await planRepo.searchOccurrence(row.searchRow); guard key == loadKey else { return }; selectedOccurrence = result }
                    catch { if key == loadKey { message = "This occurrence changed. Refresh Today to review it." } }
                }
            } else {
                guard planRepo.searchResultIsAvailable(row.searchRow), let taskID = row.taskId, let boardID = row.boardId, let sectionID = row.sectionId else { throw KairosPlannerSearch.Unavailable() }
                if schedule {
                    guard let task = planRepo.todayTask(row, revision: snapshotRevision) else { throw KairosPlannerSearch.Unavailable() }
                    scheduler = .init(task: task, boardID: boardID, sectionID: sectionID, boardTitle: row.path)
                } else { selectedTask = .init(taskID: taskID, boardID: boardID, sectionID: sectionID) }
            }
        } catch { message = "This item changed. Refresh Today to review it." }
    }
    private func act(_ row: KairosTodayRow, plan: Bool) {
        guard !busy, current != nil, !planRepo.isSaving else { return }
        busy = true; message = nil
        let revision = snapshotRevision, scope = self.scope, day = today
        Task {
            let saved: Bool
            if plan { saved = await planRepo.planTodayTask(row, revision: revision, day: day) }
            else { saved = await planRepo.completeTodayTask(row, revision: revision) }
            guard self.scope == scope else { busy = false; return }
            busy = false
            if saved {
                message = plan ? "Planned for today." : "Task completed."
                if !plan, let id = row.taskId { await profileRepo.recordTaskCompletion(taskID: id) }
            } else { message = planRepo.errorMessage ?? "Could not save. Your task remains available to review." }
        }
    }
}

