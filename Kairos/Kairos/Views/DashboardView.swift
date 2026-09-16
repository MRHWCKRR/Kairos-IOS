import SwiftUI
import UIKit

struct DashboardView: View {
    @Environment(SessionStore.self) private var session
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onNavigate: ((Int) -> Void)? = nil
    @State private var showingProfile = false
    @State private var focusTimer: FocusTimerViewModel?
    @State private var completingTaskIDs: Set<String> = []

    private var displayName: String { let name = profileRepo.profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; return name.isEmpty ? session.email : name }
    private var greeting: String { switch Calendar.current.component(.hour, from: .now) { case 5..<12: return "Good morning"; case 12..<18: return "Good afternoon"; case 18..<23: return "Good evening"; default: return "Welcome back" } }
    private var todayKey: String { let components = Calendar.current.dateComponents([.year, .month, .day], from: .now); return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0) }
    private var activeTasks: [KairosTask] { planRepo.currentPlan?.boards.filter { !$0.archived }.flatMap { $0.sections.filter { !$0.archived } }.flatMap { $0.tasks.filter { !$0.archived && (!$0.completed || completingTaskIDs.contains($0.id)) } } ?? [] }
    private var allTasks: [KairosTask] { planRepo.currentPlan?.boards.filter { !$0.archived }.flatMap { $0.sections.filter { !$0.archived } }.flatMap { $0.tasks.filter { !$0.archived } } ?? [] }
    private var completedCount: Int { allTasks.filter(\.completed).count }
    private var completion: Double { guard !allTasks.isEmpty else { return 0 }; return Double(completedCount) / Double(allTasks.count) }
    private var todayTasks: [KairosTask] { let scheduled = activeTasks.filter { $0.date == todayKey }; if !scheduled.isEmpty { return Array(scheduled.prefix(4)) }; return Array(activeTasks.filter { $0.date == nil }.prefix(4)) }
    private var activeGoals: [String?] { let saved = profileRepo.achievementsData?.goals ?? []; return (0..<3).map { saved.indices.contains($0) ? saved[$0] : nil } }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                topHeader
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
                    .padding(.bottom, 10)

                Rectangle()
                    .fill(.primary.opacity(0.10))
                    .frame(height: 0.5)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        greetingBlock
                            .padding(.bottom, 38)
                        focusCard
                            .padding(.bottom, 42)
                        todaySection
                            .padding(.bottom, 42)
                        progressSection
                            .padding(.bottom, 42)
                        boardsRow
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 30)
                    .padding(.bottom, 40)
                }
            }
            .kairosBackground()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingProfile) { ProfileView().environment(session).environment(profileRepo) }
        }
        .task { if focusTimer == nil { focusTimer = FocusTimerViewModel(profileRepo: profileRepo) } }
    }

    private var topHeader: some View {
        HStack {
            Spacer()
            Button { showingProfile = true } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(KairosColors.accent)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 46, height: 46)
            }
            .accessibilityLabel("Open profile")
            .kairosGlass(cornerRadius: 23, tint: KairosColors.accent.opacity(0.08))
        }
    }

    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greeting.uppercased()).font(.caption.weight(.semibold)).tracking(1.3).foregroundStyle(.secondary)
            Text(displayName).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.75)
            Text(.now, format: .dateTime.weekday(.wide).month(.wide).day()).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var focusCard: some View {
        Group { if let focusTimer {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) { Image(systemName: "timer").font(.caption.weight(.semibold)).foregroundStyle(KairosColors.accent); Text("FOCUS").font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(KairosColors.accent); Circle().fill(focusTimer.isRunning ? KairosColors.accent : .secondary.opacity(0.6)).frame(width: 6, height: 6).padding(.leading, 2) }
                    Text(FocusTimerViewModel.formatHMS(focusTimer.elapsedSeconds)).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit().tracking(-0.8)
                    Text(focusTimer.isRunning ? "Stay with it." : "Make some progress.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8); focusControls(focusTimer)
            }.padding(.horizontal, 18).padding(.vertical, 14).background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.background.opacity(0.72))).overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.primary.opacity(0.06), lineWidth: 1)).shadow(color: .black.opacity(0.04), radius: 14, y: 7)
        } }
    }

    private func focusControls(_ timer: FocusTimerViewModel) -> some View {
        HStack(spacing: 10) {
            Button { if timer.isRunning { timer.pause() } else { timer.start() }; fireFocusHaptic() } label: { Image(systemName: timer.isRunning ? "pause.fill" : "play.fill").font(.system(size: 15, weight: .bold)).frame(width: 44, height: 44) }.buttonStyle(.plain).foregroundStyle(.white).background(KairosColors.accent, in: Circle()).accessibilityLabel(timer.isRunning ? "Pause focus timer" : "Start focus timer")
            if timer.isRunning { Button { timer.stopAndLog(); fireFocusHaptic() } label: { Image(systemName: "stop.fill").font(.system(size: 13, weight: .semibold)).frame(width: 38, height: 38) }.buttonStyle(.plain).foregroundStyle(.primary).kairosGlass(cornerRadius: 19).accessibilityLabel("Stop focus timer").transition(.scale.combined(with: .opacity)) }
        }.animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: timer.isRunning)
    }

    private func fireFocusHaptic() { guard !reduceMotion else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred() }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(title: "Up next", action: "See all") { onNavigate?(1) }
            if todayTasks.isEmpty { VStack(alignment: .leading, spacing: 7) { Text("Your day is open").font(.headline.weight(.semibold)); Text("No unfinished tasks are scheduled. A little space can be productive too.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }.padding(.vertical, 4) }
            else { VStack(spacing: 0) { ForEach(Array(todayTasks.enumerated()), id: \.element.id) { index, task in taskRow(task); if index < todayTasks.count - 1 { Divider().padding(.leading, 34).opacity(0.35) } } } }
        }
    }

    private func taskLocation(for task: KairosTask) -> (boardID: String, sectionID: String)? { guard let plan = planRepo.currentPlan else { return nil }; for board in plan.boards where !board.archived { for section in board.sections where !section.archived { if section.tasks.contains(where: { $0.id == task.id }) { return (board.id, section.id) } } }; return nil }
    private func taskRow(_ task: KairosTask) -> some View {
        let isCompleting = completingTaskIDs.contains(task.id)
        return Button {
            guard !isCompleting, let location = taskLocation(for: task) else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.82)) { completingTaskIDs.insert(task.id) }
            if !reduceMotion { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            Task { await planRepo.toggleTask(boardID: location.boardID, sectionID: location.sectionID, taskID: task.id); await profileRepo.recordTaskCompletion(taskID: task.id); if !reduceMotion { try? await Task.sleep(for: .milliseconds(520)) }; await MainActor.run { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.34)) { completingTaskIDs.remove(task.id) } } }
        } label: {
            HStack(spacing: 14) {
                ZStack { Circle().stroke(KairosColors.accent.opacity(0.72), lineWidth: 1.7).frame(width: 20, height: 20).scaleEffect(isCompleting ? 0.92 : 1).opacity(isCompleting ? 0 : 1); Circle().fill(KairosColors.accent).frame(width: 20, height: 20).scaleEffect(isCompleting ? 1 : 0.01).opacity(isCompleting ? 1 : 0); Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white).scaleEffect(isCompleting ? 1 : 0.01).opacity(isCompleting ? 1 : 0) }.animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.62), value: isCompleting)
                VStack(alignment: .leading, spacing: 3) { Text(task.title).font(.subheadline.weight(.medium)).foregroundStyle(isCompleting ? .secondary : .primary).strikethrough(isCompleting, color: KairosColors.accent).lineLimit(2); if task.date == todayKey { Text("Today").font(.caption).foregroundStyle(.secondary) } }.opacity(isCompleting ? 0.62 : 1)
                Spacer(minLength: 8); Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).opacity(isCompleting ? 0 : 1)
            }.contentShape(Rectangle()).padding(.vertical, 14).offset(x: isCompleting ? -18 : 0).scaleEffect(isCompleting ? 0.96 : 1, anchor: .leading)
        }.buttonStyle(.plain).accessibilityLabel(task.title).accessibilityValue(isCompleting ? "Completed" : "Not completed").accessibilityHint("Double tap to complete").animation(reduceMotion ? nil : .easeInOut(duration: 0.34), value: isCompleting)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) { Text("Progress").font(.title3.weight(.bold)); Spacer(); Button { onNavigate?(4) } label: { Text("Goals").font(.caption.weight(.semibold)).foregroundStyle(KairosColors.accent) }.buttonStyle(.plain) }
            HStack(spacing: 18) { progressStat(value: "\(Int(completion * 100))%", title: "Routine", subtitle: allTasks.isEmpty ? "No tasks yet" : "\(completedCount) of \(allTasks.count) tasks"); Rectangle().fill(.primary.opacity(0.08)).frame(width: 1, height: 54); progressStat(value: goalSummary, title: "Goals", subtitle: "Keep moving forward") }
            ProgressView(value: completion).tint(KairosColors.accent).scaleEffect(y: 1.35)
        }
    }
    private var goalSummary: String { let unlocked = profileRepo.achievementsData?.unlocked?.count ?? 0; let configured = activeGoals.compactMap { $0 }.count; return configured == 0 ? "—" : "\(unlocked)/\(configured)" }
    private func progressStat(value: String, title: String, subtitle: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(value).font(.system(size: 30, weight: .bold, design: .rounded)); Text(title).font(.subheadline.weight(.semibold)); Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 12).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.26), lineWidth: 0.8) } }
    private func sectionHeader(title: String, action: String, actionHandler: @escaping () -> Void) -> some View { HStack(alignment: .firstTextBaseline) { Text(title).font(.title3.weight(.bold)); Spacer(); Button(action) { actionHandler() }.font(.caption.weight(.semibold)).foregroundStyle(KairosColors.accent).buttonStyle(.plain) } }
    private var boardsRow: some View { Button { onNavigate?(1) } label: { HStack(spacing: 14) { Image(systemName: "square.stack.3d.up.fill").font(.system(size: 18, weight: .medium)).foregroundStyle(KairosColors.accent).frame(width: 34, height: 34).background(KairosColors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous)); VStack(alignment: .leading, spacing: 3) { Text("Your workspace").font(.subheadline.weight(.semibold)).foregroundStyle(.primary); Text("Open Boards").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }.padding(.vertical, 8) }.buttonStyle(.plain).accessibilityLabel("Open Boards") }
}

#Preview { DashboardView().environment(SessionStore()).environment(StudyPlanRepository()).environment(UserProfileRepository()) }
