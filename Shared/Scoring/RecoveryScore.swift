import Foundation

/// 恢复评分（design.md §9）：
/// Recovery = 100·σ(0.35·zHRV − 0.25·zRHR − 0.10·z呼吸 − 0.10·|腕温偏移| + 0.20·z睡眠效率 + 0.05·z精力打卡)
/// z 为相对 28 天基线的稳健 z 值（median + MAD×1.4826）。
public enum RecoveryScore {

    /// 逻辑斯蒂映射：linear input → 0–100
    public static func sigmoid100(_ x: Double) -> Double {
        100 / (1 + Foundation.exp(-x))
    }

    /// 日间腕温偏移（℃）→ 得分贡献（负权重）
    public static func wristTempPenalty(offsetDegC: Double) -> Double {
        min(1, abs(offsetDegC) / 1.5) // ±1.5℃ → 扣满 0.10
    }

    /// 精力打卡 1–5 → 得分贡献（正权重 0.05）
    public static func energyCheckinScore(level: Int) -> Double {
        Double(level - 1) / 4 // 1→0, 5→1
    }

    /// 睡眠效率 → z 值（相对基线）
    public static func zEfficiency(value: Double, baseline: BaselineValue?) -> Double? {
        guard let b = baseline, b.mad > 0 else { return nil }
        return BaselineMath.robustZ(value: value, median: b.median, mad: b.mad)
    }

    /// 综合 Recovery。返回 nil 表示核心输入（zHRV 或 zRHR）缺失 → 降级。
    /// - parameters:
    ///   - zHRV: 夜 HR/HRV z 值（mandatory）
    ///   - zRHR: 夜静息心率 z 值（mandatory）
    ///   - zResp: 呼吸率 z 值（optional，默认 0）
    ///   - wristTempOffset: 腕温偏移℃（optional，默认 0）
    ///   - zSleepEff: 睡眠效率 z 值（optional，默认 0）
    ///   - energyLevel: 打卡 1–5（optional，默认 3）
    ///   - baselineDays: 已采集天数（<14 → 校准期，total=nil）
    public static func compute(zHRV: Double?,
                               zRHR: Double?,
                               zResp: Double? = nil,
                               wristTempOffset: Double? = nil,
                               zSleepEff: Double? = nil,
                               energyLevel: Int? = nil,
                               baselineDays: Int) -> Components? {
        guard let zh = zHRV, let zr = zRHR else { return nil } // 核心缺失

        let inCalibration = baselineDays < SleepScore.calibrationDaysNeeded

        // 线性组合（负项：zRHR 越高越差；腕温偏移取绝对值惩罚）
        let linear = 0.35 * zh
            - 0.25 * zr
            - 0.10 * (zResp ?? 0)
            - 0.10 * wristTempPenalty(offsetDegC: wristTempOffset ?? 0)
            + 0.20 * (zSleepEff ?? 0)
            + 0.05 * energyCheckinScore(level: energyLevel ?? 3)

        let raw = sigmoid100(linear)
        var note = ""
        if zResp == nil { note += "呼吸率缺失、" }
        if wristTempOffset == nil { note += "腕温缺失、" }
        if zSleepEff == nil { note += "睡眠效率基线缺失、" }
        if inCalibration { note = "标定期（还需 \(SleepScore.calibrationDaysNeeded - baselineDays) 天），不出总分" }

        return Components(zHRV: zh, zRHR: zr, zResp: zResp ?? 0,
                          wristTempOffset: wristTempOffset ?? 0,
                          zSleepEff: zSleepEff ?? 0,
                          energyLevel: energyLevel ?? 3,
                          total: inCalibration ? nil : raw.rounded(),
                          inCalibration: inCalibration,
                          note: note.trimmingCharacters(in: CharacterSet(charactersIn: "、")))
    }

    public struct Components: Equatable {
        public var zHRV: Double
        public var zRHR: Double
        public var zResp: Double
        public var wristTempOffset: Double
        public var zSleepEff: Double
        public var energyLevel: Int
        public var total: Double?
        public var inCalibration: Bool
        public var note: String

        /// 降级状态（缺少核心输入时为 nil）
        public var isDegraded: Bool { total == nil && !inCalibration }
    }
}
