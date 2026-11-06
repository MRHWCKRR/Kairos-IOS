import SwiftUI
import UIKit

struct TasksWorkspaceView: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingCompleted = true
    @State private var selectedTask: TaskDetailContext?
    @State private var createTarget: TaskCreateTarget?
    @State private var showCreateChooser = false
    @State private var optimisticCompletedIDs: Set<String> = []
    @State private var pendingTaskIDs: Set<String> = []
    @State private var isCreateExpanded = false
    @State private var editingBoard: KairosBoard?
    @State private var renamingSection: KairosSection?
    @State private var showingArchive = false
    @State private var archiveTarget: ArchiveTarget?

    private var boards: [KairosBoard] { planRepo.currentPlan?.boards.filter { !$0.archived } ?? [] }
    private var tasks: [KairosTask] { boards.flatMap { $0.sections.filter { !$0.archived } }.flatMap { $0.tasks.filter { !$0.archived } } }
    private var completedCount: Int { tasks.filter { $0.completed || optimisticCompletedIDs.contains($0.id) }.count }
    private var progress: Double { tasks.isEmpty ? 0 : Double(completedCount) / Double(tasks.count) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if planRepo.isLoading {
                        ProgressView("Loading your planner…").frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else if planRepo.plannerIsUnavailable {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Your planner couldn’t load", sharedIcon: "exclamationmark.triangle")
                                .font(.headline)
                            Text(planRepo.errorMessage ?? "Retry loading your planner.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("Retry") { planRepo.retryLoading() }.buttonStyle(.bordered)
                        }.padding(20).kairosCard(cornerRadius: 24)
                    } else {
                        summary
                        boardList
                        if let error = planRepo.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
                    }
                }
                .padding(.horizontal, KairosMetrics.pageHorizontal)
                .padding(.top, 16)
                .padding(.bottom, 150)
            }
            .kairosBackground()
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { creationDock }
            .sheet(item: $editingBoard) { board in
                BoardDetailsView(board: board).environment(planRepo)
            }
            .sheet(item: $renamingSection) { section in
                KairosNameEditor(heading: "Rename section", initialValue: section.title, failureMessage: { planRepo.errorMessage }) { title in
                    await planRepo.renameSection(sectionID: section.id, title: title, expectedTitle: section.title)
                }
            }
            .sheet(isPresented: $showingArchive) { PlannerArchiveView().environment(planRepo) }
            .confirmationDialog("Archive this item?", isPresented: Binding(get: { archiveTarget != nil }, set: { if !$0 { archiveTarget = nil } }), titleVisibility: .visible, presenting: archiveTarget) { target in
                Button("Archive", role: .destructive) {
                    archiveTarget = nil
                    Task {
                        switch target {
                        case .board(let id): _ = await planRepo.setBoardArchived(boardID: id, archived: true)
                        case .section(let id): _ = await planRepo.setSectionArchived(sectionID: id, archived: true)
                        case .task(let id): _ = await planRepo.setTaskArchived(taskID: id, archived: true)
                        }
                    }
                }
                Button("Cancel", role: .cancel) { archiveTarget = nil }
            } message: { _ in Text("You can restore it from Archive. Its contents will be preserved.") }
            .sheet(item: $selectedTask) { context in
                TaskDetailView(context: context)
                    .environment(planRepo)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $createTarget) { target in
                TaskCreationSheet(target: target)
                    .environment(planRepo)
                    .presentationDetents([.height(250)])
                    .presentationDragIndicator(.visible)
            }
            .confirmationDialog("Add to Kairos", isPresented: $showCreateChooser, titleVisibility: .visible) {
                Button("Board") { createTarget = .board }
                if let firstBoard = boards.first {
                    Button("Section in \(firstBoard.title)") { createTarget = .section(boardID: firstBoard.id) }
                    if let firstSection = firstBoard.sections.first(where: { !$0.archived }) {
                        Button("Task in \(firstSection.title)") { createTarget = .task(sectionID: firstSection.id) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose what you want to add. You can also drag the + button onto a board, section, or task.")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Tasks").font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-1)
                Spacer()
                Button { showingArchive = true } label: { Label("Archive", sharedIcon: "archivebox") }
                    .font(.subheadline).disabled(planRepo.isLoading || planRepo.plannerIsUnavailable)
            }
            Text("Everything you need to get done, organized into focused checklists.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your checklist").font(.headline.weight(.bold))
                    Text(tasks.isEmpty ? "Start with one small win." : "Keep the momentum going.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.14), lineWidth: 6)
                    Circle().trim(from: 0, to: progress)
                        .stroke(KairosColors.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(progress * 100))%").font(.caption.weight(.bold))
                }
                .frame(width: 58, height: 58)
            }
            HStack(spacing: 0) {
                metric("\(max(0, tasks.count - completedCount))", "Remaining")
                Divider().frame(height: 32)
                metric("\(completedCount)", "Completed")
                Divider().frame(height: 32)
                metric("\(tasks.count)", "Total")
            }
        }
        .padding(20)
        .kairosCard(cornerRadius: 26)
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var boardList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Checklists").font(.title3.weight(.bold))
                Spacer()
                Button(showingCompleted ? "Hide completed" : "Show completed") { showingCompleted.toggle() }
                    .font(.caption.weight(.semibold)).foregroundStyle(KairosColors.accent)
            }
            if boards.isEmpty {
                VStack(spacing: 8) {
                    KairosIcon("checklist", size: 30).foregroundStyle(KairosColors.accent)
                    Text("Your checklist is empty").font(.headline)
                    Text("Use the + button to create your first board.").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(30).kairosCard(cornerRadius: 24)
            } else {
                ForEach(boards) { board in boardCard(board) }
            }
        }
    }

    private func boardCard(_ board: KairosBoard) -> some View {
        let sections = board.sections.filter { !$0.archived }
        let boardTasks = sections.flatMap { $0.tasks.filter { !$0.archived } }
        let done = boardTasks.filter { $0.completed || optimisticCompletedIDs.contains($0.id) }.count
        return VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                KairosIcon("checklist", size: 17).foregroundStyle(KairosColors.accent)
                    .frame(width: 38, height: 38)
                    .background(KairosColors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(board.title).font(.headline.weight(.bold))
                    Text("\(done) of \(boardTasks.count) complete").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Edit board", sharedIcon: "pencil") { editingBoard = board }
                    Button("Archive board", sharedIcon: "archivebox", role: .destructive) { archiveTarget = .board(board.id) }
                } label: { KairosIcon("ellipsis").frame(width: 44, height: 44) }
                .disabled(planRepo.isSaving)
                .accessibilityLabel("Options for \(board.title)")
            }
            if !boardTasks.isEmpty { ProgressView(value: Double(done), total: Double(boardTasks.count)).tint(KairosColors.accent).scaleEffect(y: 1.2) }
            ForEach(sections) { section in sectionBlock(board: board, section: section) }
            Button { createTarget = .section(boardID: board.id) } label: {
                Label("Add section", sharedIcon: "plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
            }.foregroundStyle(KairosColors.accent)
        }
        .padding(18).kairosCard(cornerRadius: 26)
        .dropDestination(for: String.self) { _, _ in
            createTarget = .section(boardID: board.id)
            return true
        } isTargeted: { targeted in
            // The board itself is a contextual creation target.
        }
    }

    private func sectionBlock(board: KairosBoard, section: KairosSection) -> some View {
        let visible = section.tasks.filter { !$0.archived }
        let open = visible.filter { !$0.completed && !optimisticCompletedIDs.contains($0.id) }
        let done = visible.filter { $0.completed || optimisticCompletedIDs.contains($0.id) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title).font(.subheadline.weight(.bold))
                    Text("\(done.count) of \(visible.count) complete").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !visible.isEmpty && open.isEmpty { KairosIcon("checkmark.seal.fill").foregroundStyle(KairosColors.accent) }
                Menu {
                    Button("Rename section", sharedIcon: "pencil") { renamingSection = section }
                    Button("Archive section", sharedIcon: "archivebox", role: .destructive) { archiveTarget = .section(section.id) }
                } label: { KairosIcon("ellipsis").frame(width: 44, height: 44) }
                .disabled(planRepo.isSaving)
                .accessibilityLabel("Options for \(section.title)")
            }
            ForEach(open) { task in taskRow(board: board, section: section, task: task) }
            if showingCompleted && !done.isEmpty {
                if !open.isEmpty { Text("Completed").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 3) }
                ForEach(done) { task in taskRow(board: board, section: section, task: task) }
            }
            Button { createTarget = .task(sectionID: section.id) } label: {
                Label("Add task", sharedIcon: "plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
            }.foregroundStyle(KairosColors.accent)
        }
        .padding(15)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .dropDestination(for: String.self) { _, _ in
            createTarget = .task(sectionID: section.id)
            return true
        } isTargeted: { _ in }
    }

    private func taskRow(board: KairosBoard, section: KairosSection, task: KairosTask) -> some View {
        let completed = task.completed || optimisticCompletedIDs.contains(task.id)
        return HStack(spacing: 10) {
            Button {
                toggle(boardID: board.id, section: section, task: task)
            } label: {
                ZStack {
                    Circle().stroke(completed ? KairosColors.accent : Color.secondary.opacity(0.48), lineWidth: 1.8).frame(width: 24, height: 24)
                    if completed {
                        Circle().fill(KairosColors.accent).frame(width: 24, height: 24)
                        KairosIcon("checkmark", size: 12).foregroundStyle(.white)
                    }
                }
            }.buttonStyle(.plain)
                .disabled(task.recurrence?.enabled == true || pendingTaskIDs.contains(task.id) || planRepo.isSaving)
                .accessibilityLabel(task.recurrence?.enabled == true ? "Recurring task: \(task.title)" : completed ? "Mark \(task.title) incomplete" : "Complete \(task.title)")
                .accessibilityHint(task.recurrence?.enabled == true ? "Complete individual occurrences in Schedule." : "")

            Button { selectedTask = TaskDetailContext(taskID: task.id, boardID: board.id, sectionID: section.id) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.subheadline.weight(completed ? .medium : .semibold)).foregroundStyle(completed ? .secondary : .primary)
                        .strikethrough(completed, color: KairosColors.accent).multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        if task.recurrence?.enabled == true { Label("Repeats · manage occurrences in Schedule", sharedIcon: "repeat") }
                        if let date = task.date { Label(Self.displayDate(date, dueTime: task.dueTime, timeFormat: profileRepo.accessibilitySettings?.timeFormat ?? "12"), sharedIcon: "calendar") }
                        if task.parentTaskID != nil { Label("Subtask", sharedIcon: "arrow.turn.down.right") }
                        if (task.notes ?? task.taskDescription)?.isEmpty == false { KairosIcon("text.alignleft") }
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.buttonStyle(.plain)
            Menu {
                Button("Task details", sharedIcon: "pencil") { selectedTask = TaskDetailContext(taskID: task.id, boardID: board.id, sectionID: section.id) }
                Button("Archive task", sharedIcon: "archivebox", role: .destructive) { archiveTarget = .task(task.id) }
            } label: { KairosIcon("ellipsis").frame(width: 44, height: 44) }
            .disabled(planRepo.isSaving || pendingTaskIDs.contains(task.id))
            .accessibilityLabel("Options for \(task.title)")
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { _, _ in
            createTarget = .subtask(parentTaskID: task.id, sectionID: section.id)
            return true
        } isTargeted: { _ in }
    }

    private var creationDock: some View {
        HStack {
            Spacer()
            Button { showCreateChooser = true } label: {
                KairosIcon(isCreateExpanded ? "xmark" : "plus", size: 22).frame(width: 58, height: 58)
            }
            .foregroundStyle(.white)
            .background(KairosColors.accent, in: Circle())
            .shadow(color: KairosColors.accent.opacity(0.28), radius: 18, y: 8)
            .draggable("kairos-create")
            .simultaneousGesture(TapGesture().onEnded { isCreateExpanded.toggle() })
            .disabled(planRepo.isLoading || planRepo.plannerIsUnavailable)
            .accessibilityLabel("Add")
            .accessibilityHint("Tap to choose what to add, or drag onto a board, section, or task")
            .padding(.trailing, 18).padding(.bottom, 8)
        }
    }

    private func toggle(boardID: String, section: KairosSection, task: KairosTask) {
        guard task.recurrence?.enabled != true, !planRepo.isSaving else { return }
        guard pendingTaskIDs.insert(task.id).inserted else { return }
        let wasCompleted = task.completed || optimisticCompletedIDs.contains(task.id)
        let willComplete = !wasCompleted
        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82)) {
            if willComplete { optimisticCompletedIDs.insert(task.id) } else { optimisticCompletedIDs.remove(task.id) }
        }
        if willComplete { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        Task {
            let saved = await planRepo.toggleTask(boardID: boardID, sectionID: section.id, taskID: task.id)
            if saved && willComplete { await profileRepo.recordTaskCompletion(taskID: task.id) }
            await MainActor.run { optimisticCompletedIDs.remove(task.id); pendingTaskIDs.remove(task.id) }
        }
    }

    private static func displayDate(_ value: String, dueTime: String?, timeFormat: String) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: value) else { return value }
        formatter.dateStyle = .medium
        let base = formatter.string(from: date)
        if let dueTime { return "\(base) · \(KairosTimeDisplay.time(dueTime, format: timeFormat))" }
        return base
    }
}

private enum ArchiveTarget {
    case board(String)
    case section(String)
    case task(String)
}

struct TaskDetailContext: Identifiable {
    let taskID: String
    let boardID: String
    let sectionID: String
    var id: String { taskID }
}

enum TaskCreateTarget: Identifiable {
    case board
    case section(boardID: String)
    case task(sectionID: String)
    case subtask(parentTaskID: String, sectionID: String)
    var id: String {
        switch self { case .board: return "board"; case .section(let id): return "section-\(id)"; case .task(let id): return "task-\(id)"; case .subtask(let p, _): return "subtask-\(p)" }
    }
}

struct TaskCreationSheet: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    let target: TaskCreateTarget

    var body: some View {
        KairosNameEditor(heading: titleForTarget, saveLabel: "Create", failureMessage: { planRepo.errorMessage }) { value in
            switch target {
            case .board: return await planRepo.addBoard(title: value)
            case .section(let boardID): return await planRepo.addSection(boardID: boardID, title: value)
            case .task(let sectionID): return await planRepo.addTask(sectionID: sectionID, title: value)
            case .subtask(let parentID, let sectionID): return await planRepo.addSubtask(parentTaskID: parentID, sectionID: sectionID, title: value)
            }
        }
    }

    private var titleForTarget: String {
        switch target { case .board: return "New board"; case .section: return "New section"; case .task: return "New task"; case .subtask: return "New subtask" }
    }
}

struct TaskDetailView: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var editorCalendar
    @Environment(\.timeZone) private var editorTimeZone
    let context: TaskDetailContext
    @State private var title = ""
    @State private var taskNotes = ""
    @State private var priority = ""
    @State private var hasEstimate = false
    @State private var estimateText = ""
    @State private var checklist: [KairosChecklistItem] = []
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var hasDueTime = false
    @State private var dueTime = Date()
    @State private var hasScheduledTime = false
    @State private var scheduledStart = Date()
    @State private var scheduledEnd = Date()
    @State private var hasDeadline = false
    @State private var deadline = Date()
    @State private var showSubtaskCreator = false
    @State private var originalTask: KairosTask?
    @State private var submitting = false
    @State private var saveError: String?
    @State private var initialized = false
    @State private var hasReminder = false
    @State private var reminderText = "15"
    @State private var scheduleLocked = false
    @State private var schedulingPreference = ""
    @State private var linkedTask: TaskDetailContext?
    @State private var reminderHint: String?
    @State private var originalScope: String?
    @State private var capturedCalendar: Calendar?
    private var draftCalendar: Calendar { capturedCalendar ?? editorCalendar }
    private var draftTimeZone: TimeZone { capturedCalendar?.timeZone ?? editorTimeZone }

    private var task: KairosTask? {
        planRepo.currentPlan?.boards.first(where: { $0.id == context.boardID })?.sections.first(where: { $0.id == context.sectionID })?.tasks.first(where: { $0.id == context.taskID })
    }
    private var contextAvailable: Bool {
        guard let current = resolveLinkedTask(context.taskID) else { return false }
        return current.boardID == context.boardID && current.sectionID == context.sectionID
    }

    private var children: [KairosTask] {
        guard let task else { return [] }
        return planRepo.currentPlan?.boards.first(where: { $0.id == context.boardID })?.sections.first(where: { $0.id == context.sectionID })?.tasks.filter { $0.parentTaskID == task.id && !$0.archived } ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    titleCard
                    detailsCard
                    metadataCard
                    planningCard
                    KairosChecklistEditor(items: $checklist, allowsCompletion: originalTask?.recurrence?.enabled != true)
                    scheduleCard
                    AssignmentProgressCard(taskID: context.taskID, open: openLinkedTask)
                    childrenCard
                    if initialized && !contextAvailable { Text("This task moved or became unavailable. Your draft is still here; reopen its current details before saving.").font(.footnote).foregroundStyle(.secondary) }
                    if let saveError { Text(saveError).font(.footnote).foregroundStyle(.red) }
                    if submitting { ProgressView("Saving…") }
                }.padding(20).disabled(submitting)
            }
            .kairosBackground()
            .navigationTitle("Task details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { PlannerSearchButton().disabled(submitting) }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(submitting) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(submitting || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || originalTask == nil || originalScope == nil || originalScope != planRepo.searchScope || !contextAvailable)
                }
            }
            .interactiveDismissDisabled()
            .sheet(isPresented: $showSubtaskCreator) {
                TaskCreationSheet(target: .subtask(parentTaskID: context.taskID, sectionID: context.sectionID)).environment(planRepo)
            }
            .sheet(item: $linkedTask) { TaskDetailView(context: $0) }
            .alert("Reminder saved", isPresented: Binding(get: { reminderHint != nil }, set: { if !$0 { reminderHint = nil } })) {
                Button("Done") { reminderHint = nil; dismiss() }
            } message: { Text(reminderHint ?? "") }
            .onAppear { load() }
        }.environment(\.calendar, draftCalendar).environment(\.timeZone, draftTimeZone)
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Task title", text: $title).font(.title2.weight(.bold))
            Text("Edit the task without leaving your checklist.").font(.caption).foregroundStyle(.secondary)
        }.padding(18).kairosCard(cornerRadius: 22)
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Notes", sharedIcon: "text.alignleft").font(.subheadline.weight(.semibold))
            TextEditor(text: $taskNotes).frame(minHeight: 110).scrollContentBackground(.hidden)
                .padding(8).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.padding(18).kairosCard(cornerRadius: 22)
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Priority", selection: $priority) {
                Text("None").tag("")
                Text("Low").tag("low")
                Text("Medium").tag("medium")
                Text("High").tag("high")
                if !["", "low", "medium", "high"].contains(priority) { Text(priority).tag(priority) }
            }
            Toggle("Estimated time", isOn: $hasEstimate)
            if hasEstimate {
                TextField("Minutes (1–1440)", text: $estimateText)
                    .keyboardType(.numberPad).accessibilityLabel("Estimated minutes")
            }
            Text("Notes support up to 3000 characters.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).kairosCard(cornerRadius: 22)
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Schedule", sharedIcon: "calendar").font(.subheadline.weight(.semibold))
            Group {
                Toggle("Scheduled date", isOn: $hasDueDate)
                if hasDueDate { DatePicker("Date", selection: $dueDate, displayedComponents: .date) }
                Toggle("Scheduled time", isOn: $hasScheduledTime)
                if hasScheduledTime {
                    DatePicker("Start", selection: $scheduledStart, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $scheduledEnd, displayedComponents: .hourAndMinute)
                }
            }.disabled(scheduleLocked)
            Toggle("Deadline", isOn: $hasDeadline)
            if hasDeadline { DatePicker("Due date", selection: $deadline, displayedComponents: .date) }
            Toggle("Due time", isOn: $hasDueTime)
            if hasDueTime { DatePicker("Time", selection: $dueTime, displayedComponents: .hourAndMinute) }
            Text("Scheduled time appears in Schedule on mobile and web. Your deadline is separate.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).kairosCard(cornerRadius: 22)
    }

    private var planningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Planning & reminders", sharedIcon: "calendar.badge.clock").font(.subheadline.weight(.semibold))
            Toggle("Task reminder", isOn: $hasReminder)
            if hasReminder {
                TextField("Minutes before (1–10080)", text: $reminderText).keyboardType(.numberPad).accessibilityLabel("Reminder minutes before scheduled start")
                Text("Reminders use the scheduled date and start time. Allow notifications in iOS and Kairos Settings for alerts.").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Preferred time", selection: $schedulingPreference) {
                Text("Any time").tag("")
                Text("Morning").tag("morning"); Text("Afternoon").tag("afternoon"); Text("Evening").tag("evening")
                if !["", "morning", "afternoon", "evening"].contains(schedulingPreference) { Text("Saved: \(schedulingPreference)").tag(schedulingPreference) }
            }
            Toggle("Lock schedule", isOn: $scheduleLocked)
            Text("The lock keeps this placement fixed during AI planning and touch rescheduling. Unlock it to edit the scheduled date or time. Changing a preferred time does not move this task.").font(.caption).foregroundStyle(.secondary)
        }.padding(18).kairosCard(cornerRadius: 22)
    }

    private var childrenCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("Subtasks", sharedIcon: "arrow.turn.down.right").font(.subheadline.weight(.semibold)); Spacer(); Text("\(children.filter(\.completed).count)/\(children.count)").font(.caption).foregroundStyle(.secondary) }
            ForEach(children) { child in
                Button { openLinkedTask(child.id) } label: { HStack(spacing: 10) {
                    KairosIcon(child.completed ? "checkmark.circle.fill" : "circle").foregroundStyle(child.completed ? KairosColors.accent : .secondary)
                    Text(child.title).font(.subheadline).strikethrough(child.completed)
                    Spacer()
                } }.buttonStyle(.plain)
            }
            Button { showSubtaskCreator = true } label: { Label("Add subtask", sharedIcon: "plus") }.foregroundStyle(KairosColors.accent).disabled(originalTask?.recurrence?.enabled == true)
        }.padding(18).kairosCard(cornerRadius: 22)
    }

    private func load() {
        guard !initialized, contextAvailable, let task else { return }
        initialized = true
        var calendar = editorCalendar; calendar.timeZone = editorTimeZone; capturedCalendar = calendar
        originalScope = planRepo.searchScope
        originalTask = task
        title = task.title
        taskNotes = task.notes ?? task.taskDescription ?? ""
        priority = task.priority ?? ""
        hasEstimate = task.estimatedMinutes != nil
        estimateText = task.estimatedMinutes.map(String.init) ?? ""
        checklist = task.checklist ?? []
        hasReminder = task.reminderMinutes != nil; reminderText = String(task.reminderMinutes ?? 15)
        scheduleLocked = task.scheduleLocked ?? false; schedulingPreference = task.schedulingPreference ?? ""
        if let dateKey = task.date { hasDueDate = true; dueDate = date(from: dateKey) ?? Date() }
        if let value = task.dueTime, let date = time(from: value) { hasDueTime = true; dueTime = date }
        if let value = task.startTime, let date = time(from: value) { hasScheduledTime = true; scheduledStart = date }
        if let value = task.endTime, let date = time(from: value) { scheduledEnd = date }
        if let value = task.dueDate, let date = date(from: value) { hasDeadline = true; deadline = date }
    }

    private func save() {
        guard !submitting, let originalTask, originalScope != nil, originalScope == planRepo.searchScope, contextAvailable else { return }
        var patch = KairosTaskPatch()
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let estimate = hasEstimate ? Int(estimateText) : nil
        let reminder = hasReminder ? Int(reminderText) : nil
        guard !hasReminder || reminder.map({ (1...10080).contains($0) }) == true else { saveError = "Enter reminder minutes from 1 to 10080, or turn the reminder off."; return }
        if reminder != originalTask.reminderMinutes { patch.reminderMinutes = .set(reminder) }
        if scheduleLocked != (originalTask.scheduleLocked ?? false) { patch.scheduleLocked = .set(scheduleLocked) }
        let preference: String? = schedulingPreference.isEmpty ? nil : schedulingPreference
        if preference != originalTask.schedulingPreference { patch.schedulingPreference = .set(preference) }
        guard !hasEstimate || (estimate.map { (1...1440).contains($0) } == true) else {
            saveError = "Enter an estimate from 1 to 1440 minutes."
            return
        }
        let selectedDateKey = hasDueDate ? dateKey(from: dueDate) : nil
        let selectedDueTimeKey = hasDueTime ? timeKey(from: dueTime) : nil
        if name != originalTask.title { patch.title = .set(name) }
        if taskNotes != (originalTask.notes ?? originalTask.taskDescription ?? "") { patch.notes = .set(taskNotes) }
        let selectedPriority: String? = priority.isEmpty ? nil : priority
        if selectedPriority != originalTask.priority { patch.priority = .set(selectedPriority) }
        if estimate != originalTask.estimatedMinutes { patch.estimatedMinutes = .set(estimate) }
        if checklist != (originalTask.checklist ?? []) { patch.checklist = .set(checklist) }
        if selectedDateKey != originalTask.date { patch.date = .set(selectedDateKey) }
        if selectedDueTimeKey != originalTask.dueTime { patch.dueTime = .set(selectedDueTimeKey) }
        let start = hasScheduledTime ? timeKey(from: scheduledStart) : nil
        let end = hasScheduledTime ? timeKey(from: scheduledEnd) : nil
        if start != originalTask.startTime { patch.startTime = .set(start) }
        if end != originalTask.endTime { patch.endTime = .set(end) }
        let deadlineKey = hasDeadline ? dateKey(from: deadline) : nil
        if deadlineKey != originalTask.dueDate { patch.dueDate = .set(deadlineKey) }
        submitting = true
        saveError = nil
        Task {
            defer { submitting = false }
            guard originalScope != nil, originalScope == planRepo.searchScope, contextAvailable else { return }
            let saved = await planRepo.updateTask(taskID: context.taskID, patch: patch, expected: originalTask)
            guard originalScope == planRepo.searchScope else { return }
            if saved {
                if reminder != nil && reminder != originalTask.reminderMinutes {
                    let hint = await KairosTaskReminderScheduler.enableFromUserAction(notificationsEnabled: profileRepo.notificationSettings?.enabled != false)
                    guard self.originalScope == planRepo.searchScope else { return }
                    if let hint { reminderHint = hint; return }
                }
                dismiss()
            }
            else { saveError = planRepo.errorMessage ?? "Could not save. Your edits are still here." }
        }
    }

    private func dateKey(from date: Date) -> String { let f = DateFormatter(); f.calendar = draftCalendar; f.timeZone = draftTimeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    private func date(from key: String) -> Date? { let f = DateFormatter(); f.calendar = draftCalendar; f.timeZone = draftTimeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.date(from: key) }
    private func timeKey(from date: Date) -> String { let f = DateFormatter(); f.calendar = draftCalendar; f.timeZone = draftTimeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"; return f.string(from: date) }
    private func time(from key: String) -> Date? { let f = DateFormatter(); f.calendar = draftCalendar; f.timeZone = draftTimeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"; return f.date(from: key) }

    private func openLinkedTask(_ taskID: String) {
        guard !submitting, originalScope == planRepo.searchScope, originalScope != nil else { return }
        guard let linked = resolveLinkedTask(taskID) else { saveError = "This linked task is no longer available. Your draft is unchanged."; return }
        linkedTask = linked
    }
    private func resolveLinkedTask(_ taskID: String) -> TaskDetailContext? {
        let boards = planRepo.currentPlan?.boards ?? []
        let matches = boards.flatMap { board in board.sections.flatMap { section in section.tasks.filter { $0.id == taskID }.map { (board, section, $0) } } }
        guard matches.count == 1, let (board, section, task) = matches.first, !board.archived, !section.archived, !task.archived,
              boards.filter({ $0.id == board.id }).count == 1, board.sections.filter({ $0.id == section.id }).count == 1 else { return nil }
        return .init(taskID: task.id, boardID: board.id, sectionID: section.id)
    }
}

#Preview {
    TasksWorkspaceView().environment(StudyPlanRepository()).environment(UserProfileRepository())
}

