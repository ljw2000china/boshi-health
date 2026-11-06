import SwiftUI

/// 每日打卡视图（双端共用）：精力 1–5 + 酸痛 1–5，两步完成。
/// 手表目标 ≤3 次点击：选精力 → 选酸痛 → 自动保存完成。
struct CheckinView: View {

    enum Step { case energy, soreness, done }

    @State private var step: Step = .energy
    @State private var energy: Int?
    @State private var soreness: Int?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue]

    var body: some View {
        VStack(spacing: 16) {
            switch step {
            case .energy:
                stepView(title: "现在精力如何？", value: $energy, isEnergy: true)
            case .soreness:
                stepView(title: "肌肉酸痛如何？", value: $soreness, isEnergy: false)
            case .done:
                doneView
            }
        }
        .padding()
        .themedSurface()
        .navigationTitle("打卡")
        .task {
            // 预填今日已打卡值
            let today = await CheckinService.shared.today()
            if energy == nil { energy = today.energy }
            if soreness == nil { soreness = today.soreness }
        }
    }

    // MARK: - 打卡步骤

    private func stepView(title: String, value: Binding<Int?>, isEnergy: Bool) -> some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        if isEnergy {
                            energy = level
                            step = .soreness
                        } else {
                            soreness = level
                            Task { await save() }
                        }
                    } label: {
                        Text("\(level)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(colors[level - 1].opacity(value.wrappedValue == level ? 1.0 : 0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(stepHint(level: value.wrappedValue, isEnergy: isEnergy))
                .font(.system(size: 14))
                .foregroundStyle(PulseDesign.labelSecondary)
        }
    }

    private func stepHint(level: Int?, isEnergy: Bool) -> String {
        guard let l = level else { return "1 = 很差，5 = 很好" }
        if isEnergy {
            switch l {
            case 1: return "很累"
            case 2: return "比较累"
            case 3: return "一般"
            case 4: return "有精神"
            default: return "精力充沛"
            }
        } else {
            switch l {
            case 1: return "无酸痛"
            case 2: return "轻微"
            case 3: return "中等"
            case 4: return "明显"
            default: return "很酸"
            }
        }
    }

    // MARK: - 完成页

    private var doneView: some View {
        VStack(spacing: 16) {
            if saving {
                ProgressView("保存中…")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("已记录")
                    .font(.headline)
                HStack(spacing: 20) {
                    VStack {
                        Text("精力")
                            .font(.system(size: 14))
                            .foregroundStyle(PulseDesign.labelSecondary)
                        Text("\(energy ?? 0)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                    }
                    VStack {
                        Text("酸痛")
                            .font(.system(size: 14))
                            .foregroundStyle(PulseDesign.labelSecondary)
                        Text("\(soreness ?? 0)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                    }
                }
                Button("完成") {
                    dismiss()
                }
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - 逻辑

    private func save() async {
        guard !saving else { return }
        saving = true
        if let e = energy { await CheckinService.shared.checkinEnergy(e) }
        if let s = soreness { await CheckinService.shared.checkinSoreness(s) }
        saving = false
        step = .done
    }
}
