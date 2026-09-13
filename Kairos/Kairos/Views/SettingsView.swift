import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }

                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }
                }

                Section("Progress") {
                    NavigationLink {
                        AchievementsView()
                    } label: {
                        Label("Goals & Achievements", systemImage: "trophy.fill")
                    }

                    NavigationLink {
                        StatisticsView()
                    } label: {
                        Label("Statistics", systemImage: "chart.bar.xaxis")
                    }
                }

                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
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
