import Foundation

/// 睡眠阶段片段（Codable 值类型，测试与存储共用）。
/// stage 取值："inBed" | "awake" | "asleepCore" | "asleepDeep" | "asleepREM" | "asleepUnspecified"
public struct SleepSegment: Codable, Equatable, Sendable {
    public var stage: String
    public var start: Date
    public var end: Date

    public init(stage: String, start: Date, end: Date) {
        self.stage = stage
        self.start = start
        self.end = end
    }

    public var durationMin: Double { end.timeIntervalSince(start) / 60 }

    /// 是否 asleep 系列（可并入睡眠窗）
    public var isAsleep: Bool { stage.hasPrefix("asleep") }

    public var displayName: String {
        switch stage {
        case "inBed":            return "卧床"
        case "awake":            return "清醒"
        case "asleepCore":       return "浅睡"
        case "asleepDeep":       return "深睡"
        case "asleepREM":        return "REM"
        default:                 return "睡眠"
        }
    }
}

/// L1 清洗产出的候选窗口（尚未落库）。
public struct SleepWindowDraft: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var segments: [SleepSegment]
    /// 各阶段分钟数：["浅睡": x, "深睡": y, ...]
    public var stageMinutes: [String: Double]
    /// 效率 = asleep 时长 / 窗口总时长（0–1）
    public var efficiency: Double

    public var durationMin: Double { end.timeIntervalSince(start) / 60 }
    public var dayKey: String { SleepWindowBuilder.dayKey(for: start) }
}

/// 睡眠窗构建器：design.md §6 L1 段清洗 + L2 延伸判定 + 置信度公式。
/// 全部纯函数/纯结构，输入值类型，便于单测。
public enum SleepWindowBuilder {

    // MARK: - L1 段清洗（design.md §6）

    /// 清洗规则：
    /// 1. inBed 段不并入 asleep 窗（design「剔除 inBed 但活动能量异常段」；
    ///    M1 先整体排除，能量校验留 TODO-M1+）；
    /// 2. awake 段 <5min 丢弃（HR 上升>15bpm 豁免需 HR 序列，留 TODO-M1+）；
    /// 3. 相邻 asleep 段 gap≤20min → 合并为同一窗口（中间夹的短 awake 一并并入并记连续性损失）。
    public static func buildL1(segments: [SleepSegment]) -> [SleepWindowDraft] {
        let sorted = segments.sorted { $0.start < $1.start }
        // 1. 丢弃 <5min 的 awake（保留 ≥5min 的，其两侧不合并）
        let kept = sorted.filter { seg in
            !(seg.stage == "awake" && seg.durationMin < 5)
        }

        var windows: [SleepWindowDraft] = []
        var cur: [SleepSegment] = []
        var lastAsleepEnd: Date?

        func closeWindow() {
            guard let first = cur.first, let last = cur.last else { return }
            let start = first.start, end = last.end
            var stageMin: [String: Double] = [:]
            for s in cur { stageMin[s.displayName, default: 0] += s.durationMin }
            let asleepMin = cur.reduce(0) { $0 + $1.durationMin }
            let totalMin = end.timeIntervalSince(start) / 60
            windows.append(SleepWindowDraft(
                start: start, end: end, segments: cur,
                stageMinutes: stageMin,
                efficiency: totalMin > 0 ? min(1, asleepMin / totalMin) : 0))
            cur = []
        }

        for seg in kept {
            if seg.isAsleep {
                if let lastEnd = lastAsleepEnd, !cur.isEmpty {
                    let gapMin = seg.start.timeIntervalSince(lastEnd) / 60
                    if gapMin > 20 { closeWindow() } // gap 由保留的 ≥5min awake 填着，必断窗
                }
                cur.append(seg)
                lastAsleepEnd = seg.end
            } else {
                // 保留的 ≥5min awake：直接断窗
                closeWindow()
                lastAsleepEnd = nil
            }
        }
        closeWindow()
        return windows
    }

    // MARK: - L2 延伸判定（design.md §6）

    /// 单次判定（纯函数）：全部满足才延伸。
    /// - parameters:
    ///   - stepsSinceEnd: 窗口结束后累计步数
    ///   - standMinSinceEnd: 窗口结束后累计站立分钟
    ///   - kcalPerMin: 当前活动能量率（kcal/min）
    ///   - hr: 当前心率（bpm）
    ///   - nightHRMedian: 夜间心率中位数（窗口内 1min 聚合）
    ///   - charging: 是否充电中
    public static func l2ExtensionAllowed(steps stepsSinceEnd: Double,
                                          standMin standMinSinceEnd: Double,
                                          kcalPerMin: Double,
                                          hr: Double,
                                          nightHRMedian: Double,
                                          charging: Bool) -> Bool {
        if charging { return false }
        guard stepsSinceEnd == 0, standMinSinceEnd == 0 else { return false }
        guard kcalPerMin < 1 else { return false }
        guard hr <= nightHRMedian + 8 else { return false }
        return true
    }

    /// L2 状态机：连续失败计数与锁定（纯结构，可测）。
    public struct L2Tracker: Equatable {
        public var failCount = 0
        public var locked = false
        /// 本窗口已延伸次数（仅用于诊断）
        public var extensionCount = 0
        public static let maxFails = 3
        /// 延伸上限：窗口结束后 3h（硬编码，design.md §6）
        public static let extensionLimitSec: TimeInterval = 3 * 3600

        public init() {}

        /// 结构性硬约束：距窗口结束超过 3h / 已锁定 → 不再延伸
        public func canExtend(now: Date, windowEnd: Date) -> Bool {
            !locked && now.timeIntervalSince(windowEnd) <= Self.extensionLimitSec
        }

        /// 记录一次判定结果。返回 true 表示仍允许继续延伸。
        @discardableResult
        public mutating func record(allowed: Bool) -> Bool {
            if allowed { failCount = 0; return !locked }
            failCount += 1
            if failCount >= Self.maxFails { locked = true }
            return !locked
        }
    }

    // MARK: - 置信度（design.md §6 公式）

    public struct Confidence: Equatable {
        public var value: Double          // 0–1
        public var symbol: String         // ● ◐ ○
        public var reason: String

        public init(value: Double, hrCoverage: Double, continuity: Double, stillness: Double) {
            self.value = value
            if value >= 0.8 { symbol = "●" }
            else if value >= 0.5 { symbol = "◐" }
            else { symbol = "○" }
            var parts: [String] = []
            if hrCoverage < 0.7 { parts.append("心率覆盖不足") }
            if continuity < 0.8 { parts.append("分期不连续") }
            if stillness < 0.8 { parts.append("窗内活动偏多") }
            self.reason = parts.isEmpty ? "数据完整" : parts.joined(separator: "、")
        }
    }

    /// 置信度 = 0.4·HR覆盖率 + 0.3·分期连续性 + 0.3·窗内静止比例
    /// - hrCoverage: 窗口内 1min 心率聚合覆盖比例（0–1）
    /// - continuity: 分期连续性 = 1 − 窗口内 awake 缺口分钟/总分钟（调用方计算）
    /// - stillnessRatio: 窗内无活动能量分钟占比（0–1）
    public static func confidence(hrCoverage: Double,
                                  continuity: Double,
                                  stillnessRatio: Double) -> Confidence {
        let v = 0.4 * hrCoverage + 0.3 * continuity + 0.3 * stillnessRatio
        return Confidence(value: v, hrCoverage: hrCoverage, continuity: continuity, stillness: stillnessRatio)
    }

    // MARK: - 工具

    /// 归属日 = 窗口起始日（本地时区 yyyy-MM-dd）
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
