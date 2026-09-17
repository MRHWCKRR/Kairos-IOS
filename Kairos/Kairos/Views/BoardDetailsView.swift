import SwiftUI

struct BoardDetailsView: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(\.dismiss) private var dismiss

    let board: KairosBoard
    @State private var name: String
    @State private var description: String
    @State private var showingDeleteConfirmation = false

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

                Section("Overview") {
                    LabeledContent("Sections", value: "\(board.sections.filter { !$0.archived }.count)")
                    LabeledContent("Tasks", value: "\(board.sections.filter { !$0.archived }.flatMap { $0.tasks.filter { !$0.archived } }.count)")
                }

                Section {
                    Button("Archive Board", role: .destructive) {
                        Task {
                            await planRepo.setBoardArchived(boardID: board.id, archived: true)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Edit Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
        guard !trimmedName.isEmpty else { return }
        Task {
            await planRepo.updateBoard(
                boardID: board.id,
                title: trimmedName,
                description: trimmedDescription.isEmpty ? nil : trimmedDescription
            )
            dismiss()
        }
    }
}

#Preview {
    BoardDetailsView(board: KairosBoard(id: "preview", title: "Study", archived: false, sections: [], boardDescription: "A focused study checklist."))
        .environment(StudyPlanRepository())
}
