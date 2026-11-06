#if os(watchOS)
import Foundation
import HealthKit
import SwiftData

/// 手动力量训练会话回写 HealthKit（HKWorkout + 肌群元数据）。
/// 目的：① 健康 App 里能看到力量训练；② 表盘小组件通过 HealthKit 读取「今天练什么」。
/// 仅手表侧写入（手机侧再写会产生不同来源的重复训练）。
public actor StrengthWorkoutWriter {

    public static let shared = StrengthWorkoutWriter()

    private let store = HKHealthStore()
    private static let syncPrefix = "pulse.strength."

    /// 同步最近 N 天已结束、尚未写回的手动力量会话
    public func syncRecent(days: Int = 7, now: Date = Date()) async {
        let ctx = ModelContext(PulseStore.shared)
        let since = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate {
            $0.source == "manual" && $0.isActive == false && $0.start >= since
        }, sortBy: [SortDescriptor(\.start)])
        descriptor.fetchLimit = 50
        guard let sessions = try? ctx.fetch(descriptor), !sessions.isEmpty else { return }

        for session in sessions where !session.writtenToHK {
            let muscleGroups = muscleGroups(ctx, workoutID: session.id)
            guard !muscleGroups.isEmpty else { continue }
            await write(session, muscleGroups: muscleGroups, ctx: ctx)
        }
    }

    private func write(_ session: Workout, muscleGroups: [String], ctx: ModelContext) async {
        let end = max(session.end, session.start.addingTimeInterval(60))
        let metadata: [String: Any] = [
            TrainingDaySnapshot.metadataKey: muscleGroups.joined(separator: "+"),
            "source": "Pulse:manual",
            HKMetadataKeySyncIdentifier: Self.syncPrefix + session.id,
            HKMetadataKeySyncVersion: 1,
        ]
        let workout = HKWorkout(activityType: .traditionalStrengthTraining,
                                start: session.start, end: end,
                                duration: end.timeIntervalSince(session.start),
                                totalEnergyBurned: nil, totalDistance: nil,
                                metadata: metadata)
        do {
            try await store.save(workout)
            session.writtenToHK = true
            try? ctx.save()
        } catch {
            // 权限被拒/网络无关错误：静默跳过，下次前台再试
        }
    }

    /// 从组次推断肌群（按组数排序，最多 3 个）
    private func muscleGroups(_ ctx: ModelContext, workoutID: String) -> [String] {
        let logs = (try? ctx.fetch(FetchDescriptor<SetLog>(predicate: #Predicate {
            $0.workoutID == workoutID
        }))) ?? []
        guard !logs.isEmpty else { return [] }
        let exercises = (try? ctx.fetch(FetchDescriptor<Exercise>())) ?? []
        var lookup: [String: String] = [:]
        for e in exercises { lookup[e.id] = e.muscleGroup }
        var counts: [String: Int] = [:]
        for l in logs {
            guard let m = lookup[l.exerciseID] else { continue }
            counts[m, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(3).map(\.key)
    }

    /// 更新（例如手机端改了组数）时先删旧样本再写新样本
    public func deleteWritten(workoutID: String) async {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier,
                                                    operatorType: .equalTo,
                                                    value: Self.syncPrefix + workoutID)
        try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.deleteObjects(of: HKObjectType.workoutType(), predicate: predicate) { _, _, error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }
}
#endif
