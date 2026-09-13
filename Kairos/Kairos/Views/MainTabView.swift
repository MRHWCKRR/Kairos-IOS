import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
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
        .tint(KairosColors.accent)
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
