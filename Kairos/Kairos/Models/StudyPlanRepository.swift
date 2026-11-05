import Foundation
import Observation
import FirebaseFirestore
import FirebaseAuth

@Observable
@MainActor
final class StudyPlanRepository {
    var currentPlan: KairosStudyPlan?
    private(set) var plannerRevision = UUID()
    var isLoading = false
    private(set) var isSaving = false
    var errorMessage: String?
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var listeningUserID: String?
    private var generation = UUID()
    private var hasLoadedSnapshot = false
    var plannerIsUnavailable: Bool { !isLoading && !hasLoadedSnapshot && errorMessage != nil }

    func retryLoading() {
        guard let userID = listeningUserID, !isSaving else { return }
        startListening(userID: userID)
    }
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
                        (Self.creationDate($0.data()["createdAt"]) ?? .distantPast) <
                        (Self.creationDate($1.data()["createdAt"]) ?? .distantPast)
                    }
                    do {
                        if let newest {
                            let raw = newest.data()
                            var readable = raw
                            if !(raw["createdAt"] is Timestamp) {
                                if let date = Self.creationDate(raw["createdAt"]) {
                                    readable["createdAt"] = Timestamp(date: date)
                                } else {
                                    // Creation metadata must not hide readable tasks.
                                    readable["createdAt"] = NSNull()
                                }
                            }
                            self.currentPlan = try Firestore.Decoder().decode(KairosStudyPlan.self, from: readable, in: newest.reference)
                            self.rawPlan = raw
                        } else {
                            self.currentPlan = nil
                            self.rawPlan = [:]
                        }
                        self.plannerRevision = UUID()
                        self.hasLoadedSnapshot = true
                        self.errorMessage = nil
                    } catch {
                        self.currentPlan = nil
                        self.rawPlan = [:]
                        self.plannerRevision = UUID()
                        self.hasLoadedSnapshot = false
                        self.errorMessage = KairosPlannerDecoding.message(for: error)
                    }
                }
            }
    }

    nonisolated private static func creationDate(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        return KairosPlannerTimestamp.date(from: value)
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        generation = UUID()
        listeningUserID = nil
        currentPlan = nil
        plannerRevision = UUID()
        rawPlan = [:]
        isLoading = false
        isSaving = false
        hasLoadedSnapshot = false
        errorMessage = nil
    }

    @discardableResult
    func toggleTask(boardID: String, sectionID: String, taskID: String) async -> Bool {
        guard let task = currentPlan?.boards.first(where: { $0.id == boardID })?
            .sections.first(where: { $0.id == sectionID })?.tasks.first(where: { $0.id == taskID }) else {
            errorMessage = KairosTaskMutation.Invalid().localizedDescription
            return false
        }
        return await performTask(.setCompleted(taskID: taskID, completed: !task.completed))
    }

    @discardableResult
    private func performTask(_ command: KairosTaskCommand) async -> Bool {
        await mutateBoards { boards in boards = try KairosTaskMutation.apply(command, to: boards) }
    }

    @discardableResult
    private func mutateBoards(_ transform: (inout [KairosBoard]) throws -> Void) async -> Bool {
        guard let userID = listeningUserID else {
            errorMessage = "Sign in before editing your planner."
            return false
        }
        let before = currentPlan
        var plan = before ?? KairosStudyPlan(id: nil, userID: userID, createdAt: nil, boards: [], dayInsights: nil, scheduleEvents: nil)
        do {
            try transform(&plan.boards)
            return await persist(before: before, after: plan)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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
        defer { if generation == token { isSaving = false } }
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
                    try KairosChecklist.validateMergedPlanner(base: baseline, merged: merged)
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

    // MARK: - Recurring occurrences
    func eventSegments(on day: String) throws -> [KairosEventSegment] {
        try KairosScheduleProjection.events(rawPlan["scheduleEvents"] as? [[String: Any]] ?? [], on: day)
    }

    @discardableResult
    func editScheduleEvent(_ edit: KairosEventEdit, revision: UUID) async -> Bool {
        guard !isSaving, revision == plannerRevision, hasLoadedSnapshot, !isLoading,
              let user = Auth.auth().currentUser, user.isEmailVerified, user.uid == listeningUserID else { errorMessage = "Your planner changed or is unavailable. Reopen the event and retry."; return false }
        let uid = user.uid, token = generation
        let reference = db.collection("study_plans").document(currentPlan?.id ?? uid)
        let expected = (rawPlan["scheduleEvents"] as? [[String: Any]] ?? []).first { $0["id"] as? String == edit.eventID }
        isSaving = true
        defer { if generation == token { isSaving = false } }
        do {
            _ = try await db.runTransaction { transaction, pointer in
                do {
                    guard Auth.auth().currentUser?.uid == uid else { throw CancellationError() }
                    let snapshot = try transaction.getDocument(reference)
                    let data = snapshot.data() ?? [:]
                    guard !snapshot.exists || data["userID"] as? String == uid,
                          data["scheduleEvents"] == nil || data["scheduleEvents"] is [[String: Any]] else { throw KairosPlannerMerge.Conflict() }
                    let events = try KairosEventMutation.apply(edit, to: data["scheduleEvents"] as? [[String: Any]] ?? [], expected: expected)
                    if snapshot.exists { transaction.updateData(["scheduleEvents": events], forDocument: reference) }
                    else { transaction.setData(["userID": uid, "createdAt": FieldValue.serverTimestamp(), "boards": [], "scheduleEvents": events], forDocument: reference) }
                    return true
                } catch { pointer?.pointee = error as NSError; return nil }
            }
            guard generation == token, Auth.auth().currentUser?.uid == uid else { return false }
            errorMessage = nil; return true
        } catch { guard generation == token else { return false }; errorMessage = error.localizedDescription; return false }
    }

    @discardableResult
    func addScheduledTask(sectionID: String, title: String, day: String, start: String?, end: String?) async -> Bool {
        let id = "task-\(UUID().uuidString)"
        return await mutateBoards { boards in
            boards = try KairosTaskMutation.apply(.create(sectionID: sectionID, taskID: id, title: title, parentTaskID: nil), to: boards)
            var patch = KairosTaskPatch(); patch.date = .set(day); patch.startTime = .set(start); patch.endTime = .set(end)
            boards = try KairosTaskMutation.apply(.update(taskID: id, patch: patch, expected: nil), to: boards)
        }
    }

    func recurringOccurrences(on day: String) async throws -> [KairosRecurringOccurrence] {
        try await recurringOccurrences(onDays: [day])[day] ?? []
    }

    func recurringOccurrences(onDays days: [String]) async throws -> [String: [KairosRecurringOccurrence]] {
        var payloads: [String] = []
        var ids = Set<String>()
        for board in rawPlan["boards"] as? [[String: Any]] ?? [] where board["archived"] as? Bool != true {
            for section in board["sections"] as? [[String: Any]] ?? [] where section["archived"] as? Bool != true {
                for task in section["tasks"] as? [[String: Any]] ?? [] where task["archived"] as? Bool != true {
                    guard (task["recurrence"] as? [String: Any])?["enabled"] as? Bool == true else { continue }
                    guard let id = task["id"] as? String, ids.insert(id).inserted else { throw KairosPlannerMerge.Conflict() }
                    payloads.append(try KairosRecurrence.revision(task))
                }
            }
        }
        // Immutable JSON inputs cross the actor boundary, never Firestore objects.
        let inputs = payloads
        let work = Task.detached(priority: .userInitiated) {
            var result: [String: [KairosRecurringOccurrence]] = [:]
            for json in inputs {
                try Task.checkCancellation()
                guard let data = json.data(using: .utf8),
                      let task = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw KairosRecurrence.Unavailable() }
                let projected = try KairosRecurrence.occurrences(task: task, onDays: days)
                for (day, items) in projected { result[day, default: []] += items }
            }
            try Task.checkCancellation()
            return result.mapValues { $0.sorted { ($0.startTime ?? "99:99", $0.id) < ($1.startTime ?? "99:99", $1.id) } }
        }
        return try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
    }

    @discardableResult
    func setOccurrenceStatus(_ occurrence: KairosRecurringOccurrence, status: String) async -> Bool {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return await mutateOccurrence(occurrence) { task in
            try KairosRecurrence.settingStatus(task: task, occurrence: occurrence, status: status, timestamp: timestamp)
        }
    }

    @discardableResult
    func saveOccurrenceChecklist(_ occurrence: KairosRecurringOccurrence, items: [KairosChecklistItem]) async -> Bool {
        await mutateOccurrence(occurrence) { task in
            try KairosRecurrence.settingChecklist(task: task, occurrence: occurrence, items: items)
        }
    }

    @discardableResult
    func saveOccurrenceDetails(_ occurrence: KairosRecurringOccurrence, items: [KairosChecklistItem], status: String, schedule: KairosOccurrenceSchedule? = nil) async -> Bool {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return await mutateOccurrence(occurrence) { task in
            if status != occurrence.status || schedule != nil { guard try KairosRecurrence.revision(task) == occurrence.revision else { throw KairosPlannerMerge.Conflict() } }
            var updated = task
            if items != (occurrence.task.checklist ?? []) { updated = try KairosRecurrence.settingChecklist(task: task, occurrence: occurrence, items: items) }
            if let schedule {
                guard let refreshed = try KairosRecurrence.occurrences(task: updated, on: occurrence.displayDate).first(where: { $0.id == occurrence.id }) else { throw KairosPlannerMerge.Conflict() }
                updated = try KairosRecurrence.settingSchedule(task: updated, occurrence: refreshed, schedule: schedule)
            }
            if status != occurrence.status {
                guard let refreshed = try KairosRecurrence.occurrences(task: updated, on: schedule?.date ?? occurrence.displayDate).first(where: { $0.id == occurrence.id }) else { throw KairosPlannerMerge.Conflict() }
                updated = try KairosRecurrence.settingStatus(task: updated, occurrence: refreshed, status: status, timestamp: timestamp)
            }
            return updated
        }
    }

    private func mutateOccurrence(_ occurrence: KairosRecurringOccurrence, transform: @escaping @Sendable ([String: Any]) throws -> [String: Any]) async -> Bool {
        guard !isSaving else { errorMessage = "Wait for the current save to finish."; return false }
        guard hasLoadedSnapshot, !isLoading, let user = Auth.auth().currentUser,
              user.isEmailVerified, user.uid == listeningUserID, let planID = currentPlan?.id else {
            errorMessage = "Wait for your verified account's planner to load."
            return false
        }
        let uid = user.uid
        let token = generation
        let reference = db.collection("study_plans").document(planID)
        isSaving = true
        defer { if generation == token { isSaving = false } }
        do {
            _ = try await db.runTransaction { transaction, errorPointer in
                do {
                    guard Auth.auth().currentUser?.uid == uid else { throw CancellationError() }
                    let snapshot = try transaction.getDocument(reference)
                    guard let data = snapshot.data(), data["userID"] as? String == uid,
                          var boards = data["boards"] as? [[String: Any]] else { throw KairosPlannerMerge.Conflict() }
                    var locations: [(Int, Int, Int)] = []
                    for bi in boards.indices {
                        let sections = boards[bi]["sections"] as? [[String: Any]] ?? []
                        for si in sections.indices {
                            let tasks = sections[si]["tasks"] as? [[String: Any]] ?? []
                            for ti in tasks.indices where tasks[ti]["id"] as? String == occurrence.seriesId { locations.append((bi, si, ti)) }
                        }
                    }
                    guard locations.count == 1, let (bi, si, ti) = locations.first,
                          boards[bi]["archived"] as? Bool != true,
                          var sections = boards[bi]["sections"] as? [[String: Any]],
                          sections[si]["archived"] as? Bool != true,
                          var tasks = sections[si]["tasks"] as? [[String: Any]],
                          tasks[ti]["archived"] as? Bool != true else { throw KairosPlannerMerge.Conflict() }
                    tasks[ti] = try transform(tasks[ti])
                    sections[si]["tasks"] = tasks
                    boards[bi]["sections"] = sections
                    transaction.updateData(["boards": boards], forDocument: reference)
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

    // MARK: - Boards
    @discardableResult
    func addBoard(title: String) async -> Bool {
        return await mutateBoards { boards in
            boards.append(KairosBoard(id: "board-\(UUID().uuidString)", title: title, archived: false, sections: []))
        }
    }

    @discardableResult
    func renameBoard(boardID: String, title: String) async -> Bool {
        return await mutateBoards { boards in
            guard let i = boards.firstIndex(where: { $0.id == boardID }) else { throw KairosTaskMutation.Invalid() }
            boards[i].title = title
        }
    }

    @discardableResult
    func updateBoard(
        boardID: String,
        title: String? = nil,
        description: String? = nil,
        preserveDescription: Bool = false
    ) async -> Bool {
        return await mutateBoards { boards in
            guard let index = boards.firstIndex(where: { $0.id == boardID })
            else { throw KairosTaskMutation.Invalid() }

            if let title {
                boards[index].title = title
            }
            if description != nil || !preserveDescription {
                boards[index].boardDescription = description
            }
        }
    }

    @discardableResult
    func setBoardArchived(boardID: String, archived: Bool) async -> Bool {
        return await mutateBoards { boards in
            guard let i = boards.firstIndex(where: { $0.id == boardID }) else { throw KairosTaskMutation.Invalid() }
            boards[i].archived = archived
        }
    }

    @discardableResult
    func deleteBoardForever(boardID: String) async -> Bool {
        return await mutateBoards { boards in
            guard boards.contains(where: { $0.id == boardID }) else { throw KairosTaskMutation.Invalid() }
            boards.removeAll { $0.id == boardID }
        }
    }

    // MARK: - Sections
    @discardableResult
    func addSection(boardID: String, title: String) async -> Bool {
        return await mutateBoards { boards in
            guard let bi = boards.firstIndex(where: { $0.id == boardID && !$0.archived }) else { throw KairosTaskMutation.Invalid() }
            boards[bi].sections.append(KairosSection(id: "sec-\(UUID().uuidString)", title: title, archived: false, tasks: []))
        }
    }

    @discardableResult
    func renameSection(sectionID: String, title: String) async -> Bool {
        return await mutateBoards { boards in
            for bi in boards.indices {
                if let si = boards[bi].sections.firstIndex(where: { $0.id == sectionID }) {
                    boards[bi].sections[si].title = title
                    return
                }
            }
            throw KairosTaskMutation.Invalid()
        }
    }

    @discardableResult
    func setSectionArchived(sectionID: String, archived: Bool) async -> Bool {
        return await mutateBoards { boards in
            for bi in boards.indices {
                if let si = boards[bi].sections.firstIndex(where: { $0.id == sectionID }) {
                    boards[bi].sections[si].archived = archived
                    return
                }
            }
            throw KairosTaskMutation.Invalid()
        }
    }

    @discardableResult
    func deleteSectionForever(boardID: String, sectionID: String) async -> Bool {
        await mutateBoards { boards in
            guard let bi = boards.firstIndex(where: { $0.id == boardID }),
                  boards[bi].sections.contains(where: { $0.id == sectionID }) else { throw KairosTaskMutation.Invalid() }
            boards[bi].sections.removeAll { $0.id == sectionID }
        }
    }

    // MARK: - Tasks
    @discardableResult
    func addTask(sectionID: String, title: String) async -> Bool {
        await performTask(.create(sectionID: sectionID, taskID: "task-\(UUID().uuidString)", title: title, parentTaskID: nil))
    }

    @discardableResult
    func addSubtask(parentTaskID: String, sectionID: String, title: String) async -> Bool {
        await performTask(.create(sectionID: sectionID, taskID: "task-\(UUID().uuidString)", title: title, parentTaskID: parentTaskID))
    }

    @discardableResult
    func updateTask(taskID: String, patch: KairosTaskPatch, expected: KairosTask? = nil) async -> Bool {
        await performTask(.update(taskID: taskID, patch: patch, expected: expected))
    }

    @discardableResult
    func renameTask(taskID: String, title: String, expected: KairosTask? = nil) async -> Bool {
        var patch = KairosTaskPatch()
        patch.title = .set(title)
        return await updateTask(taskID: taskID, patch: patch, expected: expected)
    }

    @discardableResult
    func setTaskArchived(taskID: String, archived: Bool) async -> Bool {
        await performTask(.archive(taskID: taskID, archived: archived))
    }

    @discardableResult
    func deleteTaskForever(sectionID: String, taskID: String) async -> Bool {
        await performTask(.delete(sectionID: sectionID, taskID: taskID))
    }

    @discardableResult
    func setTaskDate(sectionID: String, taskID: String, dateKey: String?) async -> Bool {
        guard currentPlan?.boards.contains(where: { $0.sections.contains(where: { $0.id == sectionID && $0.tasks.contains(where: { $0.id == taskID }) }) }) == true else {
            errorMessage = KairosTaskMutation.Invalid().localizedDescription
            return false
        }
        var patch = KairosTaskPatch()
        patch.date = .set(dateKey)
        return await updateTask(taskID: taskID, patch: patch)
    }

    // MARK: - Reviewed AI plan
    @discardableResult
    func applyChatActions(_ actions: [KairosChatAction], revision: UUID) async -> Bool {
        guard plannerRevision == revision else { errorMessage = "The planner changed. Ask Kairos to review the latest schedule before applying this proposal."; return false }
        return await mutateBoards { boards in boards = try KairosChatActions.apply(actions, to: boards) }
    }

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

