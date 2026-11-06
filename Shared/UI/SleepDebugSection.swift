import SwiftUI

/// 睡眠调试区块（双端共用）：今晚窗口 / 评分 / 置信度 + 手动重算。
/// M1 验证用；产品化展示在 M2 概览页。
struct SleepDebugSection: View {

    @State private var summary: DataPipeline.SleepSummary?
    @State private var loading = false
    @State private var loaded = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("今晚睡眠")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                confidenceBadge
            }
            if loading && summary == nil {
                ProgressView()
            } else if let s = summary {
                Text("\(Self.timeFormatter.string(from: s.start)) – \(Self.timeFormatter.string(from: s.end))")
                    .font(.system(size: 20, weight: .semibold))
                    .fontDesign(.rounded)
                HStack(spacing: 14) {
                    metric("时长", String(format: "%.1f h", s.durationMin / 60))
                    metric("效率", String(format: "%.0f%%", s.efficiency * 100))
                    metric("评分", s.score.map { "\(Int($0))" } ?? "标定期")
                }
                Text(sourceText(s))
                    .font(.system(size: 14))
                    .foregroundStyle(PulseDesign.labelSecondary)
                if let n = noteText(s) {
                    Text(n)
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                }
            } else {
                Text("暂无睡眠窗口（等待数据或授权）")
                    .font(.system(size: 14))
                    .foregroundStyle(PulseDesign.labelSecondary)
            }
            Button {
                Task { await reload(force: true) }
            } label: {
                Text(loading ? "重算中…" : "重新计算")
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(loading)
        }
        .task {
            guard !loaded else { return }
            loaded = true
            await reload(force: false)
        }
    }

    // MARK: - 子视图

    private var confidenceBadge: some View {
        let conf = summary?.confidence ?? 0
        let symbol = conf >= 0.8 ? "●" : (conf >= 0.5 ? "◐" : "○")
        let color: Color = conf >= 0.8 ? .green : (conf >= 0.5 ? .orange : .red)
        return Text(symbol)
            .font(.system(size: 16))
            .foregroundStyle(color)
            .accessibilityLabel("数据置信度 \(Int(conf * 100))%")
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(PulseDesign.labelSecondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .fontDesign(.rounded)
        }
    }

    private func sourceText(_ s: DataPipeline.SleepSummary) -> String {
        var parts: [String] = []
        switch s.source {
        case SampleSource.extended.rawValue: parts.append("含自动延伸")
        case SampleSource.override.rawValue: parts.append("已手动修正")
        case SampleSource.inferred.rawValue: parts.append("活动推测（未使用系统分期）")
        default: parts.append("系统原生窗口")
        }
        parts.append("v\(s.version)")
        if s.l2FailCount > 0 { parts.append("延伸判定失败 \(s.l2FailCount) 次\(s.l2Locked ? "（已锁定）" : "")") }
        if !s.confidenceReason.isEmpty { parts.append("置信度：\(s.confidenceReason)") }
        return parts.joined(separator: " · ")
    }

    private func noteText(_ s: DataPipeline.SleepSummary) -> String? {
        s.note.isEmpty ? nil : s.note
    }

    private func reload(force: Bool) async {
        loading = true
        if force {
            await DataPipeline.shared.syncNow()
        }
        summary = await DataPipeline.shared.sleepSummary()
        loading = false
    }
}
