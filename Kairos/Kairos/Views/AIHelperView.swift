import SwiftUI

struct AIHelperView: View {
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(StudyPlanRepository.self) private var planRepo

    @State private var viewModel: AIHelperViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("AI Helper")
            .toolbar {
                if let viewModel {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                viewModel.createPlanFromChat()
                            } label: {
                                Label("Create Plan From Chat", systemImage: "list.bullet.clipboard")
                            }
                            Button(role: .destructive) {
                                viewModel.clearChat()
                            } label: {
                                Label("New Chat", systemImage: "sparkles")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = AIHelperViewModel(profileRepo: profileRepo, planRepo: planRepo)
            } else {
                viewModel?.syncHistoryFromProfile()
            }
        }
    }

    @ViewBuilder
    private func content(_ vm: AIHelperViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if vm.chatMessages.isEmpty {
                            emptyState
                        }
                        ForEach(Array(vm.chatMessages.enumerated()), id: \.offset) { index, message in
                            ChatBubble(message: message)
                                .id(index)
                        }
                        if vm.isLoading && !vm.isGeneratingBoard {
                            TypingIndicator()
                        }
                    }
                    .padding(16)
                }
                .onChange(of: vm.chatMessages.count) { _, _ in
                    guard vm.chatMessages.count > 0 else { return }
                    withAnimation {
                        proxy.scrollTo(vm.chatMessages.count - 1, anchor: .bottom)
                    }
                }
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
            }

            inputBar(vm)
        }
        .overlay {
            if vm.isGeneratingBoard {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Architecting your board...")
                            .font(.headline)
                    }
                    .padding(24)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { vm.showConfirmationDialog },
            set: { if !$0 { vm.dismissDialog() } }
        )) {
            PlanConfirmationSheet(
                viewModel: vm,
                existingBoards: planRepo.currentPlan?.boards.filter { !$0.archived } ?? []
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.purple.opacity(0.5))
            Text("Your AI Study Coach")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Ask me anything — or tell me about an assignment.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func inputBar(_ vm: AIHelperViewModel) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                "Ask anything...",
                text: Binding(get: { vm.userInput }, set: { vm.userInput = $0 }),
                axis: .vertical
            )
            .lineLimit(1...4)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Button {
                vm.handleSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
            }
            .disabled(vm.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isLoading)
        }
        .padding(12)
        .background(.bar)
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    private var isUser: Bool { message.role == "user" }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            Text(message.content)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(isUser ? Color.purple : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(isUser ? .white : .primary)

            Text(isUser ? "You" : "Kairos AI")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

private struct TypingIndicator: View {
    var body: some View {
        HStack {
            Text("…")
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Spacer()
        }
    }
}

private struct PlanConfirmationSheet: View {
    @Bindable var viewModel: AIHelperViewModel
    let existingBoards: [KairosBoard]

    var body: some View {
        NavigationStack {
            Form {
                Section("Where should we add these tasks?") {
                    Picker("Destination", selection: $viewModel.targetBoardMode) {
                        Text("A new board").tag(AIHelperViewModel.TargetBoardMode.new)
                        Text("An existing board").tag(AIHelperViewModel.TargetBoardMode.existing)
                    }
                    .pickerStyle(.segmented)

                    if viewModel.targetBoardMode == .new {
                        TextField("Board name (e.g. Math Study)", text: $viewModel.newBoardName)
                    } else if existingBoards.isEmpty {
                        Text("No existing boards yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Board", selection: $viewModel.selectedExistingBoardID) {
                            ForEach(existingBoards) { board in
                                Text(board.title).tag(board.id)
                            }
                        }
                        .onAppear {
                            if viewModel.selectedExistingBoardID.isEmpty {
                                viewModel.selectedExistingBoardID = existingBoards.first?.id ?? ""
                            }
                        }
                    }
                }

                if let plan = viewModel.pendingPlan {
                    Section("Board Preview") {
                        ForEach(plan.sections) { section in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(section.title).font(.subheadline.weight(.semibold))
                                ForEach(section.tasks) { task in
                                    Label(task.title, systemImage: "checkmark")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Configure Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.dismissDialog() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to Boards") { viewModel.confirmPlan() }
                }
            }
        }
    }
}

#Preview {
    AIHelperView()
        .environment(UserProfileRepository())
        .environment(StudyPlanRepository())
}
