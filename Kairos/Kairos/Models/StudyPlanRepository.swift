import Foundation
import Observation
import FirebaseFirestore
import FirebaseAuth

@Observable
@MainActor
final class StudyPlanRepository {
    var currentPlan: KairosStudyPlan?
    var isLoading = false
    var errorMessage: String?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func startListening(userID: String) {
        stopListening()
        isLoading = true

        listener = db.collection("study_plans")
            .whereField("userID", isEqualTo: userID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                self.isLoading = false

                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    self.currentPlan = nil
                    return
                }

                let plans = documents.compactMap { try? $0.data(as: KairosStudyPlan.self) }
                self.currentPlan = plans.max { lhs, rhs in
                    (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
                }
                self.errorMessage = nil
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func toggleTask(boardID: String, sectionID: String, taskID: String) async {
        guard var plan = currentPlan, let planID = plan.id else { return }

        guard let boardIndex = plan.boards.firstIndex(where: { $0.id == boardID }),
              let sectionIndex = plan.boards[boardIndex].sections.firstIndex(where: { $0.id == sectionID }),
              let taskIndex = plan.boards[boardIndex].sections[sectionIndex].tasks.firstIndex(where: { $0.id == taskID }) else {
            return
        }

        plan.boards[boardIndex].sections[sectionIndex].tasks[taskIndex].completed.toggle()

        do {
            let encoder = Firestore.Encoder()
            let encodedBoards = try plan.boards.map { try encoder.encode($0) }
            try await db.collection("study_plans").document(planID).updateData(["boards": encodedBoards])
        } catch {
            errorMessage = "Failed to update task: \(error.localizedDescription)"
        }
    }

    // MARK: - Shared write helper
    private func mutateBoards(_ transform: (inout [KairosBoard]) -> Void) async {
        var boards = currentPlan?.boards ?? []
        transform(&boards)

        guard let userID = Auth.auth().currentUser?.uid else { return }

        do {
            let encoder = Firestore.Encoder()
            let encodedBoards = try boards.map { try encoder.encode($0) }

            if let planID = currentPlan?.id {
                try await db.collection("study_plans").document(planID).updateData(["boards": encodedBoards])
            } else {
                _ = try await db.collection("study_plans").addDocument(data: [
                    "boards": encodedBoards,
                    "userID": userID,
                    "createdAt": FieldValue.serverTimestamp()
                ])
            }
        } catch {
            errorMessage = "Failed to update: \(error.localizedDescription)"
        }
    }

    // MARK: - Boards
    func addBoard(title: String) async {
        await mutateBoards { boards in
            boards.append(KairosBoard(id: "board-\(Int(Date().timeIntervalSince1970 * 1000))", title: title, archived: false, sections: []))
        }
    }

    func renameBoard(boardID: String, title: String) async {
        await mutateBoards { boards in
            if let i = boards.firstIndex(where: { $0.id == boardID }) { boards[i].title = title }
        }
    }

    func setBoardArchived(boardID: String, archived: Bool) async {
        await mutateBoards { boards in
            if let i = boards.firstIndex(where: { $0.id == boardID }) { boards[i].archived = archived }
        }
    }

    func deleteBoardForever(boardID: String) async {
        await mutateBoards { boards in boards.removeAll { $0.id == boardID } }
    }

    // MARK: - Sections
    func addSection(boardID: String, title: String) async {
        await mutateBoards { boards in
            guard let bi = boards.firstIndex(where: { $0.id == boardID }) else { return }
            boards[bi].sections.append(KairosSection(id: "sec-\(Int(Date().timeIntervalSince1970 * 1000))", title: title, archived: false, tasks: []))
        }
    }

    func renameSection(sectionID: String, title: String) async {
        await mutateBoards { boards in
            for bi in boards.indices {
                if let si = boards[bi].sections.firstIndex(where: { $0.id == sectionID }) {
                    boards[bi].sections[si].title = title
                    return
                }
            }
        }
    }

    func setSectionArchived(sectionID: String, archived: Bool) async {
        await mutateBoards { boards in
            for bi in boards.indices {
                if let si = boards[bi].sections.firstIndex(where: { $0.id == sectionID }) {
                    boards[bi].sections[si].archived = archived
                    return
                }
            }
        }
    }

    func deleteSectionForever(boardID: String, sectionID: String) async {
        await mutateBoards { boards in
            if let bi = boards.firstIndex(where: { $0.id == boardID }) {
                boards[bi].sections.removeAll { $0.id == sectionID }
            }
        }
    }

    // MARK: - Tasks
    func addTask(sectionID: String, title: String) async {
        await mutateBoards { boards in
            for bi in boards.indices {
                if let si = boards[bi].sections.firstIndex(where: { $0.id == sectionID }) {
                    boards[bi].sections[si].tasks.append(
                        KairosTask(id: "task-\(Int(Date().timeIntervalSince1970 * 1000))", title: title, completed: false, archived: false, date: nil)
                    )
                    return
                }
            }
        }
    }

    func renameTask(taskID: String, title: String) async {
        await mutateBoards { boards in
            for bi in boards.indices {
                for si in boards[bi].sections.indices {
                    if let ti = boards[bi].sections[si].tasks.firstIndex(where: { $0.id == taskID }) {
                        boards[bi].sections[si].tasks[ti].title = title
                        return
                    }
                }
            }
        }
    }

    func setTaskArchived(taskID: String, archived: Bool) async {
        await mutateBoards { boards in
            for bi in boards.indices {
                for si in boards[bi].sections.indices {
                    if let ti = boards[bi].sections[si].tasks.firstIndex(where: { $0.id == taskID }) {
                        boards[bi].sections[si].tasks[ti].archived = archived
                        return
                    }
                }
            }
        }
    }

    func deleteTaskForever(sectionID: String, taskID: String) async {
        await mutateBoards { boards in
            for bi in boards.indices {
                if let si = boards[bi].sections.firstIndex(where: { $0.id == sectionID }) {
                    boards[bi].sections[si].tasks.removeAll { $0.id == taskID }
                    return
                }
            }
        }
    }

    func setTaskDate(sectionID: String, taskID: String, dateKey: String?) async {
        await mutateBoards { boards in
            for bi in boards.indices {
                for si in boards[bi].sections.indices where boards[bi].sections[si].id == sectionID {
                    if let ti = boards[bi].sections[si].tasks.firstIndex(where: { $0.id == taskID }) {
                        boards[bi].sections[si].tasks[ti].date = dateKey
                        return
                    }
                }
            }
        }
    }

    // MARK: - AI plan confirmation
    /// Applies a confirmed AI-generated plan (new board or append to an
    /// existing one) plus any extracted recurring events, in a single write.
    /// Kept separate from mutateBoards because it also needs to write
    /// scheduleEvents in the same call — two sequential writes here would
    /// risk the second one reading a stale currentPlan.id if the snapshot
    /// listener hasn't caught up yet after the first write.
    func applyAiPlan(sections: [KairosSection], recurringEvents: [KairosScheduleEvent], newBoardTitle: String?, existingBoardID: String?) async {
        guard let userID = Auth.auth().currentUser?.uid else { return }

        var boards = currentPlan?.boards ?? []
        if let boardID = existingBoardID, let i = boards.firstIndex(where: { $0.id == boardID }) {
            boards[i].sections.append(contentsOf: sections)
        } else {
            let trimmed = newBoardTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (trimmed?.isEmpty == false) ? trimmed! : "AI Plan"
            boards.append(KairosBoard(id: "board-\(Int(Date().timeIntervalSince1970 * 1000))", title: title, archived: false, sections: sections))
        }

        var events = currentPlan?.scheduleEvents ?? []
        events.append(contentsOf: recurringEvents)

        do {
            let encoder = Firestore.Encoder()
            let encodedBoards = try boards.map { try encoder.encode($0) }
            let encodedEvents = try events.map { try encoder.encode($0) }

            if let planID = currentPlan?.id {
                try await db.collection("study_plans").document(planID).updateData([
                    "boards": encodedBoards,
                    "scheduleEvents": encodedEvents
                ])
            } else {
                _ = try await db.collection("study_plans").addDocument(data: [
                    "boards": encodedBoards,
                    "scheduleEvents": encodedEvents,
                    "userID": userID,
                    "createdAt": FieldValue.serverTimestamp()
                ])
            }
        } catch {
            errorMessage = "Failed to save AI plan: \(error.localizedDescription)"
        }
    }
}
