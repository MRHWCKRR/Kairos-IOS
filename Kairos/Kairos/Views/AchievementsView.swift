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
                VStack(alignment: .leading, spacing: 24) {
                    overview
                    goalsSection
                    categoryBlock(title: "Locked In Time", category: "focus")
                    categoryBlock(title: "Tasks Completed", category: "tasks")
                    categoryBlock(title: "Milestones", category: "misc")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .kairosBackground()
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(item: $selectedForDetail) { def in
            AchievementDetailSheet(def: def, unlockedTimestamp: achievements.unlocked?[def.id])
        }
    }

    private var overview: some View {
        let unlockedCount = KAIROS_ACHIEVEMENTS.filter { achievements.unlocked?[$0.id] != nil }.count

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(KairosColors.accent.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: KAIROS_ACHIEVEMENTS.isEmpty ? 0 : Double(unlockedCount) / Double(KAIROS_ACHIEVEMENTS.count))
                    .stroke(KairosColors.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(unlockedCount)")
                    .font(.headline.weight(.bold))
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text("Your progress")
                    .font(.headline)
                Text("\(unlockedCount) of \(KAIROS_ACHIEVEMENTS.count) achievements unlocked")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .kairosCard()
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Goals")
                .font(.headline)
            Text("Pick 3 achievements to keep visible on your dashboard.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
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
            VStack(spacing: 5) {
                if let def {
                    Text(def.icon).font(.title2)
                    Text(def.name)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                } else {
                    Image(systemName: "plus")
                        .foregroundStyle(.secondary)
                    Text("Select")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func categoryBlock(title: String, category: String) -> some View {
        let items = KAIROS_ACHIEVEMENTS.filter { $0.category == category }
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

        return VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 2)
            LazyVGrid(columns: columns, spacing: 12) {
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
                .opacity(unlocked ? 1 : 0.28)
            Text(def.name)
                .font(.caption.weight(.bold))
                .foregroundStyle(unlocked ? KairosColors.accent : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if unlocked {
                Label("Unlocked", systemImage: "checkmark.seal.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(KairosColors.accent)
            } else if def.type != "event" {
                ProgressView(value: progress)
                    .tint(KairosColors.accent.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 122)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(unlocked ? KairosColors.accent.opacity(0.35) : .white.opacity(0.1), lineWidth: 1)
        }
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
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 18) {
            Text(def.icon)
                .font(.system(size: 60))
            Text(def.name)
                .font(.title2.weight(.bold))
            Text(def.rarity.uppercased())
                .font(.caption.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(rarityColor(def.rarity).opacity(0.15), in: Capsule())
                .foregroundStyle(rarityColor(def.rarity))
            Text(def.desc)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            if let dateText {
                VStack(spacing: 4) {
                    Text("EARNED ON")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KairosColors.accent)
                    Text(dateText)
                        .font(.headline)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)
            } else {
                Text("NOT YET EARNED")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
        }
        .padding(28)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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
