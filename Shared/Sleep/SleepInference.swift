import Foundation

/// L0 睡眠推测：不依赖 HealthKit 睡眠分期，只用「活动信号」推断睡眠窗。
///
/// 动机（用户需求）：Apple Watch 只有在睡眠专注/睡眠计划开启时才写睡眠分期样本；
/// 未开启时 HealthKit 里一条睡眠数据都没有，App 就无法展示任何睡眠。
/// 但手表 24h 都在记录步数/站立/活动能量/心率 —— 用「静止 + 佩戴 + 低活动」
/// 就能推断出睡眠时间段（含白天小睡）。
///
/// 规则（纯函数，可单测）：
/// 1. 切成 `slotSec`（默认 10 分钟）等长槽；
/// 2. 槽判定「静止」= 步数 0 且 站立 0 且 活动能量 0；
/// 3. 槽判定「佩戴」= 该槽内有心率样本（无心率 → 可能摘表，不可信）；
/// 4. 候选槽 = 静止 ∧ 佩戴；
/// 5. 合并间隔 ≤ `maxGapMin`（30 分钟）的候选槽（起夜、短暂清醒不断窗）；
/// 6. 保留时长 ≥ `minRunMin`（30 分钟）的连续段 —— 覆盖小睡；
/// 7. 主睡眠由调用方从当日所有段中取最长。
public enum SleepInference {

    /// 槽宽（秒）
    public static let slotSec: TimeInterval = 10 * 60
    /// 允许合并的最长空档（分钟）
    public static let maxGapMin: Double = 30
    /// 最短可信睡眠段（分钟）——覆盖 30 分钟小睡
    public static let minRunMin: Double = 30
    /// 推测窗口的假设睡眠效率（静止段内含少量清醒，取经验值 0.92）
    public static let assumedEfficiency: Double = 0.92
    /// 槽内判定「活动」的步数阈值（> 此值视为活动，如起夜/白天走动）
    public static let stepActiveThreshold: Double = 20
    /// 槽内判定「活动」的活动能量阈值（kcal）
    public static let energyActiveThreshold: Double = 2
    /// 允许合并的最长连续活动槽数（2 槽 = 20 分钟，与 L1 的 gap 合并阈值一致）
    public static let activeGapToleranceSlots = 2

    /// 活动信号输入（与 SwiftData 解耦，便于单测）。
    public struct Signals {
        /// 步数样本（累计型，value = 步数）
        public var steps: [Span]
        /// 站立时间样本（value = 分钟）
        public var stand: [Span]
        /// 活动能量样本（value = kcal）
        public var energy: [Span]
        /// 心率样本（value = bpm，时间点用 end 近似）
        public var heartRate: [Span]

        public init(steps: [Span] = [], stand: [Span] = [],
                    energy: [Span] = [], heartRate: [Span] = []) {
            self.steps = steps
            self.stand = stand
            self.energy = energy
            self.heartRate = heartRate
        }

        public var isEmpty: Bool {
            steps.isEmpty && stand.isEmpty && energy.isEmpty && heartRate.isEmpty
        }
    }

    /// 一个时间跨度样本
    public struct Span: Equatable {
        public var start: Date
        public var end: Date
        public var value: Double

        public init(start: Date, end: Date, value: Double) {
            self.start = start
            self.end = end
            self.value = value
        }
    }

    /// 推测结果（对应一个候选睡眠窗口）
    public struct InferredWindow: Equatable {
        public var start: Date
        public var end: Date
        /// 静止槽占比（0–1）
        public var stillness: Double
        /// 心率覆盖槽占比（0–1）
        public var hrCoverage: Double

        public var durationMin: Double { end.timeIntervalSince(start) / 60 }
        public var dayKey: String { SleepWindowBuilder.dayKey(for: start) }

        public init(start: Date, end: Date, stillness: Double, hrCoverage: Double) {
            self.start = start
            self.end = end
            self.stillness = stillness
            self.hrCoverage = hrCoverage
        }
    }

    // MARK: - 主推理

    /// 从活动信号推断睡眠段（按时间升序）。
    /// - parameters:
    ///   - signals: 活动/心率信号
    ///   - range: 推断的时间范围（通常为某一日 00:00–24:00，或昨夜 18:00–次日 12:00）
    public static func infer(signals: Signals, range: (start: Date, end: Date)) -> [InferredWindow] {
        guard !signals.isEmpty, range.end > range.start else { return [] }

        let slot = slotSec
        let slotCount = max(1, Int((range.end.timeIntervalSince(range.start) / slot).rounded(.up)))

        var stepSum = [Double](repeating: 0, count: slotCount)
        var standSum = [Double](repeating: 0, count: slotCount)
        var energySum = [Double](repeating: 0, count: slotCount)
        var hrCount = [Int](repeating: 0, count: slotCount)

        func distribute(_ spans: [Span], into sums: inout [Double]) {
            for s in spans {
                let a = s.start, b = max(s.end, s.start.addingTimeInterval(1))
                let total = b.timeIntervalSince(a)
                guard total > 0 else { continue }
                let firstSlot = max(0, Int(a.timeIntervalSince(range.start) / slot))
                let lastSlot = min(slotCount - 1, Int(b.timeIntervalSince(range.start) / slot))
                guard firstSlot <= lastSlot else { continue }
                for i in firstSlot...lastSlot {
                    let slotStart = range.start.addingTimeInterval(Double(i) * slot)
                    let slotEnd = slotStart.addingTimeInterval(slot)
                    let overlap = max(0, min(b, slotEnd).timeIntervalSince(max(a, slotStart)))
                    if overlap > 0 { sums[i] += s.value * (overlap / total) }
                }
            }
        }

        distribute(signals.steps, into: &stepSum)
        distribute(signals.stand, into: &standSum)
        distribute(signals.energy, into: &energySum)
        for s in signals.heartRate {
            let idx = Int(s.end.timeIntervalSince(range.start) / slot)
            if idx >= 0 && idx < slotCount { hrCount[idx] += 1 }
        }

        // 槽分类：
        // - active：步数 > 阈值 / 有站立 / 活动能量超阈 → 明确清醒活动
        // - quiet：无活动且佩戴（±2 槽内有 HR）→ 睡眠候选
        // - unknown：无活动但无 HR（可能摘表）→ 断窗
        var active = [Bool](repeating: false, count: slotCount)
        var worn = [Bool](repeating: false, count: slotCount)
        for i in 0..<slotCount {
            active[i] = stepSum[i] > stepActiveThreshold
                || standSum[i] >= 1
                || energySum[i] >= energyActiveThreshold
            let lo = max(0, i - 2), hi = min(slotCount - 1, i + 2)
            worn[i] = (lo...hi).contains { hrCount[$0] > 0 }
        }

        // 两遍法：
        // Pass 1 原始静止段（任何 active/unknown 槽都断段）——白天零散静止段很短（≤20min）；
        // Pass 2 仅当两侧段都 ≥ minRunMin 且活动空档 ≤ 容差时合并（起夜/短暂清醒不断夜窗）。
        // 这样白天「每 30 分钟走 10 分钟」产生的 20min 静止段不会连成全天。
        let minRunSlots = max(1, Int((minRunMin * 60 / slot).rounded()))
        var rawRuns: [(first: Int, last: Int)] = []
        var i = 0
        while i < slotCount {
            guard !active[i], worn[i] else { i += 1; continue }
            var j = i
            while j + 1 < slotCount && !active[j + 1] && worn[j + 1] { j += 1 }
            rawRuns.append((first: i, last: j))
            i = j + 1
        }
        var runs: [(first: Int, last: Int)] = []
        for r in rawRuns {
            if let prev = runs.last {
                let gap = r.first - prev.last - 1
                let prevLen = prev.last - prev.first + 1
                let curLen = r.last - r.first + 1
                if gap <= activeGapToleranceSlots && prevLen >= minRunSlots && curLen >= minRunSlots {
                    runs[runs.count - 1] = (first: prev.first, last: r.last)
                    continue
                }
            }
            runs.append(r)
        }

        var out: [InferredWindow] = []
        for run in runs {
            let start = range.start.addingTimeInterval(Double(run.first) * slot)
            let end = range.start.addingTimeInterval(Double(run.last + 1) * slot)
            guard end.timeIntervalSince(start) / 60 >= minRunMin else { continue }
            let count = run.last - run.first + 1
            // HR 覆盖：段内佩戴槽占比
            let hrSlots = (run.first...run.last).filter { worn[$0] }.count
            // 静止比例：段内非活动槽占比（活动空档越少越高）
            let quietSlots = (run.first...run.last).filter { !active[$0] }.count
            let stillness = count > 0 ? Double(quietSlots) / Double(count) : 0
            out.append(InferredWindow(start: start, end: end,
                                      stillness: stillness,
                                      hrCoverage: count > 0 ? Double(hrSlots) / Double(count) : 0))
        }
        return out
    }

    /// 推测窗口 → 睡眠窗草稿（单一 `asleepUnspecified` 段 + 经验效率）。
    public static func draft(from w: InferredWindow) -> SleepWindowDraft {
        let seg = SleepSegment(stage: "asleepUnspecified", start: w.start, end: w.end)
        return SleepWindowDraft(start: w.start, end: w.end, segments: [seg],
                                stageMinutes: ["睡眠": w.durationMin],
                                efficiency: assumedEfficiency)
    }

    /// 推测窗口置信度（沿用 design.md §6 公式；连续性按「整段连续」记 1.0）
    public static func confidence(for w: InferredWindow) -> SleepWindowBuilder.Confidence {
        SleepWindowBuilder.confidence(hrCoverage: w.hrCoverage,
                                      continuity: 1.0,
                                      stillnessRatio: w.stillness)
    }
}
