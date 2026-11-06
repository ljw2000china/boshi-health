import SwiftUI

/// 动作示意图：按肌群画一个 Q 版小人做典型动作（离线、无图片依赖）
/// 胸=推 / 背=拉 / 腿=深蹲 / 肩=侧平举 / 臂=弯举 / 核心=平板 / 有氧=跑步
public struct ExerciseIllustrationView: View {
    let muscleGroup: String
    var tint: Color = PulseDesign.accent

    public init(muscleGroup: String, tint: Color = PulseDesign.accent) {
        self.muscleGroup = muscleGroup
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.12))
            Canvas { ctx, size in
                let scale = min(size.width, size.height) / 120
                ctx.translateBy(x: (size.width - 100 * scale) / 2,
                                y: (size.height - 120 * scale) / 2)
                ctx.scaleBy(x: scale, y: scale)
                draw(muscleGroup, ctx: &ctx)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("\(muscleGroup)动作示意图")
    }

    // MARK: - 绘制

    private func stroke(_ ctx: inout GraphicsContext, _ pts: [CGPoint],
                        width: CGFloat, color: Color) {
        guard pts.count > 1 else { return }
        var p = Path()
        p.move(to: pts[0])
        for q in pts.dropFirst() { p.addLine(to: q) }
        ctx.stroke(p, with: .color(color),
                   style: .init(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func head(_ ctx: inout GraphicsContext, center: CGPoint, r: CGFloat, color: Color) {
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(color))
    }

    private func motionLines(_ ctx: inout GraphicsContext, near p: CGPoint) {
        for i in 0..<3 {
            let off = CGFloat(i) * 7
            let rect = CGRect(x: p.x - 14 - off, y: p.y - 10 - off,
                              width: 20 + off * 2, height: 20 + off * 2)
            var arc = Path()
            arc.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                       startAngle: .degrees(-50), endAngle: .degrees(50), clockwise: false)
            ctx.stroke(arc, with: .color(.secondary.opacity(0.6 - Double(i) * 0.15)),
                       style: .init(lineWidth: 2, lineCap: .round))
        }
    }

    private func draw(_ group: String, ctx: inout GraphicsContext) {
        let skin = Color.primary
        switch group {
        case "胸": drawPush(ctx: &ctx, skin: skin)
        case "背": drawRow(ctx: &ctx, skin: skin)
        case "腿": drawSquat(ctx: &ctx, skin: skin)
        case "肩": drawRaise(ctx: &ctx, skin: skin)
        case "臂": drawCurl(ctx: &ctx, skin: skin)
        case "核心": drawPlank(ctx: &ctx, skin: skin)
        default: drawRun(ctx: &ctx, skin: skin)   // 有氧及其他
        }
    }

    // 胸：侧身前推
    private func drawPush(ctx: inout GraphicsContext, skin: Color) {
        head(&ctx, center: CGPoint(x: 42, y: 26), r: 11, color: skin)
        stroke(&ctx, [CGPoint(x: 44, y: 40), CGPoint(x: 48, y: 78)], width: 9, color: skin)          // 躯干
        stroke(&ctx, [CGPoint(x: 48, y: 78), CGPoint(x: 66, y: 110)], width: 7, color: skin)        // 前腿
        stroke(&ctx, [CGPoint(x: 48, y: 78), CGPoint(x: 28, y: 110)], width: 7, color: skin)        // 后腿
        stroke(&ctx, [CGPoint(x: 46, y: 46), CGPoint(x: 76, y: 46)], width: 7, color: skin)        // 前推手臂
        stroke(&ctx, [CGPoint(x: 46, y: 46), CGPoint(x: 72, y: 58)], width: 7, color: skin)
        motionLines(&ctx, near: CGPoint(x: 90, y: 48))
    }

    // 背：俯身划船
    private func drawRow(ctx: inout GraphicsContext, skin: Color) {
        head(&ctx, center: CGPoint(x: 30, y: 34), r: 11, color: skin)
        stroke(&ctx, [CGPoint(x: 36, y: 44), CGPoint(x: 54, y: 76)], width: 9, color: skin)          // 前倾躯干
        stroke(&ctx, [CGPoint(x: 54, y: 76), CGPoint(x: 42, y: 110)], width: 7, color: skin)
        stroke(&ctx, [CGPoint(x: 54, y: 76), CGPoint(x: 68, y: 110)], width: 7, color: skin)
        stroke(&ctx, [CGPoint(x: 44, y: 50), CGPoint(x: 64, y: 70)], width: 7, color: skin)         // 拉动手臂
        stroke(&ctx, [CGPoint(x: 44, y: 50), CGPoint(x: 60, y: 58)], width: 7, color: skin)
        motionLines(&ctx, near: CGPoint(x: 74, y: 58))
    }

    // 腿：深蹲
    private func drawSquat(ctx: inout GraphicsContext, skin: Color) {
        head(&ctx, center: CGPoint(x: 50, y: 30), r: 11, color: skin)
        stroke(&ctx, [CGPoint(x: 50, y: 44), CGPoint(x: 50, y: 74)], width: 9, color: skin)         // 躯干
        stroke(&ctx, [CGPoint(x: 50, y: 74), CGPoint(x: 30, y: 90), CGPoint(x: 28, y: 112)], width: 7, color: skin) // 屈膝腿
        stroke(&ctx, [CGPoint(x: 50, y: 74), CGPoint(x: 70, y: 90), CGPoint(x: 72, y: 112)], width: 7, color: skin)
        stroke(&ctx, [CGPoint(x: 50, y: 50), CGPoint(x: 72, y: 44)], width: 7, color: skin)         // 前平举手臂
        stroke(&ctx, [CGPoint(x: 50, y: 50), CGPoint(x: 28, y: 44)], width: 7, color: skin)
        motionLines(&ctx, near: CGPoint(x: 84, y: 42))
    }

    // 肩：侧平举
    private func drawRaise(ctx: inout GraphicsContext, skin: Color) {
        head(&ctx, center: CGPoint(x: 50, y: 26), r: 11, color: skin)
        stroke(&ctx, [CGPoint(x: 50, y: 40), CGPoint(x: 50, y: 80)], width: 9, color: skin)
        stroke(&ctx, [CGPoint(x: 50, y: 80), CGPoint(x: 38, y: 112)], width: 7, color: skin)
        stroke(&ctx, [CGPoint(x: 50, y: 80), CGPoint(x: 62, y: 112)], width: 7, color: skin)
        stroke(&ctx, [CGPoint(x: 50, y: 46), CGPoint(x: 18, y: 54)], width: 7, color: skin)         // 侧平举
        stroke(&ctx, [CGPoint(x: 50, y: 46), CGPoint(x: 82, y: 54)], width: 7, color: skin)
        motionLines(&ctx, near: CGPoint(x: 12, y: 44))
        motionLines(&ctx, near: CGPoint(x: 88, y: 44))
    }

    // 臂：弯举
    private func drawCurl(ctx: inout GraphicsContext, skin: Color) {
        head(&ctx, center: CGPoint(x: 50, y: 24), r: 11, color: skin)
        stroke(&ctx, [CGPoint(x: 50, y: 38), CGPoint(x: 50, y: 78)], width: 9, color: skin)
        stroke(&ctx, [CGPoint(x: 50, y: 78), CGPoint(x: 40, y: 110)], width: 7, color: skin)
        stroke(&ctx, [CGPoint(x: 50, y: 78), CGPoint(x: 60, y: 110)], width: 7, color: skin)
        stroke(&ctx, [CGPoint(x: 50, y: 44), CGPoint(x: 30, y: 66)], width: 7, color: skin)         // 左臂垂下
        stroke(&ctx, [CGPoint(x: 50, y: 44), CGPoint(x: 70, y: 64), CGPoint(x: 56, y: 60)], width: 7, color: skin) // 弯举
        ctx.fill(Path(roundedRect: CGRect(x: 48, y: 50, width: 16, height: 8), cornerRadius: 3), with: .color(.secondary))         // 哑铃
    }

    // 核心：平板支撑（侧视）
    private func drawPlank(ctx: inout GraphicsContext, skin: Color) {
        head(&ctx, center: CGPoint(x: 22, y: 66), r: 10, color: skin)
        stroke(&ctx, [CGPoint(x: 30, y: 70), CGPoint(x: 78, y: 64)], width: 9, color: skin)         // 身体
        stroke(&ctx, [CGPoint(x: 78, y: 64), CGPoint(x: 98, y: 70)], width: 7, color: skin)         // 腿
        stroke(&ctx, [CGPoint(x: 34, y: 74), CGPoint(x: 34, y: 96)], width: 7, color: skin)         // 前臂支撑
        stroke(&ctx, [CGPoint(x: 10, y: 100), CGPoint(x: 96, y: 100)], width: 3, color: .secondary) // 地面
    }

    // 有氧：跑步
    private func drawRun(ctx: inout GraphicsContext, skin: Color) {
        head(&ctx, center: CGPoint(x: 46, y: 24), r: 11, color: skin)
        stroke(&ctx, [CGPoint(x: 50, y: 38), CGPoint(x: 58, y: 72)], width: 9, color: skin)
        stroke(&ctx, [CGPoint(x: 58, y: 72), CGPoint(x: 76, y: 88), CGPoint(x: 74, y: 110)], width: 7, color: skin) // 前腿抬膝
        stroke(&ctx, [CGPoint(x: 58, y: 72), CGPoint(x: 38, y: 108)], width: 7, color: skin)                        // 后腿
        stroke(&ctx, [CGPoint(x: 52, y: 44), CGPoint(x: 70, y: 58), CGPoint(x: 84, y: 48)], width: 7, color: skin) // 摆臂
        stroke(&ctx, [CGPoint(x: 52, y: 44), CGPoint(x: 34, y: 62)], width: 7, color: skin)
        motionLines(&ctx, near: CGPoint(x: 22, y: 40))
    }
}
