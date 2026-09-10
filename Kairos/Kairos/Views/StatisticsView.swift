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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Range", selection: $viewModel.statsRange) {
                        Text("Week").tag(StatsRange.week)
                        Text("Month").tag(StatsRange.month)
                        Text("Year").tag(StatsRange.year)
                    }
                    .pickerStyle(.segmented)

                    chartCard(title: "Focus Time", isFocusTime: true)
                    chartCard(title: "Tasks Completed", isFocusTime: false)

                    Text("Lifetime Totals")
                        .font(.headline)

                    summaryRow(label: "Total Focus Logged", value: FocusTimerViewModel.formatHMS(focus.totalSeconds))
                    summaryRow(label: "Longest Session", value: FocusTimerViewModel.formatHMS(focus.longestSessionSeconds))
                    summaryRow(label: "Total Tasks Completed", value: "\(profileRepo.achievementsData?.lifetimeTasksCompleted ?? 0)")
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Statistics")
        }
    }

    @ViewBuilder
    private func chartCard(title: String, isFocusTime: Bool) -> some View {
        let data = viewModel.chartData(focusData: focus, isFocusTime: isFocusTime)
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.weight(.semibold))
            Chart(data) { point in
                BarMark(x: .value("Label", point.label), y: .value("Value", point.value))
                    .foregroundStyle(.purple)
            }
            .frame(height: 160)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.headline).foregroundStyle(.purple)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    StatisticsView()
        .environment(UserProfileRepository())
}
