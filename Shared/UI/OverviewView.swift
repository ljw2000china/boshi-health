import SwiftUI

/// 今日概览（双端共用）：Recovery 大数字 + 次要卡片。design.md §13：
/// 大数字 SF Rounded ≥56pt（watch 用 40pt 例外）、次要文字 ≥14pt、色盲友好（符号+颜色双编码）、深色优先。
struct OverviewView: View {

    @State private var data: DataPipeline.OverviewData?
    @State private var loading = false

    private var bigFont: Font {
        #if os(watchOS)
        .system(size: 40, weight: .bold, design: .rounded)
        #else
        .system(size: 56, weight: .bold, design: .rounded)
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if loading && data == nil {
                ProgressView("读取中…")
            } else if let d = data {
                recoveryCard(d)
                secondaryCards(d)
                if !d.recoveryNote.isEmpty && !d.inCalibration {
                    Text(d.recoveryNote)
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                }
            } else {
                emptyState
            }
        }
        .padding(.horizontal)
        .task { await reload() }
        .refreshable { await reload(force: true) }
    }

    // MARK: - 主卡：Recovery

    private func recoveryCard(_ d: DataPipeline.OverviewData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("恢复")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PulseDesign.labelSecondary)
                Spacer()
                if d.inCalibration {
                    Text("标定期 D\(d.calibrationDaysLeft)")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                } else if let r = d.recovery {
                    Text(recoverySymbol(r))
                        .font(.system(size: 18))
                        .foregroundStyle(recoveryColor(r))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if d.inCalibration {
                    Text("--")
                        .font(bigFont)
                        .foregroundStyle(PulseDesign.labelSecondary)
                } else if let r = d.recovery {
                    Text("\(Int(r))")
                        .font(bigFont)
                        .foregroundStyle(recoveryColor(r))
                } else {
                    Text("--")
                        .font(bigFont)
                        .foregroundStyle(PulseDesign.labelSecondary)
                }
                Text(d.inCalibration ? "还需 \(d.calibrationDaysLeft) 天数据" : "0–100")
                    .font(.system(size: 14))
                    .foregroundStyle(PulseDesign.labelSecondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(watchOS)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        #else
        .modifier(GlassCardFill(opacity: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        #endif
    }

    // MARK: - 次要卡：2×2 网格（手表用单列）

    private func secondaryCards(_ d: DataPipeline.OverviewData) -> some View {
        #if os(watchOS)
        VStack(alignment: .leading, spacing: 10) {
            secondaryCard("睡眠", value: d.sleepScore.map { "\(Int($0))" } ?? "--", note: "0–100")
            secondaryCard("Strain", value: d.strain.map { String(format: "%.1f", $0) } ?? "--", note: "0–21")
            secondaryCard("ACWR", value: d.acwr.map { String(format: "%.2f", $0) } ?? "--",
                          note: "甜区 0.8–1.3")
            secondaryCard("压力", value: d.stress.map { "\(Int($0))" } ?? "--", note: "0–100")
            secondaryCard("睡眠债", value: d.sleepDebt.map { String(format: "%.1fh", $0) } ?? "--", note: "近14天")
            secondaryCard("准备度", value: d.readiness.map { String(format: "%.1f", $0) } ?? "--",
                          note: d.readiness.map { ReadinessScore.advice(readiness: $0) } ?? "0–10")
        }
        #else
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                secondaryCard("睡眠", value: d.sleepScore.map { "\(Int($0))" } ?? "--", note: "0–100")
                secondaryCard("Strain", value: d.strain.map { String(format: "%.1f", $0) } ?? "--", note: "0–21")
            }
            HStack(spacing: 10) {
                secondaryCard("ACWR", value: d.acwr.map { String(format: "%.2f", $0) } ?? "--",
                              note: "甜区 0.8–1.3")
                secondaryCard("压力", value: d.stress.map { "\(Int($0))" } ?? "--", note: "0–100")
            }
            HStack(spacing: 10) {
                secondaryCard("睡眠债", value: d.sleepDebt.map { String(format: "%.1fh", $0) } ?? "--", note: "近14天")
                secondaryCard("准备度", value: d.readiness.map { String(format: "%.1f", $0) } ?? "--",
                              note: d.readiness.map { ReadinessScore.advice(readiness: $0) } ?? "0–10")
            }
        }
        #endif
    }

    private func secondaryCard(_ title: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(PulseDesign.labelSecondary)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text(note)
                .font(.system(size: 14))
                .foregroundStyle(PulseDesign.labelSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        #if os(watchOS)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        #else
        .modifier(GlassCardFill(opacity: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.circle")
                .font(.largeTitle)
                .foregroundStyle(PulseDesign.labelSecondary)
            Text("暂无数据")
                .font(.headline)
            Text("请确认已授权健康数据，佩戴手表睡眠后自动生成")
                .font(.system(size: 14))
                .foregroundStyle(PulseDesign.labelSecondary)
                .multilineTextAlignment(.center)
            Button("重新同步") {
                Task { await reload(force: true) }
            }
            .font(.system(size: 14))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - 辅助

    private func recoveryColor(_ r: Double) -> Color {
        if r >= 70 { return .green }
        if r >= 45 { return .yellow }
        return .red
    }

    private func recoverySymbol(_ r: Double) -> String {
        if r >= 70 { return "●" }
        if r >= 45 { return "◐" }
        return "○"
    }

    private func reload(force: Bool = false) async {
        loading = true
        if force {
            await DataPipeline.shared.syncNow()
            await DataPipeline.shared.rebuildBaseline()
            await DataPipeline.shared.recomputeDayScoring(dayKey: SleepWindowBuilder.dayKey(for: Date()))
        }
        data = await DataPipeline.shared.overview()
        loading = false
    }
}
