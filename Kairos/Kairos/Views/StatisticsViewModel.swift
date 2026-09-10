import Foundation
import Observation

enum StatsRange: String, CaseIterable {
    case week, month, year
}

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
}

/// Port of Android's StatisticsViewModel.getChartData — same week/month/year
/// aggregation logic over dailyFocusLog / dailyTasksLog, keyed by the shared
/// "yyyy-MM-dd" date-key format (KairosDate.dayKey).
@Observable
@MainActor
final class StatisticsViewModel {
    var statsRange: StatsRange = .week

    func chartData(focusData: KairosFocusData, isFocusTime: Bool) -> [ChartDataPoint] {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let focusLog = focusData.dailyFocusLog ?? [:]
        let tasksLog = focusData.dailyTasksLog ?? [:]

        switch statsRange {
        case .week:
            return (0..<7).reversed().compactMap { offset -> ChartDataPoint? in
                guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
                let key = KairosDate.dayKey(for: date)
                let value: Double = isFocusTime ? Double(focusLog[key] ?? 0) : Double(tasksLog[key] ?? 0)
                return ChartDataPoint(label: shortWeekdayLabel(for: date), value: value)
            }

        case .month:
            var weeks = [Double](repeating: 0, count: 5)
            let comps = calendar.dateComponents([.year, .month], from: now)
            let log = isFocusTime ? focusLog.mapValues { Double($0) } : tasksLog.mapValues { Double($0) }
            forEachLogEntry(log) { date, value in
                let dComps = calendar.dateComponents([.year, .month, .day], from: date)
                guard dComps.year == comps.year, dComps.month == comps.month, let day = dComps.day else { return }
                let weekIndex = min(4, (day - 1) / 7)
                weeks[weekIndex] += value
            }
            return weeks.enumerated().map { ChartDataPoint(label: "Wk \($0 + 1)", value: $1) }

        case .year:
            var months = [Double](repeating: 0, count: 12)
            let year = calendar.component(.year, from: now)
            let monthLabels = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            let log = isFocusTime ? focusLog.mapValues { Double($0) } : tasksLog.mapValues { Double($0) }
            forEachLogEntry(log) { date, value in
                guard calendar.component(.year, from: date) == year else { return }
                let monthIndex = calendar.component(.month, from: date) - 1
                guard months.indices.contains(monthIndex) else { return }
                months[monthIndex] += value
            }
            return months.enumerated().map { ChartDataPoint(label: monthLabels[$0], value: $1) }
        }
    }

    private func forEachLogEntry(_ log: [String: Double], _ body: (Date, Double) -> Void) {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        for (key, value) in log {
            guard let date = formatter.date(from: key) else { continue }
            body(date, value)
        }
    }

    private func shortWeekdayLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}
