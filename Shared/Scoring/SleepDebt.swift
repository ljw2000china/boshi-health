import Foundation

/// 睡眠需求与睡眠债（design.md §9）：
/// SleepNeed = 7.5h + 0.3·睡眠债 + 每 100 TRIMP +5min
/// 睡眠债 = Σ(近 14 天 SleepNeed − 实际睡眠)，只累计正缺口，上限 10h（防爆炸）。
public enum SleepDebt {

    public static let baseNeedHours: Double = 7.5
    public static let debtFactor: Double = 0.3
    public static let trimpBonusPer100: Double = 5.0 / 60.0 // 每小时
    public static let maxDebtHours: Double = 10
    public static let debtWindowDays = 14

    /// 单日睡眠需求（小时）
    public static func sleepNeedHours(debtHours: Double, trimp: Double) -> Double {
        baseNeedHours + debtFactor * max(0, debtHours) + (trimp / 100) * trimpBonusPer100
    }

    /// 睡眠债（小时）：按天累计正缺口
    /// - parameters:
    ///   - actualHours: 最近 N 天实际睡眠（今天在前，升序/降序无所谓，长度即天数）
    ///   - needHours: 对应每天的需求（缺省用 baseNeedHours）
    public static func debtHours(actualHours: [Double], needHours: [Double]? = nil) -> Double {
        let n = min(actualHours.count, debtWindowDays)
        guard n > 0 else { return 0 }
        var debt = 0.0
        for i in 0..<n {
            let need = needHours?.count == actualHours.count ? needHours![i] : baseNeedHours
            debt += max(0, need - actualHours[i])
        }
        return min(maxDebtHours, debt)
    }

    /// 睡眠债等级（用于 UI 徽标）
    public enum Level: String {
        case none = "无债"
        case mild = "轻微"
        case moderate = "中等"
        case severe = "较重"

        public var symbol: String {
            switch self {
            case .none: return "●"
            case .mild: return "◐"
            case .moderate: return "◑"
            case .severe: return "○"
            }
        }
    }

    public static func level(of debtHours: Double) -> Level {
        switch debtHours {
        case ..<1: return .none
        case ..<3: return .mild
        case ..<6: return .moderate
        default: return .severe
        }
    }
}
