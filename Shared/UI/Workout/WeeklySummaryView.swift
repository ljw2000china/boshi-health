import SwiftUI

/// 每周汇总：人体图（练过的部位变红）、总量、与上周对比、每日重点。实时刷新。
public struct WeeklySummaryView: View {

    @State private var thisWeek: TrainingSummary.WeekSummary?
    @State private var lastWeek: TrainingSummary.WeekSummary?
    @State private var cmp: TrainingSummary.Comparison?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let w = thisWeek, let c = cmp {
                    // 人体图
                    VStack(spacing: 8) {
                        HStack {
                            PulseDesign.SectionLabel("本周肌肉覆盖")
                            Spacer()
                            Text(weekRangeText(w))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(PulseDesign.labelSecondary)
                        }
                        BodyMapView(muscleSets: w.muscleSets) { m in w.intensity(for: m) }
                            .frame(height: 200)
                    }
                    .pulseCard(padding: 16)

                    // 总量对比
                    HStack(spacing: 0) {
                        metric(title: "组数", value: "\(w.totalSets)",
                               delta: deltaText(c.setDelta, unit: "组"))
                        Divider().frame(height: 40)
                        metric(title: "总容量", value: volumeText(w.volumeKg),
                               delta: volumeDeltaText(c))
                        Divider().frame(height: 40)
                        metric(title: "训练天数", value: "\(w.trainedDays)",
                               delta: "")
                    }
                    .pulseCard(padding: 16)

                    // 肌群明细
                    VStack(spacing: 10) {
                        HStack {
                            PulseDesign.SectionLabel("肌群明细（对比上周）")
                            Spacer()
                        }
                        ForEach(muscles, id: \.self) { m in
                            let sets = w.muscleSets[m] ?? 0
                            let delta = c.muscleSetDelta(m)
                            if sets > 0 || delta != 0 {
                                HStack(spacing: 10) {
                                    Text(TrainingDaySnapshot.emoji(for: m))
                                        .font(.system(size: 18))
                                        .frame(width: 28)
                                    Text(m)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                    Spacer()
                                    Text("\(sets) 组 · \(volumeText(w.muscleVolume[m] ?? 0))")
                                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                        .foregroundStyle(PulseDesign.labelSecondary)
                                    Text(deltaText(delta, unit: "组"))
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(delta > 0 ? .green : (delta < 0 ? .red : .secondary))
                                        .frame(minWidth: 48, alignment: .trailing)
                                }
                                .frame(minHeight: 32)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pulseCard(padding: 16)

                    if !w.dayFocus.isEmpty {
                        VStack(spacing: 10) {
                            HStack {
                                PulseDesign.SectionLabel("每日重点")
                                Spacer()
                            }
                            ForEach(w.dayFocus, id: \.dayKey) { item in
                                HStack {
                                    Text(shortDay(item.dayKey))
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(PulseDesign.labelSecondary)
                                    Spacer()
                                    Text(item.focus.title)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                }
                                .frame(minHeight: 30)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .pulseCard(padding: 16)
                    }

                    if let l = lastWeek {
                        HStack {
                            PulseDesign.SectionLabel("上周回顾")
                            Spacer()
                            Text("\(l.totalSets) 组 · \(volumeText(l.volumeKg)) · 训练 \(l.trainedDays) 天")
                                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                .foregroundStyle(PulseDesign.labelSecondary)
                        }
                        .pulseCard(padding: 14)
                    }
                } else {
                    ProgressView("计算本周数据…")
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .themedSurface()
        .navigationTitle("本周总结")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private var muscles: [String] { ["胸", "背", "腿", "肩", "臂", "核心"] }

    private func refresh() async {
        let (w, l, c) = await TrainingService.shared.weekComparison()
        thisWeek = w
        lastWeek = l
        cmp = c
    }

    private func metric(title: String, value: String, delta: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(PulseDesign.labelSecondary)
            Text(value)
                .font(PulseDesign.bigNumber(20))
            if !delta.isEmpty {
                Text(delta)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PulseDesign.labelSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func deltaText(_ d: Int, unit: String) -> String {
        d == 0 ? "持平" : String(format: "%@%d%@", d > 0 ? "+" : "", d, unit)
    }

    private func volumeDeltaText(_ c: TrainingSummary.Comparison) -> String {
        guard let pct = c.volumeDeltaPct else { return "上周无数据" }
        return String(format: "%@%.0f%%", pct >= 0 ? "+" : "", pct)
    }

    private func volumeText(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1ft", v / 1000) : String(format: "%.0fkg", v)
    }

    private func weekRangeText(_ w: TrainingSummary.WeekSummary) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return "\(f.string(from: w.start)) – \(f.string(from: Calendar.current.date(byAdding: .day, value: -1, to: w.end) ?? w.end))"
    }

    private func shortDay(_ key: String) -> String {
        String(key.suffix(5))  // "MM-dd"
    }
}
