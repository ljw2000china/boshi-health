import SwiftUI

/// 全局主题：渐变背景 / 照片壁纸 / 卡片透明度 / 标题字体。
/// 手机端设置页修改，所有页面即时生效（@AppStorage 持久化）。
public final class ThemeStore: ObservableObject {

    public enum BackgroundStyle: String, CaseIterable, Identifiable {
        case aurora, sunset, ocean, mint, night, mono, photo
        public var id: String { rawValue }
        public var nameZh: String {
            switch self {
            case .aurora: return "极光"
            case .sunset: return "落日"
            case .ocean:  return "海洋"
            case .mint:   return "薄荷"
            case .night:  return "暗夜"
            case .mono:   return "单色"
            case .photo:  return "照片"
            }
        }
    }

    public enum TitleFont: String, CaseIterable, Identifiable {
        case rounded, serif, minimal
        public var id: String { rawValue }
        public var nameZh: String {
            switch self {
            case .rounded: return "圆润"
            case .serif:   return "经典"
            case .minimal: return "极简"
            }
        }
    }

    // 注意：@AppStorage 在 ObservableObject 中不会触发 objectWillChange，
    // 必须用 @Published + 手动持久化（didSet），否则设置改了界面不重绘。
    private let defaults = UserDefaults.standard

    @Published public var background: BackgroundStyle {
        didSet { defaults.set(background.rawValue, forKey: "theme.background") }
    }
    @Published public var cardOpacity: Double {
        didSet { defaults.set(cardOpacity, forKey: "theme.cardOpacity") }
    }
    @Published public var titleFont: TitleFont {
        didSet { defaults.set(titleFont.rawValue, forKey: "theme.titleFont") }
    }

    public init() {
        let bg = BackgroundStyle(rawValue: defaults.string(forKey: "theme.background") ?? "")
        let tf = TitleFont(rawValue: defaults.string(forKey: "theme.titleFont") ?? "")
        _background = Published(initialValue: bg ?? .night)
        _cardOpacity = Published(initialValue: defaults.object(forKey: "theme.cardOpacity") as? Double ?? 0.14)
        _titleFont = Published(initialValue: tf ?? .rounded)
    }

    /// 照片壁纸路径（Documents/pulse_wallpaper.jpg）
    public static var wallpaperURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pulse_wallpaper.jpg")
    }

    public var hasWallpaper: Bool {
        FileManager.default.fileExists(atPath: Self.wallpaperURL.path)
    }

    public func saveWallpaper(_ data: Data) {
        try? data.write(to: Self.wallpaperURL, options: .atomic)
    }

    public func removeWallpaper() {
        try? FileManager.default.removeItem(at: Self.wallpaperURL)
        if background == .photo { background = .night }
    }
}

// MARK: - 卡片透明度（环境注入，pulseCard / PulseLinkCard 使用）

public enum PulseCardOpacityKey: EnvironmentKey {
    public static let defaultValue = 0.14
}

public extension EnvironmentValues {
    var pulseCardOpacity: Double {
        get { self[PulseCardOpacityKey.self] }
        set { self[PulseCardOpacityKey.self] = newValue }
    }
}

// MARK: - 全局背景

public struct ThemeBackgroundView: View {

    @ObservedObject public var theme: ThemeStore

    public init(theme: ThemeStore) { self.theme = theme }

    public var body: some View {
        switch theme.background {
        case .photo:
            if let ui = UIImage(contentsOfFile: ThemeStore.wallpaperURL.path) {
                GeometryReader { geo in
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()          // 自适应铺满
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .overlay(Color.black.opacity(0.28)) // 保证文字可读
                }
                .ignoresSafeArea()
            } else {
                gradientBackground(Self.colors(for: .night))
            }
        default:
            gradientBackground(Self.colors(for: theme.background))
        }
    }

    private func gradientBackground(_ colors: [Color]) -> some View {
        LinearGradient(colors: colors,
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }

    public static func colors(for style: ThemeStore.BackgroundStyle) -> [Color] {
        switch style {
        case .aurora:
            return [Color(red: 0.06, green: 0.16, blue: 0.24),
                    Color(red: 0.12, green: 0.35, blue: 0.42),
                    Color(red: 0.55, green: 0.35, blue: 0.65)]
        case .sunset:
            return [Color(red: 0.35, green: 0.16, blue: 0.24),
                    Color(red: 0.85, green: 0.45, blue: 0.25),
                    Color(red: 0.95, green: 0.65, blue: 0.45)]
        case .ocean:
            return [Color(red: 0.05, green: 0.18, blue: 0.30),
                    Color(red: 0.10, green: 0.40, blue: 0.55),
                    Color(red: 0.35, green: 0.65, blue: 0.75)]
        case .mint:
            return [Color(red: 0.08, green: 0.22, blue: 0.20),
                    Color(red: 0.25, green: 0.55, blue: 0.45),
                    Color(red: 0.65, green: 0.80, blue: 0.70)]
        case .night:
            return [Color(red: 0.07, green: 0.07, blue: 0.10),
                    Color(red: 0.16, green: 0.14, blue: 0.28),
                    Color(red: 0.28, green: 0.20, blue: 0.40)]
        case .mono, .photo:
            return [Color.black, Color.black]
        }
    }
}

// MARK: - 全局背景修饰器（每个页面根上用，保证任何页面都有渐变壁纸）

public struct ThemeBackgroundModifier: ViewModifier {
    @EnvironmentObject private var theme: ThemeStore
    public init() {}
    public func body(content: Content) -> some View {
        ZStack {
            ThemeBackgroundView(theme: theme)
                .ignoresSafeArea()
            content
        }
        // 穿透宿主层：Window / NavigationStack / TabView 都可能画系统底色，
        // 必须让底层背景显式盖掉它们
        .background(ThemeBackgroundView(theme: theme).ignoresSafeArea())
    }
}

public extension View {
    /// 给页面铺全局渐变/照片背景（内部叠在内容之下，整页铺满）
    func themeBackground() -> some View {
        modifier(ThemeBackgroundModifier())
    }
    /// 只给某个视图（通常是 ScrollView）铺背景；用在 NavigationStack 内部，
    /// 否则会被 NavigationStack 自带的不透明层挡住
    func themedSurface() -> some View {
        modifier(ThemedSurfaceModifier())
    }
}

public struct ThemedSurfaceModifier: ViewModifier {
    @EnvironmentObject private var theme: ThemeStore
    public init() {}
    public func body(content: Content) -> some View {
        content.background(ThemeBackgroundView(theme: theme).ignoresSafeArea())
    }
}

// MARK: - 标题胶囊（页面顶部居中的「薄士 / 健身 / 设置」）

public struct PageTitleBar: View {

    @ObservedObject public var theme: ThemeStore
    public let text: String

    public init(text: String, theme: ThemeStore) {
        self.text = text
        self.theme = theme
    }

    public var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(PulseDesign.mainGradient)
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(PulseDesign.mainGradient, lineWidth: 1.4)
            )
            .shadow(color: PulseDesign.accent.opacity(0.35), radius: 8, y: 3)
    }

    private var font: Font {
        switch theme.titleFont {
        case .rounded: return .system(size: 22, weight: .heavy, design: .rounded)
        case .serif:   return .system(size: 22, weight: .bold, design: .serif)
        case .minimal: return .system(size: 20, weight: .semibold)
        }
    }
}
