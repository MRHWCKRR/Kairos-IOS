import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            TasksView()
                .tabItem { Label("Boards", systemImage: "checklist") }

            AIHelperView()
                .tabItem { Label("AI", systemImage: "sparkles") }

            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }

            AchievementsView()
                .tabItem { Label("Goals", systemImage: "trophy.fill") }
        }
        .tint(KairosColors.accent)
    }
}

#Preview {
    MainTabView()
        .environment(SessionStore())
        .environment(StudyPlanRepository())
        .environment(UserProfileRepository())
}
