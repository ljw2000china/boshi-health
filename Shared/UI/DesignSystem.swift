import SwiftUI

/// 全局设计系统：薄士 —— 橙粉渐变 + 圆润粗体 + 毛玻璃 Q 弹卡片
public enum PulseDesign {

    public static let accent  = Color(red: 1.0, green: 0.5, blue: 0.25)   // 活力橙
    public static let accent2 = Color(red: 1.0, green: 0.42, blue: 0.55)  // 蜜桃粉
    public static let mint    = Color(red: 0.35, green: 0.85, blue: 0.7)

    /// 始终清晰可读的文字色（毛玻璃 / 深色背景上也不用灰色，保证对比度）
    public static let labelPrimary   = Color.primary
    public static let labelSecondary = Color.primary.opacity(0.72)
    public static let labelTertiary  = Color.primary.opacity(0.50)

    /// 主按钮渐变（橙 → 粉）
    public static let mainGradient = LinearGradient(
        colors: [accent, accent2],
        startPoint: .leading, endPoint: .trailing)

    /// 大数字标题（圆润 Heavy）
    public static func bigNumber(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// 章节小标签（如「重量 kg」）
    public struct SectionLabel: View {
        let text: String
        public init(_ text: String) { self.text = text }
        public var body: some View {
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 毛玻璃 Q 弹卡片

/// 全局卡片底：ultraThinMaterial 毛玻璃 + 大圆角 + 柔和高光描边 + 细微阴影
/// 透明度由 `EnvironmentValues.pulseCardOpacity` 控制（设置页滑杆调节 0.02–0.6）。
public struct PulseCard: ViewModifier {
    var padding: CGFloat
    var corner: CGFloat = 22
    @Environment(\.pulseCardOpacity) private var cardOpacity
    public init(padding: CGFloat = 16, corner: CGFloat = 22) {
        self.padding = padding; self.corner = corner
    }
    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    // 毛玻璃主体
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.55 + cardOpacity * 0.8)   // 透明度可调
                    // 顶部高光（Q 弹质感）
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(
                            LinearGradient(colors: [Color.white.opacity(0.18),
                                                    Color.white.opacity(0.02)],
                                           startPoint: .top, endPoint: .center)
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.22),
                                                Color.white.opacity(0.05)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)
    }
}

extension View {
    public func pulseCard(padding: CGFloat = 16, corner: CGFloat = 22) -> some View {
        modifier(PulseCard(padding: padding, corner: corner))
    }
}

// MARK: - 主按钮

/// 大号渐变主按钮（最小高度 52，全宽，Q 弹高光）
public struct PulseProminentButton: View {
    let title: String
    let systemImage: String?
    var tint: LinearGradient
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil,
                tint: LinearGradient = PulseDesign.mainGradient,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.2),
                                                      Color.clear],
                                             startPoint: .top, endPoint: .bottom))
                }
            )
            .foregroundStyle(.white)
            .shadow(color: PulseDesign.accent.opacity(0.35), radius: 10, y: 5)
        }
        .buttonStyle(PulseBouncyStyle())
    }
}

/// 次按钮（毛玻璃描边胶囊）
public struct PulseSecondaryButton: View {
    let title: String
    var tint: Color = PulseDesign.accent
    let action: () -> Void
    public init(_ title: String, tint: Color = PulseDesign.accent, action: @escaping () -> Void) {
        self.title = title; self.tint = tint; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(tint.opacity(0.7), lineWidth: 1.4))
                .foregroundStyle(tint)
        }
        .buttonStyle(PulseBouncyStyle())
    }
}

// MARK: - Q 弹按钮风格（按下缩放 + 不透明度变化）

public struct PulseBouncyStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - 导航入口卡片（手机主页用）—— 毛玻璃版

public struct PulseLinkCard<Destination: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let destination: Destination
    @Environment(\.pulseCardOpacity) private var cardOpacity

    public init(icon: String, iconColor: Color = PulseDesign.accent, title: String,
                subtitle: String, @ViewBuilder destination: () -> Destination) {
        self.icon = icon; self.iconColor = iconColor
        self.title = title; self.subtitle = subtitle
        self.destination = destination()
    }

    public var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(iconColor.opacity(0.22))
                        .frame(width: 46, height: 46)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .modifier(GlassCardFill(opacity: cardOpacity))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PulseBouncyStyle())
    }
}

/// 共享毛玻璃填充（PulseLinkCard 等不便用 modifier 的地方）
public struct GlassCardFill: ViewModifier {
    public var opacity: Double
    public init(opacity: Double) { self.opacity = opacity }
    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.55 + opacity * 0.8)
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.16),
                                                      Color.white.opacity(0.02)],
                                             startPoint: .top, endPoint: .center))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.2),
                                                Color.white.opacity(0.05)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.1), radius: 10, y: 5)
    }
}
