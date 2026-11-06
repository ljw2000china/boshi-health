import Foundation

/// 日间压力（design.md §9 简化版）：
/// Stress = 日间 HRV 相对夜间基线偏离 + HR 偏离，剔除训练时段。
/// M2 输出 0–100 与三档标签；完整模型（时变 HRV、非训练时段筛选）在 M6 精修。
public enum StressScore {

    /// 日间压力：HRV 下降 + 静息 HR 上升 → 高分
    /// - parameters:
    ///   - dayHRV: 当日日间 HRV 均值（ms）
    ///   - nightHRVMedian: 28 天夜间 HRV 基线中位数
    ///   - dayHR: 当日日间静息/低活动心率
    ///   - nightHRMedian: 28 天夜间心率基线中位数
    public static func compute(dayHRV: Double?,
                               nightHRVMedian: Double?,
                               dayHR: Double?,
                               nightHRMedian: Double?) -> Components? {
        guard let hrv = dayHRV, let hrvBase = nightHRVMedian, hrvBase > 0 else { return nil }
        // HRV 下降比例（0 = 无变化，1 = 完全消失）
        let hrvDrop = max(0, min(1, (hrvBase - hrv) / hrvBase))
        var hrRise = 0.0
        var note = ""
        if let hr = dayHR, let hrBase = nightHRMedian, hrBase > 0 {
            hrRise = max(0, min(1, (hr - hrBase) / max(hrBase, 1) ))
        } else {
            note = "心率基线缺失，仅用 HRV"
        }
        let value = 100 * (0.7 * hrvDrop + 0.3 * hrRise)
        return Components(value: value.rounded(), hrvDrop: hrvDrop, hrRise: hrRise, note: note)
    }

    public struct Components: Equatable {
        public var value: Double
        public var hrvDrop: Double
        public var hrRise: Double
        public var note: String
    }

    public enum Level: String {
        case calm = "平稳"
        case elevated = "偏高"
        case high = "较高"

        public var symbol: String {
            switch self {
            case .calm: return "●"
            case .elevated: return "◐"
            case .high: return "○"
            }
        }
    }

    public static func level(value: Double) -> Level {
        switch value {
        case ..<35: return .calm
        case ..<65: return .elevated
        default: return .high
        }
    }
}
