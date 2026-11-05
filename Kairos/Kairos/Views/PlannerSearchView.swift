import SwiftUI

/// Present above the current editor: searching never dismisses its draft.
struct PlannerSearchButton: View {
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: {
            Image(systemName: "magnifyingglass").frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain).accessibilityLabel("Search planner")
        .keyboardShortcut("k", modifiers: .command)
        .sheet(isPresented: $presented) { PlannerSearchView() }
    }
}

struct PlannerSearchView: View {
    @Environment(UserProfileRepository.self) private var profileRepo
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = profileRepo.profile.flatMap { TimeZone(identifier: $0.timezone) } ?? .current
        return value
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tick in
            PlannerSearchContent(today: KairosDate.dayKey(for: tick.date, timeZone: calendar.timeZone), calendar: calendar)
        }.environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
    }
}

private struct PlannerSearchSelection: Identifiable {
    enum Destination { case board(String), task(TaskDetailContext), occurrence(KairosRecurringOccurrence) }
    let id = UUID()
    let destination: Destination
}

private struct PlannerSearchContent: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(\.dismiss) private var dismiss
    let today: String
    let calendar: Calendar
    @State private var query = ""
    @State private var status: KairosSearchStatus = .all
    @State private var index: KairosSearchIndex?
    @State private var indexedScope = ""
    @State private var results: KairosSearchResults?
    @State private var loading = false
    @State private var error: String?
    @State private var selection: PlannerSearchSelection?
    @State private var opening = false
    @State private var retry = 0

    private var loadKey: String { "\(planRepo.searchScope ?? "unavailable")-\(planRepo.plannerRevision)-\(today)-\(calendar.timeZone.identifier)" }
    private var requestKey: String { "\(loadKey)-\(status.rawValue)-\(query)-\(retry)" }
    private var currentResults: KairosSearchResults? { indexedScope == loadKey ? results : nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                Picker("Search status", selection: $status) {
                    ForEach(KairosSearchStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 12)
                content
            }
            .kairosBackground().navigationTitle("Search").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $selection) { selected in
                switch selected.destination {
                case .task(let context): TaskDetailView(context: context)
                case .board(let id): PlannerSearchBoard(boardID: id)
                case .occurrence(let occurrence): OccurrenceDetailsView(occurrence: occurrence, calendar: calendar)
                }
            }
            .task(id: requestKey) { await refresh() }
            .onChange(of: planRepo.searchScope) { _, _ in
                query = ""; status = .all; index = nil; results = nil; selection = nil; error = nil
            }
        }
    }
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Tasks, boards, assignments", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search).accessibilityLabel("Search planner")
                .onChange(of: query) { _, value in if value.count > 500 { query = String(value.prefix(500)) } }
            if !query.isEmpty { Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }.labelStyle(.iconOnly).foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44) }
        }.padding(.horizontal, 12).frame(minHeight: 48)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(16)
    }
    @ViewBuilder private var content: some View {
        if planRepo.searchScope == nil {
            ContentUnavailableView {
                Label(planRepo.isLoading ? "Loading planner" : "Search unavailable", systemImage: "magnifyingglass")
            } description: { Text(planRepo.errorMessage ?? "Search will be available when your planner has loaded.") }
            actions: { if !planRepo.isLoading { Button("Retry") { planRepo.retryLoading(); retry += 1 } } }
        } else if let error {
            ContentUnavailableView { Label("Could not search", systemImage: "exclamationmark.triangle") }
            description: { Text(error) } actions: { Button("Retry") { retry += 1 } }
        } else if loading || currentResults == nil {
            ProgressView("Searching your planner.").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let result = currentResults {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let index {
                        Text("Recurring dates: \(index.from) to \(index.to)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(result.total > result.rows.count ? "Showing \(result.rows.count) of \(result.total) matches. Refine your search to see more." : "\(result.total) \(result.total == 1 ? "result" : "results")")
                        .font(.caption).foregroundStyle(.secondary)
                    if result.rows.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    ForEach(result.rows) { row in
                        Button { open(row) } label: { PlannerSearchRowView(row: row) }
                            .buttonStyle(.plain).disabled(opening)
                    }
                }.padding(16)
            }.scrollDismissesKeyboard(.interactively)
        }
    }
    private func refresh() async {
        guard planRepo.searchScope != nil else { return }
        let key = loadKey, capturedQuery = query, capturedStatus = status
        loading = true; error = nil
        do {
            try await Task.sleep(for: .milliseconds(180))
            let cached = indexedScope == key ? index : nil
            let payload = cached == nil ? try planRepo.searchInputJSON() : ""
            let day = today
            let work = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let index = try cached ?? KairosPlannerSearch.build(planJSON: payload, today: day)
                let result = try KairosPlannerSearch.search(index, query: capturedQuery, status: capturedStatus)
                try Task.checkCancellation()
                return (index, result)
            }
            let output = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
            try Task.checkCancellation()
            guard key == loadKey else { return }
            index = output.0; results = output.1; indexedScope = key; loading = false
        } catch is CancellationError { }
        catch { guard !Task.isCancelled, key == loadKey else { return }; loading = false; error = error.localizedDescription }
    }
    private func open(_ row: KairosSearchRow) {
        guard !opening, indexedScope == loadKey, planRepo.searchResultIsAvailable(row) else {
            error = "This result is no longer available. Retry to refresh your search."; return
        }
        let key = loadKey
        if row.target.kind == "board", let id = row.target.boardId {
            selection = .init(destination: .board(id))
        } else if row.target.occurrenceDate != nil {
            opening = true
            Task {
                defer { opening = false }
                do {
                    let occurrence = try await planRepo.searchOccurrence(row)
                    guard key == loadKey else { return }
                    selection = .init(destination: .occurrence(occurrence))
                } catch { if key == loadKey { self.error = "This occurrence changed. Retry to refresh your search." } }
            }
        } else if let task = row.target.taskId, let board = row.target.boardId, let section = row.target.sectionId {
            selection = .init(destination: .task(.init(taskID: task, boardID: board, sectionID: section)))
        }
    }
}

private struct PlannerSearchRowView: View {
    let row: KairosSearchRow
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.kind == "board" ? "square.stack.3d.up" : row.kind == "occurrence" || row.kind == "series" ? "repeat" : row.completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(KairosColors.accent).frame(width: 24).padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(row.title).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                Text(row.path + " · " + row.label).font(.caption).foregroundStyle(.secondary)
                if let assignment = row.assignmentTitle, !assignment.isEmpty { Text(assignment).font(.caption).foregroundStyle(.secondary) }
                if let date = row.date { Text("\(row.dateKind ?? "Scheduled") \(date)\(row.overdue ? " · Overdue" : "")").font(.caption).foregroundStyle(row.overdue ? Color.red : Color.secondary) }
                if let logical = row.occurrenceDate, logical != row.date { Text("Originally \(logical)").font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).kairosCard(cornerRadius: 18)
            .accessibilityElement(children: .combine)
    }
}

private struct PlannerSearchBoard: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(\.dismiss) private var dismiss
    let boardID: String
    @State private var task: TaskDetailContext?
    private var board: KairosBoard? {
        let matches = planRepo.currentPlan?.boards.filter { $0.id == boardID } ?? []
        return matches.count == 1 && matches[0].archived == false ? matches[0] : nil
    }
    private func visibleSections(_ board: KairosBoard) -> [KairosSection] {
        board.sections.filter { section in !section.archived && board.sections.filter { $0.id == section.id }.count == 1 }
    }
    private func visibleTasks(_ section: KairosSection) -> [KairosTask] {
        let all = planRepo.currentPlan?.boards.flatMap(\.sections).flatMap(\.tasks) ?? []
        let counts = Dictionary(grouping: all, by: \.id).mapValues(\.count)
        return section.tasks.filter { !$0.archived && counts[$0.id] == 1 }
    }
    var body: some View {
        NavigationStack {
            List {
                if let board {
                    if let description = board.boardDescription, !description.isEmpty { Text(description).foregroundStyle(.secondary) }
                    ForEach(visibleSections(board)) { section in
                        Section(section.title) {
                            ForEach(visibleTasks(section)) { item in
                                Button { task = .init(taskID: item.id, boardID: boardID, sectionID: section.id) } label: {
                                    Label(item.title, systemImage: item.completed ? "checkmark.circle.fill" : "circle").foregroundStyle(.primary)
                                }
                            }
                            if visibleTasks(section).isEmpty { Text("No tasks").foregroundStyle(.secondary) }
                        }
                    }
                    if visibleSections(board).isEmpty { Text("No sections yet").foregroundStyle(.secondary) }
                } else { Text("This board is no longer available.") }
            }.navigationTitle(board?.title ?? "Board").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(item: $task) { TaskDetailView(context: $0) }
        }
    }
}
