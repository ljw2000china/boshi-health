import SwiftUI
#if os(watchOS)
import WatchKit
#endif

/// 组间休息全屏页：倒计时圆环 + 跑步小人动画 + 提前结束。
public struct RestTimerView: View {
    let exerciseName: String
    let totalSec: Int
    let nextSetText: String
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var endDate: Date
    @State private var startDate = Date()
    @State private var finished = false
    @State private var lastBeepSecond = -1

    public init(exerciseName: String, totalSec: Int, nextSetText: String,
                onFinished: @escaping () -> Void) {
        self.exerciseName = exerciseName
        self.totalSec = totalSec
        self.nextSetText = nextSetText
        self.onFinished = onFinished
        _endDate = State(initialValue: Date().addingTimeInterval(TimeInterval(totalSec)))
    }

    public var body: some View {
        TimelineView(.periodic(from: startDate, by: 0.25)) { ctx in
            let remaining = max(0, endDate.timeIntervalSince(ctx.date))
            let progress = totalSec > 0 ? remaining / Double(totalSec) : 0

            VStack(spacing: 8) {
                Text(exerciseName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ZStack {
                    // 背景环
                    Circle()
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 10)
                    // 倒计时环
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            AngularGradient(colors: [.cyan, .mint, .cyan],
                                            center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: progress)

                    VStack(spacing: 0) {
                        Text(timeText(remaining))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("休息中")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 148, height: 148)
                .padding(.vertical, 2)

                RunnerAnimation(startDate: startDate)
                    .frame(height: 34)

                Text(nextSetText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Button {
                    finish()
                } label: {
                    Text("提前结束")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .onChange(of: Int(remaining.rounded())) { _, sec in
                // 最后 3 秒提示音（每档只响一次）
                if sec <= 3 && sec > 0 && sec != lastBeepSecond {
                    lastBeepSecond = sec
                    playTick()
                }
            }
        }
        .task {
            // 到点自动结束
            while !finished {
                if endDate.timeIntervalSinceNow <= 0 {
                    playDone()
                    finish()
                    return
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
        dismiss()
    }

    private func timeText(_ sec: TimeInterval) -> String {
        let s = Int(sec.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func playTick() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }

    private func playDone() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }
}

/// 可爱跑步小人：左右晃动 + 弹跳 + 地面滚动
struct RunnerAnimation: View {
    let startDate: Date

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let t = ctx.date.timeIntervalSince(startDate)
            let x = sin(t * 3.2) * 14
            let hop = -abs(sin(t * 6.4)) * 7
            let phase = t * 40

            ZStack {
                // 地面虚线滚动
                HStack(spacing: 6) {
                    ForEach(0..<9, id: \.self) { i in
                        Capsule()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 6, height: 2)
                            .offset(x: CGFloat((Double(i) * 12 - phase.truncatingRemainder(dividingBy: 12))))
                    }
                }
                .frame(width: 120, height: 2)
                .offset(y: 16)

                Image(systemName: "figure.run")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.mint)
                    .offset(x: x, y: hop)
                // 汗滴/动力小星
                Image(systemName: "sparkle")
                    .font(.system(size: 9))
                    .foregroundStyle(.cyan.opacity(0.8))
                    .offset(x: x + 18, y: hop - 14 + sin(t * 5) * 2)
            }
        }
    }
}
