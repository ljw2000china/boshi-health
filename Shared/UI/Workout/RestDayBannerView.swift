import SwiftUI

/// 焦点横幅动画：点按后表情放大，2.5s 匀速滚出屏幕左侧（自身同时旋转），
/// 停 0.5s，再 2.5s 滚回原位。表情滚到哪儿文字被擦到哪儿，回程逐段重显。
/// 期间整卡上下震动；结束后表情回缩、副标题随机换一句文案。
/// 休息日与训练日共用（手机 / 手表一致）。
public struct RestDayBannerView: View {

    public let title: String
    public let emoji: String
    public let subtitle: String
    public var onNewSubtitle: (Int) -> String

    private let outDuration: Double = 2.5   // 滚出
    private let holdDuration: Double = 0.5  // 出框停留
    private let backDuration: Double = 2.5  // 滚回

    @State private var travel: CGFloat = 0      // 表情左移量（0 = 静止右侧）
    @State private var running = false
    @State private var offsetY: CGFloat = 0
    @State private var currentSubtitle: String

    public init(title: String, emoji: String, subtitle: String,
                onNewSubtitle: @escaping (Int) -> String) {
        self.title = title
        self.emoji = emoji
        self.subtitle = subtitle
        self.onNewSubtitle = onNewSubtitle
        _currentSubtitle = State(initialValue: subtitle)
    }

    public var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                ScrollTextReveal(text: currentSubtitle,
                                 sweep: revealSweep,
                                 editing: running)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PulseDesign.labelSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            // 表情：右侧静止；动画时放大、左移出框、自身旋转
            Text(emoji)
                .font(.system(size: emojiSize))
                .shadow(color: .black.opacity(0.3), radius: running ? 6 : 2, y: 2)
                .rotationEffect(.degrees(rotationDeg))
                .offset(x: travel)
                .padding(.trailing, emojiInset)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, cardVPad)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))   // 圆角裁剪：表情滚到边缘自然消失
        .modifier(glass)                                                     // 玻璃底色画在最里面内容之上
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { run() }
        .offset(y: offsetY)
        .animation(.linear(duration: 0.05), value: offsetY)
        .accessibilityLabel("\(title)，\(currentSubtitle)。点按看表情滚过去换一句")
    }

    // MARK: - 动画

    private var rotated: Bool { running }

    /// 表情自身旋转：去程和回程都持续旋转（回程反向）
    private var rotationDeg: Double {
        running ? -Double(travel) * 1.2 : 0
    }

    /// 文字擦除进度：去程 travel 0→-(全宽+表情) 时 0→1；回程反向
    private var revealSweep: CGFloat {
        let full = fullTravel()
        guard full > 0, running else { return 0 }
        return max(0, min(1, -travel / full))
    }

    private func run() {
        guard !running else { return }
        running = true
        currentSubtitle = onNewSubtitle(Int.random(in: 0...Int.max))
        travel = 0

        // 去程：2.5s 匀速滚出左框
        withAnimation(.linear(duration: outDuration)) {
            travel = -fullTravel()
        }

        // 停 0.5s
        let holdAt = outDuration + holdDuration

        // 回程：2.5s 滚回原位
        DispatchQueue.main.asyncAfter(deadline: .now() + holdAt) {
            withAnimation(.linear(duration: backDuration)) {
                travel = 0
            }
        }

        vibrate(total: outDuration + holdDuration + backDuration)

        DispatchQueue.main.asyncAfter(deadline: .now() + outDuration + holdDuration + backDuration) {
            running = false
            offsetY = 0
        }
    }

    /// 完全滚出左框所需位移：容器宽 + 表情直径（额外冗余，确保彻底出框）
    private func fullTravel() -> CGFloat {
        #if os(iOS)
        UIScreen.main.bounds.width + emojiSize * 2
        #else
        200 + emojiSize * 2
        #endif
    }

    // MARK: - 震动

    private func vibrate(total: Double) {
        let step = 0.06
        let n = Int(total / step)
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let amp: CGFloat = t < 0.6 ? 3 : (t < 0.85 ? 2 : (t < 0.95 ? 1 : 0))
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * step) {
                offsetY = amp * (i.isMultiple(of: 2) ? -1 : 1) * 0.5
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { offsetY = 0 }
    }

    // MARK: - 尺寸

    private var emojiSize: CGFloat {
        (running ? 1.22 : 1) * (isWatch ? 30 : 36)
    }

    private var emojiInset: CGFloat {
        isWatch ? 8 : 14
    }

    private var cardVPad: CGFloat {
        isWatch ? 8 : 14
    }

    private var titleSize: CGFloat {
        isWatch ? 19 : 24
    }

    private var isWatch: Bool {
        #if os(watchOS)
        true
        #else
        false
        #endif
    }

    private var glass: GlassCardFill { GlassCardFill(opacity: 0.14) }
}

/// 跑马灯文字：sweep 0→1 自右向左逐段隐藏，回程（1→0）逐步重新显示。
private struct ScrollTextReveal: View {
    let text: String
    let sweep: CGFloat
    let editing: Bool

    private var maskFraction: CGFloat {
        guard editing else { return 1 }
        return max(0.06, min(1, 1 - sweep * 0.85))
    }

    var body: some View {
        Text(text)
            .lineLimit(1)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
            .mask(
                GeometryReader { geo in
                    Rectangle()
                        .fill(.black)
                        .frame(width: geo.size.width * maskFraction)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .animation(.linear(duration: 2.5), value: maskFraction)
                }
            )
    }
}