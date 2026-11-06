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
    var isActive = true

    private var appearance: KairosAppearanceSettings? { profileRepo.appearanceSettings }
    private var accent: Color { KairosColors.accent(for: appearance?.theme) }
    private var displayName: String { let n = profileRepo.profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; return n.isEmpty ? session.email : n }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = profileRepo.profile.flatMap { TimeZone(identifier: $0.timezone) } ?? .current
        return value
    }
    private var greeting: String { switch calendar.component(.hour, from: .now) { case 5..<12: return "Good morning"; case 12..<18: return "Good afternoon"; case 18..<23: return "Good evening"; default: return "Welcome back" } }
    private var allTasks: [KairosTask] { planRepo.currentPlan?.boards.filter { !$0.archived }.flatMap { $0.sections.filter { !$0.archived } }.flatMap { $0.tasks.filter { !$0.archived && $0.recurrence?.enabled != true } } ?? [] }
    private var completedCount: Int { allTasks.filter(\.completed).count }
    private var completion: Double { allTasks.isEmpty ? 0 : Double(completedCount) / Double(allTasks.count) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    TimelineView(.periodic(from: .now, by: 60)) { tick in
                        DashboardTodayView(isActive: isActive, today: KairosDate.dayKey(for: tick.date, timeZone: calendar.timeZone), calendar: calendar) { onNavigate?(3) }
                    }
                    focusCard
                    progressCard
                    quickActions
                }
                    .padding(.horizontal, KairosMetrics.pageHorizontal).padding(.top, 18).padding(.bottom, 150)
            }
            .scrollClipDisabled().kairosBackground().toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingProfile) { ProfileView().environment(session).environment(profileRepo) }
        }
        .environment(\.timeZone, calendar.timeZone).environment(\.calendar, calendar)
        .task { if focusTimer == nil { focusTimer = FocusTimerViewModel(profileRepo: profileRepo) } }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Spacer(); Button { showingProfile = true } label: { KairosIcon("person.crop.circle.fill", size: 24).foregroundStyle(accent).frame(width: 50, height: 50) }.kairosGlass(cornerRadius: 25, tint: accent.opacity(0.10)).accessibilityLabel("Open profile") }
            VStack(alignment: .leading, spacing: 6) { Text(greeting.uppercased()).font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(accent); Text(displayName).font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-1.2).lineLimit(1).minimumScaleFactor(0.72); Text(.now, format: .dateTime.weekday(.wide).month(.wide).day()).font(.subheadline.weight(.medium)).foregroundStyle(.secondary) }
        }
    }

    private var focusCard: some View {
        Group { if let focusTimer { VStack(alignment: .leading, spacing: 18) {
            HStack { Label("FOCUS SESSION", sharedIcon: "timer").font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(accent); Spacer(); Circle().fill(focusTimer.isRunning ? accent : .secondary.opacity(0.45)).frame(width: 7, height: 7) }
            HStack(alignment: .bottom) { VStack(alignment: .leading, spacing: 4) { Text(FocusTimerViewModel.formatHMS(focusTimer.elapsedSeconds)).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit().tracking(-1.5); Text(focusTimer.isRunning ? "Stay in the zone." : "Ready when you are.").font(.subheadline).foregroundStyle(.secondary) }; Spacer(); HStack(spacing: 10) { Button { if focusTimer.isRunning { focusTimer.pause() } else { focusTimer.start() }; fireFocusHaptic() } label: { KairosIcon(focusTimer.isRunning ? "pause.fill" : "play.fill").frame(width: 50, height: 50) }.foregroundStyle(.white).background(accent, in: Circle()).shadow(color: accent.opacity(0.24), radius: 18, y: 8); if focusTimer.isRunning { Button { focusTimer.stopAndLog(); fireFocusHaptic() } label: { KairosIcon("stop.fill").frame(width: 42, height: 42) }.foregroundStyle(.primary).kairosGlass(cornerRadius: 21) } } }
        }.padding(20).kairosCard(cornerRadius: 28) } }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 18) { HStack { VStack(alignment: .leading, spacing: 3) { Text("Your momentum").font(.title2.weight(.bold)); Text("Small wins compound.").font(.subheadline).foregroundStyle(.secondary) }; Spacer(); Button { onNavigate?(4) } label: { KairosIcon("arrow.up.right").frame(width: 34, height: 34) }.foregroundStyle(accent).kairosGlass(cornerRadius: 17, tint: accent.opacity(0.08)) }; HStack(spacing: 12) { metric("\(Int(completion * 100))%", "Tasks complete"); metric("\(completedCount)", "Completed"); metric("\(profileRepo.achievementsData?.unlocked?.count ?? 0)", "Unlocked") }; ProgressView(value: completion).tint(accent).scaleEffect(y: 1.35) }.padding(20).kairosCard(cornerRadius: 28)
    }
    private func metric(_ value: String, _ label: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(value).font(.system(size: 25, weight: .bold, design: .rounded)); Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
    private var quickActions: some View { VStack(alignment: .leading, spacing: 14) { Text("Workspace").font(.title3.weight(.bold)); HStack(spacing: 12) { quickAction("Boards", "square.stack.3d.up.fill", 1); quickAction("Calendar", "calendar", 3); quickAction("Goals", "trophy.fill", 4) } } }
    private func quickAction(_ title: String, _ icon: String, _ tab: Int) -> some View { Button { onNavigate?(tab) } label: { VStack(spacing: 10) { KairosIcon(icon, size: 18).foregroundStyle(accent).frame(width: 40, height: 40).background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous)); Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary) }.frame(maxWidth: .infinity).padding(.vertical, 14).kairosGlass(cornerRadius: 20, tint: accent.opacity(0.04)) }.buttonStyle(.plain) }
    private func fireFocusHaptic() { guard !reduceMotion else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

#Preview { DashboardView().environment(SessionStore()).environment(StudyPlanRepository()).environment(UserProfileRepository()) }

