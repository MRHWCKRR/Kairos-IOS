import SwiftUI

struct AIHelperView: View {
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AIHelperViewModel?
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel { content(viewModel) }
                else { ProgressView().tint(KairosColors.accent) }
            }
            .navigationTitle("AI Helper")
            .toolbar {
                if let viewModel {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { viewModel.createPlanFromChat() } label: { Label("Create Plan From Chat", systemImage: "list.bullet.clipboard") }
                            Button(role: .destructive) { viewModel.clearChat() } label: { Label("New Chat", systemImage: "sparkles") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
        }
        .task {
            if viewModel == nil { viewModel = AIHelperViewModel(profileRepo: profileRepo, planRepo: planRepo) }
            else { viewModel?.syncHistoryFromProfile() }
        }
    }

    @ViewBuilder
    private func content(_ vm: AIHelperViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if vm.chatMessages.isEmpty { emptyState }
                        ForEach(Array(vm.chatMessages.enumerated()), id: \.offset) { index, message in ChatBubble(message: message).id(index) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, vm.isLoading && !vm.isGeneratingBoard ? 72 : 18)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if vm.isLoading && !vm.isGeneratingBoard { TypingIndicator().padding(.horizontal, 16).padding(.bottom, 4) }
                }
                .onChange(of: vm.chatMessages.count) { _, _ in
                    guard vm.chatMessages.count > 0 else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(vm.chatMessages.count - 1, anchor: .bottom) }
                }
            }

            if let error = vm.errorMessage { Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal, 16).padding(.bottom, 6) }
            inputBar(vm)
        }
        .kairosBackground()
        .overlay {
            if vm.isGeneratingBoard {
                ZStack {
                    Color.black.opacity(0.22).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().tint(KairosColors.accent)
                        Text("Architecting your board…").font(.headline)
                        Text("Turning the conversation into a study plan").font(.caption).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center).padding(24).frame(maxWidth: 300).kairosCard(cornerRadius: 22)
                }
            }
        }
        .sheet(isPresented: Binding(get: { vm.showConfirmationDialog }, set: { if !$0 { vm.dismissDialog() } })) {
            PlanConfirmationSheet(viewModel: vm, existingBoards: planRepo.currentPlan?.boards.filter { !$0.archived } ?? [])
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(KairosColors.accent.opacity(0.12)).frame(width: 72, height: 72)
                Image(systemName: "sparkles").font(.system(size: 30, weight: .semibold)).foregroundStyle(KairosColors.accent)
            }
            Text("Your AI Study Coach").font(.title3.weight(.bold))
            Text("Ask a question, describe an assignment, or tell Kairos what you want to study.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity).padding(.top, 48).padding(.bottom, 30)
    }

    private func inputBar(_ vm: AIHelperViewModel) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask anything…", text: Binding(get: { vm.userInput }, set: { vm.userInput = $0 }), axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { if !vm.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { vm.handleSend() } }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1) }

            Button { vm.handleSend() } label: { Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).frame(width: 42, height: 42) }
                .buttonStyle(.glassProminent).tint(KairosColors.accent)
                .disabled(vm.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isLoading)
        }
        .padding(.horizontal, 12).padding(.vertical, 8).background(.bar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if inputFocused {
                HStack {
                    Spacer()
                    Button("Done") { inputFocused = false }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KairosColors.accent)
                }
                .padding(.horizontal, 16).padding(.vertical, 4).background(.bar)
            }
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    private var isUser: Bool { message.role == "user" }
    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 8) {
                if !isUser { Image(systemName: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(KairosColors.accent) }
                Text(message.content).textSelection(.enabled).padding(.horizontal, 15).padding(.vertical, 11)
                    .background(isUser ? KairosColors.accent : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(isUser ? .white : .primary)
            }
            Text(isUser ? "You" : "Kairos AI").font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 4)
        }.frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

private struct TypingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(KairosColors.accent)
            ProgressView().controlSize(.small)
            Text("Kairos is thinking…").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10).background(.regularMaterial, in: Capsule()).frame(maxWidth: 190, alignment: .leading)
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
                                ForEach(section.tasks) { task in Label(task.title, systemImage: "circle").font(.caption).foregroundStyle(.secondary) }
                            }.padding(.vertical, 3)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Color.clear)
            .navigationTitle("Configure Board").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { viewModel.dismissDialog() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add to Boards") { viewModel.confirmPlan() }.fontWeight(.semibold) }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

#Preview { AIHelperView().environment(UserProfileRepository()).environment(StudyPlanRepository()) }
