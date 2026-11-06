import SwiftUI

struct PlannerArchiveView: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(\.dismiss) private var dismiss
    @State private var restoring = false
    @State private var error: String?

    private var boards: [KairosBoard] {
        (planRepo.currentPlan?.boards ?? []).filter { board in
            board.archived || board.sections.contains { $0.archived || $0.tasks.contains(where: \.archived) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Restore a board before its sections, and a section before its tasks. Restoring a parent keeps individually archived children in Archive.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
                if restoring { ProgressView("Restoring…") }
                if boards.isEmpty { ContentUnavailableView { Label("Archive is empty", sharedIcon: "archivebox") } }
                ForEach(boards) { board in
                    Section {
                        if board.archived {
                            archiveRow(board.title, kind: "Board", canRestore: true) {
                                await planRepo.setBoardArchived(boardID: board.id, archived: false)
                            }
                        }
                        ForEach(board.sections.filter { board.archived || $0.archived || $0.tasks.contains(where: \.archived) }) { section in
                            if section.archived || board.archived {
                                archiveRow(section.title, kind: board.archived ? "Section · restore board first" : "Section", canRestore: section.archived && !board.archived) {
                                    await planRepo.setSectionArchived(sectionID: section.id, archived: false)
                                }
                            }
                            ForEach(section.tasks.filter { board.archived || section.archived || $0.archived }) { task in
                                archiveRow(task.title, kind: board.archived || section.archived ? "Task · restore parent first" : "Task", canRestore: task.archived && !board.archived && !section.archived) {
                                    await planRepo.setTaskArchived(taskID: task.id, archived: false)
                                }
                            }
                        }
                    } header: { Text(board.title) }
                }
            }
            .disabled(restoring || planRepo.isSaving || planRepo.isLoading)
            .navigationTitle("Archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(restoring) } }
            .interactiveDismissDisabled(restoring)
        }
    }

    private func archiveRow(_ title: String, kind: String, canRestore: Bool, action: @escaping () async -> Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(kind).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if canRestore {
                Button("Restore") {
                    guard !restoring, !planRepo.isSaving else { return }
                    restoring = true
                    error = nil
                    Task {
                        let saved = await action()
                        restoring = false
                        if !saved { error = planRepo.errorMessage ?? "Could not restore. Try again." }
                    }
                }.buttonStyle(.bordered)
            }
        }
    }
}

