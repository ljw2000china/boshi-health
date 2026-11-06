import Foundation
import HealthKit

#if os(watchOS)
import WatchKit
#endif

/// L2 睡眠窗延伸的后台驱动（design.md §6）。
///
/// watchOS 没有 BGTaskScheduler — 用 `WKExtension.scheduleBackgroundRefresh`：
/// 窗口结束后 3h 内、app 进后台时调度一次刷新，唤醒时执行 L2 判定。
/// 电量：3h 为硬上限（SleepWindowBuilder.L2Tracker.extensionLimitSec），
/// 锁定或超时后不再调度；每次唤醒只做一次轻量判定（4 个 HK 查询）。
public enum L2Background {

    private static let store = HKHealthStore()

    // MARK: - 调度

    /// 进后台时调用：若存在 3h 内刚结束的未锁定窗口 → 调度一次刷新
    @MainActor
    public static func scheduleIfNeeded() async {
        guard let window = await latestRecentWindow(), !window.l2Locked else {
            cancelRefresh()
            return
        }
        let elapsed = Date().timeIntervalSince(window.end)
        guard elapsed > 0, elapsed < SleepWindowBuilder.L2Tracker.extensionLimitSec else {
            cancelRefresh()
            return
        }
        let nextCheck = Date(timeIntervalSinceNow: 15 * 60)
        #if os(watchOS)
        WKExtension.shared().scheduleBackgroundRefresh(
            withPreferredDate: nextCheck,
            userInfo: nil,
            scheduledCompletion: { _ in })
        #endif
    }

    /// 取消任何已排定的后台刷新
    public static func cancelRefresh() {
        #if os(watchOS)
        WKExtension.shared().scheduleBackgroundRefresh(
            withPreferredDate: .distantFuture,
            userInfo: nil,
            scheduledCompletion: { _ in })
        #endif
    }

    // MARK: - 判定

    /// 执行一次 L2 判定。唤醒时调用（handle(_:) 或 app 前台激活）。
    public static func runCheck() async -> Bool {
        guard let window = await latestRecentWindow() else { return true }
        let since = window.end
        async let steps = sumQuantity(.stepCount, from: since)
        async let stand = sumQuantity(.appleStandTime, from: since) // 秒 → 分
        async let energy = avgEnergyPerMin(from: since)
        async let hr = latestHeartRate(from: since.addingTimeInterval(-5 * 60))
        let charging = isCharging()

        let result = await DataPipeline.shared.runL2Check(
            stepsSinceEnd: await steps,
            standMinSinceEnd: await stand / 60,
            kcalPerMin: await energy,
            hr: await hr ?? 0,
            charging: charging)
        if case .extended = result { return true }
        return true
    }

    private struct WindowInfo {
        var end: Date
        var l2Locked: Bool
    }

    private static func latestRecentWindow() async -> WindowInfo? {
        let key = SleepWindowBuilder.dayKey(for: Date().addingTimeInterval(-12 * 3600))
        let todayKey = SleepWindowBuilder.dayKey(for: Date())
        for k in [todayKey, key] {
            if let w = await DataPipeline.shared.latestSleepWindow(dayKey: k) {
                let elapsed = Date().timeIntervalSince(w.end)
                if elapsed >= 0 && elapsed <= SleepWindowBuilder.L2Tracker.extensionLimitSec {
                    return WindowInfo(end: w.end, l2Locked: false)
                }
            }
        }
        return nil
    }

    // MARK: - HK 查询（轻量）

    private static func sumQuantity(_ id: HKQuantityTypeIdentifier, from: Date) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return 0 }
        let unit: HKUnit = id == .appleStandTime ? .second() : .count()
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type,
                                      quantitySamplePredicate: HKQuery.predicateForSamples(withStart: from, end: nil),
                                      options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }

    /// 窗口结束以来的平均活动能量率（kcal/min）
    private static func avgEnergyPerMin(from: Date) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type,
                                      quantitySamplePredicate: HKQuery.predicateForSamples(withStart: from, end: nil),
                                      options: .cumulativeSum) { _, stats, _ in
                let kcal = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                let minutes = max(1, Date().timeIntervalSince(from) / 60)
                cont.resume(returning: kcal / minutes)
            }
            store.execute(q)
        }
    }

    private static func latestHeartRate(from: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type,
                                  predicate: HKQuery.predicateForSamples(withStart: from, end: nil),
                                  limit: 1,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, _ in
                let v = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                cont.resume(returning: v)
            }
            store.execute(q)
        }
    }

    private static func isCharging() -> Bool {
        #if os(watchOS)
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        let state = device.batteryState
        device.isBatteryMonitoringEnabled = false
        return state == .charging || state == .full
        #else
        return false
        #endif
    }
}
