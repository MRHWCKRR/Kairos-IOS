import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        PlanningAccessibilityView()
                    } label: {
                        Label("Accessibility", sharedIcon: "accessibility")
                    }
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", sharedIcon: "bell.badge")
                    }

                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("Appearance", sharedIcon: "circle.lefthalf.filled")
                    }
                }

                Section("Progress") {
                    NavigationLink {
                        AchievementsView()
                    } label: {
                        Label("Goals & Achievements", sharedIcon: "trophy.fill")
                    }

                    NavigationLink {
                        StatisticsView()
                    } label: {
                        Label("Statistics", sharedIcon: "chart.bar.xaxis")
                    }
                }

                Section {
                    HStack(spacing: 12) {
                        KairosIcon("sparkles")
                            .foregroundStyle(KairosColors.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Kairos")
                                .font(.headline)
                            Text("Your time, intentionally spent.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .scrollContentBackground(.hidden)
            .kairosBackground()
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environment(UserProfileRepository())
}

