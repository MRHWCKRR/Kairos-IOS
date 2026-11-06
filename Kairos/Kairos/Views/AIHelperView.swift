import SwiftUI

struct AIHelperView: View {
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(StudyPlanRepository.self) private var planRepo
    @State private var viewModel: AIHelperViewModel?
    @State private var showingHistory = false
    @State private var reviewingChanges = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    if profileRepo.isLoading { ProgressView("Loading workspace…") }
                    else if let error = profileRepo.aiWorkspaceError { ContentUnavailableView { Label("Workspace unavailable", sharedIcon: "exclamationmark.triangle") } description: { Text(error) } }
                    else if vm.showingAllChats { allChats(vm) }
                    else if let project = vm.projects.first(where: { $0.id == vm.activeProjectID }) { projectHome(project, vm: vm) }
                    else { conversation(vm) }
                } else { ProgressView() }
            }
            .kairosBackground()
            .navigationTitle("Kairos AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    KairosToolbarButton("Chats and projects", sharedIcon: "sidebar.left") { inputFocused = false; showingHistory = true }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let vm = viewModel {
                        KairosToolbarButton("New chat", sharedIcon: "square.and.pencil") { Task { await vm.newChat() } }.disabled(vm.isEditingWorkspace || profileRepo.aiWorkspace == nil)
                        Menu {
                            Button("Create plan from chat", sharedIcon: "list.bullet.clipboard") { vm.createPlanFromChat() }.disabled(vm.chatMessages.isEmpty || vm.isLoading)
                        } label: { KairosIcon("ellipsis") }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { inputFocused = false } }
            }
            .sheet(isPresented: $showingHistory) {
                if let vm = viewModel { AIWorkspaceHistory(viewModel: vm).presentationDragIndicator(.visible) }
            }
            .task { if viewModel == nil { viewModel = AIHelperViewModel(profileRepo: profileRepo, planRepo: planRepo) } }
            .onChange(of: profileRepo.aiWorkspace?.chats.map(\.id)) { _, _ in viewModel?.syncHistoryFromProfile() }
            .onChange(of: profileRepo.aiWorkspaceOwnerID) { _, _ in viewModel?.syncHistoryFromProfile() }
        }
    }

    private func conversation(_ vm: AIHelperViewModel) -> some View {
        VStack(spacing: 0) {
            if vm.currentChat?.hasUnfinishedWebActions == true { Text("Finish or cancel this chat’s pending change on the web before continuing here.").font(.caption).foregroundStyle(.secondary).padding(.horizontal) }
            if let chat = vm.currentChat, !chat.messages.isEmpty {
                Text(chat.title).font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.horizontal).padding(.top, 4)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if vm.currentChat?.messages.isEmpty != false {
                            VStack(spacing: 10) {
                                Text("What can I help with?").font(.title2.weight(.semibold))
                                Text("Study, planning, organisation, and ideas.").font(.subheadline).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 70)
                        }
                        ForEach(vm.currentChat?.messages ?? []) { message in
                            AIMessageRow(message: message)
                        }
                        if vm.pendingChats.contains(vm.activeChatID ?? "") {
                            HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Thinking…").font(.subheadline).foregroundStyle(.secondary) }
                        }
                        Color.clear.frame(height: 1).id("chat-bottom")
                    }.padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: vm.currentChat?.messages.last?.id) { _, _ in withAnimation { proxy.scrollTo("chat-bottom", anchor: .bottom) } }
                .onChange(of: vm.activeChatID) { _, _ in proxy.scrollTo("chat-bottom", anchor: .bottom) }
            }
            if let error = vm.chatErrors[vm.activeChatID ?? ""] {
                HStack { Text(error).font(.caption).foregroundStyle(.red); Spacer(); Button("Retry") { vm.retryReply() }.disabled(vm.isLoading) }.padding(.horizontal, 16).padding(.vertical, 8)
            }
            if let error = vm.errorMessage { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal) }
            if let error = profileRepo.aiProposalError { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal) }
            if let notice = vm.notificationDeliveryNotice { Text(notice).font(.caption).foregroundStyle(.secondary).padding(.horizontal) }
            if let actions = vm.proposals[vm.activeChatID ?? ""], !actions.isEmpty {
                Button("Review \(actions.count) proposed change\(actions.count == 1 ? "" : "s")", sharedIcon: "list.bullet.clipboard") { reviewingChanges = true }
                    .buttonStyle(.bordered).padding(.horizontal)
            }
            composer(vm)
        }
        .overlay {
            if vm.isGeneratingBoard { ProgressView("Preparing plan…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
        }
        .sheet(isPresented: Binding(get: { vm.showConfirmationDialog }, set: { if !$0 { vm.dismissDialog() } })) {
            PlanConfirmationSheet(viewModel: vm, existingBoards: planRepo.currentPlan?.boards.filter { !$0.archived } ?? [])
        }
        .sheet(isPresented: $reviewingChanges) { AIChangeReview(viewModel: vm) }
    }

    private func composer(_ vm: AIHelperViewModel) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message Kairos", text: Binding(get: { vm.userInput }, set: { vm.userInput = $0 }), axis: .vertical)
                .lineLimit(1...6).focused($inputFocused).padding(.leading, 8).padding(.vertical, 10)
            Button { vm.handleSend() } label: {
                KairosIcon("arrow.up", size: 17).foregroundStyle(.white).frame(width: 38, height: 38).background(KairosColors.accent, in: Circle())
            }
            .accessibilityLabel("Send message")
            .disabled(vm.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isLoading || vm.isEditingWorkspace || vm.startingMessage || vm.failedResponses[vm.activeChatID ?? ""] != nil || profileRepo.aiWorkspaceOwnerID == nil)
            .opacity(vm.isLoading || vm.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
        }
        .padding(8).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func projectHome(_ project: KairosAIWorkspace.Project, vm: AIHelperViewModel) -> some View {
        List {
            Section {
                Text(project.title).font(.title2.weight(.semibold))
                if !project.description.isEmpty { Text(project.description).foregroundStyle(.secondary) }
            }
            Section("Shared context") { Text(project.sharedContext.isEmpty ? "Add project context from Chats and projects." : project.sharedContext).font(.subheadline) }
            Section("Chats") {
                Button("New chat in project", sharedIcon: "square.and.pencil") { Task { await vm.newChat(projectID: project.id) } }
                ForEach(vm.chats.filter { $0.projectID == project.id }) { chat in
                    Button { vm.activeChatID = chat.id; vm.activeProjectID = nil; vm.showingAllChats = false } label: { Text(chat.title).foregroundStyle(.primary) }
                }
            }
        }.scrollContentBackground(.hidden)
    }
    private func allChats(_ vm: AIHelperViewModel) -> some View {
        List {
            Section("All chats") {
                ForEach(vm.chats) { chat in
                    Button { vm.activeChatID = chat.id; vm.activeProjectID = nil; vm.showingAllChats = false } label: {
                        VStack(alignment: .leading, spacing: 6) { Text(chat.title).font(.headline); Text(chat.messages.last?.content ?? "New conversation").font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }.padding(.vertical, 6).foregroundStyle(.primary)
                    }
                }
            }
        }.scrollContentBackground(.hidden)
    }
}

private struct AIMessageRow: View {
    let message: KairosAIWorkspace.Message
    var body: some View {
        HStack(alignment: .top) {
            if message.role == "user" { Spacer(minLength: 40) }
            Group {
                if message.role == "user" {
                    Text(message.content).padding(.horizontal, 16).padding(.vertical, 11).background(KairosColors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                } else {
                    AIMarkdownText(content: message.content).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.textSelection(.enabled)
        }
    }
}

private struct AIMarkdownText: View {
    let content: String
    var body: some View {
        let pieces = content.components(separatedBy: "```")
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { index, piece in
                if index % 2 == 1 {
                    ScrollView(.horizontal) { Text(piece).font(.system(.caption, design: .monospaced)).padding(12) }
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Text((try? AttributedString(markdown: piece, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(piece))
                        .font(.body).lineSpacing(4)
                }
            }
        }
        .environment(\.openURL, OpenURLAction { url in ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded })
    }
}

private struct AIWorkspaceHistory: View {
    @Bindable var viewModel: AIHelperViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var renameChat: KairosAIWorkspace.Chat?
    @State private var deleteChat: KairosAIWorkspace.Chat?
    @State private var editProject: KairosAIWorkspace.Project?
    @State private var creatingProject = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("All chats", sharedIcon: "bubble.left.and.bubble.right") { viewModel.activeProjectID = nil; viewModel.showingAllChats = true; dismiss() }
                }
                Section {
                    ForEach(viewModel.projects) { project in
                        Button { viewModel.activeProjectID = project.id; viewModel.showingAllChats = false; dismiss() } label: { Label(project.title, sharedIcon: "folder").foregroundStyle(.primary) }
                            .contextMenu { Button("Edit project") { editProject = project } }
                    }
                    Button("New project", sharedIcon: "folder.badge.plus") { creatingProject = true }
                } header: { Text("Projects") }
                Section("Chats") {
                    ForEach(viewModel.chats) { chat in
                        Button { viewModel.activeChatID = chat.id; viewModel.activeProjectID = nil; viewModel.showingAllChats = false; dismiss() } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chat.title).lineLimit(1)
                                    if let project = viewModel.projects.first(where: { $0.id == chat.projectID }) { Text(project.title).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if viewModel.pendingChats.contains(chat.id) { ProgressView().controlSize(.small) }
                                else if viewModel.activeChatID == chat.id { KairosIcon("checkmark").foregroundStyle(KairosColors.accent) }
                            }.foregroundStyle(.primary)
                        }
                        .contextMenu {
                            Button("Rename", sharedIcon: "pencil") { renameChat = chat }
                            Menu("Move to project") {
                                Button("No project") { Task { await viewModel.edit(.moveChat(id: chat.id, projectID: "")) } }
                                ForEach(viewModel.projects) { project in Button(project.title) { Task { await viewModel.edit(.moveChat(id: chat.id, projectID: project.id)) } } }
                            }
                            Button("Delete", sharedIcon: "trash", role: .destructive) { deleteChat = chat }
                        }
                    }
                }
                let orphaned = viewModel.profileRepo.aiProposals.values.filter { proposal in !viewModel.chats.contains { $0.id == proposal.chatID } }.sorted { $0.createdAt < $1.createdAt }
                if !orphaned.isEmpty {
                    Section("Previews from deleted chats") {
                        ForEach(orphaned) { proposal in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(proposal.rows.first?.title ?? "Saved changes")
                                Text("This conversation was removed on another device.").font(.caption).foregroundStyle(.secondary)
                                Button("Discard preview", role: .destructive) { Task { _ = await viewModel.discardSavedProposal(proposal) } }.disabled(viewModel.isApplyingPlan)
                            }
                        }
                    }
                }
                if let error = viewModel.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .disabled(viewModel.isEditingWorkspace)
            .safeAreaInset(edge: .top) {
                Button { Task { await viewModel.newChat(); if viewModel.errorMessage == nil { dismiss() } } } label: {
                    Label("New chat", sharedIcon: "square.and.pencil").frame(maxWidth: .infinity, alignment: .leading).padding()
                }.background(.bar).disabled(viewModel.isEditingWorkspace)
            }
            .safeAreaInset(edge: .bottom) {
                HStack { Text("AI workspace").font(.caption).foregroundStyle(.secondary); Spacer(); Link("View plans", destination: URL(string: "https://kairos-web.kirosapp.workers.dev/plans.html")!) }.padding().background(.bar)
            }
            .navigationTitle("Chats and projects").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $renameChat) { chat in
                KairosNameEditor(heading: "Rename chat", initialValue: chat.title, saveLabel: "Save", failureMessage: { viewModel.errorMessage }) { title in await viewModel.edit(.renameChat(id: chat.id, title: title)) }
            }
            .sheet(item: $editProject) { project in AIProjectEditor(viewModel: viewModel, project: project) }
            .sheet(isPresented: $creatingProject) { AIProjectEditor(viewModel: viewModel, project: nil) }
            .confirmationDialog("Delete this chat?", isPresented: Binding(get: { deleteChat != nil }, set: { if !$0 { deleteChat = nil } }), titleVisibility: .visible) {
                Button("Delete chat", role: .destructive) { if let chat = deleteChat { Task { if await viewModel.edit(.deleteChat(id: chat.id)) { viewModel.syncHistoryFromProfile() }; deleteChat = nil } } }
            } message: { Text("This also removes the conversation from your web workspace.") }
        }
    }
}

private struct AIProjectEditor: View {
    @Bindable var viewModel: AIHelperViewModel
    let project: KairosAIWorkspace.Project?
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description: String
    @State private var context: String
    @State private var confirmingDelete = false
    init(viewModel: AIHelperViewModel, project: KairosAIWorkspace.Project?) {
        self.viewModel = viewModel; self.project = project
        _title = State(initialValue: project?.title ?? ""); _description = State(initialValue: project?.description ?? ""); _context = State(initialValue: project?.sharedContext ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Project") { TextField("Name", text: $title); TextField("Description", text: $description, axis: .vertical).lineLimit(2...5) }
                Section("Shared context") { TextEditor(text: $context).frame(minHeight: 140); Text("Used across chats in this project on mobile and web.").font(.caption).foregroundStyle(.secondary) }
                if let error = viewModel.errorMessage { Text(error).foregroundStyle(.red) }
                if project != nil { Button("Delete project", role: .destructive) { confirmingDelete = true } }
            }
            .disabled(viewModel.isEditingWorkspace).interactiveDismissDisabled()
            .navigationTitle(project == nil ? "New project" : "Edit project").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(viewModel.isEditingWorkspace) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { if await viewModel.edit(.saveProject(id: project?.id ?? "project-" + UUID().uuidString, title: title, description: description, context: context, creating: project == nil)) { dismiss() } } }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isEditingWorkspace)
                }
            }
            .confirmationDialog("Delete project? Chats will be kept in All chats.", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete project", role: .destructive) { if let project { Task { if await viewModel.edit(.deleteProject(id: project.id)) { viewModel.activeProjectID = nil; dismiss() } } } }
            }
        }
    }
}

private struct AIChangeReview: View {
    @Bindable var viewModel: AIHelperViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Proposed changes") {
                    ForEach(viewModel.profileRepo.aiProposals[viewModel.activeChatID ?? ""]?.rows ?? []) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.action).font(.headline)
                            Text(row.title)
                            LabeledContent("Before", value: row.before)
                            LabeledContent("After", value: row.after)
                            if row.destructive { Text("This removes the item or selected occurrence from your planner.").font(.caption).foregroundStyle(.red) }
                        }
                    }
                }
                if let error = viewModel.errorMessage { Text(error).foregroundStyle(.red) }
                Text("This preview is saved to your account. If the planner changes, request a fresh preview before applying.").font(.caption).foregroundStyle(.secondary)
                if let proposal = viewModel.profileRepo.aiProposals[viewModel.activeChatID ?? ""] { LabeledContent("Timezone", value: proposal.timezone).font(.caption) }
                if viewModel.proposals[viewModel.activeChatID ?? ""]?.contains(where: { $0.type.contains("reminder") }) == true { Text("Reminder delivery uses your iOS notification permission and Kairos notification preference. Unscheduled tasks notify once they have a date and start time.").font(.caption).foregroundStyle(.secondary) }
                Button("Discard changes", role: .destructive) { Task { if await viewModel.discardProposals() { dismiss() } } }
            }.disabled(viewModel.isApplyingPlan).interactiveDismissDisabled(viewModel.isApplyingPlan)
            .navigationTitle("Review changes").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(viewModel.isApplyingPlan) }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { Task { if await viewModel.applyProposals() { dismiss() } } }.disabled(viewModel.isApplyingPlan) }
            }
        }
    }
}

private struct PlanConfirmationSheet: View {
    @Bindable var viewModel: AIHelperViewModel
    let existingBoards: [KairosBoard]
    var body: some View {
        NavigationStack {
            Form {
                if let error = viewModel.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
                Section("Where should we add these tasks?") {
                    Picker("Destination", selection: $viewModel.targetBoardMode) {
                        Text("A new board").tag(AIHelperViewModel.TargetBoardMode.new)
                        Text("An existing board").tag(AIHelperViewModel.TargetBoardMode.existing)
                    }.pickerStyle(.segmented)
                    if viewModel.targetBoardMode == .new { TextField("Board name (e.g. Math Study)", text: $viewModel.newBoardName) }
                    else if existingBoards.isEmpty { Text("No existing boards yet.").foregroundStyle(.secondary) }
                    else {
                        Picker("Board", selection: $viewModel.selectedExistingBoardID) {
                            ForEach(existingBoards) { board in Text(board.title).tag(board.id) }
                        }.onAppear { if viewModel.selectedExistingBoardID.isEmpty { viewModel.selectedExistingBoardID = existingBoards.first?.id ?? "" } }
                    }
                }
                if let plan = viewModel.pendingPlan {
                    Section("Board Preview") {
                        ForEach(plan.sections) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.title).font(.subheadline.weight(.semibold))
                                ForEach(section.tasks) { task in Label(task.title, sharedIcon: "circle").font(.caption).foregroundStyle(.secondary) }
                            }.padding(.vertical, 3)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Color.clear).disabled(viewModel.isApplyingPlan)
            .interactiveDismissDisabled(viewModel.isApplyingPlan)
            .navigationTitle("Configure Board").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { viewModel.dismissDialog() }.disabled(viewModel.isApplyingPlan) }
                ToolbarItem(placement: .confirmationAction) { Button("Add to Boards") { viewModel.confirmPlan() }.fontWeight(.semibold).disabled(viewModel.isApplyingPlan) }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

#Preview { AIHelperView().environment(UserProfileRepository()).environment(StudyPlanRepository()) }

