//
//  File.swift
//  Kairos
//
//  Created by Yunfei Na on 19/8/2026.
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }

            TasksView()
                .tabItem { Label("Tasks", systemImage: "checklist") }

            AIHelperView()
                .tabItem { Label("AI Helper", systemImage: "sparkles") }

            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
        }
        .tint(.purple)
    }
}

#Preview {
    MainTabView()
        .environment(StudyPlanRepository())
        .environment(UserProfileRepository())
}
