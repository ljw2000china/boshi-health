import Foundation
import HealthKit

/// HealthKit 服务：M0 仅授权请求 + 调试查询封装。
///
/// 注意：HealthKit 不回读「读权限」的授权状态（隐私设计），
/// 这里的状态机表达「设备是否可用」与「是否已发起过请求」。
/// 未授权/被拒时查询正常返回空，由调试页空态展示。
@MainActor
public final class HKService: ObservableObject {

    public static let shared = HKService()

    /// 授权流程状态
    public enum AuthState: String {
        case unavailable  // 设备不支持 HealthKit
        case notRequested // 尚未发起授权请求
        case requested    // 已发起请求（读权限状态无法回读）
        case failed       // 请求过程出错
    }

    @Published public private(set) var authState: AuthState = .notRequested

    /// 底层 store（线程安全，允许后台隔离方法直接访问）
    public nonisolated let store = HKHealthStore()

    private static let requestedKey = "pulse.hk.auth.requested"

    private init() {
        if !HKHealthStore.isHealthDataAvailable() {
            authState = .unavailable
        } else if UserDefaults.standard.bool(forKey: Self.requestedKey) {
            authState = .requested
        }
    }

    /// App 启动时调用：请求 design.md §10 全部读类型 + 写类型（workout；手表另含睡眠）。
    /// 注意：必须每启动都调用——授权是增量幂等的，只有新增类型时系统才会弹窗
    /// （例如老版本用户升级后新增的睡眠写权限，若提前 return 就永远拿不到权限）。
    public func requestAuthorizationIfNeeded() async {
        guard authState != .unavailable else { return }
        do {
            try await store.requestAuthorization(toShare: HKTypeRegistry.writeTypes,
                                                 read: HKTypeRegistry.readTypes)
            UserDefaults.standard.set(true, forKey: Self.requestedKey)
            authState = .requested
            PulseLog.write("auth OK (read=\(HKTypeRegistry.readTypes.count) write=\(HKTypeRegistry.writeTypes.count))")
            // 授权后立刻验证一次读能力（授权前查询只会返回空，无法回读状态）
            if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
                let n = await countSamples(sleep, days: 7)
                PulseLog.write("  auth verify sleep7d=\(n)")
            }
            if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
                let n = await countSamples(steps, days: 7)
                PulseLog.write("  auth verify steps7d=\(n)")
            }
        } catch {
            authState = .failed
            PulseLog.write("auth FAILED: \(error.localizedDescription)")
        }
    }

    /// 近 N 天样本计数（授权后自检用）
    private func countSamples(_ type: HKSampleType, days: Int) async -> Int {
        await withCheckedContinuation { cont in
            let start = Date().addingTimeInterval(-Double(days) * 86400)
            let p = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
            let q = HKSampleQuery(sampleType: type, predicate: p, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, s, _ in
                cont.resume(returning: s?.count ?? 0)
            }
            store.execute(q)
        }
    }

    // MARK: - 调试查询

    /// 24h 计数拉取上限：防止高频样本（心率等）全量驻留造成内存峰值；超限显示「≥N」。
    private static let debugCountLimit = 5000

    /// 每类样本的调试汇总：最新值 + 更新时间 + 最近 24h 计数。
    /// 顺序与 HKTypeRegistry.readEntries 一致。
    public func debugSummaries() async -> [DebugTypeSummary] {
        let now = Date()
        let start = now.addingTimeInterval(-24 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [])

        var result: [DebugTypeSummary] = []
        for entry in HKTypeRegistry.readEntries {
            let type = entry.sampleType
            let latest = await runSampleQuery(type: type, predicate: nil, limit: 1).first
            // 24h 计数限量拉取（上限+1 判断是否截断），防内存峰值；仅调试页手动刷新时执行。
            let recent = await runSampleQuery(type: type, predicate: predicate, limit: Self.debugCountLimit + 1)
            result.append(DebugTypeSummary(
                typeIdentifier: entry.identifier,
                displayName: entry.nameZh,
                latestValueText: latest.map { self.valueText(for: $0, entry: entry) } ?? "",
                latestDate: latest?.endDate,
                last24hCount: min(recent.count, Self.debugCountLimit),
                last24hTruncated: recent.count > Self.debugCountLimit
            ))
        }
        return result
    }

    /// 某类型的样本明细（手机调试页点入查看），默认最近 200 条。
    public func debugSamples(typeIdentifier: String, limit: Int = 200) async -> [DebugSample] {
        guard let entry = HKTypeRegistry.entry(for: typeIdentifier) else { return [] }
        let samples = await runSampleQuery(type: entry.sampleType, predicate: nil, limit: limit)
        return samples.map { sample in
            DebugSample(
                id: sample.uuid,
                typeIdentifier: entry.identifier,
                displayName: entry.nameZh,
                valueText: valueText(for: sample, entry: entry),
                startDate: sample.startDate,
                endDate: sample.endDate,
                sourceName: sample.sourceRevision.source.name
            )
        }
    }

    // MARK: - 内部

    /// 通用样本查询：按 endDate 倒序，回调切回 continuation。
    private nonisolated func runSampleQuery(type: HKSampleType,
                                            predicate: NSPredicate?,
                                            limit: Int) async -> [HKSample] {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }

    /// 样本值 → 展示文本（按注册项的格式化方式）
    private func valueText(for sample: HKSample, entry: HKTypeEntry) -> String {
        switch entry.format {
        case .decimal0, .decimal1, .decimal2:
            guard let q = sample as? HKQuantitySample, let unit = entry.unit else { return "—" }
            let v = q.quantity.doubleValue(for: unit)
            switch entry.format {
            case .decimal0: return String(format: "%.0f", v)
            case .decimal1: return String(format: "%.1f", v)
            default:        return String(format: "%.2f", v)
            }
        case .percent:
            guard let q = sample as? HKQuantitySample, let unit = entry.unit else { return "—" }
            return String(format: "%.0f%%", q.quantity.doubleValue(for: unit) * 100)
        case .distanceKm:
            guard let q = sample as? HKQuantitySample, let unit = entry.unit else { return "—" }
            return String(format: "%.2f km", q.quantity.doubleValue(for: unit) / 1000)
        case .sleepCategory:
            guard let c = sample as? HKCategorySample,
                  let v = HKCategoryValueSleepAnalysis(rawValue: c.value) else { return "—" }
            return Self.sleepCategoryName(v)
        case .workout:
            guard let w = sample as? HKWorkout else { return "—" }
            return "\(Self.workoutActivityName(w.workoutActivityType)) \(Int(w.duration / 60))分钟"
        }
    }

    /// 睡眠分类 → 中文
    private static func sleepCategoryName(_ value: HKCategoryValueSleepAnalysis) -> String {
        switch value {
        case .inBed:            return "卧床"
        case .asleepUnspecified: return "睡眠"
        case .awake:            return "清醒"
        case .asleepCore:       return "核心睡眠"
        case .asleepDeep:       return "深睡"
        case .asleepREM:        return "快速眼动"
        @unknown default:       return "未知"
        }
    }

    /// 常见训练类型 → 中文
    private static func workoutActivityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:                        return "跑步"
        case .walking:                        return "步行"
        case .cycling:                        return "骑行"
        case .swimming:                       return "游泳"
        case .traditionalStrengthTraining:    return "力量训练"
        case .functionalStrengthTraining:     return "功能性力量"
        case .elliptical:                     return "椭圆机"
        case .yoga:                           return "瑜伽"
        case .hiking:                         return "徒步"
        case .other:                          return "其他"
        default:                              return "运动(\(type.rawValue))"
        }
    }
}
