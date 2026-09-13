import SwiftUI
import Charts

struct StatisticsView: View {
    @Environment(UserProfileRepository.self) private var profileRepo
    @State private var viewModel = StatisticsViewModel()

    private var focus: KairosFocusData {
        profileRepo.focusData ?? defaultFocusData()
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    rangePicker
                    chartCard(title: "Focus Time", subtitle: "Minutes logged", isFocusTime: true)
                    chartCard(title: "Tasks Completed", subtitle: "Completed each period", isFocusTime: false)
                    lifetimeCard
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .kairosBackground()
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your progress")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("See how consistently you are showing up.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var rangePicker: some View {
        Picker("Range", selection: $viewModel.statsRange) {
            Text("Week").tag(StatsRange.week)
            Text("Month").tag(StatsRange.month)
            Text("Year").tag(StatsRange.year)
        }
        .pickerStyle(.segmented)
        .padding(5)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func chartCard(title: String, subtitle: String, isFocusTime: Bool) -> some View {
        let data = viewModel.chartData(focusData: focus, isFocusTime: isFocusTime)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline.weight(.bold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isFocusTime ? "timer" : "checkmark.circle.fill")
                    .foregroundStyle(KairosColors.accent)
            }

            Chart(data) { point in
                BarMark(
                    x: .value("Label", point.label),
                    y: .value("Value", isFocusTime ? point.value / 60.0 : point.value)
                )
                .foregroundStyle(KairosColors.accent.gradient)
                .cornerRadius(5)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 170)
            .accessibilityLabel("\(title) chart")
        }
        .padding(18)
        .kairosCard(cornerRadius: 26)
    }

    private var lifetimeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lifetime totals")
                .font(.headline.weight(.bold))
            summaryRow(label: "Total Focus Logged", value: FocusTimerViewModel.formatHMS(focus.totalSeconds), icon: "timer")
            summaryRow(label: "Longest Session", value: FocusTimerViewModel.formatHMS(focus.longestSessionSeconds), icon: "flame.fill")
            summaryRow(label: "Tasks Completed", value: "\(profileRepo.achievementsData?.lifetimeTasksCompleted ?? 0)", icon: "checkmark.circle.fill")
        }
        .padding(18)
        .kairosCard(cornerRadius: 26)
    }

    private func summaryRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(KairosColors.accent)
                .frame(width: 30)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
        }
        .padding(.vertical, 7)
    }
}

#Preview {
    StatisticsView()
        .environment(UserProfileRepository())
}
