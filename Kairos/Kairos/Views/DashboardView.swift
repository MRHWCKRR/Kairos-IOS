import SwiftUI

struct DashboardView: View {
    @Environment(SessionStore.self) private var session
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingProfile = false
    @State private var focusTimer: FocusTimerViewModel?

    private var displayName: String {
        let name = profileRepo.profile?.displayName ?? ""
        return name.isEmpty ? session.email : name
    }

    private var allTasks: [KairosTask] {
        planRepo.currentPlan?.boards.flatMap { board in
            board.sections.filter { !$0.archived }.flatMap { $0.tasks.filter { !$0.archived } }
        } ?? []
    }

    private var completedCount: Int { allTasks.filter(\.completed).count }

    private var completion: Double {
        guard !allTasks.isEmpty else { return 0 }
        return Double(completedCount) / Double(allTasks.count)
    }

    private var activeGoals: [String?] {
        let saved = profileRepo.achievementsData?.goals ?? []
        return (0..<3).map { saved.indices.contains($0) ? saved[$0] : nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    focusCard
                    goalsCard
                    routineCard
                    boardsPreview
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
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
            VStack(alignment: .leading, spacing: 3) {
                Text("Welcome back")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(displayName)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 12)

            Button { showingProfile = true } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(KairosColors.accent)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel("Open profile")
            .kairosGlass(cornerRadius: 18, tint: KairosColors.accent.opacity(0.10))
        }
    }

    private var focusCard: some View {
        Group {
            if let focusTimer {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Label("FOCUS TIMER", systemImage: "timer")
                            .font(.caption.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(KairosColors.accent)
                        Spacer()
                        Text(focusTimer.isRunning ? "ACTIVE" : "READY")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(focusTimer.isRunning ? KairosColors.accent : .secondary)
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

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Active Goals")
                    .font(.headline.weight(.bold))
                Spacer()
                Image(systemName: "trophy.fill")
                    .foregroundStyle(KairosColors.accent)
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
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(KairosColors.accent)
            }
        }
        .padding(18)
        .kairosCard(cornerRadius: 26)
    }

    @ViewBuilder
    private var boardsPreview: some View {
        if planRepo.isLoading {
            ProgressView("Loading your plan…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
        } else if let plan = planRepo.currentPlan {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Your Boards")
                        .font(.headline.weight(.bold))
                    Spacer()
                    Text("\(plan.boards.filter { !$0.archived }.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                ForEach(plan.boards.filter { !$0.archived }.prefix(2)) { board in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(board.title)
                            .font(.subheadline.weight(.bold))
                        ForEach(board.sections.filter { !$0.archived }.prefix(2)) { section in
                            HStack(spacing: 9) {
                                Image(systemName: "square.stack.3d.up")
                                    .foregroundStyle(KairosColors.accent)
                                Text(section.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(section.tasks.filter { !$0.archived && $0.completed }.count)/\(section.tasks.filter { !$0.archived }.count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding(18)
            .kairosCard(cornerRadius: 26)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 30))
                    .foregroundStyle(KairosColors.accent)
                Text("No study plan yet")
                    .font(.headline)
                Text("Create a plan on Kairos web or Android to see it here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .kairosCard(cornerRadius: 26)
        }
    }
}

#Preview {
    DashboardView()
        .environment(SessionStore())
        .environment(StudyPlanRepository())
        .environment(UserProfileRepository())
}
