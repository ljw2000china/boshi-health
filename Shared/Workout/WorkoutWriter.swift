import Foundation
import HealthKit

/// HKWorkout 写回（design.md §7：source metadata=Pulse:auto）。
/// 自动检测的训练回写 HKWorkout；同时段已有原生 workout 则只读引用不重复写。
public enum WorkoutWriter {

    private static let store = HKHealthStore()

    /// 写入一条 HKWorkout
    /// - parameters:
    ///   - start: 真实检测起点（回填）
    ///   - end: 结束时间
    ///   - type: 训练类型
    ///   - totalEnergyKcal: 总消耗（可选）
    ///   - totalDistanceM: 总距离（可选，跑步用）
    ///   - autoDetected: 是否自动检测（metadata source 标记）
    @discardableResult
    public static func write(start: Date, end: Date,
                             type: WorkoutDetector.WorkoutType,
                             totalEnergyKcal: Double? = nil,
                             totalDistanceM: Double? = nil,
                             autoDetected: Bool = true) async -> UUID? {
        let activityType = hkActivityType(for: type)
        let config = HKWorkoutConfiguration()
        config.activityType = activityType

        let metadata: [String: Any] = [
            "source": autoDetected ? "Pulse:auto" : "Pulse:manual",
        ]

        var samples: [HKSample] = []
        if let kcal = totalEnergyKcal,
           let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
            let sample = HKQuantitySample(type: energyType, quantity: quantity,
                                          start: start, end: end)
            samples.append(sample)
        }

        let workout = HKWorkout(activityType: activityType,
                                start: start, end: end,
                                workoutEvents: nil,
                                totalEnergyBurned: totalEnergyKcal.map { HKQuantity(unit: .kilocalorie(), doubleValue: $0) },
                                totalDistance: totalDistanceM.map { HKQuantity(unit: .meter(), doubleValue: $0) },
                                device: .local(),
                                metadata: metadata)
        do {
            try await store.save([workout])
            return workout.uuid
        } catch {
            return nil
        }
    }

    /// 检查同时段是否已有原生 workout（避免重复写）
    public static func hasExistingWorkout(at start: Date, end: Date) async -> Bool {
        let workoutType = HKObjectType.workoutType()
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: workoutType, predicate: pred,
                                  limit: 1, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: !(samples?.isEmpty ?? true))
            }
            store.execute(q)
        }
    }

    private static func hkActivityType(for type: WorkoutDetector.WorkoutType) -> HKWorkoutActivityType {
        switch type {
        case .strength, .traditionalStrength: return .traditionalStrengthTraining
        case .running: return .running
        case .elliptical: return .elliptical
        case .mixed: return .mixedCardio
        }
    }
}
