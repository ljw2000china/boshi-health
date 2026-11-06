import SwiftUI

/// 滑动手势行：向左滑露出「编辑 / 删除」大按钮（上下占满行高、圆角胶囊形），
/// 向右滑只有轻微位移（渐近阻尼，越滑越少），松手回弹。
/// 内容层背景**不透明**，彻底遮挡按钮，未滑动时看不到任何按钮颜色。
public struct SwipeActionsRow<Content: View>: View {

    public let onEdit: (() -> Void)?
    public let onDelete: (() -> Void)?
    public let onTap: (() -> Void)?
    public let corner: CGFloat
    @ViewBuilder public let content: () -> Content

    @Environment(\.colorScheme) private var scheme
    @State private var offset: CGFloat = 0
    @State private var isOpen = false
    @State private var dragging = false
    @State private var dragStart: CGFloat = 0

    private let buttonWidth: CGFloat = 88
    private let buttonGap: CGFloat = 7
    private let rightLimit: CGFloat = 24

    private var actionsWidth: CGFloat {
        let count = (onEdit != nil ? 1 : 0) + (onDelete != nil ? 1 : 0)
        return CGFloat(count) * buttonWidth + CGFloat(max(count - 1, 0)) * buttonGap
    }

    public init(onEdit: (() -> Void)? = nil,
                onDelete: (() -> Void)? = nil,
                onTap: (() -> Void)? = nil,
                corner: CGFloat = 14,
                @ViewBuilder content: @escaping () -> Content) {
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onTap = onTap
        self.corner = corner
        self.content = content
    }

    public var body: some View {
        ZStack(alignment: .trailing) {
            // ── 按钮层（右侧排列，圆角胶囊，间距清晰）
            HStack(spacing: buttonGap) {
                if let onEdit {
                    actionButton(title: "编辑", icon: "square.and.pencil",
                                 tint: PulseDesign.accent) {
                        snap(0); onEdit()
                    }
                }
                if let onDelete {
                    actionButton(title: "删除", icon: "trash.fill",
                                 tint: Color(red: 0.92, green: 0.28, blue: 0.28)) {
                        snap(0); onDelete()
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.trailing, 0)

            // ── 内容层（不透明背景，完全遮挡按钮）
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(opaqueCardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.14 : 0.7),
                                                    Color.white.opacity(scheme == .dark ? 0.04 : 0.3)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                .offset(x: offset)
                .gesture(swipeGesture)
                .onTapGesture {
                    if isOpen { snap(0) } else { onTap?() }
                }
        }
        .frame(maxWidth: .infinity)
    }

    /// 不透明卡片底色（深色模式深灰，浅色模式浅灰），确保按钮不透出
    private var opaqueCardFill: Color {
        scheme == .dark
            ? Color(red: 0.16, green: 0.16, blue: 0.20)
            : Color(red: 0.94, green: 0.94, blue: 0.97)
    }

    // MARK: - 按钮（圆角矩形，上下占满）

    private func actionButton(title: String, icon: String, tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(width: buttonWidth)
            .frame(maxHeight: .infinity)
            .background(
                LinearGradient(colors: [tint, tint.opacity(0.78)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: corner - 2, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: corner - 2, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: - 手势

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { v in
                if !dragging {
                    dragging = true
                    dragStart = offset
                }
                withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.9)) {
                    offset = resisted(dragStart + v.translation.width)
                }
            }
            .onEnded { v in
                dragging = false
                let projected = offset + resisted(v.predictedEndTranslation.width - v.translation.width) * 0.3
                if projected <= -actionsWidth * 0.38 {
                    snap(-actionsWidth)
                    isOpen = true
                } else {
                    snap(0)
                    isOpen = false
                }
            }
    }

    /// 左滑：超过按钮宽度后强阻尼；右滑：渐近式阻尼（越滑越少，上限很小）
    private func resisted(_ raw: CGFloat) -> CGFloat {
        if raw < 0 {
            let over = -raw - actionsWidth
            return over <= 0 ? raw : -actionsWidth - over * 0.12
        }
        return rightLimit * (raw / (raw + 55))
    }

    private func snap(_ x: CGFloat) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            offset = x
            if x == 0 { isOpen = false }
        }
    }
}
