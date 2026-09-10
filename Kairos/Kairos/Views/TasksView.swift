import SwiftUI

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

    private var visibleBoards: [KairosBoard] {
        planRepo.currentPlan?.boards.filter { !$0.archived } ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if planRepo.isLoading {
                        ProgressView("Loading tasks…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
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
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newBoardName = ""
                        showAddBoard = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .alert("New Board", isPresented: $showAddBoard) {
                TextField("Board name", text: $newBoardName)
                Button("Cancel", role: .cancel) {}
                Button("Add") { confirmAddBoard() }
            }
            .alert("New Section", isPresented: Binding(
                get: { boardForNewSection != nil },
                set: { if !$0 { boardForNewSection = nil } }
            )) {
                TextField("Section name", text: $newSectionName)
                Button("Cancel", role: .cancel) { boardForNewSection = nil }
                Button("Add") { confirmAddSection() }
            }
            .alert("New Task", isPresented: Binding(
                get: { sectionForNewTask != nil },
                set: { if !$0 { sectionForNewTask = nil } }
            )) {
                TextField("Task name", text: $newTaskName)
                Button("Cancel", role: .cancel) { sectionForNewTask = nil }
                Button("Add") { confirmAddTask() }
            }
            .alert("Rename Board", isPresented: Binding(
                get: { boardToRename != nil },
                set: { if !$0 { boardToRename = nil } }
            )) {
                TextField("Board name", text: $renameBoardText)
                Button("Cancel", role: .cancel) { boardToRename = nil }
                Button("Save") { confirmRenameBoard() }
            }
            .alert("Rename Section", isPresented: Binding(
                get: { sectionToRename != nil },
                set: { if !$0 { sectionToRename = nil } }
            )) {
                TextField("Section name", text: $renameSectionText)
                Button("Cancel", role: .cancel) { sectionToRename = nil }
                Button("Save") { confirmRenameSection() }
            }
            .alert("Rename Task", isPresented: Binding(
                get: { taskToRename != nil },
                set: { if !$0 { taskToRename = nil } }
            )) {
                TextField("Task name", text: $renameTaskText)
                Button("Cancel", role: .cancel) { taskToRename = nil }
                Button("Save") { confirmRenameTask() }
            }
        }
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

    @ViewBuilder
    private func boardCard(_ board: KairosBoard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(board.title)
                    .font(.headline)
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
                    .font(.subheadline)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
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
                let id = board.id
                Task { await planRepo.setBoardArchived(boardID: id, archived: true) }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sectionBlock(board: KairosBoard, section: KairosSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
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
            .padding(.leading, 4)
        }
    }

    @ViewBuilder
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
                let id = section.id
                Task { await planRepo.setSectionArchived(sectionID: id, archived: true) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.tertiary)
        }
    }

    private func taskRow(boardID: String, section: KairosSection, task: KairosTask) -> some View {
        let sectionID = section.id
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
        .swipeActions(edge: .trailing) {
            Button("Rename") {
                renameTaskText = task.title
                taskToRename = (section, task)
            }
            .tint(.blue)

            Button("Archive", role: .destructive) {
                Task { await planRepo.setTaskArchived(taskID: taskID, archived: true) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No boards yet")
                .font(.headline)
            Text("Tap + to create your first board.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

#Preview {
    TasksView()
        .environment(StudyPlanRepository())
        .environment(UserProfileRepository())
}
