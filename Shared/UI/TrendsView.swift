import SwiftUI

/// 趋势页（双端共用）：昨夜睡眠图表 + 近 14 天恢复/睡眠/负荷趋势。
/// 手表与手机共用同一实现，仅间距与图表高度不同。
public struct TrendsView: View {

    @State private var points: [DataPipeline.DailyPoint] = []
    @State private var detail: DataPipeline.SleepDetail?
    @State private var loading = false
    @State private var days = 14

    private var compact: Bool {
        #if os(watchOS)
        true
        #else
        false
        #endif
    }

    public init() {}

    @State private var autoRebuildAttempted = false

    public var body: some View {
        ScrollView {
            VStack(spacing: compact ? 10 : 14) {
                if loading && points.isEmpty {
                    ProgressView("读取中…")
                } else if points.allSatisfy({ $0.recovery == nil && $0.sleepScore == nil && $0.strain == nil }) {
                    emptySection
                } else {
                    sleepSection
                    recoverySection
                    sleepDurationSection
                    strainSection
                }
            }
            .padding(.horizontal, compact ? 4 : 16)
            .padding(.vertical, compact ? 4 : 8)
        }
        .themedSurface()
        .navigationTitle("趋势")
        .task { await reload() }
        .refreshable { await reload(force: true) }
    }

    /// 空态：数据刚同步完还没算分，自动补一次基线+重算
    private var emptySection: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 36))
                .foregroundStyle(PulseDesign.labelSecondary)
            Text("还没有可画的数据")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text("趋势需要：睡眠窗口 + 14 天基线（恢复/压力）。\n数据刚同步时系统正在重算，稍等片刻或下拉刷新。")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(PulseDesign.labelSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .task(id: autoRebuildAttempted) {
            guard !autoRebuildAttempted else { return }
            autoRebuildAttempted = true
            await DataPipeline.shared.rebuildBaseline()
            await DataPipeline.shared.rebuildRecent(days: 14)
            await reload()
        }
    }

    // MARK: - 昨夜睡眠

    @ViewBuilder
    private var sleepSection: some View {
        if let d = detail {
            ChartCard(title: "昨夜睡眠", value: timeRange(d)) {
                VStack(alignment: .leading, spacing: 8) {
                    SleepStageTimeline(detail: d, height: compact ? 60 : 90)
                    SleepStageBreakdown(detail: d, height: compact ? 14 : 18)
                    HStack(spacing: compact ? 10 : 16) {
                        stat("时长", String(format: "%.1fh", d.asleepMin / 60))
                        stat("效率", String(format: "%.0f%%", efficiency(d)))
                        stat("评分", d.score.map { "\(Int($0))" } ?? "--")
                    }
                    SleepStageLegend()
                    Text(sourceText(d))
                        .font(.system(size: compact ? 11 : 13))
                        .foregroundStyle(PulseDesign.labelSecondary)
                }
            }
        } else {
            ChartCard(title: "昨夜睡眠") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("暂无睡眠数据")
                        .font(.system(size: 15, weight: .semibold))
                    Text("佩戴手表睡觉后自动识别（支持午睡）。若长时间无数据，请确认健康授权已开启。")
                        .font(.system(size: compact ? 12 : 14))
                        .foregroundStyle(PulseDesign.labelSecondary)
                }
            }
        }
    }

    // MARK: - 恢复趋势

    private var recoverySection: some View {
        ChartCard(title: "恢复趋势", value: "\(days) 天") {
            RecoveryTrendChart(points: points, height: compact ? 96 : 150)
        }
    }

    private var sleepDurationSection: some View {
        ChartCard(title: "睡眠时长", value: avgSleepText) {
            SleepDurationChart(points: points, height: compact ? 96 : 150)
        }
    }

    private var strainSection: some View {
        ChartCard(title: "训练负荷", value: avgStrainText) {
            StrainChart(points: points, height: compact ? 82 : 130)
        }
    }

    // MARK: - 辅助

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: compact ? 11 : 13))
                .foregroundStyle(PulseDesign.labelSecondary)
            Text(value)
                .font(.system(size: compact ? 15 : 17, weight: .semibold, design: .rounded))
        }
    }

    private func timeRange(_ d: DataPipeline.SleepDetail) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "\(f.string(from: d.start))–\(f.string(from: d.end))"
    }

    private func efficiency(_ d: DataPipeline.SleepDetail) -> Double {
        let total = d.end.timeIntervalSince(d.start) / 60
        return total > 0 ? min(1, d.asleepMin / total) * 100 : 0
    }

    private func sourceText(_ d: DataPipeline.SleepDetail) -> String {
        var parts: [String] = []
        switch d.source {
        case SampleSource.extended.rawValue: parts.append("含自动延伸")
        case SampleSource.override.rawValue: parts.append("已手动修正")
        case SampleSource.inferred.rawValue: parts.append("活动推测（未使用系统分期）")
        default: parts.append("系统分期")
        }
        let symbol = d.confidence >= 0.8 ? "●" : (d.confidence >= 0.5 ? "◐" : "○")
        parts.append("置信度 \(symbol) \(Int(d.confidence * 100))%")
        if !d.confidenceReason.isEmpty { parts.append(d.confidenceReason) }
        return parts.joined(separator: " · ")
    }

    private var avgSleepText: String {
        let hs = points.compactMap(\.sleepHours)
        guard !hs.isEmpty else { return "" }
        return String(format: "均 %.1fh", hs.reduce(0, +) / Double(hs.count))
    }

    private var avgStrainText: String {
        let ss = points.compactMap(\.strain)
        guard !ss.isEmpty else { return "" }
        return String(format: "均 %.1f", ss.reduce(0, +) / Double(ss.count))
    }

    private func reload(force: Bool = false) async {
        loading = true
        if force {
            await DataPipeline.shared.syncNow()
            await DataPipeline.shared.rebuildBaseline()
            await DataPipeline.shared.recomputeDayScoring(
                dayKey: SleepWindowBuilder.dayKey(for: Date()))
        }
        points = await DataPipeline.shared.metricHistory(days: days)
        detail = await DataPipeline.shared.sleepDetail()
        loading = false
    }
}
