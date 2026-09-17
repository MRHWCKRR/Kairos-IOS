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
    @State private var isCreateExpanded = false

    private var boards: [KairosBoard] { planRepo.currentPlan?.boards.filter { !$0.archived } ?? [] }
    private var tasks: [KairosTask] { boards.flatMap { $0.sections.filter { !$0.archived } }.flatMap { $0.tasks.filter { !$0.archived } } }
    private var completedCount: Int { tasks.filter { $0.completed || optimisticCompletedIDs.contains($0.id) }.count }
    private var progress: Double { tasks.isEmpty ? 0 : Double(completedCount) / Double(tasks.count) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    summary
                    boardList
                }
                .padding(.horizontal, KairosMetrics.pageHorizontal)
                .padding(.top, 16)
                .padding(.bottom, 150)
            }
            .kairosBackground()
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { creationDock }
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
            Text("Tasks").font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-1)
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
                    Image(systemName: "checklist").font(.system(size: 30)).foregroundStyle(KairosColors.accent)
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
                Image(systemName: "checklist").font(.headline.weight(.semibold)).foregroundStyle(KairosColors.accent)
                    .frame(width: 38, height: 38)
                    .background(KairosColors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(board.title).font(.headline.weight(.bold))
                    Text("\(done) of \(boardTasks.count) complete").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.tertiary)
            }
            if !boardTasks.isEmpty { ProgressView(value: Double(done), total: Double(boardTasks.count)).tint(KairosColors.accent).scaleEffect(y: 1.2) }
            ForEach(sections) { section in sectionBlock(board: board, section: section) }
            Button { createTarget = .section(boardID: board.id) } label: {
                Label("Add section", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
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
                if !visible.isEmpty && open.isEmpty { Image(systemName: "checkmark.seal.fill").foregroundStyle(KairosColors.accent) }
            }
            ForEach(open) { task in taskRow(board: board, section: section, task: task) }
            if showingCompleted && !done.isEmpty {
                if !open.isEmpty { Text("Completed").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 3) }
                ForEach(done) { task in taskRow(board: board, section: section, task: task) }
            }
            Button { createTarget = .task(sectionID: section.id) } label: {
                Label("Add task", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
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
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    }
                }
            }.buttonStyle(.plain).accessibilityLabel(completed ? "Mark \(task.title) incomplete" : "Complete \(task.title)")

            Button { selectedTask = TaskDetailContext(taskID: task.id, boardID: board.id, sectionID: section.id) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.subheadline.weight(completed ? .medium : .semibold)).foregroundStyle(completed ? .secondary : .primary)
                        .strikethrough(completed, color: KairosColors.accent).multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        if let date = task.date { Label(Self.displayDate(date, dueTime: task.dueTime), systemImage: "calendar") }
                        if task.parentTaskID != nil { Label("Subtask", systemImage: "arrow.turn.down.right") }
                        if task.taskDescription?.isEmpty == false { Image(systemName: "text.alignleft") }
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.buttonStyle(.plain)
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
                Image(systemName: isCreateExpanded ? "xmark" : "plus")
                    .font(.title2.weight(.semibold)).frame(width: 58, height: 58)
            }
            .foregroundStyle(.white)
            .background(KairosColors.accent, in: Circle())
            .shadow(color: KairosColors.accent.opacity(0.28), radius: 18, y: 8)
            .draggable("kairos-create")
            .simultaneousGesture(TapGesture().onEnded { isCreateExpanded.toggle() })
            .accessibilityLabel("Add")
            .accessibilityHint("Tap to choose what to add, or drag onto a board, section, or task")
            .padding(.trailing, 18).padding(.bottom, 8)
        }
    }

    private func toggle(boardID: String, section: KairosSection, task: KairosTask) {
        let wasCompleted = task.completed || optimisticCompletedIDs.contains(task.id)
        let willComplete = !wasCompleted
        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82)) {
            if willComplete { optimisticCompletedIDs.insert(task.id) } else { optimisticCompletedIDs.remove(task.id) }
        }
        if willComplete { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        Task {
            await planRepo.toggleTask(boardID: boardID, sectionID: section.id, taskID: task.id)
            if willComplete { await profileRepo.recordTaskCompletion(taskID: task.id) }
            await MainActor.run { optimisticCompletedIDs.remove(task.id) }
        }
    }

    private static func displayDate(_ value: String, dueTime: String?) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: value) else { return value }
        formatter.dateStyle = .medium
        let base = formatter.string(from: date)
        if let dueTime { return "\(base) · \(dueTime)" }
        return base
    }
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

private struct TaskCreationSheet: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(\.dismiss) private var dismiss
    let target: TaskCreateTarget
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(titleForTarget).font(.title3.weight(.bold))
            TextField("Name", text: $title).textFieldStyle(.roundedBorder)
            Button("Create") { create() }.buttonStyle(.glassProminent).tint(KairosColors.accent).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer()
        }.padding(24)
    }

    private var titleForTarget: String {
        switch target { case .board: return "New board"; case .section: return "New section"; case .task: return "New task"; case .subtask: return "New subtask" }
    }

    private func create() {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty else { return }
        Task {
            switch target {
            case .board: await planRepo.addBoard(title: value)
            case .section(let boardID): await planRepo.addSection(boardID: boardID, title: value)
            case .task(let sectionID): await planRepo.addTask(sectionID: sectionID, title: value)
            case .subtask(let parentID, let sectionID): await planRepo.addSubtask(parentTaskID: parentID, sectionID: sectionID, title: value)
            }
            dismiss()
        }
    }
}

struct TaskDetailView: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(\.dismiss) private var dismiss
    let context: TaskDetailContext
    @State private var title = ""
    @State private var taskDescription = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var hasDueTime = false
    @State private var dueTime = Date()
    @State private var showSubtaskCreator = false
    @State private var subtaskTitle = ""
    @State private var initialized = false

    private var task: KairosTask? {
        planRepo.currentPlan?.boards.first(where: { $0.id == context.boardID })?.sections.first(where: { $0.id == context.sectionID })?.tasks.first(where: { $0.id == context.taskID })
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
                    scheduleCard
                    childrenCard
                }.padding(20)
            }
            .kairosBackground()
            .navigationTitle("Task details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { save(); dismiss() } } }
            .onAppear { load() }
        }
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Task title", text: $title).font(.title2.weight(.bold))
            Text("Edit the task without leaving your checklist.").font(.caption).foregroundStyle(.secondary)
        }.padding(18).kairosCard(cornerRadius: 22)
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Description", systemImage: "text.alignleft").font(.subheadline.weight(.semibold))
            TextEditor(text: $taskDescription).frame(minHeight: 110).scrollContentBackground(.hidden)
                .padding(8).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.padding(18).kairosCard(cornerRadius: 22)
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Schedule", systemImage: "calendar").font(.subheadline.weight(.semibold))
            Toggle("Due date", isOn: $hasDueDate)
            if hasDueDate { DatePicker("Date", selection: $dueDate, displayedComponents: .date) }
            Toggle("Due time", isOn: $hasDueTime)
            if hasDueTime { DatePicker("Time", selection: $dueTime, displayedComponents: .hourAndMinute) }
            Text("Scheduled tasks automatically appear on the matching day in Kairos Calendar. Apple Calendar export remains opt-in.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).kairosCard(cornerRadius: 22)
    }

    private var childrenCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("Subtasks", systemImage: "arrow.turn.down.right").font(.subheadline.weight(.semibold)); Spacer(); Text("\(children.filter(\.completed).count)/\(children.count)").font(.caption).foregroundStyle(.secondary) }
            ForEach(children) { child in
                HStack(spacing: 10) {
                    Image(systemName: child.completed ? "checkmark.circle.fill" : "circle").foregroundStyle(child.completed ? KairosColors.accent : .secondary)
                    Text(child.title).font(.subheadline).strikethrough(child.completed)
                    Spacer()
                }
            }
            Button { showSubtaskCreator = true } label: { Label("Add subtask", systemImage: "plus") }.foregroundStyle(KairosColors.accent)
        }.padding(18).kairosCard(cornerRadius: 22)
        .alert("New subtask", isPresented: $showSubtaskCreator) {
            TextField("Subtask", text: $subtaskTitle)
            Button("Add") { let value = subtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty else { return }; Task { await planRepo.addSubtask(parentTaskID: context.taskID, sectionID: context.sectionID, title: value); subtaskTitle = "" } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func load() {
        guard !initialized, let task else { return }
        initialized = true
        title = task.title
        taskDescription = task.taskDescription ?? ""
        if let dateKey = task.date { hasDueDate = true; dueDate = Self.date(from: dateKey) ?? Date() }
        if let value = task.dueTime, let date = Self.time(from: value) { hasDueTime = true; dueTime = date }
    }

    private func save() {
        let dateKey = hasDueDate ? Self.dateKey(from: dueDate) : nil
        let timeKey = hasDueTime ? Self.timeKey(from: dueTime) : nil
        Task { await planRepo.updateTask(taskID: context.taskID, title: title.trimmingCharacters(in: .whitespacesAndNewlines), description: taskDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : taskDescription, date: dateKey, dueTime: timeKey) }
    }

    private static func dateKey(from date: Date) -> String { let f = DateFormatter(); f.calendar = .current; f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    private static func date(from key: String) -> Date? { let f = DateFormatter(); f.calendar = .current; f.dateFormat = "yyyy-MM-dd"; return f.date(from: key) }
    private static func timeKey(from date: Date) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date) }
    private static func time(from key: String) -> Date? { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.date(from: key) }
}

#Preview {
    TasksWorkspaceView().environment(StudyPlanRepository()).environment(UserProfileRepository())
}
