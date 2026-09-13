import SwiftUI

struct SettingsView: View {
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingAppearance = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }

                    Button {
                        showingAppearance = true
                    } label: {
                        Label("Appearance", systemImage: colorScheme == .dark ? "moon.fill" : "sun.max.fill")
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
            .sheet(isPresented: $showingAppearance) {
                AppearanceSettingsView()
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(UserProfileRepository())
}
