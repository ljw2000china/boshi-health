import Foundation

/// 训练汇总纯计算（与 SwiftData 解耦，便于单测）：
/// 日总结（今日练什么）、周汇总（人体图强度 + 与上周对比）、单动作进步曲线（PB 突破 + 维持天数）。
public enum TrainingSummary {

    // MARK: - 基础类型

    public struct TrainingSet: Sendable, Equatable, Identifiable {
        public var workoutID: String
        public var exerciseID: String
        public var exerciseName: String
        public var muscleGroup: String
        public var reps: Int
        public var weightKg: Double
        public var order: Int
        public var date: Date

        public var id: String { "\(workoutID)|\(exerciseID)|\(order)" }
        public var volumeKg: Double { Double(reps) * weightKg }

        public init(workoutID: String, exerciseID: String, exerciseName: String,
                    muscleGroup: String, reps: Int, weightKg: Double, order: Int, date: Date) {
            self.workoutID = workoutID
            self.exerciseID = exerciseID
            self.exerciseName = exerciseName
            self.muscleGroup = muscleGroup
            self.reps = reps
            self.weightKg = weightKg
            self.order = order
            self.date = date
        }
    }

    /// 当日训练重点（"练胸日"）
    public struct Focus: Sendable, Equatable {
        public var muscles: [String]
        public var title: String

        public init(muscles: [String], title: String) {
            self.muscles = muscles
            self.title = title
        }

        public static let rest = Focus(muscles: [], title: "休息日")
    }

    public struct DaySummary: Sendable, Equatable {
        public var dayKey: String
        public var sets: [TrainingSet]
        public var totalSets: Int
        public var volumeKg: Double
        public var muscleSets: [String: Int]
        public var focus: Focus
        /// 动作出现顺序（去重）
        public var exerciseOrder: [String]

        public func sets(for exerciseID: String) -> [TrainingSet] {
            sets.filter { $0.exerciseID == exerciseID }.sorted { $0.order < $1.order }
        }

        /// dayKey（yyyy-MM-dd）→ 当天中午的时间，用于日期选择器回显
        public var dayKeyDate: Date {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = .current
            guard let d = f.date(from: dayKey) else { return Date() }
            return Calendar.current.date(byAdding: .hour, value: 12, to: d) ?? d
        }

        public func exerciseName(_ exerciseID: String) -> String {
            sets.first { $0.exerciseID == exerciseID }?.exerciseName ?? exerciseID
        }

        public var isEmpty: Bool { totalSets == 0 }

        public static func empty(dayKey: String) -> DaySummary {
            DaySummary(dayKey: dayKey, sets: [], totalSets: 0, volumeKg: 0,
                       muscleSets: [:], focus: .rest, exerciseOrder: [])
        }
    }

    public struct WeekSummary: Sendable {
        /// 强度封顶组数（单肌群一周 12 组 → 人体图着色 100%）
        public static let intensityCapSets: Double = 12

        public var start: Date
        public var end: Date
        public var totalSets: Int
        public var volumeKg: Double
        public var trainedDays: Int
        public var muscleSets: [String: Int]
        public var muscleVolume: [String: Double]
        /// dayKey → 当日重点（用于时间线展示）
        public var dayFocus: [(dayKey: String, focus: Focus)]

        public func intensity(for muscle: String) -> Double {
            let s = Double(muscleSets[muscle] ?? 0)
            return min(1, s / Self.intensityCapSets)
        }

        /// 本周最强重点（出现次数最多）
        public var dominantFocus: Focus {
            var counts: [String: Int] = [:]
            for (_, f) in dayFocus {
                for m in f.muscles { counts[m, default: 0] += 1 }
            }
            guard let top = counts.max(by: { $0.value < $1.value })?.key else { return .rest }
            return Focus(muscles: [top], title: "本周以\(top)为主")
        }

        public static func empty(start: Date, end: Date) -> WeekSummary {
            WeekSummary(start: start, end: end, totalSets: 0, volumeKg: 0, trainedDays: 0,
                        muscleSets: [:], muscleVolume: [:], dayFocus: [])
        }
    }

    public struct Comparison: Sendable {
        public var thisWeek: WeekSummary
        public var lastWeek: WeekSummary
        public var setDelta: Int
        public var volumeDelta: Double
        /// 上周为 0 时无法算百分比（nil = 无对比基准）
        public var volumeDeltaPct: Double?

        public func muscleSetDelta(_ muscle: String) -> Int {
            (thisWeek.muscleSets[muscle] ?? 0) - (lastWeek.muscleSets[muscle] ?? 0)
        }
    }

    public struct ProgressDay: Sendable, Identifiable, Equatable {
        public var id: String { dayKey }
        public var dayKey: String
        public var date: Date
        public var maxWeightKg: Double
        public var bestReps: Int
        public var volumeKg: Double
        /// Epley 估算 1RM
        public var estOneRM: Double
    }

    public struct Milestone: Sendable, Identifiable, Equatable {
        public var id: Date { date }
        public var weightKg: Double
        public var date: Date
        /// 该重量成绩维持天数（到下一次突破或今天）
        public var heldDays: Int
    }

    public struct Progress: Sendable, Equatable {
        public var exerciseID: String
        public var points: [ProgressDay]
        public var personalBest: Double
        public var pbDate: Date?
        /// 当前最好成绩已维持天数
        public var heldDays: Int
        public var milestones: [Milestone]
        /// 最近一次 vs 此前最好
        public var isNewPB: Bool
    }

    // MARK: - 日总结

    public static func summarizeDay(dayKey: String, sets: [TrainingSet]) -> DaySummary {
        let sorted = sets.sorted { $0.date < $1.date }
        var muscleSets: [String: Int] = [:]
        var order: [String] = []
        for s in sorted {
            muscleSets[s.muscleGroup, default: 0] += 1
            if !order.contains(s.exerciseID) { order.append(s.exerciseID) }
        }
        return DaySummary(dayKey: dayKey,
                          sets: sorted,
                          totalSets: sorted.count,
                          volumeKg: sorted.reduce(0) { $0 + $1.volumeKg },
                          muscleSets: muscleSets,
                          focus: focus(from: muscleSets),
                          exerciseOrder: order)
    }

    /// 训练重点命名：主肌群 + （次肌群组数 ≥ 主肌群 55% 时合并）
    public static func focus(from muscleSets: [String: Int]) -> Focus {
        let ranked = muscleSets.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        guard let main = ranked.first else { return .rest }
        var muscles = [main.key]
        if ranked.count > 1, Double(ranked[1].value) >= Double(main.value) * 0.55 {
            muscles.append(ranked[1].key)
        }
        return Focus(muscles: muscles, title: "练" + muscles.joined(separator: "+") + "日")
    }

    // MARK: - 周汇总

    /// 周一 00:00 起的一周（本地时区）
    public static func weekInterval(containing date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        var cal = calendar
        cal.firstWeekday = 2 // 周一
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let start = cal.date(from: comps) ?? cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
        return (start, end)
    }

    public static func summarizeWeek(sets: [TrainingSet],
                                     interval: (start: Date, end: Date),
                                     calendar: Calendar = .current) -> WeekSummary {
        let inside = sets.filter { $0.date >= interval.start && $0.date < interval.end }
        var muscleSets: [String: Int] = [:]
        var muscleVolume: [String: Double] = [:]
        var dayMap: [String: [TrainingSet]] = [:]
        for s in inside {
            muscleSets[s.muscleGroup, default: 0] += 1
            muscleVolume[s.muscleGroup, default: 0] += s.volumeKg
            dayMap[dayKey(for: s.date, calendar: calendar), default: []].append(s)
        }
        let dayFocus = dayMap.keys.sorted().map { key -> (dayKey: String, focus: Focus) in
            let daySets = dayMap[key] ?? []
            var ms: [String: Int] = [:]
            for s in daySets { ms[s.muscleGroup, default: 0] += 1 }
            return (key, focus(from: ms))
        }
        return WeekSummary(start: interval.start, end: interval.end,
                           totalSets: inside.count,
                           volumeKg: inside.reduce(0) { $0 + $1.volumeKg },
                           trainedDays: dayMap.count,
                           muscleSets: muscleSets, muscleVolume: muscleVolume,
                           dayFocus: dayFocus)
    }

    public static func compare(thisWeek: WeekSummary, lastWeek: WeekSummary) -> Comparison {
        let pct: Double? = lastWeek.volumeKg > 0
            ? (thisWeek.volumeKg - lastWeek.volumeKg) / lastWeek.volumeKg * 100
            : nil
        return Comparison(thisWeek: thisWeek, lastWeek: lastWeek,
                          setDelta: thisWeek.totalSets - lastWeek.totalSets,
                          volumeDelta: thisWeek.volumeKg - lastWeek.volumeKg,
                          volumeDeltaPct: pct)
    }

    // MARK: - 动作进步

    /// Epley 公式估算 1RM
    public static func estOneRM(weightKg: Double, reps: Int) -> Double {
        guard reps > 0, weightKg > 0 else { return 0 }
        return weightKg * (1 + Double(reps) / 30)
    }

    public static func progress(exerciseID: String, sets: [TrainingSet],
                                now: Date = Date(), calendar: Calendar = .current) -> Progress {
        let mine = sets.filter { $0.exerciseID == exerciseID }
        var byDay: [String: [TrainingSet]] = [:]
        for s in mine { byDay[dayKey(for: s.date, calendar: calendar), default: []].append(s) }

        var points: [ProgressDay] = []
        var runningMax: Double = 0
        var milestones: [Milestone] = []
        for key in byDay.keys.sorted() {
            let daySets = byDay[key] ?? []
            guard let top = daySets.max(by: { $0.weightKg < $1.weightKg }) else { continue }
            let volume = daySets.reduce(0) { $0 + $1.volumeKg }
            points.append(ProgressDay(dayKey: key, date: daySets.map(\.date).min() ?? now,
                                      maxWeightKg: top.weightKg, bestReps: top.reps,
                                      volumeKg: volume,
                                      estOneRM: estOneRM(weightKg: top.weightKg, reps: top.reps)))
            if top.weightKg > runningMax {
                runningMax = top.weightKg
                milestones.append(Milestone(weightKg: top.weightKg,
                                            date: daySets.map(\.date).min() ?? now,
                                            heldDays: 0))
            }
        }
        // 填补「维持天数」：到下一次突破（或今天）
        for i in milestones.indices {
            let next = i + 1 < milestones.count ? milestones[i + 1].date : now
            let days = calendar.dateComponents([.day], from: milestones[i].date, to: next).day ?? 0
            milestones[i].heldDays = max(0, days)
        }
        let pb = points.map(\.maxWeightKg).max() ?? 0
        let pbDate = milestones.last?.date
        let held = milestones.last?.heldDays ?? 0
        let isNewPB = milestones.count >= 2 && milestones.last?.date != milestones.dropLast().last?.date
        return Progress(exerciseID: exerciseID, points: points, personalBest: pb,
                        pbDate: pbDate, heldDays: held, milestones: milestones,
                        isNewPB: isNewPB && held <= 7)
    }

    // MARK: - 工具

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
