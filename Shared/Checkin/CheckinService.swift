import Foundation
import SwiftData

/// 每日打卡（精力/酸痛，1–5）。
/// 打卡写入 DailyMetric，触发当日评分重算（打卡小权重进 Recovery）。
public actor CheckinService {

    public static let shared = CheckinService()
    let container = PulseStore.shared

    private init() {}

    /// 打卡能量 1–5
    public func checkinEnergy(_ level: Int, dayKey: String? = nil) async {
        await write(energy: level, soreness: nil, dayKey: dayKey ?? SleepWindowBuilder.dayKey(for: Date()))
    }

    /// 打卡酸痛 1–5
    public func checkinSoreness(_ level: Int, dayKey: String? = nil) async {
        await write(energy: nil, soreness: level, dayKey: dayKey ?? SleepWindowBuilder.dayKey(for: Date()))
    }

    /// 读取今日打卡
    public func today() async -> (energy: Int?, soreness: Int?) {
        let ctx = ModelContext(container)
        let dayKey = SleepWindowBuilder.dayKey(for: Date())
        var d = FetchDescriptor<DailyMetric>(predicate: #Predicate { $0.dateKey == dayKey })
        d.fetchLimit = 1
        let m = try? ctx.fetch(d).first
        return (m?.energy, m?.soreness)
    }

    /// 读取昨日打卡
    public func yesterday() async -> (energy: Int?, soreness: Int?) {
        let ctx = ModelContext(container)
        let dayKey = SleepWindowBuilder.dayKey(for: Date().addingTimeInterval(-24 * 3600))
        var d = FetchDescriptor<DailyMetric>(predicate: #Predicate { $0.dateKey == dayKey })
        d.fetchLimit = 1
        let m = try? ctx.fetch(d).first
        return (m?.energy, m?.soreness)
    }

    // MARK: - 写入

    private func write(energy: Int?, soreness: Int?, dayKey: String) async {
        let ctx = ModelContext(container)
        var d = FetchDescriptor<DailyMetric>(predicate: #Predicate { $0.dateKey == dayKey })
        d.fetchLimit = 1
        let m = (try? ctx.fetch(d).first) ?? DailyMetric(dateKey: dayKey)
        if let e = energy { m.energy = e }
        if let s = soreness { m.soreness = s }
        ctx.insert(m)
        try? ctx.save()
        // 重算当日评分（打卡是 Recovery 的小权重输入）
        await DataPipeline.shared.recomputeDayScoring(dayKey: dayKey)
    }
}
