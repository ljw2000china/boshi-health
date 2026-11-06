import SwiftUI
import Charts

/// 动作进步：重量突破时间曲线、PB 维持时长、突破记录。
public struct ExerciseProgressView: View {

    @State private var exercises: [(id: String, name: String, count: Int)] = []
    @State private var selected: String?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if exercises.isEmpty {
                    Text("还没有训练记录，先去练一次。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PulseDesign.labelSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    // 动作切换（横向胶囊）
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(exercises, id: \.id) { ex in
                                let on = ex.id == selected
                                Button {
                                    selected = ex.id
                                } label: {
                                    Text(ex.name)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .padding(.horizontal, 14)
                                        .frame(minHeight: 36)
                                        .background(on ? AnyShapeStyle(PulseDesign.mainGradient)
                                                       : AnyShapeStyle(Color.secondary.opacity(0.14)),
                                                    in: Capsule())
                                        .foregroundStyle(on ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    if let sel = selected {
                        ProgressCards(exerciseID: sel)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .themedSurface()
        .navigationTitle("进步曲线")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
    }

    private func refresh() async {
        exercises = await TrainingService.shared.trainedExerciseIDs()
        if selected == nil { selected = exercises.first?.id }
    }
}

/// 单动作进步卡片组
struct ProgressCards: View {
    let exerciseID: String
    @State private var progress: TrainingSummary.Progress?

    var body: some View {
        Group {
            if let p = progress {
                if p.points.isEmpty {
                    Text("暂无数据")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PulseDesign.labelSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
                    // PB 卡
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("个人最好")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(PulseDesign.labelSecondary)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(weightText(p.personalBest))
                                    .font(PulseDesign.bigNumber(40))
                                Text("kg")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(PulseDesign.labelSecondary)
                            }
                            if let d = p.pbDate {
                                Text("PB 于 \(dateText(d))")
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(PulseDesign.labelTertiary)
                            }
                        }
                        Spacer(minLength: 0)
                        VStack(spacing: 2) {
                            Text("\(p.heldDays)")
                                .font(PulseDesign.bigNumber(26))
                                .foregroundStyle(PulseDesign.accent)
                            Text("已维持（天）")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(PulseDesign.labelSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(PulseDesign.accent.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 14))
                    }
                    .pulseCard(padding: 16)

                    // 曲线卡
                    VStack(alignment: .leading, spacing: 10) {
                        PulseDesign.SectionLabel("重量曲线")
                        Chart {
                            ForEach(p.points) { pt in
                                AreaMark(x: .value("日期", pt.date),
                                         y: .value("重量", pt.maxWeightKg))
                                    .foregroundStyle(
                                        LinearGradient(colors: [PulseDesign.accent.opacity(0.35),
                                                                PulseDesign.accent.opacity(0.02)],
                                                       startPoint: .top, endPoint: .bottom))
                                    .interpolationMethod(.monotone)
                                LineMark(x: .value("日期", pt.date),
                                         y: .value("重量", pt.maxWeightKg))
                                    .foregroundStyle(PulseDesign.accent)
                                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                    .interpolationMethod(.monotone)
                                PointMark(x: .value("日期", pt.date),
                                          y: .value("重量", pt.maxWeightKg))
                                    .foregroundStyle(PulseDesign.accent2)
                                    .symbolSize(34)
                            }
                            if p.personalBest > 0 {
                                RuleMark(y: .value("PB", p.personalBest))
                                    .foregroundStyle(.red.opacity(0.45))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .annotation(position: .top, alignment: .leading) {
                                        Text("PB")
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .foregroundStyle(.red.opacity(0.7))
                                    }
                            }
                        }
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: 160)
                    }
                    .pulseCard(padding: 16)

                    // 突破记录
                    if !p.milestones.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            PulseDesign.SectionLabel("突破记录")
                            ForEach(p.milestones.reversed()) { m in
                                HStack(spacing: 10) {
                                    Image(systemName: "trophy.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.yellow)
                                    Text(weightText(m.weightKg) + " kg")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                    Spacer()
                                    Text(dateText(m.date))
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(PulseDesign.labelSecondary)
                                    Text("维持 \(m.heldDays) 天")
                                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                        .foregroundStyle(PulseDesign.labelTertiary)
                                        .frame(minWidth: 58, alignment: .trailing)
                                }
                                .frame(minHeight: 30)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .pulseCard(padding: 16)
                    }
                }
            } else {
                ProgressView().padding(.top, 30)
            }
        }
        .task(id: exerciseID) {
            progress = await TrainingService.shared.progress(exerciseID: exerciseID)
        }
    }

    private func weightText(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }

    private func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: d)
    }
}
