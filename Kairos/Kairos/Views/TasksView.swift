import SwiftUI
import UIKit

struct TasksView: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(UserProfileRepository.self) private var profileRepo

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
    @State private var notificationManager = KairosNotificationManager()

    private var visibleBoards: [KairosBoard] {
        planRepo.currentPlan?.boards.filter { !$0.archived } ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if planRepo.isLoading {
                        ProgressView("Loading your workspace…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else if visibleBoards.isEmpty {
                        emptyState
                    } else {
                        ForEach(visibleBoards) { board in
                            boardCard(board)
                        }
                    }

                    if let error = planRepo.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 90)
            }
            .kairosBackground()
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                Button {
                    newBoardName = ""
                    showAddBoard = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .frame(width: 58, height: 58)
                }
                .foregroundStyle(.white)
                .background(KairosColors.accent, in: Circle())
                .shadow(color: KairosColors.accent.opacity(0.25), radius: 18, y: 8)
                .padding(.bottom, 4)
                .accessibilityLabel("Add board")
                .accessibilityHint("Creates a new study board")
            }
            .alert("New Board", isPresented: $showAddBoard) {
                TextField("Board name", text: $newBoardName)
                Button("Cancel", role: .cancel) {}
                Button("Add") { confirmAddBoard() }
            }
            .alert("New Section", isPresented: Binding(get: { boardForNewSection != nil }, set: { if !$0 { boardForNewSection = nil } })) {
                TextField("Section name", text: $newSectionName)
                Button("Cancel", role: .cancel) { boardForNewSection = nil }
                Button("Add") { confirmAddSection() }
            }
            .alert("New Task", isPresented: Binding(get: { sectionForNewTask != nil }, set: { if !$0 { sectionForNewTask = nil } })) {
                TextField("Task name", text: $newTaskName)
                Button("Cancel", role: .cancel) { sectionForNewTask = nil }
                Button("Add") { confirmAddTask() }
            }
            .alert("Rename Board", isPresented: Binding(get: { boardToRename != nil }, set: { if !$0 { boardToRename = nil } })) {
                TextField("Board name", text: $renameBoardText)
                Button("Cancel", role: .cancel) { boardToRename = nil }
                Button("Save") { confirmRenameBoard() }
            }
            .alert("Rename Section", isPresented: Binding(get: { sectionToRename != nil }, set: { if !$0 { sectionToRename = nil } })) {
                TextField("Section name", text: $renameSectionText)
                Button("Cancel", role: .cancel) { sectionToRename = nil }
                Button("Save") { confirmRenameSection() }
            }
            .alert("Rename Task", isPresented: Binding(get: { taskToRename != nil }, set: { if !$0 { taskToRename = nil } })) {
                TextField("Task name", text: $renameTaskText)
                Button("Cancel", role: .cancel) { taskToRename = nil }
                Button("Save") { confirmRenameTask() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Your Boards")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Manage your active workspace. Build a day that works for you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func boardCard(_ board: KairosBoard) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(board.title, systemImage: "square.stack.3d.up.fill")
                    .font(.headline.weight(.bold))
                Spacer()
                boardMenu(board)
            }

            ForEach(board.sections.filter { !$0.archived }) { section in
                sectionBlock(board: board, section: section)
            }

            Button {
                newSectionName = ""
                boardForNewSection = board
            } label: {
                Label("Add Section", systemImage: "plus")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(KairosColors.accent)
        }
        .padding(18)
        .kairosCard(cornerRadius: 26)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(board.title)
    }

    @ViewBuilder
    private func boardMenu(_ board: KairosBoard) -> some View {
        Menu {
            Button("Rename") { renameBoardText = board.title; boardToRename = board }
            Button("Add Section") { newSectionName = ""; boardForNewSection = board }
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
        .accessibilityHint("Rename, add a section, or archive this board")
    }

    private func sectionBlock(board: KairosBoard, section: KairosSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                sectionMenu(board: board, section: section)
            }

            ForEach(section.tasks.filter { !$0.archived }) { task in
                taskRow(boardID: board.id, section: section, task: task)
            }

            Button {
                newTaskName = ""
                sectionForNewTask = (board, section)
            } label: {
                Label("Add Task", systemImage: "plus")
                    .font(.caption)
            }
            .foregroundStyle(KairosColors.accent)
            .padding(.leading, 4)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func sectionMenu(board: KairosBoard, section: KairosSection) -> some View {
        Menu {
            Button("Rename") { renameSectionText = section.title; sectionToRename = (board, section) }
            Button("Add Task") { newTaskName = ""; sectionForNewTask = (board, section) }
            Button("Archive", role: .destructive) {
                Task { await planRepo.setSectionArchived(sectionID: section.id, archived: true) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.tertiary)
        }
        .accessibilityLabel("Section actions")
        .accessibilityHint("Rename, add a task, or archive this section")
    }

    private func taskRow(boardID: String, section: KairosSection, task: KairosTask) -> some View {
        Button {
            let willComplete = !task.completed
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
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.completed ? KairosColors.accent : .secondary)
                Text(task.title)
                    .font(.subheadline)
                    .foregroundStyle(task.completed ? .secondary : .primary)
                    .strikethrough(task.completed)
                Spacer()
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.title)
        .accessibilityValue(task.completed ? "Completed" : "Not completed")
        .accessibilityHint(task.completed ? "Double tap to mark incomplete" : "Double tap to complete")
        .swipeActions(edge: .trailing) {
            Button("Rename") { renameTaskText = task.title; taskToRename = (section, task) }.tint(.blue)
            Button("Archive", role: .destructive) { Task { await planRepo.setTaskArchived(taskID: task.id, archived: true) } }
        }
    }

    private func notifyIfBoardCompleted(boardID: String) async {
        guard profileRepo.notificationSettings?.enabled != false,
              profileRepo.notificationSettings?.boardCompletion != false,
              let board = planRepo.currentPlan?.boards.first(where: { $0.id == boardID }) else { return }

        let tasks = board.sections
            .filter { !$0.archived }
            .flatMap { $0.tasks.filter { !$0.archived } }
        guard !tasks.isEmpty, tasks.allSatisfy(\.completed) else { return }

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
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 34))
                .foregroundStyle(KairosColors.accent)
            Text("No boards yet")
                .font(.headline)
            Text("Create a board to start organizing your routine.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .kairosCard(cornerRadius: 26)
    }
}

#Preview {
    TasksView()
        .environment(StudyPlanRepository())
        .environment(UserProfileRepository())
}
