import SwiftUI

/// 数字输入面板：点击重量/次数数字后弹出，支持 0–999 整数 + 可选 .5。
/// watchOS 用 fullScreenCover 呈现，iOS 用 sheet。
public struct NumericPadView: View {
    let title: String
    let unit: String
    let maxValue: Int
    let allowsHalf: Bool
    var onConfirm: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var digits: String = ""
    @State private var half: Bool = false

    public init(title: String, unit: String = "kg", initial: Double,
                maxValue: Int = 999, allowsHalf: Bool = true,
                onConfirm: @escaping (Double) -> Void) {
        self.title = title
        self.unit = unit
        self.maxValue = maxValue
        self.allowsHalf = allowsHalf
        self.onConfirm = onConfirm
        var v = initial
        let isHalf = allowsHalf && (v.truncatingRemainder(dividingBy: 1) == 0.5)
        if isHalf { v -= 0.5 }
        _digits = State(initialValue: String(Int(v)))
        _half = State(initialValue: isHalf)
    }

    private var value: Double {
        let base = Double(Int(digits) ?? 0)
        return half ? base + 0.5 : base
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 预览区
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(digits.isEmpty ? "0" : digits)
                        .font(PulseDesign.bigNumber(52))
                        .contentTransition(.numericText())
                    if half {
                        Text(".5")
                            .font(PulseDesign.bigNumber(52))
                    }
                    Text(unit)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 64)
            }
            .padding(.top, 8)

            // 数字键盘（宽松布局）
            let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(1...9, id: \.self) { n in
                    padKey(Text(String(n))) { appendDigit(n) }
                }
                padKey(Image(systemName: "delete.left")) {
                    if !digits.isEmpty { digits.removeLast() }
                }
                padKey(Text("0")) { appendDigit(0) }
                padKey(Text(half ? ".5 ✓" : ".5")) {
                    if allowsHalf { half.toggle() }
                }
                .opacity(allowsHalf ? 1 : 0.25)
                .disabled(!allowsHalf)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            PulseProminentButton("确定 \(displayValue)\(unit)") {
                onConfirm(value)
                dismiss()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        #if os(watchOS)
        .containerBackground(.fill.tertiary, for: .navigation)
        #else
        .presentationDetents([.fraction(0.72)])
        #endif
    }

    private var displayValue: String {
        if allowsHalf && half { return "\(Int(value)).5" }
        return "\(Int(value))"
    }

    private func padKey<V: View>(_ content: V, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            content
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
                .background(Color.secondary.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func appendDigit(_ n: Int) {
        let next = digits.isEmpty ? String(n) : digits + String(n)
        guard (Int(next) ?? 0) <= maxValue else { return }
        // 不允许前导零
        if digits == "0" { digits = String(n) } else { digits = next }
    }
}
