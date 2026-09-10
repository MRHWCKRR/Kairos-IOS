import SwiftUI

struct AchievementsView: View {
    @Environment(UserProfileRepository.self) private var profileRepo
    @State private var selectedForDetail: AchievementDef?

    private var achievements: KairosAchievementsData {
        profileRepo.achievementsData ?? defaultAchievementsData()
    }

    private var trackable: [AchievementDef] {
        KAIROS_ACHIEVEMENTS.filter { $0.type != "event" }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    goalsSection
                    categoryBlock(title: "Locked In Time", category: "focus")
                    categoryBlock(title: "Tasks Completed", category: "tasks")
                    categoryBlock(title: "Milestones", category: "misc")
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Achievements")
        }
        .sheet(item: $selectedForDetail) { def in
            AchievementDetailSheet(def: def, unlockedTimestamp: achievements.unlocked?[def.id])
        }
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Goals").font(.headline)
            Text("Pick 3 goals to track on your dashboard.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    goalSelector(index: index)
                }
            }
        }
    }

    private func goalSelector(index: Int) -> some View {
        let goals = achievements.goals ?? [nil, nil, nil]
        let goalID = goals.indices.contains(index) ? goals[index] : nil
        let def = trackable.first { $0.id == goalID }

        return Menu {
            Button("None") {
                Task { await profileRepo.setGoal(index: index, achievementID: nil) }
            }
            ForEach(trackable) { item in
                Button("\(item.icon) \(item.name)") {
                    Task { await profileRepo.setGoal(index: index, achievementID: item.id) }
                }
            }
        } label: {
            VStack(spacing: 4) {
                if let def {
                    Text(def.icon).font(.title2)
                    Text(def.name).font(.caption2.weight(.bold)).lineLimit(1)
                } else {
                    Image(systemName: "plus").foregroundStyle(.secondary)
                    Text("Select").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func categoryBlock(title: String, category: String) -> some View {
        let items = KAIROS_ACHIEVEMENTS.filter { $0.category == category }
        let columns = [GridItem(.flexible()), GridItem(.flexible())]

        return VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { def in
                    badgeCard(def)
                        .onTapGesture { selectedForDetail = def }
                }
            }
        }
    }

    private func badgeCard(_ def: AchievementDef) -> some View {
        let unlocked = achievements.unlocked?[def.id] != nil
        let progress = progressFraction(def)

        return VStack(spacing: 8) {
            Text(def.icon)
                .font(.system(size: 28))
                .opacity(unlocked ? 1 : 0.3)
            Text(def.name)
                .font(.caption.weight(.bold))
                .foregroundStyle(unlocked ? .purple : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if unlocked {
                Text("Unlocked")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.purple.opacity(0.7))
            } else if def.type != "event" {
                ProgressView(value: progress)
                    .tint(.purple.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(12)
        .background(
            unlocked ? Color.purple.opacity(0.1) : Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(unlocked ? Color.purple.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }

    private func progressFraction(_ def: AchievementDef) -> Double {
        guard def.threshold > 0 else { return 0 }
        switch def.type {
        case "focus_seconds":
            return min(1, Double(profileRepo.focusData?.totalSeconds ?? 0) / Double(def.threshold))
        case "tasks_completed":
            return min(1, Double(achievements.lifetimeTasksCompleted) / Double(def.threshold))
        default:
            return 0
        }
    }
}

private struct AchievementDetailSheet: View {
    let def: AchievementDef
    let unlockedTimestamp: Int64?

    private var dateText: String? {
        guard let ts = unlockedTimestamp else { return nil }
        let date = Date(timeIntervalSince1970: Double(ts) / 1000)
        let f = DateFormatter()
        f.dateStyle = .long
        return f.string(from: date)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(def.icon).font(.system(size: 60))
            Text(def.name).font(.title2.weight(.bold))
            Text(def.rarity.uppercased())
                .font(.caption.weight(.bold))
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(rarityColor(def.rarity).opacity(0.15), in: Capsule())
                .foregroundStyle(rarityColor(def.rarity))
            Text(def.desc)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            if let dateText {
                VStack(spacing: 4) {
                    Text("EARNED ON").font(.caption.weight(.bold)).foregroundStyle(.purple.opacity(0.6))
                    Text(dateText).font(.headline)
                }
                .padding(16)
                .background(Color.purple.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            } else {
                Text("NOT YET EARNED")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .padding(32)
        .presentationDetents([.medium])
    }

    private func rarityColor(_ rarity: String) -> Color {
        switch rarity {
        case "Mythic": return .yellow
        case "Legendary": return .purple
        case "Epic": return .blue
        case "Rare": return .green
        default: return .gray
        }
    }
}

#Preview {
    AchievementsView()
        .environment(UserProfileRepository())
}
