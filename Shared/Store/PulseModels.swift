import Foundation
import SwiftData

// MARK: - design.md §4 数据模型（M1 子集）
// RawSample / SleepWindow / DailyMetric / Baseline

/// 原始样本缓存（90 天滚动，之后降采样为日聚合 —— 降采样实现留 M2 TODO）
@Model
public final class RawSample {
    /// HK UUID（唯一去重键）；本地合成样本用 "local:<uuid>"
    @Attribute(.unique) public var hkUUID: String
    /// HK identifier，如 "HKQuantityTypeIdentifierHeartRate"
    public var type: String
    /// 子类型：睡眠阶段名（asleepCore 等）/ workout activityType rawValue；数量类型为空串
    public var subtype: String
    public var value: Double
    public var start: Date
    public var end: Date
    /// SampleSource.rawValue
    public var source: String

    public init(hkUUID: String, type: String, subtype: String = "",
                value: Double, start: Date, end: Date, source: String) {
        self.hkUUID = hkUUID
        self.type = type
        self.subtype = subtype
        self.value = value
        self.start = start
        self.end = end
        self.source = source
    }
}

/// 睡眠窗口（design.md §6 L1–L5）。L4/L5 以 version 递增保留历史，永不覆盖。
@Model
public final class SleepWindow {
    /// 归属日 = 窗口起始日 "yyyy-MM-dd"（本地时区）
    public var dayKey: String
    public var start: Date
    public var end: Date
    /// JSON：[SleepSegment]（SleepSegment 为 Codable 值类型）
    public var segmentsJSON: String
    /// "l1Native" | "l2Extended" | "l4Override"
    public var source: String
    /// 0–1，design.md §6 置信度公式
    public var confidence: Double
    public var confidenceReason: String
    public var version: Int
    /// L2 连续 3 次判定失败后锁定，不再延伸
    public var l2Locked: Bool
    public var l2FailCount: Int

    public init(dayKey: String, start: Date, end: Date, segmentsJSON: String,
                source: String, confidence: Double, confidenceReason: String,
                version: Int, l2Locked: Bool = false, l2FailCount: Int = 0) {
        self.dayKey = dayKey
        self.start = start
        self.end = end
        self.segmentsJSON = segmentsJSON
        self.source = source
        self.confidence = confidence
        self.confidenceReason = confidenceReason
        self.version = version
        self.l2Locked = l2Locked
        self.l2FailCount = l2FailCount
    }
}

/// 一日一行汇总（design.md §4）。M1 只填 sleepScore 与 confidenceJSON。
@Model
public final class DailyMetric {
    @Attribute(.unique) public var dateKey: String   // "yyyy-MM-dd"
    public var recovery: Double?
    public var sleepScore: Double?
    public var sleepNeed: Double?
    public var sleepDebt: Double?
    public var strain: Double?
    public var acwr: Double?
    public var stress: Double?
    /// 今日准备度 0–10（综合）
    public var readiness: Double?
    /// 打卡：精力 1–5（nil = 未打卡）
    public var energy: Int?
    /// 打卡：酸痛 1–5（nil = 未打卡）
    public var soreness: Int?
    public var confidenceJSON: String

    public init(dateKey: String, sleepScore: Double? = nil, confidenceJSON: String = "{}") {
        self.dateKey = dateKey
        self.sleepScore = sleepScore
        self.confidenceJSON = confidenceJSON
    }
}

/// 28 天滚动基线（design.md §9）：中位数 + MAD（稳健化 z 分数分母）
@Model
public final class Baseline {
    @Attribute(.unique) public var metric: String  // "restingHR" | "hrv" | "respiratory" | "wristTemp"
    public var median: Double
    public var mad: Double
    /// 参与计算的天数（<14 → 校准期，不出总分）
    public var sampleDays: Int
    public var computedAt: Date

    public init(metric: String, median: Double, mad: Double, sampleDays: Int, computedAt: Date) {
        self.metric = metric
        self.median = median
        self.mad = mad
        self.sampleDays = sampleDays
        self.computedAt = computedAt
    }
}

// MARK: - 训练与组次（design.md §4/§8）

@Model
public final class Workout {
    @Attribute(.unique) public var id: String
    public var dayKey: String
    public var start: Date
    public var end: Date
    public var type: String           // WorkoutDetector.WorkoutType rawValue
    public var source: String         // SampleSource.rawValue（auto/manual/native）
    public var trimp: Double
    public var hrr60: Double?
    public var totalEnergyKcal: Double?
    /// HKWorkout UUID（写回后填）
    public var hkUUID: String?
    /// 是否已写回 HealthKit
    public var writtenToHK: Bool
    /// 手动力量训练会话是否进行中（健身房流程用）
    public var isActive: Bool

    public init(id: String = UUID().uuidString, dayKey: String, start: Date, end: Date,
                type: String, source: String, trimp: Double = 0, hrr60: Double? = nil,
                totalEnergyKcal: Double? = nil, hkUUID: String? = nil, writtenToHK: Bool = false,
                isActive: Bool = false) {
        self.id = id
        self.dayKey = dayKey
        self.start = start
        self.end = end
        self.type = type
        self.source = source
        self.trimp = trimp
        self.hrr60 = hrr60
        self.totalEnergyKcal = totalEnergyKcal
        self.hkUUID = hkUUID
        self.writtenToHK = writtenToHK
        self.isActive = isActive
    }
}

@Model
public final class SetLog {
    public var workoutID: String
    public var exerciseID: String
    public var reps: Int
    public var weightKg: Double
    public var restSec: Int
    public var order: Int           // 组序号（1-based）
    public var loggedAt: Date

    public init(workoutID: String, exerciseID: String, reps: Int, weightKg: Double,
                restSec: Int = 90, order: Int, loggedAt: Date = Date()) {        self.workoutID = workoutID
        self.exerciseID = exerciseID
        self.reps = reps
        self.weightKg = weightKg
        self.restSec = restSec
        self.order = order
        self.loggedAt = loggedAt
    }
}

@Model
public final class Exercise {
    @Attribute(.unique) public var id: String
    public var nameZh: String
    public var nameEn: String
    public var muscleGroup: String   // 胸/背/腿/肩/臂/核心/有氧
    public var type: String          // strength/cardio
    public var isDefault: Bool       // 种子库

    public init(id: String, nameZh: String, nameEn: String,
                muscleGroup: String, type: String, isDefault: Bool = true) {
        self.id = id
        self.nameZh = nameZh
        self.nameEn = nameEn
        self.muscleGroup = muscleGroup
        self.type = type
        self.isDefault = isDefault
    }
}

@Model
public final class Routine {
    @Attribute(.unique) public var id: String
    public var name: String
    public var exerciseIDs: String   // JSON [String]
    public var targetSets: Int
    public var targetReps: Int
    public var targetWeightKg: Double

    public init(id: String = UUID().uuidString, name: String, exerciseIDs: String,
                targetSets: Int = 4, targetReps: Int = 10, targetWeightKg: Double = 0) {
        self.id = id
        self.name = name
        self.exerciseIDs = exerciseIDs
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeightKg = targetWeightKg
    }
}
