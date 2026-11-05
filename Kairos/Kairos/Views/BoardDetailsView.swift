import SwiftUI

struct BoardDetailsView: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(\.dismiss) private var dismiss

    let board: KairosBoard
    @State private var name: String
    @State private var description: String
    @State private var submitting = false
    @State private var saveError: String?

    init(board: KairosBoard) {
        self.board = board
        _name = State(initialValue: board.title)
        _description = State(initialValue: board.boardDescription ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Board name", text: $name)
                        .font(.headline)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Board details")
                } footer: {
                    Text("Changes are saved to your Kairos study plan and stay synced across your devices.")
                }

                if let saveError { Text(saveError).font(.footnote).foregroundStyle(.red) }
                if submitting { ProgressView("Saving…") }

                Section("Overview") {
                    LabeledContent("Sections", value: "\(board.sections.filter { !$0.archived }.count)")
                    LabeledContent("Tasks", value: "\(board.sections.filter { !$0.archived }.flatMap { $0.tasks.filter { !$0.archived } }.count)")
                }

                Section {
                    Button("Archive Board", role: .destructive) {
                        guard !submitting else { return }
                        submitting = true
                        Task {
                            let saved = await planRepo.setBoardArchived(boardID: board.id, archived: true)
                            submitting = false
                            if saved { dismiss() } else { saveError = planRepo.errorMessage }
                        }
                    }
                }
            }
            .disabled(submitting)
            .interactiveDismissDisabled()
            .navigationTitle("Edit Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { PlannerSearchButton().disabled(submitting) }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(submitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !submitting else { return }
        submitting = true
        saveError = nil
        Task {
            let saved = await planRepo.updateBoard(
                boardID: board.id,
                title: trimmedName,
                description: trimmedDescription.isEmpty ? nil : trimmedDescription
            )
            submitting = false
            if saved { dismiss() } else { saveError = planRepo.errorMessage ?? "Could not save. Your edits are still here." }
        }
    }
}

#Preview {
    BoardDetailsView(board: KairosBoard(id: "preview", title: "Study", archived: false, sections: [], boardDescription: "A focused study checklist."))
        .environment(StudyPlanRepository())
}
