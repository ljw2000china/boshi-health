import SwiftUI

/// 重量数字：整数大号、小数位缩小，避免 "22.5" 被截断或换行
struct BigNumberText: View {
    let value: Double
    var fontSize: CGFloat = 44

    private var wholePart: Int { Int(value) }
    private var fracDigit: Int { Int(((value - Double(wholePart)) * 10).rounded()) }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text("\(wholePart)")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
            if fracDigit > 0 {
                Text(".\(fracDigit)")
                    .font(.system(size: fontSize * 0.55, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .contentTransition(.numericText())
    }
}

/// 数值调节控件：− 数字 ＋（48pt 按钮，大数字显示，数字可点击直接输入）
struct QuantityControl: View {
    let title: String
    @Binding var value: Double
    let step: Double
    let range: ClosedRange<Double>
    /// 次数模式：显示整数
    var isCount: Bool = false
    /// 点按数字（弹出数字键盘，由父级呈现）
    var onEdit: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button { value = max(range.lowerBound, value - step) } label: {
                    Image(systemName: "minus")
                        .font(.title3.weight(.bold))
                        .frame(width: 48, height: 48)
                        .background(Color.secondary.opacity(0.14), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 2)

                Button {
                    if let onEdit { onEdit() }
                } label: {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        if isCount {
                            Text("\(Int(value))")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.4)
                                .contentTransition(.numericText())
                        } else {
                            BigNumberText(value: value, fontSize: 40)
                        }
                        if onEdit != nil {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(minWidth: 0)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onEdit == nil)

                Spacer(minLength: 2)

                Button { value = min(range.upperBound, value + step) } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.bold))
                        .frame(width: 48, height: 48)
                        .background(PulseDesign.mainGradient, in: Circle())
                        .foregroundStyle(.white)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 圆形退出箭头（左上角，换动作/返回）
struct CircularBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(Color.secondary.opacity(0.2), in: Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }
}
