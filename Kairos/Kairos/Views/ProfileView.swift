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
                VStack(spacing: 18) {
                    header
                    quickStats
                    profileLink("Notifications", subtitle: "Choose when Kairos can reach you", icon: "bell.badge.fill", tint: KairosColors.accent) {
                        NotificationSettingsView().environment(profileRepo)
                    }
                    profileLink("Achievements", subtitle: "Track progress & unlock badges", icon: "trophy.fill", tint: .orange) {
                        AchievementsView().environment(profileRepo)
                    }
                    profileLink("Statistics", subtitle: "Focus time & task trends", icon: "chart.bar.fill", tint: .blue) {
                        StatisticsView().environment(profileRepo)
                    }
                    signOutButton
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .kairosBackground()
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
                    .fill(KairosColors.accent.opacity(0.14))
                    .frame(width: 82, height: 82)
                Text(initials)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(KairosColors.accent)
            }
            .kairosGlass(cornerRadius: 42, tint: KairosColors.accent.opacity(0.12))

            Text(displayName)
                .font(.title3.weight(.bold))
            Text(session.email)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var quickStats: some View {
        HStack(spacing: 12) {
            statCard(title: "Focus Time", value: formattedFocusTime, icon: "flame.fill")
            statCard(title: "Tasks Done", value: "\(profileRepo.achievementsData?.lifetimeTasksCompleted ?? 0)", icon: "checkmark.circle.fill")
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(KairosColors.accent)
            Text(value)
                .font(.title3.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .kairosCard(cornerRadius: 18)
    }

    private func profileLink<Destination: View>(
        _ title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .kairosCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            session.signOut()
            dismiss()
        } label: {
            HStack {
                Text("Sign Out")
                Spacer()
                Image(systemName: "rectangle.portrait.and.arrow.right")
            }
            .font(.subheadline.weight(.semibold))
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var formattedFocusTime: String {
        FocusTimerViewModel.formatHMS(profileRepo.focusData?.totalSeconds ?? 0)
    }
}

#Preview {
    ProfileView()
        .environment(SessionStore())
        .environment(UserProfileRepository())
}
