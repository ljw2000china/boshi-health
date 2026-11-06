import Foundation
import SwiftData

/// 组次记录服务（design.md §8）：记组、休息计时、参考值查询。
public actor SetLogger {

    public static let shared = SetLogger()
    let container = PulseStore.shared
    private init() {}

    // MARK: - 记组

    /// 记录一组
    /// - returns: 新组序号
    @discardableResult
    public func log(workoutID: String, exerciseID: String,
                    reps: Int, weightKg: Double, restSec: Int = 90) async -> Int {
        let ctx = ModelContext(container)
        let order = nextOrder(ctx, workoutID: workoutID, exerciseID: exerciseID)
        let entry = SetLog(workoutID: workoutID, exerciseID: exerciseID,
                           reps: reps, weightKg: weightKg, restSec: restSec, order: order)
        ctx.insert(entry)
        try? ctx.save()
        return order
    }

    /// 读取某动作在某训练中的所有组
    public func sets(workoutID: String, exerciseID: String) async -> [SetLog] {
        let ctx = ModelContext(container)
        var d = FetchDescriptor<SetLog>(predicate: #Predicate {
            $0.workoutID == workoutID && $0.exerciseID == exerciseID
        }, sortBy: [SortDescriptor(\.order)])
        return (try? ctx.fetch(d)) ?? []
    }

    /// 删除一组
    public func delete(workoutID: String, exerciseID: String, order: Int) async {
        let ctx = ModelContext(container)
        var d = FetchDescriptor<SetLog>(predicate: #Predicate {
            $0.workoutID == workoutID && $0.exerciseID == exerciseID && $0.order == order
        })
        for s in (try? ctx.fetch(d)) ?? [] { ctx.delete(s) }
        try? ctx.save()
    }

    // MARK: - 参考值

    /// 上次做某动作的最后一组（重量×次数）
    public func lastSet(of exerciseID: String, before workoutID: String? = nil) async -> (weightKg: Double, reps: Int)? {
        let ctx = ModelContext(container)
        var d = FetchDescriptor<SetLog>(predicate: #Predicate {
            $0.exerciseID == exerciseID
        }, sortBy: [SortDescriptor(\.loggedAt, order: .reverse)])
        d.fetchLimit = 1
        guard let s = try? ctx.fetch(d).first else { return nil }
        return (s.weightKg, s.reps)
    }

    /// 上次某动作所有组的平均次数 ≥ 目标 → 建议 +2.5kg（design.md §8 渐进建议）
    public func progressiveSuggestion(exerciseID: String, targetReps: Int) async -> Double? {
        let ctx = ModelContext(container)
        var d = FetchDescriptor<SetLog>(predicate: #Predicate {
            $0.exerciseID == exerciseID
        }, sortBy: [SortDescriptor(\.loggedAt, order: .reverse)])
        d.fetchLimit = 20
        let recent = (try? ctx.fetch(d)) ?? []
        guard !recent.isEmpty else { return nil }
        // 取最近一次训练的组
        let lastWorkoutID = recent.first?.workoutID ?? ""
        let lastSets = recent.filter { $0.workoutID == lastWorkoutID }
        guard !lastSets.isEmpty else { return nil }
        let avgReps = Double(lastSets.reduce(0) { $0 + $1.reps }) / Double(lastSets.count)
        guard avgReps >= Double(targetReps) else { return nil }
        let lastWeight = lastSets.map(\.weightKg).max() ?? 0
        return lastWeight + 2.5
    }

    // MARK: - 内部

    private func nextOrder(_ ctx: ModelContext, workoutID: String, exerciseID: String) -> Int {
        var d = FetchDescriptor<SetLog>(predicate: #Predicate {
            $0.workoutID == workoutID && $0.exerciseID == exerciseID
        }, sortBy: [SortDescriptor(\.order, order: .reverse)])
        d.fetchLimit = 1
        return ((try? ctx.fetch(d).first)?.order ?? 0) + 1
    }
}
