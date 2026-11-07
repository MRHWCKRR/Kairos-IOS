import SwiftUI

struct FocusSessionControls: View {
    @Environment(SessionStore.self) private var account
    let allowsGeneralStart: Bool
    private var timer: FocusTimerCoordinator { .shared }
    @State private var confirmingDiscard = false
    var body: some View {
        if timer.belongs(to: account.userID) {
            VStack(alignment: .leading, spacing: 10) {
                if let session = timer.session {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.target?.title ?? "General focus").font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text(FocusTimerViewModel.formatHMS(timer.elapsedSeconds)).font(.title2.monospacedDigit()).accessibilityLabel("Elapsed focus time")
                        }
                        Spacer()
                        if !timer.hasPendingLog {
                            Button(timer.isRunning ? "Pause" : "Resume") { if timer.isRunning { timer.pause() } else { timer.start() } }.buttonStyle(.bordered)
                        }
                    }
                    HStack {
                        Button(timer.hasPendingLog ? "Retry log" : "Log time") { timer.log() }.buttonStyle(.borderedProminent).disabled(timer.isSaving || timer.elapsedSeconds < 1)
                        if !timer.hasPendingLog || timer.expiredRequest {
                            Button(timer.expiredRequest ? "Clear reviewed request" : "Discard", role: .destructive) { confirmingDiscard = true }.buttonStyle(.bordered).disabled(timer.isSaving)
                        }
                    }
                    if timer.hasPendingLog { Text(timer.expiredRequest ? "This request is too old to replay. Review your focus totals or web history before clearing it." : "Your exact log request is retained until the save is confirmed.").font(.caption).foregroundStyle(.secondary) }
                    else { Text(timer.isRunning ? "The timer keeps elapsed time in the background. Relaunch recovery pauses at the last saved checkpoint." : "Paused. Resume when you are ready.").font(.caption).foregroundStyle(.secondary) }
                } else if allowsGeneralStart {
                    Text("Focus session").font(.headline)
                    Button("Start general focus") { timer.start() }.buttonStyle(.borderedProminent).disabled(!timer.canStart)
                }
                if timer.isSaving { ProgressView("Saving focus…") }
                if let error = timer.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
                if let notice = timer.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                if timer.session == nil, timer.notice != nil || timer.errorMessage != nil { Button("Dismiss message") { timer.clearFeedback() }.font(.caption) }
            }
            .confirmationDialog(timer.expiredRequest ? "Clear this reviewed recovery request?" : "Discard this unlogged focus session?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard session", role: .destructive) { timer.discardReviewedSession() }
            } message: {
                Text(timer.expiredRequest ? "Clearing does not change logged time. Check your totals or web history first." : "This removes the local timer. Logged focus time stays unchanged.")
            }
        }
    }
}

struct TaskFocusView: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    let taskID: String
    var occurrenceDate: String? = nil
    private var timer: FocusTimerCoordinator { .shared }
    @State private var target: KairosFocusTarget?
    @State private var summary: KairosFocusSummary?
    @State private var loadedKey = ""
    private var key: String { "\(planRepo.searchScope ?? "")-\(planRepo.plannerRevision)-\(taskID)-\(occurrenceDate ?? "")" }
    var body: some View {
        Group {
        if loadedKey == key, let target, let summary, let scope = planRepo.searchScope {
            VStack(alignment: .leading, spacing: 10) {
                Text("Focus time").font(.headline)
                Text("Planned: \(summary.plannedMinutes) min · Logged: \(FocusTimerViewModel.formatHMS(summary.loggedSeconds))").font(.subheadline)
                Text("Remaining estimate: \(summary.remainingMinutes) min").font(.caption).foregroundStyle(.secondary)
                if timer.session == nil {
                    Button("Start focus") { timer.start(target: target, expectedScope: scope) }.buttonStyle(.borderedProminent).disabled(!timer.canStart)
                    Text("Uses the saved task. Starting focus keeps your editor draft.").font(.caption).foregroundStyle(.secondary)
                }
                FocusSessionControls(allowsGeneralStart: false)
            }.padding(18).kairosCard(cornerRadius: 22)
        } else { FocusSessionControls(allowsGeneralStart: false) }
        }
        .task(id: key) {
            let captured = key
            let result = try? planRepo.focusTarget(taskID: taskID, occurrenceDate: occurrenceDate)
            guard !Task.isCancelled, captured == key else { return }
            target = result?.0; summary = result?.1; loadedKey = captured
        }
    }
}

struct FocusBreakdownView: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @State private var report: KairosFocusBreakdown?
    @State private var loadedKey = ""
    @State private var selection = "boards"
    @State private var search = ""
    @State private var error: String?
    private var key: String { "\(planRepo.searchScope ?? "")-\(planRepo.plannerRevision)" }
    private var rows: [KairosFocusBreakdown.Row] {
        guard loadedKey == key, let report else { return [] }
        let source = selection == "boards" ? report.boards : selection == "assignments" ? report.assignments : report.tasks.flatMap { [$0] + ($0.occurrences ?? []) }
        return source.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || ($0.occurrenceDate?.contains(search) == true) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Focus breakdown").font(.headline)
            Text("Lifetime · Current planner").font(.subheadline).foregroundStyle(.secondary)
            if loadedKey == key, let report { Text("Attributed: \(FocusTimerViewModel.formatHMS(report.totalSeconds))").font(.subheadline.weight(.semibold)) }
            Text("Includes archived work. General focus, deleted tasks and other planners remain in overall totals. Assignment rollups are shown separately from board totals.").font(.caption).foregroundStyle(.secondary)
            Picker("Breakdown", selection: $selection) {
                Text("Boards").tag("boards"); Text("Assignments").tag("assignments"); Text("Tasks").tag("tasks")
            }.pickerStyle(.segmented)
            TextField("Filter focus rows", text: $search).textFieldStyle(.roundedBorder)
            if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            if rows.isEmpty { Text("No matching focus rows.").font(.subheadline).foregroundStyle(.secondary) }
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title + (row.occurrenceDate.map { " · \($0)" } ?? "") + (row.archived ? " · Archived" : "")).font(.subheadline.weight(.semibold))
                        Text("Logged \(FocusTimerViewModel.formatHMS(row.loggedSeconds)) · Estimate \(row.estimatedMinutes.map { "\($0) min" } ?? "unavailable")").font(.caption).foregroundStyle(.secondary)
                        if let estimate = row.estimatedMinutes, row.loggedSeconds > Int64(estimate) * 60 {
                            Text("\((row.loggedSeconds - Int64(estimate) * 60) / 60) min over the current estimate").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.padding(18).kairosCard(cornerRadius: 26)
            .task(id: key) {
                let captured = key
                do {
                    let value = try await planRepo.focusBreakdown(); try Task.checkCancellation()
                    guard key == captured else { return }; report = value; loadedKey = captured; error = nil
                } catch is CancellationError { }
                catch { guard key == captured, !Task.isCancelled else { return }; self.error = "Focus breakdown is unavailable. Your saved time is unchanged." }
            }
            .onChange(of: planRepo.searchScope) { _, _ in report = nil; loadedKey = ""; search = ""; selection = "boards"; error = nil }
    }
}
