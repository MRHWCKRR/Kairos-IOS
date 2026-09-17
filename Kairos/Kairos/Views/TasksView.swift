import SwiftUI
import UIKit

struct TasksView: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showAddBoard = false
    @State private var newBoardName = ""
    @State private var boardForNewSection: KairosBoard?
    @State private var newSectionName = ""
    @State private var sectionForNewTask: (board: KairosBoard, section: KairosSection)?
    @State private var newTaskName = ""
    @State private var boardToRename: KairosBoard?
    @State private var renameBoardText = ""
    @State private var sectionToRename: (board: KairosBoard, section: KairosSection)?
    @State private var renameSectionText = ""
    @State private var taskToRename: (section: KairosSection, task: KairosTask)?
    @State private var renameTaskText = ""
    @State private var reminderManager = KairosReminderManager()
    @State private var notificationManager = KairosNotificationManager()
    @State private var showingReminderAlert = false
    @State private var reminderMessage = ""
    @State private var isAddBoardButtonExpanded = false
    @State private var showingCompleted = true
    @State private var optimisticCompletedIDs: Set<String> = []

    private var visibleBoards: [KairosBoard] {
        planRepo.currentPlan?.boards.filter { !$0.archived } ?? []
    }

    private var allVisibleTasks: [KairosTask] {
        visibleBoards.flatMap { $0.sections.filter { !$0.archived } }.flatMap { $0.tasks.filter { !$0.archived } }
    }

    private var completedTaskCount: Int {
        allVisibleTasks.filter { $0.completed || optimisticCompletedIDs.contains($0.id) }.count
    }

    var body: some View {
        NavigationStack {
            workspaceContent
                .kairosBackground()
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .bottom, spacing: 0) { addBoardButton }
                .applyTasksAlerts(
                    showAddBoard: $showAddBoard,
                    newBoardName: $newBoardName,
                    boardForNewSection: $boardForNewSection,
                    newSectionName: $newSectionName,
                    sectionForNewTask: $sectionForNewTask,
                    newTaskName: $newTaskName,
                    boardToRename: $boardToRename,
                    renameBoardText: $renameBoardText,
                    sectionToRename: $sectionToRename,
                    renameSectionText: $renameSectionText,
                    taskToRename: $taskToRename,
                    renameTaskText: $renameTaskText,
                    showingReminderAlert: $showingReminderAlert,
                    reminderMessage: $reminderMessage,
                    reduceMotion: reduceMotion,
                    confirmAddBoard: confirmAddBoard,
                    confirmAddSection: confirmAddSection,
                    confirmAddTask: confirmAddTask,
                    confirmRenameBoard: confirmRenameBoard,
                    confirmRenameSection: confirmRenameSection,
                    confirmRenameTask: confirmRenameTask
                )
                .onAppear { reminderManager.refreshAuthorizationState() }
        }
    }

    private var workspaceContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header
                summaryCard

                if planRepo.isLoading {
                    ProgressView("Loading your tasks…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else if visibleBoards.isEmpty {
                    emptyState
                } else {
                    boardList
                }

                if let error = planRepo.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, KairosMetrics.pageHorizontal)
            .padding(.top, 16)
            .padding(.bottom, 150)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Tasks")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-1)
            Text("Everything you need to get done, organized into focused checklists.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your checklist").font(.headline.weight(.bold))
                    Text(completedTaskCount == 0 ? "Start with one small win." : "Keep the momentum going.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.14), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progressFraction)
                        .stroke(KairosColors.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(progressFraction * 100))%")
                        .font(.caption.weight(.bold))
                }
                .frame(width: 58, height: 58)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: progressFraction)
            }

            HStack(spacing: 0) {
                summaryMetric("\(max(0, allVisibleTasks.count - completedTaskCount))", "Remaining")
                Divider().frame(height: 32)
                summaryMetric("\(completedTaskCount)", "Completed")
                Divider().frame(height: 32)
                summaryMetric("\(allVisibleTasks.count)", "Total")
            }
        }
        .padding(20)
        .kairosCard(cornerRadius: 26)
    }

    private var progressFraction: Double {
        guard !allVisibleTasks.isEmpty else { return 0 }
        return Double(completedTaskCount) / Double(allVisibleTasks.count)
    }

    private func summaryMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var boardList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Checklists").font(.title3.weight(.bold))
                Spacer()
                Button(showingCompleted ? "Hide completed" : "Show completed") {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showingCompleted.toggle() }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(KairosColors.accent)
            }

            ForEach(visibleBoards) { board in
                boardCard(board)
            }
        }
    }

    private var addBoardButton: some View {
        HStack {
            Spacer()
            Button {
                newBoardName = ""
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                    isAddBoardButtonExpanded.toggle()
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showAddBoard = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .rotationEffect(.degrees(isAddBoardButtonExpanded ? 45 : 0))
                    .frame(width: 58, height: 58)
            }
            .foregroundStyle(.white)
            .background(KairosColors.accent, in: Circle())
            .shadow(color: KairosColors.accent.opacity(0.25), radius: 18, y: 8)
            .accessibilityLabel("Add board")
            .accessibilityHint("Creates a new study board")
            .padding(.trailing, 4)
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private func boardCard(_ board: KairosBoard) -> some View {
        let sections = board.sections.filter { !$0.archived }
        let boardTasks = sections.flatMap { $0.tasks.filter { !$0.archived } }
        let completed = boardTasks.filter { $0.completed || optimisticCompletedIDs.contains($0.id) }.count

        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                Image(systemName: "checklist")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(KairosColors.accent)
                    .frame(width: 38, height: 38)
                    .background(KairosColors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(board.title).font(.headline.weight(.bold))
                    Text("\(completed) of \(boardTasks.count) complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                boardMenu(board)
            }

            if !boardTasks.isEmpty {
                ProgressView(value: Double(completed), total: Double(boardTasks.count))
                    .tint(KairosColors.accent)
                    .scaleEffect(y: 1.2)
            }

            ForEach(sections) { section in
                sectionBlock(board: board, section: section)
            }

            Button {
                newSectionName = ""
                boardForNewSection = board
            } label: {
                Label("Add section", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(KairosColors.accent)
        }
        .padding(18)
        .kairosCard(cornerRadius: 26)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(board.title)
    }

    private func boardMenu(_ board: KairosBoard) -> some View {
        Menu {
            Button("Rename") {
                renameBoardText = board.title
                boardToRename = board
            }
            Button("Add Section") {
                newSectionName = ""
                boardForNewSection = board
            }
            Button("Archive", role: .destructive) {
                Task { await planRepo.setBoardArchived(boardID: board.id, archived: true) }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .kairosGlass(cornerRadius: 16)
        }
        .accessibilityLabel("Board actions")
    }

    private func sectionBlock(board: KairosBoard, section: KairosSection) -> some View {
        let visibleTasks = section.tasks.filter { !$0.archived }
        let openTasks = visibleTasks.filter { !$0.completed && !optimisticCompletedIDs.contains($0.id) }
        let completedTasks = visibleTasks.filter { $0.completed || optimisticCompletedIDs.contains($0.id) }
        let sectionComplete = !visibleTasks.isEmpty && openTasks.isEmpty

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title).font(.subheadline.weight(.bold))
                    Text(visibleTasks.isEmpty ? "No tasks yet" : "\(completedTasks.count) of \(visibleTasks.count) complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if sectionComplete {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(KairosColors.accent)
                        .transition(.scale.combined(with: .opacity))
                }
                sectionMenu(board: board, section: section)
            }

            if !openTasks.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(openTasks.enumerated()), id: \.element.id) { index, task in
                        taskRow(boardID: board.id, section: section, task: task)
                        if index < openTasks.count - 1 { Divider().padding(.leading, 44).opacity(0.28) }
                    }
                }
            }

            if showingCompleted && !completedTasks.isEmpty {
                if !openTasks.isEmpty {
                    Text("Completed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                VStack(spacing: 0) {
                    ForEach(Array(completedTasks.enumerated()), id: \.element.id) { index, task in
                        taskRow(boardID: board.id, section: section, task: task)
                        if index < completedTasks.count - 1 { Divider().padding(.leading, 44).opacity(0.20) }
                    }
                }
            }

            Button {
                newTaskName = ""
                sectionForNewTask = (board, section)
            } label: {
                Label("Add task", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(KairosColors.accent)
            .padding(.top, 2)
        }
        .padding(15)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func sectionMenu(board: KairosBoard, section: KairosSection) -> some View {
        Menu {
            Button("Rename") {
                renameSectionText = section.title
                sectionToRename = (board, section)
            }
            Button("Add Task") {
                newTaskName = ""
                sectionForNewTask = (board, section)
            }
            Button("Archive", role: .destructive) {
                Task { await planRepo.setSectionArchived(sectionID: section.id, archived: true) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.tertiary)
                .frame(width: 30, height: 30)
        }
        .accessibilityLabel("Section actions")
    }

    private func taskRow(boardID: String, section: KairosSection, task: KairosTask) -> some View {
        let isCompleted = task.completed || optimisticCompletedIDs.contains(task.id)

        return Button {
            toggleTask(boardID: boardID, section: section, task: task)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(isCompleted ? KairosColors.accent : Color.secondary.opacity(0.48), lineWidth: 1.8)
                        .frame(width: 24, height: 24)
                    if isCompleted {
                        Circle().fill(KairosColors.accent).frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                Text(task.title)
                    .font(.subheadline.weight(isCompleted ? .medium : .semibold))
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                    .strikethrough(isCompleted, color: KairosColors.accent)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                if task.date != nil && !isCompleted {
                    Image(systemName: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82), value: isCompleted)
        .accessibilityLabel(task.title)
        .accessibilityValue(isCompleted ? "Completed" : "Not completed")
        .accessibilityHint(isCompleted ? "Double tap to mark incomplete" : "Double tap to complete")
        .contextMenu {
            Button { addTaskToReminders(task) } label: { Label("Add to Reminders", systemImage: "checklist") }
            Button {
                renameTaskText = task.title
                taskToRename = (section, task)
            } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) {
                Task { await planRepo.setTaskArchived(taskID: task.id, archived: true) }
            } label: { Label("Archive", systemImage: "archivebox") }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Rename") {
                renameTaskText = task.title
                taskToRename = (section, task)
            }.tint(.blue)
            Button("Remind") { addTaskToReminders(task) }.tint(KairosColors.accent)
            Button("Archive", role: .destructive) {
                Task { await planRepo.setTaskArchived(taskID: task.id, archived: true) }
            }
        }
    }

    private func toggleTask(boardID: String, section: KairosSection, task: KairosTask) {
        let currentlyCompleted = task.completed || optimisticCompletedIDs.contains(task.id)
        let willComplete = !currentlyCompleted

        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82)) {
            if willComplete { optimisticCompletedIDs.insert(task.id) }
            else { optimisticCompletedIDs.remove(task.id) }
        }

        if willComplete {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        Task {
            await planRepo.toggleTask(boardID: boardID, sectionID: section.id, taskID: task.id)
            if willComplete {
                await profileRepo.recordTaskCompletion(taskID: task.id)
                await notifyIfBoardCompleted(boardID: boardID)
            }
            await MainActor.run {
                optimisticCompletedIDs.remove(task.id)
            }
        }
    }

    private func addTaskToReminders(_ task: KairosTask) {
        Task {
            if reminderManager.authorizationState == .notDetermined {
                guard await reminderManager.requestAccess() else {
                    showReminderMessage("Allow Kairos access to Reminders in iOS Settings, then try again.")
                    return
                }
            }
            guard reminderManager.authorizationState == .authorized else {
                showReminderMessage("Kairos does not have access to Reminders. Enable it in iOS Settings and try again.")
                return
            }
            do {
                let created = try await reminderManager.addReminderIfNeeded(title: task.title, dueDate: reminderDueDate(for: task), notes: "Created from Kairos")
                showReminderMessage(created ? "Added “\(task.title)” to Apple Reminders." : "“\(task.title)” is already in Apple Reminders.")
            } catch { showReminderMessage(error.localizedDescription) }
        }
    }

    private func showReminderMessage(_ message: String) {
        reminderMessage = message
        showingReminderAlert = true
    }

    private func reminderDueDate(for task: KairosTask) -> Date? {
        guard let value = task.date else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func notifyIfBoardCompleted(boardID: String) async {
        let notificationsEnabled = profileRepo.notificationSettings?.enabled != false
        let boardCompletionEnabled = profileRepo.notificationSettings?.boardCompletion != false
        guard notificationsEnabled, boardCompletionEnabled else { return }
        guard let board = planRepo.currentPlan?.boards.first(where: { $0.id == boardID }) else { return }
        let activeTasks = board.sections.filter { !$0.archived }.flatMap { $0.tasks.filter { !$0.archived } }
        guard !activeTasks.isEmpty, activeTasks.allSatisfy(\.completed) else { return }
        await notificationManager.postBoardCompletion(boardTitle: board.title)
    }

    private func confirmAddBoard() {
        let name = newBoardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task { await planRepo.addBoard(title: name) }
    }

    private func confirmAddSection() {
        guard let board = boardForNewSection else { return }
        let name = newSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        boardForNewSection = nil
        guard !name.isEmpty else { return }
        Task { await planRepo.addSection(boardID: board.id, title: name) }
    }

    private func confirmAddTask() {
        guard let target = sectionForNewTask else { return }
        let name = newTaskName.trimmingCharacters(in: .whitespacesAndNewlines)
        sectionForNewTask = nil
        guard !name.isEmpty else { return }
        Task { await planRepo.addTask(sectionID: target.section.id, title: name) }
    }

    private func confirmRenameBoard() {
        guard let board = boardToRename else { return }
        let name = renameBoardText.trimmingCharacters(in: .whitespacesAndNewlines)
        boardToRename = nil
        guard !name.isEmpty else { return }
        Task { await planRepo.renameBoard(boardID: board.id, title: name) }
    }

    private func confirmRenameSection() {
        guard let target = sectionToRename else { return }
        let name = renameSectionText.trimmingCharacters(in: .whitespacesAndNewlines)
        sectionToRename = nil
        guard !name.isEmpty else { return }
        Task { await planRepo.renameSection(sectionID: target.section.id, title: name) }
    }

    private func confirmRenameTask() {
        guard let target = taskToRename else { return }
        let name = renameTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        taskToRename = nil
        guard !name.isEmpty else { return }
        Task { await planRepo.renameTask(taskID: target.task.id, title: name) }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(KairosColors.accent)
            Text("Your checklist is empty").font(.headline)
            Text("Create a board, add a section, and start with your first task.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .kairosCard(cornerRadius: 26)
    }
}

private extension View {
    func applyTasksAlerts(
        showAddBoard: Binding<Bool>,
        newBoardName: Binding<String>,
        boardForNewSection: Binding<KairosBoard?>,
        newSectionName: Binding<String>,
        sectionForNewTask: Binding<(board: KairosBoard, section: KairosSection)?>,
        newTaskName: Binding<String>,
        boardToRename: Binding<KairosBoard?>,
        renameBoardText: Binding<String>,
        sectionToRename: Binding<(board: KairosBoard, section: KairosSection)?>,
        renameSectionText: Binding<String>,
        taskToRename: Binding<(section: KairosSection, task: KairosTask)?>,
        renameTaskText: Binding<String>,
        showingReminderAlert: Binding<Bool>,
        reminderMessage: Binding<String>,
        reduceMotion: Bool,
        confirmAddBoard: @escaping () -> Void,
        confirmAddSection: @escaping () -> Void,
        confirmAddTask: @escaping () -> Void,
        confirmRenameBoard: @escaping () -> Void,
        confirmRenameSection: @escaping () -> Void,
        confirmRenameTask: @escaping () -> Void
    ) -> some View {
        self
            .alert("New Board", isPresented: showAddBoard) {
                TextField("Board name", text: newBoardName)
                Button("Cancel", role: .cancel) { }
                Button("Add", action: confirmAddBoard)
            }
            .alert("New Section", isPresented: Binding(get: { boardForNewSection.wrappedValue != nil }, set: { if !$0 { boardForNewSection.wrappedValue = nil } })) {
                TextField("Section name", text: newSectionName)
                Button("Cancel", role: .cancel) { boardForNewSection.wrappedValue = nil }
                Button("Add", action: confirmAddSection)
            }
            .alert("New Task", isPresented: Binding(get: { sectionForNewTask.wrappedValue != nil }, set: { if !$0 { sectionForNewTask.wrappedValue = nil } })) {
                TextField("Task name", text: newTaskName)
                Button("Cancel", role: .cancel) { sectionForNewTask.wrappedValue = nil }
                Button("Add", action: confirmAddTask)
            }
            .alert("Rename Board", isPresented: Binding(get: { boardToRename.wrappedValue != nil }, set: { if !$0 { boardToRename.wrappedValue = nil } })) {
                TextField("Board name", text: renameBoardText)
                Button("Cancel", role: .cancel) { boardToRename.wrappedValue = nil }
                Button("Save", action: confirmRenameBoard)
            }
            .alert("Rename Section", isPresented: Binding(get: { sectionToRename.wrappedValue != nil }, set: { if !$0 { sectionToRename.wrappedValue = nil } })) {
                TextField("Section name", text: renameSectionText)
                Button("Cancel", role: .cancel) { sectionToRename.wrappedValue = nil }
                Button("Save", action: confirmRenameSection)
            }
            .alert("Rename Task", isPresented: Binding(get: { taskToRename.wrappedValue != nil }, set: { if !$0 { taskToRename.wrappedValue = nil } })) {
                TextField("Task name", text: renameTaskText)
                Button("Cancel", role: .cancel) { taskToRename.wrappedValue = nil }
                Button("Save", action: confirmRenameTask)
            }
            .alert("Add to Reminders", isPresented: showingReminderAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(reminderMessage.wrappedValue)
            }
    }
}

#Preview {
    TasksView()
        .environment(StudyPlanRepository())
        .environment(UserProfileRepository())
}
