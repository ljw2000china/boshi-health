import Foundation
import HealthKit

/// 睡眠数据诊断：告诉用户「手机里到底有没有数据」，避免空态黑盒。
public enum SleepDiagnostics {

    public struct TypeReport: Sendable {
        public var identifier: String
        public var nameZh: String
        public var lastSample: Date?
        public var count7d: Int
    }

    /// 关键读类型：睡眠 / 步数 / 能量 / 心率 / 静息心率 / HRV
    public static func report() async -> [TypeReport] {
        let store = HKHealthStore()
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let wanted: [(String, String)] = [
            (HKCategoryTypeIdentifier.sleepAnalysis.rawValue, "睡眠"),
            (HKQuantityTypeIdentifier.stepCount.rawValue, "步数"),
            (HKQuantityTypeIdentifier.activeEnergyBurned.rawValue, "活动能量"),
            (HKQuantityTypeIdentifier.heartRate.rawValue, "心率"),
            (HKQuantityTypeIdentifier.restingHeartRate.rawValue, "静息心率"),
            (HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue, "心率变异性"),
        ]
        let since = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        var results: [TypeReport] = []
        for (id, name) in wanted {
            guard let type = HKObjectType.quantityType(forIdentifier:
                    HKQuantityTypeIdentifier(rawValue: id)) ?? HKObjectType.categoryType(forIdentifier:
                    HKCategoryTypeIdentifier(rawValue: id)) else { continue }
            let (last, count) = await sampleInfo(store, type: type, since: since)
            results.append(TypeReport(identifier: id, nameZh: name,
                                      lastSample: last, count7d: count))
        }
        return results
    }

    private static func sampleInfo(_ store: HKHealthStore, type: HKSampleType,
                                   since: Date) async -> (Date?, Int) {
        await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: since, end: nil,
                                                        options: .strictStartDate)
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate,
                                                                     ascending: false)]) { _, samples, _ in
                cont.resume(returning: ((samples?.first?.endDate, samples?.count ?? 0)))
            }
            store.execute(q)
        }
    }
}
