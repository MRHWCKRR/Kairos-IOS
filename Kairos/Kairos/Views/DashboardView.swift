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

    private var displayName: String {
        let name = profileRepo.profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? session.email : name
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        case 18..<23: return "Good evening"
        default: return "Welcome back"
        }
    }

    private var todayKey: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private var activeTasks: [KairosTask] {
        planRepo.currentPlan?.boards.filter { !$0.archived }
            .flatMap { $0.sections.filter { !$0.archived } }
            .flatMap { $0.tasks.filter { !$0.archived && !$0.completed } } ?? []
    }

    private var allTasks: [KairosTask] {
        planRepo.currentPlan?.boards.filter { !$0.archived }
            .flatMap { $0.sections.filter { !$0.archived } }
            .flatMap { $0.tasks.filter { !$0.archived } } ?? []
    }

    private var completedCount: Int { allTasks.filter(\.completed).count }

    private var completion: Double {
        guard !allTasks.isEmpty else { return 0 }
        return Double(completedCount) / Double(allTasks.count)
    }

    private var todayTasks: [KairosTask] {
        let scheduled = activeTasks.filter { $0.date == todayKey }
        if !scheduled.isEmpty { return Array(scheduled.prefix(4)) }
        return Array(activeTasks.filter { $0.date == nil }.prefix(4))
    }

    private var activeGoals: [String?] {
        let saved = profileRepo.achievementsData?.goals ?? []
        return (0..<3).map { saved.indices.contains($0) ? saved[$0] : nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.bottom, 42)
                    focusCard.padding(.bottom, 42)
                    todaySection.padding(.bottom, 42)
                    progressSection.padding(.bottom, 42)
                    boardsRow
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .kairosBackground()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingProfile) {
                ProfileView().environment(session).environment(profileRepo)
            }
        }
        .task {
            if focusTimer == nil { focusTimer = FocusTimerViewModel(profileRepo: profileRepo) }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(greeting.uppercased()).font(.caption.weight(.semibold)).tracking(1.3).foregroundStyle(.secondary)
                Text(displayName).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.75)
                Text(.now, format: .dateTime.weekday(.wide).month(.wide).day()).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            Button { showingProfile = true } label: {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 30, weight: .medium)).foregroundStyle(KairosColors.accent).symbolRenderingMode(.hierarchical).frame(width: 46, height: 46)
            }
            .accessibilityLabel("Open profile")
            .kairosGlass(cornerRadius: 23, tint: KairosColors.accent.opacity(0.08))
        }
    }

    private var focusCard: some View {
        Group {
            if let focusTimer {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Label("FOCUS", systemImage: "timer").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(KairosColors.accent)
                        Spacer()
                        HStack(spacing: 7) {
                            Circle().fill(focusTimer.isRunning ? KairosColors.accent : .secondary.opacity(0.6)).frame(width: 7, height: 7)
                            Text(focusTimer.isRunning ? "In session" : "Ready").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 26)

                    Text(FocusTimerViewModel.formatHMS(focusTimer.elapsedSeconds))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .tracking(-1.2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .bottom) {
                        Text(focusTimer.isRunning ? "Stay with it." : "Make some progress.").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        if let longest = profileRepo.focusData?.longestSessionSeconds, longest > 0 {
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("Best session").font(.caption2).foregroundStyle(.secondary)
                                Text(FocusTimerViewModel.formatHMS(longest)).font(.caption.weight(.semibold))
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 26)

                    focusControls(focusTimer)
                }
                .padding(26)
                .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(.background.opacity(0.72)))
                .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(.primary.opacity(0.06), lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 24, y: 12)
            }
        }
    }

    private func focusControls(_ timer: FocusTimerViewModel) -> some View {
        HStack(spacing: 12) {
            Button {
                if timer.isRunning { timer.pause() } else { timer.start() }
                fireFocusHaptic()
            } label: {
                Label(timer.isRunning ? "Pause" : "Start Focus", systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.plain).foregroundStyle(.white).background(KairosColors.accent, in: Capsule())

            if timer.isRunning {
                Button { timer.stopAndLog(); fireFocusHaptic() } label: {
                    Image(systemName: "stop.fill").frame(width: 48, height: 48)
                }
                .buttonStyle(.plain).foregroundStyle(.primary).kairosGlass(cornerRadius: 24)
                .accessibilityLabel("Stop focus timer")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: timer.isRunning)
    }

    private func fireFocusHaptic() {
        guard !reduceMotion else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(title: "Up next", action: "See all") { onNavigate?(1) }
            if todayTasks.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Your day is open").font(.headline.weight(.semibold))
                    Text("No unfinished tasks are scheduled. A little space can be productive too.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(todayTasks.enumerated()), id: \.element.id) { index, task in
                        taskRow(task)
                        if index < todayTasks.count - 1 { Divider().padding(.leading, 34).opacity(0.35) }
                    }
                }
            }
        }
    }

    private func taskRow(_ task: KairosTask) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "circle").font(.system(size: 19, weight: .medium)).foregroundStyle(KairosColors.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                if task.date == todayKey { Text("Today").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text("Progress").font(.title3.weight(.bold))
                Spacer()
                Button { onNavigate?(4) } label: { Text("Goals").font(.caption.weight(.semibold)).foregroundStyle(KairosColors.accent) }.buttonStyle(.plain)
            }
            HStack(spacing: 18) {
                progressStat(value: "\(Int(completion * 100))%", title: "Routine", subtitle: allTasks.isEmpty ? "No tasks yet" : "\(completedCount) of \(allTasks.count) tasks")
                Rectangle().fill(.primary.opacity(0.08)).frame(width: 1, height: 54)
                progressStat(value: goalSummary, title: "Goals", subtitle: "Keep moving forward")
            }
            ProgressView(value: completion).tint(KairosColors.accent).scaleEffect(y: 1.35)
        }
    }

    private var goalSummary: String {
        let unlocked = profileRepo.achievementsData?.unlocked?.count ?? 0
        let configured = activeGoals.compactMap { $0 }.count
        return configured == 0 ? "—" : "\(unlocked)/\(configured)"
    }

    private func progressStat(value: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded))
            Text(title).font(.subheadline.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(title: String, action: String, actionHandler: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            Button(action) { actionHandler() }.font(.caption.weight(.semibold)).foregroundStyle(KairosColors.accent).buttonStyle(.plain)
        }
    }

    private var boardsRow: some View {
        Button { onNavigate?(1) } label: {
            HStack(spacing: 14) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 18, weight: .medium)).foregroundStyle(KairosColors.accent).frame(width: 34, height: 34).background(KairosColors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your workspace").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text("Open Boards").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Boards")
    }
}

#Preview {
    DashboardView().environment(SessionStore()).environment(StudyPlanRepository()).environment(UserProfileRepository())
}
