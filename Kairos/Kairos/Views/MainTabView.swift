import SwiftUI

struct MainTabView: View {
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab = 0

    private var appearance: KairosAppearanceSettings? { profileRepo.appearanceSettings }
    private var accent: Color { KairosColors.accent(for: appearance?.theme) }
    private var preferredScheme: ColorScheme? {
        switch appearance?.mode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView { tab in select(tab) }
                .tag(0)

            TasksView()
                .tag(1)

            AIHelperView()
                .tag(2)

            CalendarView()
                .tag(3)

            AchievementsView()
                .tag(4)
        }
        .tint(accent)
        .preferredColorScheme(preferredScheme)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            premiumTabBar
        }
        .onOpenURL { url in
            guard url.scheme == KairosDeepLink.scheme,
                  url.host == KairosDeepLink.focusTimerPath else { return }
            select(0)
            FocusTimerCoordinator.shared.start()
        }
    }

    private func select(_ tab: Int) {
        if reduceMotion {
            selectedTab = tab
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                selectedTab = tab
            }
        }
    }

    private var premiumTabBar: some View {
        HStack(spacing: 6) {
            tabButton(0, title: "Home", icon: "house.fill")
            tabButton(1, title: "Boards", icon: "square.stack.3d.up.fill")
            tabButton(2, title: "AI", icon: "sparkles", prominent: true)
            tabButton(3, title: "Calendar", icon: "calendar")
            tabButton(4, title: "Goals", icon: "trophy.fill")
        }
        .padding(7)
        .frame(maxWidth: 430)
        .kairosGlass(cornerRadius: 30)
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func tabButton(_ tab: Int, title: String, icon: String, prominent: Bool = false) -> some View {
        let selected = selectedTab == tab
        Button { select(tab) } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: prominent ? 17 : 16, weight: .semibold))
                    .symbolEffect(.bounce, value: selected && !reduceMotion)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(selected ? accent : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: prominent ? 56 : 50)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: prominent ? 20 : 17, style: .continuous)
                        .fill(accent.opacity(0.12))
                }
            }
            .overlay {
                if prominent && selected {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(accent.opacity(0.18), lineWidth: 0.8)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview {
    MainTabView()
        .environment(SessionStore())
        .environment(StudyPlanRepository())
        .environment(UserProfileRepository())
}
