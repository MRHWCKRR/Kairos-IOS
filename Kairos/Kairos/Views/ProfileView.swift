import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(\.dismiss) private var dismiss

    private var displayName: String {
        let name = profileRepo.profile?.displayName ?? ""
        return name.isEmpty ? "Kairos User" : name
    }

    private var initials: String {
        let parts = displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "K" : String(letters).uppercased()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    quickStats
                    achievementsLink
                    statisticsLink
                    settingsSection
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 76, height: 76)
                Text(initials)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.purple)
            }

            Text(displayName)
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Text(session.email)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var quickStats: some View {
        HStack(spacing: 12) {
            statCard(
                title: "Focus Time",
                value: formattedFocusTime,
                icon: "flame.fill"
            )
            statCard(
                title: "Tasks Done",
                value: "\(profileRepo.achievementsData?.lifetimeTasksCompleted ?? 0)",
                icon: "checkmark.circle.fill"
            )
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.purple)
            Text(value)
                .font(.title3.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var formattedFocusTime: String {
        FocusTimerViewModel.formatHMS(profileRepo.focusData?.totalSeconds ?? 0)
    }

    private var achievementsLink: some View {
        NavigationLink {
            AchievementsView()
                .environment(profileRepo)
        } label: {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Achievements")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Track progress & unlock badges")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var statisticsLink: some View {
        NavigationLink {
            StatisticsView()
                .environment(profileRepo)
        } label: {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Statistics")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Focus time & task trends")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var settingsSection: some View {
        VStack(spacing: 0) {
            Button(role: .destructive) {
                session.signOut()
                dismiss()
            } label: {
                HStack {
                    Text("Sign Out")
                    Spacer()
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .padding(16)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    ProfileView()
        .environment(SessionStore())
        .environment(UserProfileRepository())
}
