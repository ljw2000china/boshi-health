import Foundation

/// 睡眠评分 v1（design.md §9 原文）：
/// Sleep = 40·时长分 + 25·效率 + 20·结构偏离 + 15·规律性
/// 基线门控：前 14 天校准期不出总分（total == nil，仅给分项）。
public enum SleepScore {

    /// 目标睡眠时长（M1 固定 7.5h；SleepNeed 个性化在 M2/M3）
    public static let targetHours: Double = 7.5
    /// 校准期天数（design.md §9）
    public static let calibrationDaysNeeded = 14

    public struct Components: Equatable {
        public var duration: Double      // 0–1
        public var efficiency: Double    // 0–1
        public var structure: Double     // 0–1（结构偏离的反向分）
        public var regularity: Double    // 0–1
        public var total: Double?        // 0–100；校准期为 nil
        public var inCalibration: Bool
        public var note: String

        public var durationContribution: Double { 40 * duration }
        public var efficiencyContribution: Double { 25 * efficiency }
        public var structureContribution: Double { 20 * structure }
        public var regularityContribution: Double { 15 * regularity }
    }

    /// - parameters:
    ///   - durationHours: 实际 asleep 时长（小时）
    ///   - efficiency: 睡眠效率 0–1（asleep/窗口）
    ///   - structureDeviation: 结构偏离度 0–1 反向分；M1 传 nil → 占位 0.5（TODO-M2 按分期结构基线计算）
    ///   - sleepMidpoints: 历史入睡中点（Date），≥3 个时计算规律性；否则占位 0.5
    ///   - baselineDays: 已完成采集的天数（<14 → 校准期）
    public static func compute(durationHours: Double,
                               efficiency: Double,
                               structureDeviation: Double?,
                               sleepMidpoints: [Date],
                               baselineDays: Int) -> Components {
        let duration = min(1, max(0, durationHours / targetHours))
        let eff = min(1, max(0, efficiency))
        let structureReal = structureDeviation != nil
        let regularityReal = sleepMidpoints.count >= 3
        let structure = structureDeviation.map { min(1, max(0, $0)) } ?? 0.5 // TODO-M2
        let regularity = regularityScore(midpoints: sleepMidpoints)

        let inCalibration = baselineDays < calibrationDaysNeeded
        // 占位分不得抬高总分（诚实原则）：只对真实分项做权重重归一化
        var num = 40 * duration + 25 * eff
        var den = 40.0 + 25.0
        if structureReal { num += 20 * structure; den += 20 }
        if regularityReal { num += 15 * regularity; den += 15 }
        let raw = durationHours <= 0 ? 0 : 100 * num / den

        var note = ""
        if !structureReal { note = "结构分占位（不计入）" }
        if !regularityReal {
            note += note.isEmpty ? "规律性待积累（不计入）" : "、规律性待积累（不计入）"
        }
        if inCalibration {
            note = "标定期（还需 \(calibrationDaysNeeded - baselineDays) 天），不出总分"
        }
        return Components(duration: duration, efficiency: eff, structure: structure,
                          regularity: regularity,
                          total: inCalibration ? nil : raw.rounded(),
                          inCalibration: inCalibration, note: note)
    }

    /// 规律性 = 1 − min(1, σ(入睡中点小时)/2h)。样本 <3 返回 0.5 占位。
    /// 跨午夜处理：相对平均值的 unwrap（相邻样本差 >12h 时 ±24h 调整），
    /// 覆盖 23:59 vs 00:01 这种 2 分钟偏差被算成 24h 的边界。
    public static func regularityScore(midpoints: [Date], calendar: Calendar = .current) -> Double {
        guard midpoints.count >= 3 else { return 0.5 }
        var hours: [Double] = midpoints.map { d in
            let c = calendar.dateComponents([.hour, .minute], from: d)
            return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        }
        // unwrap：从第二个起，相对前一个值调整 ±24h 使差值落在 [-12, 12]
        for i in hours.indices.dropFirst() {
            while hours[i] - hours[i - 1] > 12 { hours[i] -= 24 }
            while hours[i] - hours[i - 1] < -12 { hours[i] += 24 }
        }
        let mean = hours.reduce(0, +) / Double(hours.count)
        let variance = hours.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(hours.count)
        let sigma = variance.squareRoot()
        return 1 - min(1, sigma / 2)
    }
}
