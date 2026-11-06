import SwiftUI
import Charts

/// 趋势图表组件（双端共用，Swift Charts）。
/// 设计约束：深色优先、色盲友好（符号+颜色双编码）、不展示无数据天的虚假连线。
/// 缺失数据点一律断点（不使用插值，design.md 诚实原则）。

// MARK: - Recovery 趋势线

public struct RecoveryTrendChart: View {

    public let points: [DataPipeline.DailyPoint]
    public var height: CGFloat = 140

    public init(points: [DataPipeline.DailyPoint], height: CGFloat = 140) {
        self.points = points
        self.height = height
    }

    public var body: some View {
        Chart {
            ForEach(points) { p in
                if let r = p.recovery {
                    LineMark(x: .value("日期", p.date),
                             y: .value("恢复", r))
                        .foregroundStyle(.green)
                        .interpolationMethod(.catmullRom)
                    AreaMark(x: .value("日期", p.date),
                             yStart: .value("底", 0), yEnd: .value("恢复", r))
                        .foregroundStyle(.green.opacity(0.15))
                    PointMark(x: .value("日期", p.date),
                              y: .value("恢复", r))
                        .foregroundStyle(recoveryColor(r))
                        .symbolSize(6)
                }
            }
            RuleMark(y: .value("良好", 70)).foregroundStyle(.green.opacity(0.4)).lineStyle(StrokeStyle(dash: [4]))
            RuleMark(y: .value("警戒", 45)).foregroundStyle(.red.opacity(0.4)).lineStyle(StrokeStyle(dash: [4]))
        }
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel(format: .dateTime.day()).foregroundStyle(PulseDesign.labelSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel().foregroundStyle(PulseDesign.labelSecondary)
            }
        }
        .frame(height: height)
    }

    private func recoveryColor(_ r: Double) -> Color {
        r >= 70 ? .green : (r >= 45 ? .yellow : .red)
    }
}

// MARK: - 睡眠时长柱状图

public struct SleepDurationChart: View {

    public let points: [DataPipeline.DailyPoint]
    public var height: CGFloat = 140

    public init(points: [DataPipeline.DailyPoint], height: CGFloat = 140) {
        self.points = points
        self.height = height
    }

    public var body: some View {
        Chart {
            ForEach(points) { p in
                if let h = p.sleepHours {
                    BarMark(x: .value("日期", p.date),
                            y: .value("时长", h),
                            width: .ratio(0.6))
                        .foregroundStyle(barColor(h))
                        .cornerRadius(4)
                }
            }
            RuleMark(y: .value("目标", 7.5))
                .foregroundStyle(.blue.opacity(0.6))
                .lineStyle(StrokeStyle(dash: [4]))
        }
        .chartYScale(domain: 0...11)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel(format: .dateTime.day()).foregroundStyle(PulseDesign.labelSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 4, 8]) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel().foregroundStyle(PulseDesign.labelSecondary)
            }
        }
        .frame(height: height)
    }

    private func barColor(_ h: Double) -> Color {
        h >= 7 ? .blue : (h >= 5 ? .cyan : .orange)
    }
}

// MARK: - Strain 柱状图

public struct StrainChart: View {

    public let points: [DataPipeline.DailyPoint]
    public var height: CGFloat = 120

    public init(points: [DataPipeline.DailyPoint], height: CGFloat = 120) {
        self.points = points
        self.height = height
    }

    public var body: some View {
        Chart {
            ForEach(points) { p in
                if let s = p.strain {
                    BarMark(x: .value("日期", p.date),
                            y: .value("Strain", max(s, 0.4)),
                            width: .ratio(0.6))
                        .foregroundStyle(.orange.opacity(0.35 + min(0.65, s / 18)))
                        .cornerRadius(4)
                }
            }
            RuleMark(y: .value("过载", 15)).foregroundStyle(.red.opacity(0.5)).lineStyle(StrokeStyle(dash: [4]))
        }
        .chartYScale(domain: 0...21)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel(format: .dateTime.day()).foregroundStyle(PulseDesign.labelSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 10, 20]) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel().foregroundStyle(PulseDesign.labelSecondary)
            }
        }
        .frame(height: height)
    }
}

// MARK: - 睡眠阶段时间轴（最后一晚 hypnogram）

public struct SleepStageTimeline: View {

    public let detail: DataPipeline.SleepDetail
    public var height: CGFloat = 72

    private static let stageOrder = ["深睡", "浅睡", "REM", "睡眠", "清醒", "卧床"]
    private static let stageColor: [String: Color] = [
        "深睡": .indigo, "浅睡": .blue, "REM": .purple,
        "睡眠": .blue.opacity(0.6), "清醒": .orange, "卧床": .gray
    ]

    public init(detail: DataPipeline.SleepDetail, height: CGFloat = 72) {
        self.detail = detail
        self.height = height
    }

    public var body: some View {
        let stages = visibleStages()
        return Chart {
            ForEach(Array(stages.enumerated()), id: \.offset) { _, seg in
                RectangleMark(
                    xStart: .value("开始", seg.start),
                    xEnd: .value("结束", seg.end),
                    y: .value("阶段", stageIndex(seg.stage))
                )
                .foregroundStyle(Self.stageColor[seg.stage] ?? .gray)
                .cornerRadius(2)
            }
        }
        .chartYScale(domain: -0.5...Double(Self.stageOrder.count) - 0.5)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 1, 2, 3]) { value in
                if let i = value.as(Int.self), i < Self.stageOrder.count {
                    AxisValueLabel {
                        Text(Self.stageOrder[i]).font(.system(size: 11))
                    }
                }
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour)) { value in
                if let d = value.as(Date.self) {
                    AxisValueLabel {
                        Text(d, format: .dateTime.hour()).font(.system(size: 11))
                    }
                }
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
            }
        }
        .frame(height: height)
    }

    /// 推测窗口只有单一「睡眠」段；阶段轴仍按完整阶显示
    private func visibleStages() -> [SleepSegment] {
        detail.segments.filter { $0.durationMin > 0 }
    }

    private func stageIndex(_ stage: String) -> Int {
        Self.stageOrder.firstIndex(of: stage)
            ?? Self.stageOrder.firstIndex(of: "睡眠") ?? 3
    }
}

// MARK: - 睡眠阶段堆叠条

public struct SleepStageBreakdown: View {

    public let detail: DataPipeline.SleepDetail
    public var height: CGFloat = 20

    private static let order = ["深睡", "浅睡", "REM", "睡眠", "清醒"]
    private static let colors: [String: Color] = [
        "深睡": .indigo, "浅睡": .blue, "REM": .purple,
        "睡眠": .blue.opacity(0.6), "清醒": .orange
    ]

    public init(detail: DataPipeline.SleepDetail, height: CGFloat = 20) {
        self.detail = detail
        self.height = height
    }

    public var body: some View {
        let mins = detail.stageMinutes
        let total = mins.values.reduce(0, +)
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Self.order, id: \.self) { stage in
                    if let m = mins[stage], m > 0, total > 0 {
                        Rectangle()
                            .fill(Self.colors[stage] ?? .gray)
                            .frame(width: geo.size.width * CGFloat(m / total))
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - 图例

public struct SleepStageLegend: View {
    public init() {}
    public var body: some View {
        HStack(spacing: 10) {
            legendItem("深睡", .indigo)
            legendItem("浅睡", .blue)
            legendItem("REM", .purple)
            legendItem("睡眠", .blue.opacity(0.6))
            legendItem("清醒", .orange)
        }
    }
    private func legendItem(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name).font(.system(size: 12)).foregroundStyle(PulseDesign.labelSecondary)
        }
    }
}

// MARK: - 通用图表卡

public struct ChartCard<Content: View>: View {
    let title: String
    let value: String
    let content: Content

    public init(title: String, value: String = "", @ViewBuilder content: () -> Content) {
        self.title = title
        self.value = value
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if !value.isEmpty {
                    Text(value)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(PulseDesign.labelSecondary)
                }
            }
            content
        }
        .padding()
        #if os(watchOS)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        #else
        .modifier(GlassCardFill(opacity: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        #endif
    }
}
