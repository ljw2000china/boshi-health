import Foundation

/// 今日准备度（design.md §9）：
/// Readiness = f(Recovery, SleepDebt, 昨日 Strain, ACWR, 酸痛打卡) → 0–10
/// 设计取向：以 Recovery 为主，睡眠债/昨日负荷/ACWR 风险扣分，酸痛打卡修正。
public enum ReadinessScore {

    /// - parameters:
    ///   - recovery: 0–100（缺失 → 返回 nil）
    ///   - sleepDebtHours: 睡眠债小时
    ///   - yesterdayStrain: 昨日 Strain（0–21）
    ///   - acwrRisk: ACWR 风险分（0–10）
    ///   - soreness: 酸痛打卡 1–5（1 无酸痛，5 很酸）
    public static func compute(recovery: Double?,
                               sleepDebtHours: Double,
                               yesterdayStrain: Double,
                               acwrRisk: Double,
                               soreness: Int? = nil) -> Double? {
        guard let rec = recovery else { return nil }
        var score = rec / 10 // 0–10
        score -= min(2.0, sleepDebtHours / 5)         // 债 5h → −1，10h → −2
        score -= min(1.0, yesterdayStrain / 21)       // 昨日满负荷 → −1
        score -= min(1.5, acwrRisk * 0.15)            // 风险 10 → −1.5
        if let s = soreness {
            score -= Double(max(0, s - 3)) * 0.4      // 4 → −0.4，5 → −0.8
        }
        return max(0, min(10, score)).rounded(toPlaces: 1)
    }

    /// 0–10 → 建议标签（不给具体训练处方，只给方向）
    public static func advice(readiness: Double) -> String {
        switch readiness {
        case 8...: return "状态好，可正常或加量训练"
        case 6..<8: return "状态尚可，按计划训练"
        case 4..<6: return "建议中等强度，注意补觉"
        default: return "优先恢复，避免高强度"
        }
    }

    /// 徽标符号（色盲友好：符号 + 颜色双编码）
    public static func symbol(readiness: Double) -> String {
        switch readiness {
        case 8...: return "●"
        case 6..<8: return "◕"
        case 4..<6: return "◐"
        default: return "○"
        }
    }
}

extension Double {
    /// 保留小数位（四舍五入）
    func rounded(toPlaces places: Int) -> Double {
        let m = Foundation.pow(10, Double(places))
        return (self * m).rounded() / m
    }
}
