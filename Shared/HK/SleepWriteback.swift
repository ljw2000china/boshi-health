import Foundation
import HealthKit

#if os(watchOS)
/// 睡眠回写 HealthKit（推测窗口 → 健康 App「睡眠」）。
///
/// 为什么放在手表侧：手表是数据的原始来源与主要持有者，其本地 Health 库写回后会由
/// iCloud 健康同步到手机；手机上再写一次会产生重复样本（两侧 bundle 不同，同步标识无法互相替换）。
///
/// 三条安全规则：
/// 1. 只回写「推测来源」的窗口 —— 系统分期本来就在健康里，无需再写；
/// 2. 写入前查询健康内该时段是否已有**非 Pulse** 睡眠样本 —— 有则跳过，绝不与原生数据打架；
/// 3. 使用 `HKMetadataKeySyncIdentifier` + version 幂等替换 —— 同一晚反复重算只会更新不会堆积。
///
/// 配套：`HKSyncEngine` 读回时会**丢弃** Pulse 自己写回的睡眠样本，避免
/// 「推测 → 写回 → 被当成系统分期 → 标签失真」的反馈环。
public actor SleepWriteback {

    public static let shared = SleepWriteback()

    /// 用户开关（默认开启，用户明确要求把睡眠同步到健康）
    public static let enabledKey = "pulse.sleep.writeback.enabled"
    public static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private let store = HKHealthStore()
    /// 同步标识前缀（用于识别「我们自己写的」样本）
    static let syncPrefix = "pulse.sleep."
    /// 自定义元数据：标记为活动推测
    static let inferredKey = "PulseInferredSleep"
    /// 已回写版本记录（便于跳过重复查询）
    static let writtenKeyPrefix = "pulse.sleep.written."

    public enum Outcome: String, Sendable {
        case written = "已写入健康"
        case disabled = "开关已关闭"
        case unavailable = "设备不支持健康"
        case nativeExists = "健康已有原生睡眠数据，跳过"
        case denied = "健康写入权限被拒绝"
        case invalid = "窗口无效"
        case failed = "写入失败"
    }

    /// 回写某一晚的推测窗口（幂等）。
    public func write(dayKey: String, start: Date, end: Date, version: Int) async -> Outcome {
        guard Self.isEnabled else { return .disabled }
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        guard end > start, end.timeIntervalSince(start) >= 20 * 60 else { return .invalid }
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return .unavailable }
        // 已写过同一版本（或更新版本）→ 直接跳过，避免每次重算都查健康
        if let written = UserDefaults.standard.string(forKey: Self.writtenKeyPrefix + dayKey),
           let v = Int(written), v >= version { return .written }

        if store.authorizationStatus(for: type) == .sharingDenied { return .denied }

        // 规则 2：同区间内已有非 Pulse 的睡眠样本（系统分期 / 第三方）→ 让位，不写
        if await hasForeignSleep(type: type, start: start, end: end) { return .nativeExists }

        let sample = HKCategorySample(
            type: type,
            value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            start: start,
            end: end,
            metadata: [
                HKMetadataKeySyncIdentifier: Self.syncPrefix + dayKey,
                HKMetadataKeySyncVersion: version,
                Self.inferredKey: true,
            ])
        do {
            try await store.save(sample)
            UserDefaults.standard.set(String(version), forKey: Self.writtenKeyPrefix + dayKey)
            return .written
        } catch {
            return .failed
        }
    }

    /// 删除某晚由 Pulse 写回的样本（系统分期出现后让位原生数据）
    public func delete(dayKey: String) async {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: nil, options: [])
        let samples: [HKSample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, _ in
                cont.resume(returning: s ?? [])
            }
            store.execute(q)
        }
        let ours = samples.filter { s in
            (s.metadata?[HKMetadataKeySyncIdentifier] as? String) == Self.syncPrefix + dayKey
        }
        UserDefaults.standard.removeObject(forKey: Self.writtenKeyPrefix + dayKey)
        guard !ours.isEmpty else { return }
        try? await store.delete(ours)
    }

    /// 查询某时段内的睡眠样本，判断是否存在非 Pulse 写入的样本。
    private func hasForeignSleep(type: HKCategoryType, start: Date, end: Date) async -> Bool {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples: [HKSample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, _ in
                cont.resume(returning: s ?? [])
            }
            store.execute(q)
        }
        return samples.contains { s in
            let ourWrite = (s.metadata?[HKMetadataKeySyncIdentifier] as? String)?
                .hasPrefix(Self.syncPrefix) ?? false
            return !ourWrite
        }
    }
}
#endif
