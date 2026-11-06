import Foundation

/// 训练负荷（design.md §9）：
/// TRIMP = Σ(心率区间分钟 × 区间权重 [1,2,3,4,5]) + 0.3·NEAT
/// Strain = 21·(1−e^(−TRIMP/K))
/// K 暂取 200（标定期后按历史动态调整 TODO-M4）。
public enum StrainScore {

    /// 默认 K（TRIMP 饱和常数）；标定期后按历史峰值调整 TODO-M4
    public static let defaultK: Double = 200
    /// NEAT 权重（每千卡非训练活动能量）
    public static let neatFactor: Double = 0.3

    /// 心率区间权重（1–5 区）
    public static let zoneWeights: [Double] = [1, 2, 3, 4, 5]

    /// 5 区间分钟数组 → TRIMP（不含 NEAT）
    /// zones[0]=zone1 … zones[4]=zone5
    public static func trimp(zoneMinutes: [Double], neatKcal: Double = 0) -> Double {
        guard zoneMinutes.count == 5 else { return 0 }
        let base = zip(zoneMinutes, zoneWeights).map { $0 * $1 }.reduce(0, +)
        return base + neatKcal * neatFactor
    }

    /// 心率 → 区间（最大心率法：85–95% zone5, 77–85% zone4, 65–77% zone3, 55–65% zone2, <55% zone1）
    public static func zone(hr: Double, maxHR: Double) -> Int {
        let r = hr / max(maxHR, 1)
        switch r {
        case 0.85...: return 5
        case 0.77..<0.85: return 4
        case 0.65..<0.77: return 3
        case 0.55..<0.65: return 2
        default: return 1
        }
    }

    /// 心率样本序列 → 区间分钟（按相邻样本间隔归并）
    /// samples: [(hr, timestamp)]，时间差 >120s 的间隔截断为 120s（防手表摘戴造成虚假时长）
    public static func zoneMinutes(hrSamples: [(hr: Double, at: Date)], maxHR: Double) -> [Double] {
        var zones = [Double](repeating: 0, count: 5)
        guard hrSamples.count >= 2 else { return zones }
        for i in 1..<hrSamples.count {
            let dt = min(120, hrSamples[i].at.timeIntervalSince(hrSamples[i-1].at)) / 60 // 分钟
            let z = zone(hr: hrSamples[i-1].hr, maxHR: maxHR)
            zones[z - 1] += dt
        }
        return zones
    }

    /// TRIMP → Strain（0–21）
    public static func strain(trimp: Double, k: Double = defaultK) -> Double {
        21 * (1 - Foundation.exp(-trimp / k))
    }

    /// 心率恢复：训练结束即刻 HR − 60s 后 HR（design.md §9 HRR60）
    /// 返回 nil 表示数据不足（结束后 60±15s 内无样本）
    public static func hrr60(workoutEndHR: Double, samples: [(hr: Double, at: Date)], workoutEnd: Date) -> Double? {
        let window = samples.filter {
            let dt = $0.at.timeIntervalSince(workoutEnd)
            return dt >= 45 && dt <= 75
        }.sorted { $0.at < $1.at }
        guard let first = window.first else { return nil }
        return workoutEndHR - first.hr
    }
}
