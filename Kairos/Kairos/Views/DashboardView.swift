import SwiftUI
import UIKit

struct DashboardView: View {
    @Environment(SessionStore.self) private var session
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Lets the dashboard send the user to another top-level Kairos surface
    /// without coupling the dashboard to TabView state.
    var onNavigate: ((Int) -> Void)? = nil

    @State private var showingProfile = false
    @State private var focusTimer: FocusTimerViewModel?

    private var displayName: String {
        let name = profileRepo.profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? session.email : name
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        case 18..<23: return "Good evening"
        default: return "Welcome back"
        }
    }

    private var todayKey: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private var activeTasks: [KairosTask] {
        planRepo.currentPlan?.boards
            .filter { !$0.archived }
            .flatMap { $0.sections.filter { !$0.archived } }
            .flatMap { $0.tasks.filter { !$0.archived && !$0.completed } } ?? []
    }

    private var allTasks: [KairosTask] {
        planRepo.currentPlan?.boards
            .filter { !$0.archived }
            .flatMap { $0.sections.filter { !$0.archived } }
            .flatMap { $0.tasks.filter { !$0.archived } } ?? []
    }

    private var completedCount: Int { allTasks.filter(\.completed).count }

    private var completion: Double {
        guard !allTasks.isEmpty else { return 0 }
        return Double(completedCount) / Double(allTasks.count)
    }

    private var todayTasks: [KairosTask] {
        let scheduled = activeTasks.filter { $0.date == todayKey }
        if !scheduled.isEmpty { return Array(scheduled.prefix(4)) }
        return Array(activeTasks.filter { $0.date == nil }.prefix(4))
    }

    private var todayFocusSeconds: Int64 {
        profileRepo.focusData?.dailyFocusLog?[todayKey] ?? 0
    }

    private var activeGoals: [String?] {
        let saved = profileRepo.achievementsData?.goals ?? []
        return (0..<3).map { saved.indices.contains($0) ? saved[$0] : nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    dailyOverview
                    focusCard
                    todayTasksCard
                    goalsCard
                    routineCard
                    boardsPreview
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .kairosBackground()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingProfile) {
                ProfileView()
                    .environment(session)
                    .environment(profileRepo)
            }
        }
        .task {
            if focusTimer == nil {
                focusTimer = FocusTimerViewModel(profileRepo: profileRepo)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(displayName)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button { showingProfile = true } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(KairosColors.accent)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Open profile")
            .kairosGlass(cornerRadius: 18, tint: KairosColors.accent.opacity(0.10))
        }
    }

    private var dailyOverview: some View {
        HStack(spacing: 10) {
            overviewMetric(
                title: "Focus today",
                value: formatCompactDuration(todayFocusSeconds),
                systemImage: "timer"
            )

            overviewMetric(
                title: "Tasks done",
                value: "\(completedCount)/\(allTasks.count)",
                systemImage: "checkmark.circle.fill"
            )

            overviewMetric(
                title: "Progress",
                value: "\(Int(completion * 100))%",
                systemImage: "chart.line.uptrend.xyaxis"
            )
        }
    }

    private func overviewMetric(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(KairosColors.accent)

            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .kairosCard(cornerRadius: 20)
    }

    private var focusCard: some View {
        Group {
            if let focusTimer {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center) {
                        Label("FOCUS TIMER", systemImage: "timer")
                            .font(.caption.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(KairosColors.accent)

                        Spacer()

                        HStack(spacing: 6) {
                            Circle()
                                .fill(focusTimer.isRunning ? KairosColors.accent : .secondary)
                                .frame(width: 6, height: 6)
                            Text(focusTimer.isRunning ? "ACTIVE" : "READY")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(focusTimer.isRunning ? KairosColors.accent : .secondary)
                        }
                    }

                    HStack(alignment: .lastTextBaseline) {
                        Text(FocusTimerViewModel.formatHMS(focusTimer.elapsedSeconds))
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .monospacedDigit()

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text("Longest")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(FocusTimerViewModel.formatHMS(profileRepo.focusData?.longestSessionSeconds ?? 0))
                                .font(.caption.weight(.semibold))
                        }
                    }

                    focusControls(focusTimer)
                }
                .padding(20)
                .kairosCard(cornerRadius: 30)
            }
        }
    }

    private func focusControls(_ timer: FocusTimerViewModel) -> some View {
        HStack(spacing: 10) {
            Button {
                if timer.isRunning {
                    timer.pause()
                } else {
                    timer.start()
                }
                fireFocusHaptic()
            } label: {
                Label(
                    timer.isRunning ? "Pause" : "Start Focus",
                    systemImage: timer.isRunning ? "pause.fill" : "play.fill"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(KairosColors.accent, in: Capsule())
            .accessibilityLabel(timer.isRunning ? "Pause focus timer" : "Start focus timer")
            .accessibilityHint(timer.isRunning ? "Pauses the current focus session" : "Starts the focus timer")

            Button {
                timer.stopAndLog()
                fireFocusHaptic()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .kairosGlass(cornerRadius: 23)
            .accessibilityLabel("Stop focus timer")
            .accessibilityHint("Stops and logs the current focus session")
            .frame(width: timer.isRunning ? 46 : 0)
            .opacity(timer.isRunning ? 1 : 0)
            .clipped()
            .allowsHitTesting(timer.isRunning)
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82),
            value: timer.isRunning
        )
    }

    private func fireFocusHaptic() {
        guard !reduceMotion else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    @ViewBuilder
    private var todayTasksCard: some View {
        if !todayTasks.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Up next")
                            .font(.headline.weight(.bold))
                        Text(todayTasks.count == 1 ? "One task ready when you are" : "A few things to move forward")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("See all") {
                        onNavigate?(1)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KairosColors.accent)
                    .kairosGlass(cornerRadius: 16, tint: KairosColors.accent.opacity(0.08))
                }

                VStack(spacing: 0) {
                    ForEach(Array(todayTasks.enumerated()), id: \.element.id) { index, task in
                        HStack(spacing: 12) {
                            Image(systemName: "circle")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(KairosColors.accent)

                            Text(task.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)

                            Spacer(minLength: 8)

                            if task.date == todayKey {
                                Text("Today")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 11)

                        if index < todayTasks.count - 1 {
                            Divider()
                                .opacity(0.45)
                        }
                    }
                }
            }
            .padding(18)
            .kairosCard(cornerRadius: 26)
        }
    }

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Active Goals")
                        .font(.headline.weight(.bold))
                    Text("Keep the momentum going")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onNavigate?(4)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .frame(width: 34, height: 34)
                }
                .foregroundStyle(KairosColors.accent)
                .kairosGlass(cornerRadius: 17, tint: KairosColors.accent.opacity(0.08))
                .accessibilityLabel("Open goals")
            }

            ForEach(Array(activeGoals.enumerated()), id: \.offset) { index, goalID in
                goalRow(index: index, achievementID: goalID)
            }
        }
        .padding(18)
        .kairosCard(cornerRadius: 26)
    }

    private func goalRow(index: Int, achievementID: String?) -> some View {
        let fallback = ["Adept", "Novice", "Task Titan"][index]
        let def = KAIROS_ACHIEVEMENTS.first(where: { $0.id == achievementID })
        let title = def?.name ?? fallback
        let progress = def.map(goalProgress(for:)) ?? 0

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Text(def?.icon ?? ["🌀", "🔥", "🗿"][index])
                    .font(.title3)

                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .tint(KairosColors.accent)
        }
    }

    private func goalProgress(for def: AchievementDef) -> Double {
        let current: Int64
        switch def.type {
        case "focus_seconds": current = profileRepo.focusData?.totalSeconds ?? 0
        case "tasks_completed": current = Int64(profileRepo.achievementsData?.lifetimeTasksCompleted ?? 0)
        default: current = profileRepo.achievementsData?.unlocked?[def.id] != nil ? 1 : 0
        }
        guard def.threshold > 0 else { return current > 0 ? 1 : 0 }
        return min(Double(current) / Double(def.threshold), 1)
    }

    private var routineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Routine Stats")
                        .font(.headline.weight(.bold))
                    Text("Today’s progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(Int(completion * 100))%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(KairosColors.accent)
            }

            ProgressView(value: completion)
                .tint(KairosColors.accent)
                .scaleEffect(y: 1.5)
                .padding(.vertical, 4)

            HStack {
                Text("\(completedCount) of \(allTasks.count) tasks completed")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: completion >= 1 ? "checkmark.seal.fill" : "checkmark.circle.fill")
                    .foregroundStyle(KairosColors.accent)
            }
        }
        .padding(18)
        .kairosCard(cornerRadius: 26)
    }

    @ViewBuilder
    private var boardsPreview: some View {
        if planRepo.isLoading {
            HStack {
                ProgressView()
                Text("Loading your plan…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(20)
            .kairosCard(cornerRadius: 26)
        } else if let plan = planRepo.currentPlan {
            let boards = plan.boards.filter { !$0.archived }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your Boards")
                            .font(.headline.weight(.bold))
                        Text(boards.isEmpty ? "Nothing here yet" : "A quick look at your work")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        onNavigate?(1)
                    } label: {
                        Text("Open")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(KairosColors.accent)
                    .kairosGlass(cornerRadius: 16, tint: KairosColors.accent.opacity(0.08))
                }

                ForEach(Array(boards.prefix(2))) { board in
                    boardPreview(board)
                }

                if boards.count > 2 {
                    Text("+\(boards.count - 2) more boards")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                }
            }
            .padding(18)
            .kairosCard(cornerRadius: 26)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(KairosColors.accent)

                Text("Your workspace is waiting")
                    .font(.headline)

                Text("Create a plan on Kairos web or Android to see your boards here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Open Boards") {
                    onNavigate?(1)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KairosColors.accent)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .kairosCard(cornerRadius: 26)
        }
    }

    private func boardPreview(_ board: KairosBoard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.caption)
                    .foregroundStyle(KairosColors.accent)

                Text(board.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)

                Spacer()
            }

            ForEach(Array(board.sections.filter { !$0.archived }.prefix(2))) { section in
                let visibleTasks = section.tasks.filter { !$0.archived }

                HStack(spacing: 9) {
                    Image(systemName: "circle.dotted")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(section.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)

                    Spacer()

                    Text("\(visibleTasks.filter(\.completed).count)/\(visibleTasks.count)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func formatCompactDuration(_ seconds: Int64) -> String {
        guard seconds > 0 else { return "0m" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(max(minutes, 1))m"
    }
}

#Preview {
    DashboardView()
        .environment(SessionStore())
        .environment(StudyPlanRepository())
        .environment(UserProfileRepository())
}
