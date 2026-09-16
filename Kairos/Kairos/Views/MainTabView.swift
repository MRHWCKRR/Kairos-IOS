import SwiftUI

struct MainTabView: View {
    @Environment(UserProfileRepository.self) private var profileRepo
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
            DashboardView { tab in
                withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(0)

            TasksView()
                .tabItem { Label("Boards", systemImage: "checklist") }
                .tag(1)

            AIHelperView()
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(2)

            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(3)

            AchievementsView()
                .tabItem { Label("Goals", systemImage: "trophy.fill") }
                .tag(4)
        }
        .tint(accent)
        .preferredColorScheme(preferredScheme)
        .onOpenURL { url in
            guard url.scheme == KairosDeepLink.scheme,
                  url.host == KairosDeepLink.focusTimerPath else { return }
            selectedTab = 0
            FocusTimerCoordinator.shared.start()
        }
    }
}

#Preview {
    MainTabView()
        .environment(SessionStore())
        .environment(StudyPlanRepository())
        .environment(UserProfileRepository())
}
