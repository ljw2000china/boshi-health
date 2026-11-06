import Foundation

/// ACWR（急性:慢性负荷比，design.md §9）：
/// ACWR = mean(Strain,7d) / mean(Strain,28d)
/// 甜区 0.8–1.3；>1.5 高伤风险；<0.8 降负荷。
public enum ACWRScore {

    public static let sweetZoneLow = 0.8
    public static let sweetZoneHigh = 1.3
    public static let riskThreshold = 1.5

    /// 最近 28 天每日 strain（今天在前）→ ACWR
    public static func acwr(last28Strain: [Double]) -> Double? {
        guard last28Strain.count >= 28 else { return nil } // 需要满 28 天，否则降级
        let acute = last28Strain.prefix(7).reduce(0, +) / 7
        let chronic = last28Strain.reduce(0, +) / 28
        guard chronic > 0 else { return nil } // 无历史训练 → 无法计算
        return acute / chronic
    }

    public enum Status: String {
        case undertrained = "under"
        case sweet = "sweet"
        case overload = "overload"
        case risk = "risk"

        public var colorName: String {
            switch self {
            case .undertrained: return "grey"
            case .sweet: return "green"
            case .overload: return "yellow"
            case .risk: return "red"
            }
        }
    }

    /// ACWR → 状态
    public static func status(of value: Double) -> Status {
        if value < sweetZoneLow { return .undertrained }
        if value <= sweetZoneHigh { return .sweet }
        if value <= riskThreshold { return .overload }
        return .risk
    }

    /// 0–10 风险分（0 = 甜区中心，10 = >1.5）
    public static func riskScore(of value: Double) -> Double {
        let d = abs(value - (sweetZoneLow + sweetZoneHigh) / 2)
        return min(10, d / (riskThreshold - (sweetZoneLow + sweetZoneHigh) / 2) * 10)
    }
}
