import Foundation
import Observation
import FirebaseFirestore
import FirebaseAuth

@Observable
@MainActor
final class StudyPlanRepository {
    var currentPlan: KairosStudyPlan?
    var isLoading = false
    private(set) var isSaving = false
    var errorMessage: String?
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var listeningUserID: String?
    private var generation = UUID()
    private var hasLoadedSnapshot = false
    private var rawPlan: [String: Any] = [:]

    func startListening(userID: String) {
        stopListening()
        listeningUserID = userID
        let token = generation
        isLoading = true
        listener = db.collection("study_plans").whereField("userID", isEqualTo: userID)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.generation == token, Auth.auth().currentUser?.uid == userID else { return }
                    self.isLoading = false
                    if let error { self.errorMessage = error.localizedDescription; return }
                    guard let snapshot else { self.errorMessage = "Could not load your planner."; return }
                    // Do not fall back to an older plan when the newest one cannot decode.
                    let newest = snapshot.documents.max {
                        (($0.data()["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast) <
                        (($1.data()["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast)
                    }
                    do {
                        self.currentPlan = try newest?.data(as: KairosStudyPlan.self)
                        self.rawPlan = newest?.data() ?? [:]
                        self.hasLoadedSnapshot = true
                        self.errorMessage = nil
                    } catch {
                        self.hasLoadedSnapshot = false
                        self.errorMessage = "This planner contains data this build cannot read. Update Kairos before editing it."
                    }
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        generation = UUID()
        listeningUserID = nil
        currentPlan = nil
        rawPlan = [:]
        isLoading = false
        hasLoadedSnapshot = false
        errorMessage = nil
    }

    @discardableResult
    func toggleTask(boardID: String, sectionID: String, taskID: String) async -> Bool {
        guard var plan = currentPlan,
              let bi = plan.boards.firstIndex(where: { $0.id == boardID }),
              let si = plan.boards[bi].sections.firstIndex(where: { $0.id == sectionID }),
              let ti = plan.boards[bi].sections[si].tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        let before = currentPlan
        let willComplete = !plan.boards[bi].sections[si].tasks[ti].completed
        plan.boards[bi].sections[si].tasks[ti].completed = willComplete

        if willComplete {
            setParentCompletion(
                in: &plan.boards[bi].sections[si].tasks,
                startingAt: taskID
            )
        } else if let parentID = plan.boards[bi].sections[si].tasks[ti].parentTaskID {
            markAncestorsIncomplete(
                in: &plan.boards[bi].sections[si].tasks,
                parentID: parentID
            )
        }
        return await persist(before: before, after: plan)
    }

    private func setParentCompletion(
        in tasks: inout [KairosTask],
        startingAt taskID: String
    ) {
        guard let task = tasks.first(where: { $0.id == taskID }),
              task.completed,
              let parentID = task.parentTaskID,
              let parentIndex = tasks.firstIndex(where: { $0.id == parentID })
        else { return }

        let children = tasks.filter {
            $0.parentTaskID == parentID && !$0.archived
        }
        guard !children.isEmpty else { return }

        tasks[parentIndex].completed = children.allSatisfy(\.completed)

        if tasks[parentIndex].completed {
            setParentCompletion(in: &tasks, startingAt: parentID)
        }
    }

    private func markAncestorsIncomplete(
        in tasks: inout [KairosTask],
        parentID: String
    ) {
        guard let index = tasks.firstIndex(where: { $0.id == parentID })
        else { return }

        tasks[index].completed = false

        if let grandparentID = tasks[index].parentTaskID {
            markAncestorsIncomplete(in: &tasks, parentID: grandparentID)
        }
    }

    private func mutateBoards(_ transform: (inout [KairosBoard]) -> Void) async {
        guard let userID = listeningUserID else { return }
        let before = currentPlan
        var plan = before ?? KairosStudyPlan(id: nil, userID: userID, createdAt: nil, boards: [], dayInsights: nil, scheduleEvents: nil)
        transform(&plan.boards)
        _ = await persist(before: before, after: plan)
    }

    private func persist(before: KairosStudyPlan?, after: KairosStudyPlan, includeEvents: Bool = false) async -> Bool {
        guard !isSaving else { errorMessage = "Wait for your current change to finish saving."; return false }
        guard hasLoadedSnapshot, !isLoading, let user = Auth.auth().currentUser,
              user.isEmailVerified, user.uid == listeningUserID, after.userID == user.uid else {
            errorMessage = "Wait for your verified account's planner to load before editing."
            return false
        }
        let uid = user.uid
        let token = generation
        let reference = db.collection("study_plans").document(before?.id ?? uid)
        isSaving = true
        defer { isSaving = false }
        do {
            let encoder = Firestore.Encoder()
            var base: [String: Any] = ["boards": try (before?.boards ?? []).map { try encoder.encode($0) }]
            var local: [String: Any] = ["boards": try after.boards.map { try encoder.encode($0) }]
            if includeEvents {
                base["scheduleEvents"] = try (before?.scheduleEvents ?? []).map { try encoder.encode($0) }
                local["scheduleEvents"] = try (after.scheduleEvents ?? []).map { try encoder.encode($0) }
            }
            let baseline = try Self.normalizedPlanner(rawPlan)
            let desired = try KairosPlannerMerge.applyingKnownEdits(base: base, local: local, to: baseline)
            _ = try await db.runTransaction { transaction, errorPointer in
                do {
                    guard Auth.auth().currentUser?.uid == uid else { throw CancellationError() }
                    let snapshot = try transaction.getDocument(reference)
                    if before != nil && !snapshot.exists { throw KairosPlannerMerge.Conflict() }
                    let raw = snapshot.data() ?? [:]
                    guard !snapshot.exists || raw["userID"] as? String == uid else { throw KairosPlannerMerge.Conflict() }
                    let remote = try Self.normalizedPlanner(raw)
                    let merged = try KairosPlannerMerge.merge(base: baseline, local: desired, remote: remote)
                    var fields: [String: Any] = ["boards": merged["boards"] ?? []]
                    if includeEvents { fields["scheduleEvents"] = merged["scheduleEvents"] ?? [] }
                    if !snapshot.exists {
                        fields["userID"] = uid
                        fields["createdAt"] = FieldValue.serverTimestamp()
                        transaction.setData(fields, forDocument: reference)
                    } else {
                        transaction.updateData(fields, forDocument: reference)
                    }
                    return true
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
            guard generation == token, Auth.auth().currentUser?.uid == uid else { return false }
            errorMessage = nil
            return true
        } catch {
            guard generation == token else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    nonisolated private static func normalizedPlanner(_ data: [String: Any]) throws -> [String: Any] {
        var result = data
        guard data["boards"] == nil || data["boards"] is [[String: Any]] else { throw KairosPlannerMerge.Conflict() }
        // A legacy section-only document needs migration on the web before native edits.
        guard data["boards"] != nil || data["sections"] == nil else { throw KairosPlannerMerge.Conflict() }
        result["boards"] = try (data["boards"] as? [[String: Any]] ?? []).map { board in
            var b = board
            b["archived"] = b["archived"] ?? false
            guard let sections = b["sections"] as? [[String: Any]] else { throw KairosPlannerMerge.Conflict() }
            b["sections"] = try sections.map { section in
                var s = section; s["archived"] = s["archived"] ?? false
                guard let tasks = s["tasks"] as? [[String: Any]] else { throw KairosPlannerMerge.Conflict() }
                s["tasks"] = tasks.map { task in
                    var t = task
                    t["archived"] = t["archived"] ?? false
                    t["completed"] = t["completed"] ?? false
                    return t
                }
                return s
            }
            return b
        }
        result["scheduleEvents"] = data["scheduleEvents"] ?? []
        return result
    }

    // MARK: - Boards
    func addBoard(title: String) async {
        await mutateBoards { boards in
            boards.append(KairosBoard(id: "board-\(UUID().uuidString)", title: title, archived: false, sections: []))
        }
    }

    func renameBoard(boardID: String, title: String) async {
        await mutateBoards { boards in
            if let i = boards.firstIndex(where: { $0.id == boardID }) { boards[i].title = title }
        }
    }

    func updateBoard(
        boardID: String,
        title: String? = nil,
        description: String? = nil,
        preserveDescription: Bool = false
    ) async {
        await mutateBoards { boards in
            guard let index = boards.firstIndex(where: { $0.id == boardID })
            else { return }

            if let title {
                boards[index].title = title
            }
            if description != nil || !preserveDescription {
                boards[index].boardDescription = description
            }
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
            boards[bi].sections.append(KairosSection(id: "sec-\(UUID().uuidString)", title: title, archived: false, tasks: []))
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
                        KairosTask(id: "task-\(UUID().uuidString)", title: title, completed: false, archived: false, date: nil)
                    )
                    return
                }
            }
        }
    }

    func addSubtask(
        parentTaskID: String,
        sectionID: String,
        title: String
    ) async {
        await mutateBoards { boards in
            for bi in boards.indices {
                guard let si = boards[bi].sections.firstIndex(
                    where: { $0.id == sectionID }
                ) else { continue }

                boards[bi].sections[si].tasks.append(
                    KairosTask(
                        id: "task-\(UUID().uuidString)",
                        title: title,
                        completed: false,
                        archived: false,
                        date: nil,
                        taskDescription: nil,
                        dueTime: nil,
                        parentTaskID: parentTaskID
                    )
                )
                return
            }
        }
    }

    func updateTask(
        taskID: String,
        title: String? = nil,
        description: String? = nil,
        date: String? = nil,
        dueTime: String? = nil,
        parentTaskID: String? = nil
    ) async {
        await mutateBoards { boards in
            for bi in boards.indices {
                for si in boards[bi].sections.indices {
                    guard let ti = boards[bi].sections[si].tasks.firstIndex(
                        where: { $0.id == taskID }
                    ) else { continue }

                    if let title {
                        boards[bi].sections[si].tasks[ti].title = title
                    }
                    boards[bi].sections[si].tasks[ti].taskDescription = description
                    boards[bi].sections[si].tasks[ti].date = date
                    boards[bi].sections[si].tasks[ti].dueTime = dueTime

                    if parentTaskID != nil {
                        boards[bi].sections[si].tasks[ti].parentTaskID = parentTaskID
                    }
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

    // MARK: - Reviewed AI plan
    @discardableResult
    func applyAiPlan(sections: [KairosSection], recurringEvents: [KairosScheduleEvent], newBoardTitle: String?, existingBoardID: String?) async -> Bool {
        guard let uid = listeningUserID else { return false }
        let before = currentPlan
        var plan = before ?? KairosStudyPlan(id: nil, userID: uid, createdAt: nil, boards: [], dayInsights: nil, scheduleEvents: nil)
        if let id = existingBoardID {
            guard let index = plan.boards.firstIndex(where: { $0.id == id && !$0.archived }) else {
                errorMessage = "This board is unavailable. Choose another board."
                return false
            }
            plan.boards[index].sections.append(contentsOf: sections)
        } else {
            let title = newBoardTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { errorMessage = "Give the board a name first."; return false }
            plan.boards.append(KairosBoard(id: "board-\(UUID().uuidString)", title: title, archived: false, sections: sections))
        }
        plan.scheduleEvents = (plan.scheduleEvents ?? []) + recurringEvents
        return await persist(before: before, after: plan, includeEvents: true)
    }
}

