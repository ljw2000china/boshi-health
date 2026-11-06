import Foundation
import SwiftData

/// 力量训练服务：会话（开始/结束）+ 组次 CRUD + 汇总（今日/本周/进步）。
/// 手表记组实时同步到手机；手机编辑的记录反向同步回手表。
public actor TrainingService {

    public static let shared = TrainingService()
    let container = PulseStore.shared
    private init() {}

    // MARK: - 内存缓存（写操作 invalidate，读取走缓存 → 页面秒开）

    private var cacheVersion = 0
    private var cacheStamp = Date.distantPast
    private var cacheDay: [String: TrainingSummary.DaySummary] = [:]
    private var cacheWeek: (this: TrainingSummary.WeekSummary,
                            last: TrainingSummary.WeekSummary,
                            comparison: TrainingSummary.Comparison)?
    private var cacheExercises: [String: (name: String, muscle: String)] = [:]

    /// 让缓存到期（同一天内也可能多次训练，30s 新鲜度保证列表与新增同步）
    private static let cacheTTL: TimeInterval = 30

    private func invalidate() {
        cacheVersion &+= 1
        cacheStamp = .distantPast
        cacheDay = [:]
        cacheWeek = nil
    }

    private func exerciseLookup(_ ctx: ModelContext) -> [String: (name: String, muscle: String)] {
        if let cache = cacheExercises.nilIfEmpty { return cache }
        let rows = (try? ctx.fetch(FetchDescriptor<Exercise>())) ?? []
        var lookup: [String: (name: String, muscle: String)] = [:]
        for e in rows { lookup[e.id] = (e.nameZh, e.muscleGroup) }
        cacheExercises = lookup
        return lookup
    }

    public static let sessionType = "strength"
    public static let sessionSource = "manual"

    // MARK: - 会话

    /// 当前进行中的会话（跨天也能续上，只要 isActive）
    public func activeSession() async -> Workout? {
        let ctx = ModelContext(container)
        var d = FetchDescriptor<Workout>(predicate: #Predicate { $0.isActive == true },
                                         sortBy: [SortDescriptor(\.start, order: .reverse)])
        d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }

    /// 开始训练（已有进行中会话则直接返回它）
    public func startSession(now: Date = Date()) async -> Workout {
        if let existing = await activeSession() { return existing }
        let ctx = ModelContext(container)
        let w = Workout(dayKey: TrainingSummary.dayKey(for: now), start: now, end: now,
                        type: Self.sessionType, source: Self.sessionSource, isActive: true)
        ctx.insert(w)
        try? ctx.save()
        invalidate()
        syncSession(w, deleted: false)
        return w
    }

    /// 结束训练（无组次的空会话直接删除）
    public func endSession(_ id: String, now: Date = Date()) async {
        let ctx = ModelContext(container)
        var d = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        guard let w = try? ctx.fetch(d).first else { return }
        let hasSets = !((try? ctx.fetch(FetchDescriptor<SetLog>(
            predicate: #Predicate { $0.workoutID == id }))) ?? []).isEmpty
        if !hasSets {
            ctx.delete(w)
            try? ctx.save()
            invalidate()
            syncSession(w, deleted: true)
            return
        }
        w.end = now
        w.isActive = false
        try? ctx.save()
        invalidate()
        syncSession(w, deleted: false)
        #if os(watchOS)
        Task { await StrengthWorkoutWriter.shared.syncRecent(days: 3, now: now) }
        #endif
    }

    // MARK: - 组次

    /// 记一组（返回组序号）
    @discardableResult
    public func logSet(workoutID: String, exerciseID: String, reps: Int, weightKg: Double,
                       restSec: Int = 90, now: Date = Date()) async -> Int {
        let ctx = ModelContext(container)
        let order = nextOrder(ctx, workoutID: workoutID, exerciseID: exerciseID)
        let entry = SetLog(workoutID: workoutID, exerciseID: exerciseID, reps: reps,
                           weightKg: weightKg, restSec: restSec, order: order, loggedAt: now)
        ctx.insert(entry)
        touchSession(ctx, id: workoutID, now: now)
        try? ctx.save()
        invalidate()
        syncSet(entry, deleted: false)
        return order
    }

    /// 修改一组（手机历史编辑 / 手表纠错）
    public func updateSet(workoutID: String, exerciseID: String, order: Int,
                          reps: Int, weightKg: Double) async {
        let ctx = ModelContext(container)
        guard let entry = fetchSet(ctx, workoutID, exerciseID, order) else { return }
        entry.reps = reps
        entry.weightKg = weightKg
        try? ctx.save()
        invalidate()
        syncSet(entry, deleted: false)
    }

    /// 删除一组
    public func deleteSet(workoutID: String, exerciseID: String, order: Int) async {
        let ctx = ModelContext(container)
        guard let entry = fetchSet(ctx, workoutID, exerciseID, order) else { return }
        let dto = SetLogDTO(workoutID: workoutID, exerciseID: exerciseID, order: order,
                            reps: entry.reps, weightKg: entry.weightKg,
                            loggedAt: entry.loggedAt, deleted: true)
        ctx.delete(entry)
        // 删除后重排序号，保持 1..n 连续
        let rest = ((try? ctx.fetch(FetchDescriptor<SetLog>(predicate: #Predicate {
            $0.workoutID == workoutID && $0.exerciseID == exerciseID
        }, sortBy: [SortDescriptor(\.order)]))) ?? [])
        for (i, s) in rest.enumerated() { s.order = i + 1 }
        try? ctx.save()
        invalidate()
        send(dto)
    }

    /// 为历史某天手动补一条训练（手机端「添加记录」）
    public func createManualSession(dayKey: String, start: Date, end: Date) async -> Workout {
        let ctx = ModelContext(container)
        let w = Workout(dayKey: dayKey, start: start, end: end,
                        type: Self.sessionType, source: Self.sessionSource, isActive: false)
        ctx.insert(w)
        try? ctx.save()
        invalidate()
        syncSession(w, deleted: false)
        return w
    }

    /// 删除整个会话（含组次）
    public func deleteSession(_ id: String) async {
        let ctx = ModelContext(container)
        var d = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        guard let w = try? ctx.fetch(d).first else { return }
        for s in (try? ctx.fetch(FetchDescriptor<SetLog>(
            predicate: #Predicate { $0.workoutID == id }))) ?? [] { ctx.delete(s) }
        ctx.delete(w)
        try? ctx.save()
        invalidate()
        syncSession(w, deleted: true)
    }

    /// 改会话日期（记录错了改回来）：整体平移，保持时长
    public func updateSessionDate(_ id: String, newDate: Date) async {
        let ctx = ModelContext(container)
        var d = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        guard let w = try? ctx.fetch(d).first else { return }
        let duration = max(w.end.timeIntervalSince(w.start), 60)
        let delta = newDate.timeIntervalSince(w.start)
        w.start = newDate
        w.end = newDate.addingTimeInterval(duration)
        w.dayKey = TrainingSummary.dayKey(for: newDate)
        let logs = (try? ctx.fetch(FetchDescriptor<SetLog>(
            predicate: #Predicate { $0.workoutID == id }))) ?? []
        for s in logs {
            s.loggedAt = s.loggedAt.addingTimeInterval(delta)
        }
        try? ctx.save()
        invalidate()
        syncSession(w, deleted: false)
    }

    // MARK: - 查询

    /// 某会话的所有组（含动作名/肌群）
    public func sessionSets(workoutID: String) async -> [TrainingSummary.TrainingSet] {
        let ctx = ModelContext(container)
        let logs = (try? ctx.fetch(FetchDescriptor<SetLog>(
            predicate: #Predicate { $0.workoutID == workoutID },
            sortBy: [SortDescriptor(\.loggedAt), SortDescriptor(\.order)]))) ?? []
        return mapSets(ctx, logs)
    }

    /// 今日总结（含「练X日」）
    public func daySummary(dayKey: String? = nil, now: Date = Date()) async -> TrainingSummary.DaySummary {
        let key = dayKey ?? TrainingSummary.dayKey(for: now)
        if Date().timeIntervalSince(cacheStamp) < Self.cacheTTL,
           let hit = cacheDay[key] { return hit }
        let ctx = ModelContext(container)
        let lookup = exerciseLookup(ctx)
        let sessions = (try? ctx.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { $0.dayKey == key }))) ?? []
        let ids = Set(sessions.map(\.id))
        guard !ids.isEmpty else { return .empty(dayKey: key) }
        let logs = (try? ctx.fetch(FetchDescriptor<SetLog>(
            sortBy: [SortDescriptor(\.loggedAt)]))) ?? []
        let result = TrainingSummary.summarizeDay(
            dayKey: key,
            sets: logs.filter { ids.contains($0.workoutID) }.map { mapOne($0, lookup) })
        cacheDay[key] = result
        cacheStamp = Date()
        return result
    }

    /// 单个会话的汇总（手机历史详情用）
    public func sessionDaySummary(workoutID: String) async -> TrainingSummary.DaySummary {
        let ctx = ModelContext(container)
        var d = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == workoutID })
        d.fetchLimit = 1
        let dayKey = (try? ctx.fetch(d).first)?.dayKey ?? ""
        let sets = await sessionSets(workoutID: workoutID)
        return TrainingSummary.summarizeDay(dayKey: dayKey, sets: sets)
    }

    /// 周汇总 + 与上周对比
    public func weekComparison(containing date: Date = Date()) async
        -> (this: TrainingSummary.WeekSummary, last: TrainingSummary.WeekSummary,
            comparison: TrainingSummary.Comparison) {
        if Date().timeIntervalSince(cacheStamp) < Self.cacheTTL, let hit = cacheWeek {
            return hit
        }
        let ctx = ModelContext(container)
        let cal = Calendar.current
        let thisInterval = TrainingSummary.weekInterval(containing: date, calendar: cal)
        let lastInterval = TrainingSummary.weekInterval(
            containing: cal.date(byAdding: .day, value: -7, to: date) ?? date, calendar: cal)
        let all = mapSets(ctx, (try? ctx.fetch(FetchDescriptor<SetLog>())) ?? [])
        let thisWeek = TrainingSummary.summarizeWeek(sets: all, interval: thisInterval)
        let lastWeek = TrainingSummary.summarizeWeek(sets: all, interval: lastInterval)
        let cmp = TrainingSummary.compare(thisWeek: thisWeek, lastWeek: lastWeek)
        cacheWeek = (thisWeek, lastWeek, cmp)
        cacheStamp = Date()
        return (thisWeek, lastWeek, cmp)
    }

    /// 单动作进步曲线
    public func progress(exerciseID: String, now: Date = Date()) async -> TrainingSummary.Progress {
        let ctx = ModelContext(container)
        let logs = (try? ctx.fetch(FetchDescriptor<SetLog>(predicate: #Predicate {
            $0.exerciseID == exerciseID
        }, sortBy: [SortDescriptor(\.loggedAt)]))) ?? []
        return TrainingSummary.progress(exerciseID: exerciseID, sets: mapSets(ctx, logs), now: now)
    }

    /// 有记录的动作列表（供进步页选择）
    public func trainedExerciseIDs() async -> [(id: String, name: String, count: Int)] {
        let ctx = ModelContext(container)
        let logs = (try? ctx.fetch(FetchDescriptor<SetLog>())) ?? []
        let sets = mapSets(ctx, logs)
        var counts: [String: (String, Int)] = [:]
        for s in sets { counts[s.exerciseID, default: (s.exerciseName, 0)].1 += 1 }
        return counts.map { (id: $0.key, name: $0.value.0, count: $0.value.1) }
            .sorted { $0.count > $1.count }
    }

    /// 历史会话列表（按开始时间倒序）
    public struct SessionSummary: Sendable, Identifiable {
        public var id: String
        public var dayKey: String
        public var start: Date
        public var end: Date
        public var isActive: Bool
        public var totalSets: Int
        public var volumeKg: Double
        public var focus: TrainingSummary.Focus
        public var exerciseNames: [String]
    }

    public func recentSessions(limit: Int = 30, days: Int = 60) async -> [SessionSummary] {
        let ctx = ModelContext(container)
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        var d = FetchDescriptor<Workout>(predicate: #Predicate {
            $0.source == "manual" && $0.start >= since
        }, sortBy: [SortDescriptor(\.start, order: .reverse)])
        d.fetchLimit = limit
        let workouts = (try? ctx.fetch(d)) ?? []
        let allLogs = (try? ctx.fetch(FetchDescriptor<SetLog>())) ?? []
        var byWorkout: [String: [SetLog]] = [:]
        for l in allLogs { byWorkout[l.workoutID, default: []].append(l) }
        return workouts.map { w in
            let sets = mapSets(ctx, byWorkout[w.id] ?? [])
            var ms: [String: Int] = [:]
            for s in sets { ms[s.muscleGroup, default: 0] += 1 }
            var names: [String] = []
            for s in sets where !names.contains(s.exerciseName) { names.append(s.exerciseName) }
            return SessionSummary(id: w.id, dayKey: w.dayKey, start: w.start, end: w.end,
                                  isActive: w.isActive, totalSets: sets.count,
                                  volumeKg: sets.reduce(0) { $0 + $1.volumeKg },
                                  focus: TrainingSummary.focus(from: ms), exerciseNames: names)
        }
    }

    // MARK: - 同步接收

    func importSetLog(_ dto: SetLogDTO) async {
        let ctx = ModelContext(container)
        if dto.deleted {
            if let e = fetchSet(ctx, dto.workoutID, dto.exerciseID, dto.order) { ctx.delete(e) }
            try? ctx.save()
            return
        }
        if let e = fetchSet(ctx, dto.workoutID, dto.exerciseID, dto.order) {
            e.reps = dto.reps
            e.weightKg = dto.weightKg
            e.loggedAt = dto.loggedAt
        } else {
            ctx.insert(SetLog(workoutID: dto.workoutID, exerciseID: dto.exerciseID,
                              reps: dto.reps, weightKg: dto.weightKg, order: dto.order,
                              loggedAt: dto.loggedAt))
        }
        try? ctx.save()
    }

    func importSession(_ dto: WorkoutSessionDTO) async {
        let ctx = ModelContext(container)
        var d = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == dto.id })
        d.fetchLimit = 1
        let existing = try? ctx.fetch(d).first
        if dto.deleted {
            if let w = existing {
                for s in (try? ctx.fetch(FetchDescriptor<SetLog>(predicate: #Predicate {
                    $0.workoutID == dto.id
                }))) ?? [] { ctx.delete(s) }
                ctx.delete(w)
            }
            try? ctx.save()
            return
        }
        if let w = existing {
            w.end = dto.end
            w.isActive = dto.isActive
            w.dayKey = dto.dayKey
        } else {
            ctx.insert(Workout(id: dto.id, dayKey: dto.dayKey, start: dto.start, end: dto.end,
                               type: dto.type, source: dto.source, isActive: dto.isActive))
        }
        try? ctx.save()
    }

    // MARK: - 内部

    private func mapSets(_ ctx: ModelContext, _ logs: [SetLog]) -> [TrainingSummary.TrainingSet] {
        let lookup = exerciseLookup(ctx)
        return logs.map { mapOne($0, lookup) }
    }

    private func mapOne(_ l: SetLog,
                        _ lookup: [String: (name: String, muscle: String)])
        -> TrainingSummary.TrainingSet {
        let ex = lookup[l.exerciseID]
        return TrainingSummary.TrainingSet(workoutID: l.workoutID, exerciseID: l.exerciseID,
                                           exerciseName: ex?.name ?? l.exerciseID,
                                           muscleGroup: ex?.muscle ?? "其他",
                                           reps: l.reps, weightKg: l.weightKg,
                                           order: l.order, date: l.loggedAt)
    }

    private func fetchSet(_ ctx: ModelContext, _ workoutID: String,
                          _ exerciseID: String, _ order: Int) -> SetLog? {
        let d = FetchDescriptor<SetLog>(predicate: #Predicate {
            $0.workoutID == workoutID && $0.exerciseID == exerciseID && $0.order == order
        })
        return try? ctx.fetch(d).first
    }

    private func nextOrder(_ ctx: ModelContext, workoutID: String, exerciseID: String) -> Int {
        let d = FetchDescriptor<SetLog>(predicate: #Predicate {
            $0.workoutID == workoutID && $0.exerciseID == exerciseID
        })
        let existing = (try? ctx.fetch(d)) ?? []
        return (existing.map(\.order).max() ?? 0) + 1
    }

    private func touchSession(_ ctx: ModelContext, id: String, now: Date) {
        var d = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        guard let w = try? ctx.fetch(d).first else { return }
        w.end = now
        if !w.isActive { w.isActive = true }
    }

    // MARK: - 同步发送

    private func syncSet(_ entry: SetLog, deleted: Bool) {
        send(SetLogDTO(workoutID: entry.workoutID, exerciseID: entry.exerciseID,
                       order: entry.order, reps: entry.reps, weightKg: entry.weightKg,
                       loggedAt: entry.loggedAt, deleted: deleted))
    }

    private func syncSession(_ w: Workout, deleted: Bool) {
        let dto = WorkoutSessionDTO(id: w.id, dayKey: w.dayKey, start: w.start, end: w.end,
                                    isActive: w.isActive, type: w.type, source: w.source,
                                    deleted: deleted)
        Task { @MainActor in
            guard let data = try? JSONEncoder().encode(dto) else { return }
            WCSyncService.shared.sendSetLogPayload(data, kind: .session)
        }
    }

    private func send(_ dto: SetLogDTO) {
        Task { @MainActor in
            guard let data = try? JSONEncoder().encode(dto) else { return }
            WCSyncService.shared.sendSetLogPayload(data, kind: .setLog)
        }
    }
}

private extension Dictionary {
    /// 仅在非空时返回（缓存判断用）
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
