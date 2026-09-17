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

    private var appearance: KairosAppearanceSettings? { profileRepo.appearanceSettings }
    private var accent: Color { KairosColors.accent(for: appearance?.theme) }
    private var displayName: String { let n = profileRepo.profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; return n.isEmpty ? session.email : n }
    private var greeting: String { switch Calendar.current.component(.hour, from: .now) { case 5..<12: return "Good morning"; case 12..<18: return "Good afternoon"; case 18..<23: return "Good evening"; default: return "Welcome back" } }
    private var todayKey: String { let c = Calendar.current.dateComponents([.year,.month,.day], from: .now); return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0) }
    private var allTasks: [KairosTask] { planRepo.currentPlan?.boards.filter { !$0.archived }.flatMap { $0.sections.filter { !$0.archived } }.flatMap { $0.tasks.filter { !$0.archived } } ?? [] }
    private var activeTasks: [KairosTask] { allTasks.filter { !$0.completed || completingTaskIDs.contains($0.id) } }
    private var completedCount: Int { allTasks.filter(\.completed).count }
    private var completion: Double { allTasks.isEmpty ? 0 : Double(completedCount) / Double(allTasks.count) }
    private var todayAllTasks: [KairosTask] { allTasks.filter { $0.date == todayKey } }
    private var todayCompletedCount: Int { todayAllTasks.filter(\.completed).count }
    private var todayCompletion: Double { todayAllTasks.isEmpty ? 0 : Double(todayCompletedCount) / Double(todayAllTasks.count) }
    private var todayTasks: [KairosTask] { let scheduled = activeTasks.filter { $0.date == todayKey }; return Array((scheduled.isEmpty ? activeTasks.filter { $0.date == nil } : scheduled).prefix(5)) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) { hero; dailyOverview; focusCard; todayCard; progressCard; quickActions }
                    .padding(.horizontal, KairosMetrics.pageHorizontal).padding(.top, 18).padding(.bottom, 150)
            }
            .scrollClipDisabled().kairosBackground().toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingProfile) { ProfileView().environment(session).environment(profileRepo) }
        }
        .task { if focusTimer == nil { focusTimer = FocusTimerViewModel(profileRepo: profileRepo) } }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Spacer(); Button { showingProfile = true } label: { Image(systemName: "person.crop.circle.fill").font(.system(size: 24, weight: .medium)).foregroundStyle(accent).frame(width: 50, height: 50) }.kairosGlass(cornerRadius: 25, tint: accent.opacity(0.10)).accessibilityLabel("Open profile") }
            VStack(alignment: .leading, spacing: 6) { Text(greeting.uppercased()).font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(accent); Text(displayName).font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-1.2).lineLimit(1).minimumScaleFactor(0.72); Text(.now, format: .dateTime.weekday(.wide).month(.wide).day()).font(.subheadline.weight(.medium)).foregroundStyle(.secondary) }
        }
    }

    private var dailyOverview: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle().stroke(accent.opacity(0.13), lineWidth: 8)
                    Circle().trim(from: 0, to: todayCompletion).stroke(accent, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("\(Int(todayCompletion * 100))%").font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                }
                .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today").font(.title3.weight(.bold))
                    Text(todayAllTasks.isEmpty ? "A fresh start. Nothing scheduled yet." : todayCompletedCount == todayAllTasks.count ? "Everything scheduled is complete." : "Keep the important things moving.")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 0) {
                dailyMetric("\(todayCompletedCount)", "Done")
                Divider().frame(height: 30)
                dailyMetric("\(max(todayAllTasks.count - todayCompletedCount, 0))", "Remaining")
                Divider().frame(height: 30)
                dailyMetric("\(todayAllTasks.count)", "Scheduled")
            }
            .padding(.vertical, 2)
        }
        .padding(20)
        .kairosCard(cornerRadius: 28)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: todayCompletion)
    }

    private func dailyMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var focusCard: some View {
        Group { if let focusTimer { VStack(alignment: .leading, spacing: 18) {
            HStack { Label("FOCUS SESSION", systemImage: "timer").font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(accent); Spacer(); Circle().fill(focusTimer.isRunning ? accent : .secondary.opacity(0.45)).frame(width: 7, height: 7) }
            HStack(alignment: .bottom) { VStack(alignment: .leading, spacing: 4) { Text(FocusTimerViewModel.formatHMS(focusTimer.elapsedSeconds)).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit().tracking(-1.5); Text(focusTimer.isRunning ? "Stay in the zone." : "Ready when you are.").font(.subheadline).foregroundStyle(.secondary) }; Spacer(); HStack(spacing: 10) { Button { if focusTimer.isRunning { focusTimer.pause() } else { focusTimer.start() }; fireFocusHaptic() } label: { Image(systemName: focusTimer.isRunning ? "pause.fill" : "play.fill").frame(width: 50, height: 50) }.foregroundStyle(.white).background(accent, in: Circle()).shadow(color: accent.opacity(0.24), radius: 18, y: 8); if focusTimer.isRunning { Button { focusTimer.stopAndLog(); fireFocusHaptic() } label: { Image(systemName: "stop.fill").frame(width: 42, height: 42) }.foregroundStyle(.primary).kairosGlass(cornerRadius: 21) } } }
        }.padding(20).kairosCard(cornerRadius: 28) } }
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) { VStack(alignment: .leading, spacing: 3) { Text("Up next").font(.title2.weight(.bold)); Text(todayTasks.isEmpty ? "Your day has some breathing room." : "A short list, a clear head.").font(.subheadline).foregroundStyle(.secondary) }; Spacer(); Button("See all") { onNavigate?(1) }.font(.subheadline.weight(.semibold)).foregroundStyle(accent) }
            if todayTasks.isEmpty { HStack(spacing: 12) { Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(accent); Text("Nothing waiting on you right now.").font(.subheadline.weight(.medium)).foregroundStyle(.secondary) }.padding(.vertical, 8) }
            else { VStack(spacing: 0) { ForEach(Array(todayTasks.enumerated()), id: \.element.id) { index, task in taskRow(task); if index < todayTasks.count - 1 { Divider().padding(.leading, 38).opacity(0.28) } } } }
        }.padding(20).kairosCard(cornerRadius: 28)
    }

    private func taskLocation(for task: KairosTask) -> (boardID: String, sectionID: String)? {
        guard let plan = planRepo.currentPlan else { return nil }
        for board in plan.boards where !board.archived { for section in board.sections where !section.archived { if section.tasks.contains(where: { $0.id == task.id }) { return (board.id, section.id) } } }
        return nil
    }

    private func taskRow(_ task: KairosTask) -> some View {
        let completing = completingTaskIDs.contains(task.id)
        return Button {
            guard !completing, let location = taskLocation(for: task) else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82)) { completingTaskIDs.insert(task.id) }
            if !reduceMotion { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            Task {
                await planRepo.toggleTask(boardID: location.boardID, sectionID: location.sectionID, taskID: task.id)
                await profileRepo.recordTaskCompletion(taskID: task.id)
            }
            Task {
                if !reduceMotion { try? await Task.sleep(for: .milliseconds(180)) }
                await MainActor.run {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { completingTaskIDs.remove(task.id) }
                }
            }
        } label: {
            HStack(spacing: 13) {
                ZStack { Circle().stroke(accent.opacity(0.72), lineWidth: 1.7).frame(width: 21, height: 21); if completing { Circle().fill(accent).frame(width: 21, height: 21); Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) } }
                VStack(alignment: .leading, spacing: 3) { Text(task.title).font(.subheadline.weight(.semibold)).foregroundStyle(completing ? .secondary : .primary).strikethrough(completing, color: accent).lineLimit(2); if task.date == todayKey { Text("Today").font(.caption).foregroundStyle(.secondary) } }
                Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }.padding(.vertical, 12)
        }.buttonStyle(.plain)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 18) { HStack { VStack(alignment: .leading, spacing: 3) { Text("Your momentum").font(.title2.weight(.bold)); Text("Small wins compound.").font(.subheadline).foregroundStyle(.secondary) }; Spacer(); Button { onNavigate?(4) } label: { Image(systemName: "arrow.up.right").frame(width: 34, height: 34) }.foregroundStyle(accent).kairosGlass(cornerRadius: 17, tint: accent.opacity(0.08)) }; HStack(spacing: 12) { metric("\(Int(completion * 100))%", "Routine"); metric("\(completedCount)", "Completed"); metric("\(profileRepo.achievementsData?.unlocked?.count ?? 0)", "Unlocked") }; ProgressView(value: completion).tint(accent).scaleEffect(y: 1.35) }.padding(20).kairosCard(cornerRadius: 28)
    }
    private func metric(_ value: String, _ label: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(value).font(.system(size: 25, weight: .bold, design: .rounded)); Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
    private var quickActions: some View { VStack(alignment: .leading, spacing: 14) { Text("Workspace").font(.title3.weight(.bold)); HStack(spacing: 12) { quickAction("Boards", "square.stack.3d.up.fill", 1); quickAction("Calendar", "calendar", 3); quickAction("Goals", "trophy.fill", 4) } } }
    private func quickAction(_ title: String, _ icon: String, _ tab: Int) -> some View { Button { onNavigate?(tab) } label: { VStack(spacing: 10) { Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(accent).frame(width: 40, height: 40).background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous)); Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary) }.frame(maxWidth: .infinity).padding(.vertical, 14).kairosGlass(cornerRadius: 20, tint: accent.opacity(0.04)) }.buttonStyle(.plain) }
    private func fireFocusHaptic() { guard !reduceMotion else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

#Preview { DashboardView().environment(SessionStore()).environment(StudyPlanRepository()).environment(UserProfileRepository()) }
