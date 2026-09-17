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
                if let error { self.errorMessage = error.localizedDescription; return }
                guard let documents = snapshot?.documents, !documents.isEmpty else { self.currentPlan = nil; return }
                let plans = documents.compactMap { try? $0.data(as: KairosStudyPlan.self) }
                self.currentPlan = plans.max { lhs, rhs in (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast) }
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
              let taskIndex = plan.boards[boardIndex].sections[sectionIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }

        let willComplete = !plan.boards[boardIndex].sections[sectionIndex].tasks[taskIndex].completed
        plan.boards[boardIndex].sections[sectionIndex].tasks[taskIndex].completed = willComplete
        if willComplete {
            setParentCompletion(in: &plan.boards[boardIndex].sections[sectionIndex].tasks, startingAt: taskID)
        } else if let parentID = plan.boards[boardIndex].sections[sectionIndex].tasks[taskIndex].parentTaskID {
            markAncestorsIncomplete(in: &plan.boards[boardIndex].sections[sectionIndex].tasks, parentID: parentID)
        }

        let previousPlan = currentPlan
        currentPlan = plan
        do {
            let encoder = Firestore.Encoder()
            let encodedBoards = try plan.boards.map { try encoder.encode($0) }
            try await db.collection("study_plans").document(planID).updateData(["boards": encodedBoards])
            errorMessage = nil
        } catch {
            currentPlan = previousPlan
            errorMessage = "Failed to update task: \(error.localizedDescription)"
        }
    }

    private func setParentCompletion(in tasks: inout [KairosTask], startingAt taskID: String) {
        guard let task = tasks.first(where: { $0.id == taskID }), task.completed,
              let parentID = task.parentTaskID,
              let parentIndex = tasks.firstIndex(where: { $0.id == parentID }) else { return }
        let children = tasks.filter { $0.parentTaskID == parentID && !$0.archived }
        guard !children.isEmpty else { return }
        tasks[parentIndex].completed = children.allSatisfy(\.completed)
        if tasks[parentIndex].completed { setParentCompletion(in: &tasks, startingAt: parentID) }
    }

    private func markAncestorsIncomplete(in tasks: inout [KairosTask], parentID: String) {
        guard let parentIndex = tasks.firstIndex(where: { $0.id == parentID }) else { return }
        tasks[parentIndex].completed = false
        if let grandparentID = tasks[parentIndex].parentTaskID { markAncestorsIncomplete(in: &tasks, parentID: grandparentID) }
    }

    // MARK: - Optimistic board mutation
    private func mutateBoards(_ transform: (inout [KairosBoard]) -> Void) async {
        guard let userID = Auth.auth().currentUser?.uid else { errorMessage = "You must be signed in to edit boards."; return }
        let previousPlan = currentPlan
        var boards = currentPlan?.boards ?? []
        transform(&boards)
        if let plan = currentPlan {
            var optimisticPlan = plan
            optimisticPlan.boards = boards
            currentPlan = optimisticPlan
        } else {
            currentPlan = KairosStudyPlan(id: nil, userID: userID, createdAt: nil, boards: boards, dayInsights: nil, scheduleEvents: nil)
        }
        do {
            let encoder = Firestore.Encoder()
            let encodedBoards = try boards.map { try encoder.encode($0) }
            if let planID = previousPlan?.id {
                try await db.collection("study_plans").document(planID).updateData(["boards": encodedBoards])
            } else {
                let reference = try await db.collection("study_plans").addDocument(data: ["boards": encodedBoards, "userID": userID, "createdAt": FieldValue.serverTimestamp()])
                currentPlan?.id = reference.documentID
            }
            errorMessage = nil
        } catch {
            currentPlan = previousPlan
            errorMessage = "Failed to update: \(error.localizedDescription)"
        }
    }

    // MARK: - Boards
    func addBoard(title: String) async { await mutateBoards { boards in boards.append(KairosBoard(id: "board-\(UUID().uuidString)", title: title, archived: false, sections: [])) } }
    func renameBoard(boardID: String, title: String) async { await mutateBoards { boards in if let i = boards.firstIndex(where: { $0.id == boardID }) { boards[i].title = title } } }
    func setBoardArchived(boardID: String, archived: Bool) async { await mutateBoards { boards in if let i = boards.firstIndex(where: { $0.id == boardID }) { boards[i].archived = archived } } }
    func deleteBoardForever(boardID: String) async { await mutateBoards { boards in boards.removeAll { $0.id == boardID } } }

    // MARK: - Sections
    func addSection(boardID: String, title: String) async {
        await mutateBoards { boards in
            guard let bi = boards.firstIndex(where: { $0.id == boardID }) else { return }
            boards[bi].sections.append(KairosSection(id: "sec-\(UUID().uuidString)", title: title, archived: false, tasks: []))
        }
    }
    func renameSection(sectionID: String, title: String) async { await mutateBoards { boards in for bi in boards.indices { if let si = boards[bi].sections.firstIndex(where: { $0.id == sectionID }) { boards[bi].sections[si].title = title; return } } } }
    func setSectionArchived(sectionID: String, archived: Bool) async { await mutateBoards { boards in for bi in boards.indices { if let si = boards[bi].sections.firstIndex(where: { $0.id == sectionID }) { boards[bi].sections[si].archived = archived; return } } } }
    func deleteSectionForever(boardID: String, sectionID: String) async { await mutateBoards { boards in if let bi = boards.firstIndex(where: { $0.id == boardID }) { boards[bi].sections.removeAll { $0.id == sectionID } } } }

    // MARK: - Tasks
    func addTask(sectionID: String, title: String) async {
        await mutateBoards { boards in
            for bi in boards.indices {
                if let si = boards[bi].sections.firstIndex(where: { $0.id == sectionID }) {
                    boards[bi].sections[si].tasks.append(KairosTask(id: "task-\(UUID().uuidString)", title: title, completed: false, archived: false, date: nil))
                    return
                }
            }
        }
    }

    func addSubtask(parentTaskID: String, sectionID: String, title: String) async {
        await mutateBoards { boards in
            for bi in boards.indices {
                guard let si = boards[bi].sections.firstIndex(where: { $0.id == sectionID }) else { continue }
                boards[bi].sections[si].tasks.append(KairosTask(id: "task-\(UUID().uuidString)", title: title, completed: false, archived: false, date: nil, taskDescription: nil, dueTime: nil, parentTaskID: parentTaskID))
                return
            }
        }
    }

    func updateTask(taskID: String, title: String? = nil, description: String? = nil, date: String? = nil, dueTime: String? = nil, parentTaskID: String? = nil) async {
        await mutateBoards { boards in
            for bi in boards.indices {
                for si in boards[bi].sections.indices {
                    if let ti = boards[bi].sections[si].tasks.firstIndex(where: { $0.id == taskID }) {
                        if let title { boards[bi].sections[si].tasks[ti].title = title }
                        boards[bi].sections[si].tasks[ti].taskDescription = description
                        boards[bi].sections[si].tasks[ti].date = date
                        boards[bi].sections[si].tasks[ti].dueTime = dueTime
                        if parentTaskID != nil { boards[bi].sections[si].tasks[ti].parentTaskID = parentTaskID }
                        return
                    }
                }
            }
        }
    }

    func renameTask(taskID: String, title: String) async { await mutateBoards { boards in for bi in boards.indices { for si in boards[bi].sections.indices { if let ti = boards[bi].sections[si].tasks.firstIndex(where: { $0.id == taskID }) { boards[bi].sections[si].tasks[ti].title = title; return } } } } }
    func setTaskArchived(taskID: String, archived: Bool) async { await mutateBoards { boards in for bi in boards.indices { for si in boards[bi].sections.indices { if let ti = boards[bi].sections[si].tasks.firstIndex(where: { $0.id == taskID }) { boards[bi].sections[si].tasks[ti].archived = archived; return } } } } }
    func deleteTaskForever(sectionID: String, taskID: String) async { await mutateBoards { boards in if let bi = boards.firstIndex(where: { $0.id == sectionID }) { boards[bi].sections.removeAll { $0.id == taskID } } } }
    func setTaskDate(sectionID: String, taskID: String, dateKey: String?) async { await mutateBoards { boards in for bi in boards.indices { for si in boards[bi].sections.indices where boards[bi].sections[si].id == sectionID { if let ti = boards[bi].sections[si].tasks.firstIndex(where: { $0.id == taskID }) { boards[bi].sections[si].tasks[ti].date = dateKey; return } } } } }

    // MARK: - AI plan confirmation
    func applyAiPlan(sections: [KairosSection], recurringEvents: [KairosScheduleEvent], newBoardTitle: String?, existingBoardID: String?) async {
        guard let userID = Auth.auth().currentUser?.uid else { errorMessage = "You must be signed in to apply an AI plan."; return }
        let previousPlan = currentPlan
        var boards = currentPlan?.boards ?? []
        if let boardID = existingBoardID, let i = boards.firstIndex(where: { $0.id == boardID }) { boards[i].sections.append(contentsOf: sections) }
        else {
            let trimmed = newBoardTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (trimmed?.isEmpty == false) ? trimmed! : "AI Plan"
            boards.append(KairosBoard(id: "board-\(UUID().uuidString)", title: title, archived: false, sections: sections))
        }
        var events = currentPlan?.scheduleEvents ?? []
        events.append(contentsOf: recurringEvents)
        if let plan = currentPlan { var optimisticPlan = plan; optimisticPlan.boards = boards; optimisticPlan.scheduleEvents = events; currentPlan = optimisticPlan }
        else { currentPlan = KairosStudyPlan(id: nil, userID: userID, createdAt: nil, boards: boards, dayInsights: nil, scheduleEvents: events) }
        do {
            let encoder = Firestore.Encoder()
            let encodedBoards = try boards.map { try encoder.encode($0) }
            let encodedEvents = try events.map { try encoder.encode($0) }
            if let planID = previousPlan?.id {
                try await db.collection("study_plans").document(planID).updateData(["boards": encodedBoards, "scheduleEvents": encodedEvents])
            } else {
                let reference = try await db.collection("study_plans").addDocument(data: ["boards": encodedBoards, "scheduleEvents": encodedEvents, "userID": userID, "createdAt": FieldValue.serverTimestamp()])
                currentPlan?.id = reference.documentID
            }
            errorMessage = nil
        } catch {
            currentPlan = previousPlan
            errorMessage = "Failed to apply AI plan: \(error.localizedDescription)"
        }
    }
}
