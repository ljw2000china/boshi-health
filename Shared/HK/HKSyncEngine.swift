import Foundation
import HealthKit

/// HealthKit → RawSample 的增量同步（design.md §5）。
/// - 每类型一个 HKAnchoredObjectQuery，anchor 持久化（首次回填最近 60 天）
/// - HKObserverQuery 订阅变化触发增量（前台 + 系统交付时）
/// - 落库去重（hkUUID 唯一）；样本来源一律 .system（HealthKit 原样采集）
public actor HKSyncEngine {

    public static let shared = HKSyncEngine()

    private let store = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []
    private var syncing = false

    private init() {}

    private static let anchorPrefix = "pulse.hk.anchor."
    private static let firstSyncKey = "pulse.hk.firstSyncDone"

    // MARK: - 同步入口

    /// 强制重拉：清除全部 anchor，按各类型回填窗口重新同步（修复「授权前 anchor 已推进导致历史丢数据」）。
    public func resyncAll() async {
        let defaults = UserDefaults.standard
        for entry in HKTypeRegistry.readEntries {
            defaults.removeObject(forKey: Self.anchorPrefix + entry.identifier)
        }
        await syncAll()
    }

    /// 全量/增量同步全部读类型（可被 observer 与手动调用）。
    public func syncAll() async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        for entry in HKTypeRegistry.readEntries {
            await syncOne(entry)
        }
        UserDefaults.standard.set(true, forKey: Self.firstSyncKey)
    }

    private func syncOne(_ entry: HKTypeEntry) async {
        let type = entry.sampleType
        let anchorKey = Self.anchorPrefix + entry.identifier
        let anchorData = UserDefaults.standard.data(forKey: anchorKey)
        let anchor: HKQueryAnchor? = anchorData.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        // 每类型独立回填：anchor 为空时按该类型回填窗口拉全量（不依赖全局 firstSync 标记——
        // 否则首次同步发生在授权完成前会导致 anchor 推进、历史数据永久丢失）。
        // 心率为高频样本（1/min），回填窗口收窄防内存峰值。
        let backfillDays = entry.backfillDays
        let start = (anchor == nil) ? Date().addingTimeInterval(-Double(backfillDays) * 24 * 3600) : nil

        let (samples, deleted, newAnchor, errDesc) = await withCheckedContinuation { cont in
            let q = HKAnchoredObjectQuery(type: type,
                                          predicate: start.map { HKQuery.predicateForSamples(withStart: $0, end: nil) },
                                          anchor: anchor, limit: HKObjectQueryNoLimit) { _, s, d, a, e in
                cont.resume(returning: (s ?? [], d ?? [], a, e?.localizedDescription))
            }
            store.execute(q)
        }
        PulseLog.write("sync \(entry.identifier) anchor=\(anchor != nil) got=\(samples.count) del=\(deleted.count) err=\(errDesc ?? "-")")
        guard let newAnchor else { return }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: newAnchor, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: anchorKey)
        }
        guard !samples.isEmpty || !deleted.isEmpty else { return }
        // 丢弃 Pulse 自己写回的睡眠样本：否则「推测 → 写回健康 → 被读回当系统分期」形成反馈环，
        // 窗口来源标签失真（应为「活动推测」而变成「系统原生」）。
        let usable = samples.filter { !Self.isPulseSleepWriteback($0) }
        PulseLog.write("  → ingest \(usable.count) usable")
        await DataPipeline.shared.ingest(samples: usable.map(mapSample(_:)),
                                         deletedUUIDs: deleted.map(\.uuid))
    }

    /// 是否为 Pulse 睡眠回写样本（依据写入时打的同步标识元数据）
    private static func isPulseSleepWriteback(_ sample: HKSample) -> Bool {
        guard sample.sampleType.identifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue else { return false }
        if let sync = sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
           sync.hasPrefix("pulse.sleep.") { return true }
        if sample.metadata?["PulseInferredSleep"] != nil { return true }
        return sample.sourceRevision.source.bundleIdentifier.hasPrefix("com.boshi")
    }

    // MARK: - 变化订阅

    /// 启动观察查询（每次变化触发 syncOne）。enableBackgroundDelivery(.hourly)。
    /// 电量：被动数据后台交付为系统行为（design.md §12 可忽略）；L2 唤醒走 BGAppRefreshTask。
    public func startObservers(onChange: @escaping (String) -> Void) async {
        for entry in HKTypeRegistry.readEntries {
            let q = HKObserverQuery(sampleType: entry.sampleType, predicate: nil) { [weak self] _, completion, _ in
                onChange(entry.identifier)
                Task {
                    await self?.syncOne(entry)
                    completion()
                }
            }
            store.execute(q)
            observerQueries.append(q)
            try? await store.enableBackgroundDelivery(for: entry.sampleType, frequency: .hourly)
        }
    }

    public func stopObservers() {
        for q in observerQueries { store.stop(q) }
        observerQueries.removeAll()
    }

    // MARK: - 样本映射

    /// HKSample → RawSample（纯值构造，落库在 DataPipeline）
    public func mapSample(_ sample: HKSample) -> RawSamplePayload {
        var subtype = ""
        var value = 0.0
        let identifier = sample.sampleType.identifier
        if let cat = sample as? HKCategorySample {
            // 睡眠阶段名（asleepCore/awake/...）
            subtype = SleepCategoryStage(rawValue: cat.value).map(\.name) ?? ""
            value = Double(cat.value)
        } else if let q = sample as? HKQuantitySample {
            let entry = HKTypeRegistry.readEntries.first { $0.identifier == identifier }
            if let unit = entry?.unit {
                value = q.quantity.doubleValue(for: unit)
            } else if identifier == HKQuantityTypeIdentifier.appleStandTime.rawValue {
                value = q.quantity.doubleValue(for: .second()) / 60
            } else {
                value = q.quantity.doubleValue(for: .count())
            }
        } else if let w = sample as? HKWorkout {
            subtype = String(w.workoutActivityType.rawValue)
            // value 存总能量 kcal（Strain 计算用）；时长由 end-start 可得
            value = w.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
        }
        return RawSamplePayload(hkUUID: sample.uuid.uuidString, type: identifier, subtype: subtype,
                                value: value, start: sample.startDate, end: sample.endDate,
                                source: SampleSource.system.rawValue)
    }
}

/// 传递用值类型（避免 SyncEngine 依赖 SwiftData）
public struct RawSamplePayload {
    public var hkUUID: String
    public var type: String
    public var subtype: String
    public var value: Double
    public var start: Date
    public var end: Date
    public var source: String
    public init(hkUUID: String, type: String, subtype: String, value: Double,
                start: Date, end: Date, source: String) {
        self.hkUUID = hkUUID; self.type = type; self.subtype = subtype
        self.value = value; self.start = start; self.end = end; self.source = source
    }
}

/// HKCategoryTypeSleepAnalysis value → 阶段名（与 SleepSegment.stage 对齐）
public enum SleepCategoryStage: Int {
    case inBed = 0
    case asleepUnspecified = 1
    case awake = 2
    case asleepCore = 3
    case asleepDeep = 4
    case asleepREM = 5

    public var name: String {
        switch self {
        case .inBed: return "inBed"
        case .asleepUnspecified: return "asleepUnspecified"
        case .awake: return "awake"
        case .asleepCore: return "asleepCore"
        case .asleepDeep: return "asleepDeep"
        case .asleepREM: return "asleepREM"
        }
    }
}
