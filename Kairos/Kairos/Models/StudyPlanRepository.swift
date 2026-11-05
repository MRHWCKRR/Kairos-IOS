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

    // Search owns no listeners or writes, and never exposes a previous account.
    var searchScope: String? {
        guard hasLoadedSnapshot, !isLoading, let owner = listeningUserID,
              let user = Auth.auth().currentUser, user.uid == owner, user.isEmailVerified else { return nil }
        return "\(generation)-\(owner)-\(currentPlan?.id ?? "empty")"
    }
    func searchInputJSON() throws -> String {
        guard searchScope != nil else { throw KairosPlannerSearch.Unavailable() }
        return try KairosPlannerSearch.inputJSON(rawPlan)
    }
    func todayInputJSON() throws -> String {
        var value = try KairosTouchSchedule.object(searchInputJSON())
        value["scheduleEvents"] = KairosScheduleProjection.eventInput(rawPlan["scheduleEvents"] as? [[String: Any]] ?? [])
        return try KairosTouchSchedule.json(value)
    }
    func todayTask(_ row: KairosTodayRow, revision: UUID) -> KairosTask? {
        guard row.kind == "task", row.occurrenceDate == nil, revision == plannerRevision,
              searchResultIsAvailable(row.searchRow),
              let board = currentPlan?.boards.first(where: { $0.id == row.boardId }),
              let section = board.sections.first(where: { $0.id == row.sectionId }),
              let task = section.tasks.first(where: { $0.id == row.taskId }), task.recurrence?.enabled != true, !task.completed else { return nil }
        return task
    }
    @discardableResult
    func completeTodayTask(_ row: KairosTodayRow, revision: UUID) async -> Bool {
        guard !isSaving, let task = todayTask(row, revision: revision) else {
            errorMessage = "This task changed. Review Today before trying again."; return false
        }
        return await performTask(.setCompleted(taskID: task.id, completed: true))
    }
    @discardableResult
    func planTodayTask(_ row: KairosTodayRow, revision: UUID, day: String) async -> Bool {
        guard !isSaving, let task = todayTask(row, revision: revision), task.scheduleLocked != true else {
            errorMessage = "This task changed or its schedule is locked. Open its details to review it."; return false
        }
        var patch = KairosTaskPatch(); patch.date = .set(day)
        return await updateTask(taskID: task.id, patch: patch, expected: task)
    }
    func searchResultIsAvailable(_ row: KairosSearchRow) -> Bool {
        guard searchScope != nil, let boards = currentPlan?.boards else { return false }
        let matches = boards.filter { $0.id == row.target.boardId }
        guard matches.count == 1, let board = matches.first, !board.archived else { return false }
        if row.target.kind == "board" { return true }
        let sections = board.sections.filter { $0.id == row.target.sectionId }
        guard sections.count == 1, let section = sections.first, !section.archived else { return false }
        let all = boards.flatMap(\.sections).flatMap(\.tasks).filter { $0.id == row.target.taskId }
        guard all.count == 1, let task = section.tasks.first(where: { $0.id == row.target.taskId }), !task.archived else { return false }
        return row.target.occurrenceDate == nil || task.recurrence?.enabled == true
    }
    func searchOccurrence(_ row: KairosSearchRow) async throws -> KairosRecurringOccurrence {
        guard searchResultIsAvailable(row), let logicalDay = row.target.occurrenceDate, let displayedDay = row.date else { throw KairosPlannerSearch.Unavailable() }
        let scope = searchScope, revision = plannerRevision
        let tasks = try KairosAIProposalEngine.maps(rawPlan["boards"]).flatMap { try KairosAIProposalEngine.maps($0["sections"]) }.flatMap { try KairosAIProposalEngine.maps($0["tasks"]) }
        guard let task = tasks.first(where: { $0["id"] as? String == row.target.taskId }) else { throw KairosPlannerSearch.Unavailable() }
        let payload = try KairosRecurrence.revision(task)
        let work = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let task = try KairosTouchSchedule.object(payload)
            let occurrence = try KairosRecurrence.occurrences(task: task, on: displayedDay).first { $0.occurrenceDate == logicalDay && !["skipped", "deleted"].contains($0.status) }
            try Task.checkCancellation()
            guard let occurrence else { throw KairosPlannerSearch.Unavailable() }
            return occurrence
        }
        let result = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
        guard searchScope == scope, plannerRevision == revision else { throw KairosPlannerSearch.Unavailable() }
        return result
    }

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
    func beginTouchEdit(target: KairosTouchTarget, timezone: String, allowCompleted: Bool) throws -> KairosTouchDraft {
        guard hasLoadedSnapshot, !isLoading, !isSaving, let user = Auth.auth().currentUser, user.isEmailVerified, user.uid == listeningUserID, let planID = currentPlan?.id else { throw KairosTouchSchedule.Failure("Wait for your verified account’s planner to load.") }
        return try KairosTouchSchedule.begin(plan: rawPlan, target: target, ownerID: user.uid, planID: planID, timezone: timezone, allowCompleted: allowCompleted)
    }

    func saveTouchEdit(_ draft: KairosTouchDraft, placement: KairosSchedulePlacement) async -> KairosTouchUndo? {
        guard hasLoadedSnapshot, !isLoading, !isSaving, let user = Auth.auth().currentUser, user.isEmailVerified, user.uid == listeningUserID, user.uid == draft.ownerID, currentPlan?.id == draft.planID else { errorMessage = "Your account or planner changed. Reopen Schedule before retrying."; return nil }
        let uid = user.uid, token = generation
        let reference = db.collection("study_plans").document(draft.planID), userRef = db.collection("users").document(uid)
        isSaving = true
        defer { if generation == token { isSaving = false } }
        do {
            let fingerprint = try KairosAIProposalEngine.digest(["id": draft.id, "target": KairosTouchSchedule.encode(draft.target), "expected": draft.expectedJSON, "date": placement.date, "start": placement.start, "end": placement.end, "timezone": draft.timezone])
            let result = try await db.runTransaction { transaction, pointer in
                do {
                    guard let current = Auth.auth().currentUser, current.uid == uid, current.isEmailVerified else { throw CancellationError() }
                    let snapshot = try transaction.getDocument(reference)
                    let profile = try transaction.getDocument(userRef).data() ?? [:]
                    guard let raw = snapshot.data(), raw["userID"] as? String == uid else { throw KairosPlannerMerge.Conflict() }
                    var receipts = try KairosAIProposalEngine.maps(raw["scheduleTouchReceipts"])
                    if let receipt = receipts.first(where: { $0["id"] as? String == draft.id }) {
                        guard receipt["fingerprint"] as? String == fingerprint, receipt["undone"] as? Bool != true, let undo = receipt["undoJSON"] as? String else { throw KairosTouchSchedule.Failure("This schedule change was already undone or its identity changed.") }
                        return undo
                    }
                    guard draft.createdAt > (raw["scheduleTouchReceiptFloor"] as? Double ?? 0) else { throw KairosTouchSchedule.Failure("This retry is too old to confirm safely. Check Schedule before making a new change.") }
                    let settings = profile["settings"] as? [String: Any], account = settings?["profile"] as? [String: Any]
                    guard account?["timezone"] as? String == nil || account?["timezone"] as? String == draft.timezone else { throw KairosTouchSchedule.Failure("Your timezone changed. Start the gesture again.") }
                    let allowCompleted = (settings?["planning"] as? [String: Any])?["rescheduleCompleted"] as? Bool == true
                    let applied = try KairosTouchSchedule.apply(plan: raw, draft: draft, placement: placement, allowCompleted: allowCompleted)
                    let undo = try KairosTouchSchedule.encode(applied.undo)
                    receipts.append(["id": draft.id, "createdAt": draft.createdAt, "fingerprint": fingerprint, "undoJSON": undo, "undone": false])
                    var floor = raw["scheduleTouchReceiptFloor"] as? Double ?? 0
                    while true {
                        let bytes = try JSONSerialization.data(withJSONObject: receipts).count
                        if receipts.count <= 100 && bytes <= 64_000 { break }
                        guard receipts.count > 1 else { throw KairosTouchSchedule.Failure("This schedule receipt is too large.") }
                        floor = max(floor, receipts.removeFirst()["createdAt"] as? Double ?? 0)
                    }
                    transaction.updateData(["boards": applied.plan["boards"] ?? [], "scheduleTouchReceipts": receipts, "scheduleTouchReceiptFloor": floor], forDocument: reference)
                    return undo
                } catch { pointer?.pointee = error as NSError; return nil }
            }
            guard token == generation, Auth.auth().currentUser?.uid == uid, let json = result as? String else { return nil }
            let undo = try JSONDecoder().decode(KairosTouchUndo.self, from: Data(json.utf8))
            errorMessage = nil; return undo
        } catch { guard token == generation else { return nil }; errorMessage = error.localizedDescription; return nil }
    }

    @discardableResult
    func undoTouchEdit(_ undo: KairosTouchUndo) async -> Bool {
        guard hasLoadedSnapshot, !isLoading, !isSaving, let user = Auth.auth().currentUser, user.isEmailVerified, user.uid == listeningUserID, user.uid == undo.ownerID, currentPlan?.id == undo.planID else { errorMessage = "Your account or planner changed. Reopen Schedule before retrying."; return false }
        let uid = user.uid, token = generation, reference = db.collection("study_plans").document(undo.planID), userRef = db.collection("users").document(user.uid)
        isSaving = true
        defer { if generation == token { isSaving = false } }
        do {
            let expected = try KairosTouchSchedule.encode(undo)
            _ = try await db.runTransaction { transaction, pointer in
                do {
                    guard let current = Auth.auth().currentUser, current.uid == uid, current.isEmailVerified else { throw CancellationError() }
                    let snapshot = try transaction.getDocument(reference)
                    let profile = try transaction.getDocument(userRef).data() ?? [:]
                    guard let raw = snapshot.data(), raw["userID"] as? String == uid else { throw KairosPlannerMerge.Conflict() }
                    var receipts = try KairosAIProposalEngine.maps(raw["scheduleTouchReceipts"])
                    guard let index = receipts.firstIndex(where: { $0["id"] as? String == undo.id }), receipts[index]["undoJSON"] as? String == expected else { throw KairosTouchSchedule.Failure("This saved Undo is no longer available.") }
                    if receipts[index]["undone"] as? Bool == true { return true }
                    let settings = profile["settings"] as? [String: Any], account = settings?["profile"] as? [String: Any]
                    guard account?["timezone"] as? String == nil || account?["timezone"] as? String == undo.timezone else { throw KairosTouchSchedule.Failure("Your timezone changed. Review Schedule before using Undo.") }
                    let allowCompleted = (settings?["planning"] as? [String: Any])?["rescheduleCompleted"] as? Bool == true
                    let restored = try KairosTouchSchedule.undo(plan: raw, record: undo, allowCompleted: allowCompleted)
                    receipts[index]["undone"] = true
                    transaction.updateData(["boards": restored["boards"] ?? [], "scheduleTouchReceipts": receipts], forDocument: reference)
                    return true
                } catch { pointer?.pointee = error as NSError; return nil }
            }
            guard token == generation, Auth.auth().currentUser?.uid == uid else { return false }
            errorMessage = nil; return true
        } catch { guard token == generation else { return false }; errorMessage = error.localizedDescription; return false }
    }

    func taskReminderCandidates(timezone: String) async throws -> [KairosReminderCandidate] {
        guard hasLoadedSnapshot, !isLoading else { return [] }
        let calendar = KairosAIProposalEngine.calendar(timezone)
        let today = calendar.startOfDay(for: Date())
        let days = (0..<35).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }.map { KairosDate.dayKey(for: $0, timeZone: calendar.timeZone) }
        let occurrences = try await recurringOccurrences(onDays: days)
        var candidates: [KairosReminderCandidate] = []
        let tasks = currentPlan?.boards.filter { !$0.archived }.flatMap { $0.sections.filter { !$0.archived } }.flatMap { $0.tasks.filter { !$0.archived && !$0.completed && $0.recurrence?.enabled != true } } ?? []
        for task in tasks {
            if let date = task.date, let start = task.startTime, let minutes = task.reminderMinutes { candidates.append(.init(id: task.id, title: task.title, date: date, startTime: start, minutesBefore: minutes)) }
        }
        let reminderSeries = Set((currentPlan?.boards.filter { !$0.archived }.flatMap { $0.sections.filter { !$0.archived } }.flatMap { $0.tasks.filter { !$0.archived && !$0.completed } } ?? []).map(\.id))
        for occurrence in occurrences.values.flatMap({ $0 }) where occurrence.status == "pending" && reminderSeries.contains(occurrence.seriesId) {
            if let start = occurrence.startTime, let minutes = occurrence.task.reminderMinutes { candidates.append(.init(id: occurrence.id, title: occurrence.task.title, date: occurrence.displayDate, startTime: start, minutesBefore: minutes)) }
        }
        return candidates
    }
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
            boards = try KairosBoardMutation.apply(.renameBoard(boardID: boardID, title: title), to: boards)
        }
    }

    @discardableResult
    func updateBoard(
        boardID: String,
        title: String? = nil,
        description: String? = nil,
        preserveDescription: Bool = false,
        expected: KairosBoard? = nil
    ) async -> Bool {
        return await mutateBoards { boards in
            guard let index = boards.firstIndex(where: { $0.id == boardID })
            else { throw KairosTaskMutation.Invalid() }
            boards = try KairosBoardMutation.apply(.renameBoard(boardID: boardID, title: boards[index].title), to: boards)
            if let expected, expected.id != boardID { throw KairosPlannerMerge.Conflict() }
            if let title, expected == nil || title != expected?.title {
                if let expected, boards[index].title != expected.title && boards[index].title != title { throw KairosPlannerMerge.Conflict() }
                boards = try KairosBoardMutation.apply(.renameBoard(boardID: boardID, title: title), to: boards)
            }
            if (description != nil || !preserveDescription), expected == nil || description != expected?.boardDescription {
                if let expected, boards[index].boardDescription != expected.boardDescription && boards[index].boardDescription != description { throw KairosPlannerMerge.Conflict() }
                boards[index].boardDescription = description
            }
        }
    }

    @discardableResult
    func setBoardArchived(boardID: String, archived: Bool) async -> Bool {
        return await mutateBoards { boards in
            boards = try KairosBoardMutation.apply(.archiveBoard(boardID: boardID, archived: archived), to: boards)
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
            boards = try KairosBoardMutation.apply(.renameSection(sectionID: sectionID, title: title), to: boards)
        }
    }

    @discardableResult
    func setSectionArchived(sectionID: String, archived: Bool) async -> Bool {
        return await mutateBoards { boards in
            boards = try KairosBoardMutation.apply(.archiveSection(sectionID: sectionID, archived: archived), to: boards)
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
    func aiReviewFingerprint() throws -> String {
        guard hasLoadedSnapshot, !isLoading else { throw KairosAIProposalEngine.Invalid("Wait for your planner to load.") }
        return try KairosAIProposalEngine.fingerprint(rawPlan)
    }

    func makeAIProposal(actions: [KairosChatAction], ownerID: String, chatID: String, timezone: String, request: String, expectedFingerprint: String, allowCompletedRescheduling: Bool = false) throws -> KairosAIProposal {
        guard Auth.auth().currentUser?.uid == ownerID, listeningUserID == ownerID, try aiReviewFingerprint() == expectedFingerprint else { throw KairosAIProposalEngine.Invalid("Your planner changed while Kairos was replying. Ask again to review the latest plan.") }
        return try KairosAIProposalEngine.make(actions: actions, plan: rawPlan, ownerID: ownerID, chatID: chatID, planID: currentPlan?.id ?? ownerID, timezone: timezone, request: request, allowCompletedRescheduling: allowCompletedRescheduling)
    }

    @discardableResult
    func applySavedAIProposal(_ proposal: KairosAIProposal) async -> Bool {
        guard !isSaving, hasLoadedSnapshot, !isLoading, let user = Auth.auth().currentUser, user.isEmailVerified,
              user.uid == listeningUserID, user.uid == proposal.ownerID, (currentPlan?.id ?? user.uid) == proposal.planID else { errorMessage = "Wait for the preview’s verified account and planner to load."; return false }
        let uid = user.uid, token = generation
        let planRef = db.collection("study_plans").document(proposal.planID)
        let userRef = db.collection("users").document(uid)
        // A confirmed receipt can settle a retry even when local state has moved.
        let prepared = try? KairosAIProposalEngine.prepare(proposal, plan: rawPlan)
        isSaving = true
        defer { if generation == token { isSaving = false } }
        do {
            try KairosAIProposalEngine.validate(proposal)
            _ = try await db.runTransaction { transaction, pointer in
                do {
                    guard let activeUser = Auth.auth().currentUser, activeUser.uid == uid, activeUser.isEmailVerified else { throw CancellationError() }
                    let planSnapshot = try transaction.getDocument(planRef)
                    let userSnapshot = try transaction.getDocument(userRef)
                    let remote = planSnapshot.data() ?? [:], profile = userSnapshot.data() ?? [:]
                    guard !planSnapshot.exists || remote["userID"] as? String == uid else { throw KairosPlannerMerge.Conflict() }
                    if try KairosAIProposalEngine.wasApplied(proposal, plan: remote) {
                        if var proposals = profile["aiNativeProposals"] as? [String: Any], let current = proposals[proposal.chatID] as? [String: Any], current["id"] as? String == proposal.id {
                            let restored = try JSONDecoder().decode(KairosAIProposal.self, from: JSONSerialization.data(withJSONObject: current))
                            guard try KairosAIProposalEngine.payloadFingerprint(restored) == KairosAIProposalEngine.payloadFingerprint(proposal) else { throw KairosPlannerMerge.Conflict() }
                            proposals.removeValue(forKey: proposal.chatID)
                            var patch = try KairosAIProposalHistory.retire(proposal, state: "applied", user: profile); patch["aiNativeProposals"] = proposals
                            transaction.updateData(patch, forDocument: userRef)
                        }
                        return true
                    }
                    guard let saved = (profile["aiNativeProposals"] as? [String: Any])?[proposal.chatID] as? [String: Any] else { throw KairosAIProposalEngine.Invalid("This preview was discarded or changed on another device.") }
                    let stored = try JSONDecoder().decode(KairosAIProposal.self, from: JSONSerialization.data(withJSONObject: saved))
                    guard try KairosAIProposalEngine.payloadFingerprint(stored) == KairosAIProposalEngine.payloadFingerprint(proposal),
                          try KairosAIProposalEngine.fingerprint(remote) == proposal.beforeFingerprint, let prepared else { throw KairosAIProposalEngine.Invalid("Your planner or preview changed. Discard it and request a fresh preview.") }
                    let settings = profile["settings"] as? [String: Any]
                    guard ((settings?["planning"] as? [String: Any])?["rescheduleCompleted"] as? Bool == true) == proposal.allowCompletedRescheduling else { throw KairosAIProposalEngine.Invalid("Your planning preferences changed. Request a fresh preview.") }
                    let userProfile = settings?["profile"] as? [String: Any]
                    guard userProfile?["timezone"] as? String == nil || userProfile?["timezone"] as? String == proposal.timezone else { throw KairosAIProposalEngine.Invalid("Your timezone changed. Request a fresh preview.") }
                    guard let workspaceRaw = profile["aiWorkspace"] as? [String: Any],
                          let chat = try KairosAIWorkspace.read(workspaceRaw, legacy: [], owner: uid).chats.first(where: { $0.id == proposal.chatID }), !chat.hasUnfinishedWebActions else { throw KairosAIProposalEngine.Invalid("This chat was removed or has an unfinished web change.") }
                    let merged = try KairosPlannerMerge.merge(base: prepared.before, local: prepared.after, remote: remote)
                    let response = KairosAIWorkspace.Message(id: "applied-" + proposal.id, role: "assistant", content: "Applied the reviewed changes to your planner.")
                    let workspace = try KairosAIWorkspace.applying(.append(chatID: proposal.chatID, messages: [response]), to: workspaceRaw, legacy: [], owner: uid)
                    var proposals = profile["aiNativeProposals"] as? [String: Any] ?? [:]
                    proposals.removeValue(forKey: proposal.chatID)
                    var receipts = try KairosAIProposalEngine.maps(remote["aiNativeActionReceipts"])
                    receipts.append(try KairosAIProposalEngine.receipt(proposal))
                    var floor = remote["aiNativeActionReceiptFloor"] as? Double ?? 0
                    while true {
                        let bytes = try JSONSerialization.data(withJSONObject: receipts).count
                        if receipts.count <= 100 && bytes <= 64_000 { break }
                        guard receipts.count > 1 else { throw KairosAIProposalEngine.Invalid("This apply receipt is too large.") }
                        floor = max(floor, receipts.removeFirst()["createdAt"] as? Double ?? 0)
                    }
                    var fields: [String: Any] = ["boards": merged["boards"] ?? [], "scheduleEvents": merged["scheduleEvents"] ?? [], "aiNativeActionReceipts": receipts, "aiNativeActionReceiptFloor": floor]
                    if planSnapshot.exists { transaction.updateData(fields, forDocument: planRef) }
                    else { fields["userID"] = uid; fields["createdAt"] = FieldValue.serverTimestamp(); transaction.setData(fields, forDocument: planRef) }
                    var profilePatch: [String: Any] = ["aiWorkspace": workspace, "aiNativeProposals": proposals]
                    profilePatch.merge(try KairosAIProposalHistory.retire(proposal, state: "applied", user: profile)) { _, new in new }
                    var progress = profile
                    for id in prepared.completedTaskIDs {
                        let patch = try KairosProgress.taskCompletion(data: progress, taskID: id, dayKey: KairosDate.dayKey(for: Date(), timeZone: TimeZone(identifier: proposal.timezone) ?? .current))
                        progress.merge(patch) { _, new in new }; profilePatch.merge(patch) { _, new in new }
                    }
                    transaction.updateData(profilePatch, forDocument: userRef)
                    return true
                } catch { pointer?.pointee = error as NSError; return nil }
            }
            guard token == generation, Auth.auth().currentUser?.uid == uid else { return false }
            errorMessage = nil; return true
        } catch { guard token == generation else { return false }; errorMessage = error.localizedDescription; return false }
    }

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

