import SwiftUI

/// 半透明人体图：正面（胸/肩/臂/核心/腿）+ 背面（背/肩/臂/腿）。
/// 已训练肌群按本周组数强度变红（透明度 0.2 → 0.85）。
public struct BodyMapView: View {
    /// 肌群 → 0–1 强度
    let intensity: (String) -> Double
    var muscleSets: [String: Int] = [:]

    public init(muscleSets: [String: Int], intensity: @escaping (String) -> Double) {
        self.muscleSets = muscleSets
        self.intensity = intensity
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                silhouette(back: false)
                    .frame(maxWidth: .infinity)
                silhouette(back: true)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 190)

            HStack(spacing: 3) {
                Text("正面")
                Spacer()
                Text("背面")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if !muscleSets.isEmpty {
                legend
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 4) {
            ForEach(["胸", "背", "腿", "肩", "臂", "核心"], id: \.self) { m in
                let n = muscleSets[m] ?? 0
                HStack(spacing: 2) {
                    Circle()
                        .fill(n > 0 ? Color.red.opacity(0.35 + 0.5 * intensity(m))
                                    : Color.secondary.opacity(0.25))
                        .frame(width: 7, height: 7)
                    Text("\(m)\(n > 0 ? "\(n)" : "")")
                        .font(.system(size: 10))
                        .foregroundStyle(n > 0 ? .primary : .secondary)
                }
            }
        }
    }

    // MARK: - 人体轮廓

    private func fill(_ muscle: String) -> Color {
        let i = intensity(muscle)
        guard (muscleSets[muscle] ?? 0) > 0 else { return Color.secondary.opacity(0.12) }
        return Color.red.opacity(0.18 + 0.62 * i)
    }

    private func stroke(_ muscle: String) -> Color {
        (muscleSets[muscle] ?? 0) > 0 ? Color.red.opacity(0.55) : Color.secondary.opacity(0.18)
    }

    private func region(_ muscle: String, x: CGFloat, y: CGFloat,
                        w: CGFloat, h: CGFloat, r: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: r)
            .fill(fill(muscle))
            .overlay(RoundedRectangle(cornerRadius: r).stroke(stroke(muscle), lineWidth: 0.7))
            .frame(width: w, height: h)
            .offset(x: x - 50, y: y - 110)
    }

    private func silhouette(back: Bool) -> some View {
        ZStack {
            // 头部 + 躯干底
            Circle()
                .fill(Color.secondary.opacity(0.10))
                .frame(width: 24, height: 24)
                .offset(y: -94)
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
                .frame(width: 44, height: 86)
                .offset(y: -24)
            // 脖子
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.10))
                .frame(width: 12, height: 10)
                .offset(y: -76)

            if back {
                region("背", x: 50, y: 72, w: 38, h: 54, r: 8)
                region("肩", x: 28, y: 46, w: 16, h: 16, r: 8)
                region("肩", x: 72, y: 46, w: 16, h: 16, r: 8)
                region("臂", x: 21, y: 82, w: 13, h: 52, r: 6)
                region("臂", x: 79, y: 82, w: 13, h: 52, r: 6)
                region("腿", x: 41, y: 148, w: 15, h: 60, r: 7)
                region("腿", x: 59, y: 148, w: 15, h: 60, r: 7)
            } else {
                region("胸", x: 50, y: 66, w: 36, h: 26, r: 7)
                region("肩", x: 28, y: 46, w: 16, h: 16, r: 8)
                region("肩", x: 72, y: 46, w: 16, h: 16, r: 8)
                region("核心", x: 50, y: 96, w: 32, h: 30, r: 6)
                region("臂", x: 21, y: 82, w: 13, h: 52, r: 6)
                region("臂", x: 79, y: 82, w: 13, h: 52, r: 6)
                region("腿", x: 41, y: 148, w: 15, h: 60, r: 7)
                region("腿", x: 59, y: 148, w: 15, h: 60, r: 7)
            }
        }
        .frame(width: 100, height: 220)
        .scaleEffect(0.82)
    }
}
