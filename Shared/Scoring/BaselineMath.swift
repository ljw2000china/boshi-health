import Foundation

/// 28 天滚动基线（design.md §9）：中位数 + MAD（稳健化）。
/// 纯计算部分在此；落库与调度在 DataPipeline。
public enum BaselineMath {

    /// 中位数
    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    /// MAD = median(|x − median|)，再乘 1.4826 折算为稳健 σ
    public static func mad(_ values: [Double]) -> Double? {
        guard let m = median(values) else { return nil }
        let devs = values.map { abs($0 - m) }
        guard let madRaw = median(devs) else { return nil }
        return madRaw * 1.4826
    }

    /// 稳健 z 分数（MAD 为 0 时返回 nil，避免除零）
    public static func robustZ(value: Double, median: Double, mad: Double) -> Double? {
        guard mad > 0 else { return nil }
        return (value - median) / mad
    }
}

/// 基线快照值类型（与 @Model Baseline 解耦，便于测试）
public struct BaselineValue: Equatable {
    public var metric: String
    public var median: Double
    public var mad: Double
    public var sampleDays: Int

    public init(metric: String, median: Double, mad: Double, sampleDays: Int) {
        self.metric = metric
        self.median = median
        self.mad = mad
        self.sampleDays = sampleDays
    }

    /// 从每日值数组构建（nil 值已剔除）
    public static func build(metric: String, dailyValues: [Double]) -> BaselineValue? {
        guard let m = BaselineMath.median(dailyValues),
              let s = BaselineMath.mad(dailyValues) else { return nil }
        return BaselineValue(metric: metric, median: m, mad: s, sampleDays: dailyValues.count)
    }
}
