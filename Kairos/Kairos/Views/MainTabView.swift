import SwiftUI

struct MainTabView: View {
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab = 0

    private var appearance: KairosAppearanceSettings? { profileRepo.appearanceSettings }
    private var accent: Color { KairosColors.accent(for: appearance?.theme) }
    private var preferredScheme: ColorScheme? {
        switch appearance?.mode { case "light": return .light; case "dark": return .dark; default: return nil }
    }

    var body: some View {
        ZStack { tabContent }
            .tint(accent)
            .preferredColorScheme(preferredScheme)
            .safeAreaInset(edge: .bottom, spacing: 0) { premiumTabBar.padding(.bottom, 8) }
            .onOpenURL { url in
                guard url.scheme == KairosDeepLink.scheme, url.host == KairosDeepLink.focusTimerPath else { return }
                select(0)
                FocusTimerCoordinator.shared.start()
            }
    }

    @ViewBuilder
    private var tabContent: some View {
        DashboardView { tab in select(tab) }
            .opacity(selectedTab == 0 ? 1 : 0)
            .allowsHitTesting(selectedTab == 0)
            .accessibilityHidden(selectedTab != 0)

        TasksWorkspaceView()
            .opacity(selectedTab == 1 ? 1 : 0)
            .allowsHitTesting(selectedTab == 1)
            .accessibilityHidden(selectedTab != 1)

        AIHelperView()
            .opacity(selectedTab == 2 ? 1 : 0)
            .allowsHitTesting(selectedTab == 2)
            .accessibilityHidden(selectedTab != 2)

        CalendarView()
            .opacity(selectedTab == 3 ? 1 : 0)
            .allowsHitTesting(selectedTab == 3)
            .accessibilityHidden(selectedTab != 3)

        AchievementsView()
            .opacity(selectedTab == 4 ? 1 : 0)
            .allowsHitTesting(selectedTab == 4)
            .accessibilityHidden(selectedTab != 4)
    }

    private func select(_ tab: Int) {
        if reduceMotion { selectedTab = tab }
        else { withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { selectedTab = tab } }
    }

    private var premiumTabBar: some View {
        HStack(spacing: 4) {
            tabButton(0, title: "Home", icon: "house.fill")
            tabButton(1, title: "Boards", icon: "square.stack.3d.up.fill")
            tabButton(2, title: "AI", icon: "sparkles", prominent: true)
            tabButton(3, title: "Calendar", icon: "calendar")
            tabButton(4, title: "Goals", icon: "trophy.fill")
        }
        .padding(5).frame(maxWidth: 430)
        .kairosGlass(cornerRadius: 24, tint: accent.opacity(0.08))
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func tabButton(_ tab: Int, title: String, icon: String, prominent: Bool = false) -> some View {
        let selected = selectedTab == tab
        Button { select(tab) } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: prominent ? 17 : 15, weight: .semibold)).symbolEffect(.bounce, value: selected && !reduceMotion)
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(selected ? accent : .secondary)
            .frame(maxWidth: .infinity).frame(height: 46)
            .background { if selected { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(accent.opacity(0.13)) } }
            .overlay { if prominent && selected { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(accent.opacity(0.18), lineWidth: 0.8) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview {
    MainTabView().environment(SessionStore()).environment(StudyPlanRepository()).environment(UserProfileRepository())
}
