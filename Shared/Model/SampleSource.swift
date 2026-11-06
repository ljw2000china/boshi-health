import Foundation

/// 样本来源标记（design.md §3）：所有写入/派生数据必须标记来源。
public enum SampleSource: String, Codable, CaseIterable {
    case system     // HealthKit 系统采集
    case extended   // App 延伸判定（如睡眠窗口延伸）
    case override   // 用户手动修正
    case auto       // 自动检测产生（训练）
    case manual     // 用户手动记录
    case native     // 系统健身 App 产生（只读引用）
    case inferred   // L0 活动信号推测（无系统睡眠分期时的兜底）

    /// 中文展示名
    public var displayName: String {
        switch self {
        case .system:   return "系统采集"
        case .extended: return "延伸判定"
        case .override: return "手动修正"
        case .auto:     return "自动检测"
        case .manual:   return "手动记录"
        case .native:   return "系统健身"
        case .inferred: return "活动推测"
        }
    }
}
