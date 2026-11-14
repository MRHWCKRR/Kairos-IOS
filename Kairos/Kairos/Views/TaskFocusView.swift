import SwiftUI

struct FocusSessionControls: View {
    @Environment(SessionStore.self) private var account
    @Environment(UserProfileRepository.self) private var profileRepo
    let allowsGeneralStart: Bool
    var compact = false
    private var timer: FocusTimerCoordinator { .shared }
    private var appearance: KairosTimerAppearance {
        let value = profileRepo.appearanceSettings
        return KairosTimerAppearance(type: value?.timerType, theme: value?.timerTheme, border: value?.timerBorder)
    }
    @State private var confirmingDiscard = false
    var body: some View {
        if timer.belongs(to: account.userID) {
            VStack(alignment: .leading, spacing: compact ? 10 : 16) {
                if let session = timer.session {
                    if compact {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.target?.title ?? "General focus").font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(timer.isRunning ? "Focusing" : timer.hasPendingLog ? "Ready to log" : "Paused").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            FocusTimerFace(seconds: timer.elapsedSeconds, running: timer.isRunning, appearance: appearance, compact: true)
                        }
                    } else {
                        HStack {
                            Text("FOCUS SESSION").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(KairosColors.accent)
                            Spacer()
                            Text(timer.isRunning ? "In progress" : timer.hasPendingLog ? "Ready to log" : "Paused")
                                .font(.caption.weight(.semibold)).foregroundStyle(KairosColors.accent)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(KairosColors.accent.opacity(0.1), in: Capsule())
                        }
                        Text(session.target?.title ?? "General focus").font(.title3.weight(.semibold)).lineLimit(2)
                        FocusTimerFace(seconds: timer.elapsedSeconds, running: timer.isRunning, appearance: appearance)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    HStack(spacing: 10) {
                        if !timer.hasPendingLog {
                            Button { if timer.isRunning { timer.pause() } else { timer.start() } } label: {
                                Text(timer.isRunning ? "Pause" : "Resume").frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.bordered)
                        }
                        Button { timer.log() } label: {
                            Text(timer.hasPendingLog ? "Retry log" : "Log time").frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.borderedProminent).disabled(timer.isSaving || timer.elapsedSeconds < 1)
                    }
                    if !timer.hasPendingLog || timer.expiredRequest {
                        Button(timer.expiredRequest ? "Clear reviewed request" : "Discard", role: .destructive) { confirmingDiscard = true }
                            .font(.footnote).frame(maxWidth: .infinity, minHeight: 44).disabled(timer.isSaving)
                    }
                    if timer.hasPendingLog { Text(timer.expiredRequest ? "This request is too old to replay. Review your focus totals or web history before clearing it." : "Your exact log request is retained until the save is confirmed.").font(.caption).foregroundStyle(.secondary) }
                    else if !compact { Text(timer.isRunning ? "The timer keeps elapsed time in the background. Relaunch recovery pauses at the last saved checkpoint." : "Paused. Resume when you are ready.").font(.caption).foregroundStyle(.secondary) }
                } else if allowsGeneralStart {
                    HStack(alignment: .top, spacing: 14) {
                        KairosIcon("timer", size: 22).foregroundStyle(KairosColors.accent)
                            .frame(width: 50, height: 50)
                            .background(KairosColors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Focus time").font(.title3.weight(.bold))
                            Text("Settle in and give one thing your attention.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Button { timer.start() } label: {
                        Label("Start focus", sharedIcon: "timer").frame(maxWidth: .infinity).frame(minHeight: 44)
                    }.buttonStyle(.borderedProminent).disabled(!timer.canStart)
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

private struct FocusTimerFace: View {
    let seconds: Int64
    let running: Bool
    let appearance: KairosTimerAppearance
    var compact = false
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 48

    private var time: String { FocusTimerViewModel.formatHMS(seconds) }
    private var accent: Color {
        switch appearance.theme {
        case "cyan": return Color(red: 0.10, green: 0.70, blue: 0.78)
        case "green": return Color(red: 0.18, green: 0.68, blue: 0.42)
        case "amber": return Color(red: 0.88, green: 0.55, blue: 0.08)
        case "rose": return Color(red: 0.88, green: 0.28, blue: 0.50)
        default: return Color(red: 0.49, green: 0.27, blue: 0.96)
        }
    }

    var body: some View {
        Group {
            if compact {
                Text(time).font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(accent)
            } else {
                switch appearance.type {
                case "watch":
                    ZStack {
                        Circle().stroke(accent.opacity(0.32), lineWidth: 7)
                        VStack(spacing: 6) {
                            Text(time).font(.system(size: clockSize * 0.55, weight: .bold, design: .rounded).monospacedDigit()).minimumScaleFactor(0.7).lineLimit(1)
                            Text(running ? "FOCUSING" : "PAUSED").font(.caption2.weight(.bold)).tracking(1.3).foregroundStyle(accent)
                        }.padding(14)
                    }.frame(width: 172, height: 172)
                case "nuclear":
                    VStack(spacing: 4) {
                        Text(time).font(.system(.title2, design: .monospaced).weight(.black)).minimumScaleFactor(0.65).lineLimit(1)
                        Text(running ? "⚠ SEQUENCE ACTIVE ⚠" : "SYSTEM STANDBY").font(.caption2.weight(.bold)).tracking(1.2)
                    }
                    .foregroundStyle(accent).padding(12).background(Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                default:
                    VStack(spacing: 7) {
                        Text(time).font(.system(size: clockSize, weight: .semibold, design: .rounded).monospacedDigit()).minimumScaleFactor(0.7).lineLimit(1)
                        Text(running ? "ELAPSED FOCUS" : "PAUSED TIME").font(.caption2.weight(.bold)).tracking(1.3)
                    }.foregroundStyle(accent).frame(maxWidth: .infinity)
                }
            }
        }
        .padding(compact || appearance.border == "none" ? 0 : 10)
        .overlay { if !compact { border } }
        .shadow(color: !compact && appearance.border == "glow" ? accent.opacity(0.25) : .clear, radius: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Elapsed focus time \(time)")
    }

    @ViewBuilder private var border: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        switch appearance.border {
        case "glow": shape.stroke(accent, lineWidth: 2)
        case "neon": shape.stroke(LinearGradient(colors: [.cyan, .pink], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
        case "hazard": shape.stroke(accent, style: StrokeStyle(lineWidth: 3, dash: [7, 4]))
        default: EmptyView()
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
                    Button { timer.start(target: target, expectedScope: scope) } label: {
                        Label("Focus on this task", sharedIcon: "timer").frame(maxWidth: .infinity).frame(minHeight: 44)
                    }.buttonStyle(.borderedProminent).disabled(!timer.canStart)
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
