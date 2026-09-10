import SwiftUI
import FirebaseAuth

struct DashboardView: View {
    @Environment(SessionStore.self) private var session
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(UserProfileRepository.self) private var profileRepo
    @State private var showingProfile = false
    @State private var focusTimer: FocusTimerViewModel?

    private var displayName: String {
        let name = profileRepo.profile?.displayName ?? ""
        return name.isEmpty ? session.email : name
    }

    private var allTasks: [KairosTask] {
        planRepo.currentPlan?.boards.flatMap { $0.sections.flatMap { $0.tasks } } ?? []
    }

    private var completedCount: Int {
        allTasks.filter(\.completed).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if let focusTimer {
                        FocusTimerCard(viewModel: focusTimer)
                    }

                    if planRepo.isLoading {
                        ProgressView("Loading your plan…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if let plan = planRepo.currentPlan {
                        progressSummary
                        boardsList(plan: plan)
                    } else {
                        emptyState
                    }

                    if let error = planRepo.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Kairos")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingProfile = true
                    } label: {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.purple)
                    }
                }
            }
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Welcome back")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(displayName)
                .font(.system(size: 26, weight: .bold, design: .rounded))
        }
    }

    private var progressSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(completedCount) of \(allTasks.count) tasks done")
                    .font(.subheadline.weight(.semibold))
                ProgressView(value: allTasks.isEmpty ? 0 : Double(completedCount), total: Double(max(allTasks.count, 1)))
                    .tint(.purple)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func boardsList(plan: KairosStudyPlan) -> some View {
        ForEach(plan.boards.filter { !$0.archived }) { board in
            VStack(alignment: .leading, spacing: 12) {
                Text(board.title)
                    .font(.headline)

                ForEach(board.sections.filter { !$0.archived }) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(section.tasks.filter { !$0.archived }) { task in
                            taskRow(task: task, boardID: board.id, sectionID: section.id)
                        }
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private func taskRow(task: KairosTask, boardID: String, sectionID: String) -> some View {
        let taskID = task.id
        let willComplete = !task.completed

        return Button {
            Task {
                await planRepo.toggleTask(boardID: boardID, sectionID: sectionID, taskID: taskID)
                if willComplete {
                    await profileRepo.recordTaskCompletion(taskID: taskID)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.completed ? .purple : .secondary)

                Text(task.title)
                    .font(.body)
                    .foregroundStyle(task.completed ? .secondary : .primary)
                    .strikethrough(task.completed)

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No study plan yet")
                .font(.headline)
            Text("Create one on Kairos web or Android to see it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

private struct FocusTimerCard: View {
    let viewModel: FocusTimerViewModel
    @Environment(UserProfileRepository.self) private var profileRepo

    private var longestSessionText: String {
        FocusTimerViewModel.formatHMS(profileRepo.focusData?.longestSessionSeconds ?? 0)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(viewModel.isRunning ? "FOCUS ACTIVE" : "TIMER READY")
                .font(.caption.weight(.bold))
                .foregroundStyle(viewModel.isRunning ? .purple : .secondary)
                .tracking(1)

            Text(FocusTimerViewModel.formatHMS(viewModel.elapsedSeconds))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(viewModel.isRunning ? .purple : .primary)

            Text("Longest: \(longestSessionText)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if viewModel.isRunning {
                    Button {
                        viewModel.pause()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        viewModel.start()
                    } label: {
                        Label("Start Focus", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }

                Button {
                    viewModel.stopAndLog()
                } label: {
                    Text("Stop")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    DashboardView()
        .environment(SessionStore())
        .environment(StudyPlanRepository())
        .environment(UserProfileRepository())
}
