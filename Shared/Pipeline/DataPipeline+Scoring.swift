import Foundation
import SwiftData

/// 日评分聚合（design.md §9）：把 RawSample/SleepWindow/Baseline 汇总进 DailyMetric。
/// 与 DataPipeline 同 actor 隔离；放在独立文件便于单测与阅读。
extension DataPipeline {

    /// 重算某日全部评分写入 DailyMetric（sleepScore 由睡眠窗模块写，其余在此）
    /// - parameter rebuildBaselineFirst: true 时先刷新 28 天基线（首次/每日一次）
    public func recomputeDayScoring(dayKey: String) async {
        guard let day = date(from: dayKey) else { return }
        let ctx = ModelContext(container)
        let cal = Calendar.current
        let dayEnd = cal.date(byAdding: .day, value: 1, to: day)!

        // 1. 基线
        let baselines = fetchBaselines(ctx)

        // 2. 夜间生理指标（以睡眠窗为准）
        let window = latestWindow(ctx, dayKey: dayKey)
        let sleepStart = window?.start ?? day
        let sleepEnd = window?.end ?? dayEnd
        let nightHRV = meanValue(ctx, type: HKTypeIdentifiers.hrvID, from: sleepStart, to: sleepEnd)
        let nightResp = meanValue(ctx, type: HKTypeIdentifiers.respiratoryID, from: sleepStart, to: sleepEnd)
        let nightTemp = meanValue(ctx, type: HKTypeIdentifiers.wristTempID, from: sleepStart, to: sleepEnd)
        // 静息心率：HK 每日一条 restingHeartRate，取当日值
        let restingHR = meanValue(ctx, type: HKTypeIdentifiers.restingHRID, from: day, to: dayEnd)
            ?? meanValue(ctx, type: HKTypeIdentifiers.heartRateID, from: sleepStart, to: sleepEnd)

        // 3. 睡眠效率与时长
        let segments = window.map { decodeSegments($0.segmentsJSON) } ?? []
        let asleepMin = segments.filter { $0.isAsleep }.reduce(0) { $0 + $1.durationMin }
        let windowMin = window.map { $0.end.timeIntervalSince($0.start) / 60 } ?? 0
        let sleepEfficiency = windowMin > 0 ? min(1, asleepMin / windowMin) : 0

        // 4. Strain（训练区间分钟 + NEAT）
        let strainResult = dayStrain(ctx, day: day, dayEnd: dayEnd)
        let existing = fetchDailyMetric(ctx, dayKey: dayKey)

        // 5. 睡眠债（近 14 天）
        let debt = recentSleepDebt(ctx, before: dayKey)
        let need = SleepDebt.sleepNeedHours(debtHours: debt, trimp: strainResult.trimp)

        // 6. Recovery
        let zHRV = zScore(nightHRV, baselines["hrv"])
        let zRHR = zScore(restingHR, baselines["restingHR"])
        let zResp = zScore(nightResp, baselines["respiratory"])
        let wristOffset = wristTempOffset(nightTemp, baselines["wristTemp"])
        let recovery = RecoveryScore.compute(zHRV: zHRV, zRHR: zRHR, zResp: zResp,
                                             wristTempOffset: wristOffset,
                                             zSleepEff: efficiencyZ(sleepEfficiency),
                                             energyLevel: existing?.energy,
                                             baselineDays: baselineDays(baselines))

        // 7. 压力（日间）
        let dayHRV = dayTimeMean(ctx, type: HKTypeIdentifiers.hrvID, day: day, dayEnd: dayEnd)
        let dayHR = dayTimeMean(ctx, type: HKTypeIdentifiers.heartRateID, day: day, dayEnd: dayEnd)
        let stress = StressScore.compute(dayHRV: dayHRV,
                                         nightHRVMedian: baselines["hrv"]?.median,
                                         dayHR: dayHR,
                                         nightHRMedian: baselines["restingHR"]?.median)

        // 8. ACWR（近 28 天）
        let recentStrains = recentStrain(ctx, before: dayKey)
        let acwrValue = ACWRScore.acwr(last28Strain: recentStrains)
        let acwrRisk = acwrValue.map { ACWRScore.riskScore(of: $0) } ?? 0

        // 9. Readiness
        let yesterday = cal.date(byAdding: .day, value: -1, to: day)!
        let yesterdayStrain = fetchDailyMetric(ctx, dayKey: SleepWindowBuilder.dayKey(for: yesterday))?.strain ?? 0
        let readiness = ReadinessScore.compute(recovery: recovery?.total,
                                               sleepDebtHours: debt,
                                               yesterdayStrain: yesterdayStrain,
                                               acwrRisk: acwrRisk,
                                               soreness: existing?.soreness)

        // 10. 写入
        let metric = existing ?? DailyMetric(dateKey: dayKey)
        metric.recovery = recovery?.total
        metric.strain = strainResult.strain.rounded(toPlaces: 1)
        metric.acwr = acwrValue?.rounded(toPlaces: 2)
        metric.stress = stress?.value
        metric.sleepNeed = need.rounded(toPlaces: 1)
        metric.sleepDebt = debt.rounded(toPlaces: 1)
        metric.readiness = readiness
        var extra: [String: Any] = [
            "recoveryNote": recovery?.note ?? "核心输入缺失（HRV/静息心率基线）",
            "stressNote": stress?.note ?? "HRV 缺失",
            "trimp": strainResult.trimp,
        ]
        if let z = zHRV { extra["zHRV"] = z }
        if let z = zRHR { extra["zRHR"] = z }
        metric.confidenceJSON = mergeConfidence(metric.confidenceJSON, extra)
        ctx.insert(metric)
        try? ctx.save()

        // 同步到配对设备（手表↔手机）
        let dto = DailyMetricDTO(dateKey: metric.dateKey,
                                 energy: metric.energy,
                                 soreness: metric.soreness)
        if let encoded = try? JSONEncoder().encode(dto) {
            await WCSyncService.shared.sendDailyMetric(encoded)
        }
    }

    /// 由原始数值直接计算当日评分（不依赖 SwiftData，便于单测）
    public struct DayInput {
        public var dayKey: String
        public var nightHRV: Double?
        public var restingHR: Double?
        public var nightResp: Double?
        public var wristTemp: Double?
        public var sleepEfficiency: Double
        public var sleepAsleepHours: Double
        public var strain: Double
        public var trimp: Double
        public var energy: Int?
        public var soreness: Int?
    }

    public struct DayOutput: Equatable {
        public var recovery: Double?
        public var strain: Double
        public var acwr: Double?
        public var stress: Double?
        public var sleepNeed: Double
        public var sleepDebt: Double
        public var readiness: Double?
        public var notes: [String]
    }

    /// 纯函数版本（单测用）：基线以字典传入（metric → BaselineValue）
    public static func computeDay(input: DayInput,
                                  baselines: [String: BaselineValue],
                                  recentStrains: [Double],
                                  recentSleepHours: [Double],
                                  yesterdayStrain: Double) -> DayOutput {
        var notes: [String] = []
        func rz(_ v: Double?, _ b: BaselineValue?) -> Double? {
            guard let v, let b, b.mad > 0 else { return nil }
            return BaselineMath.robustZ(value: v, median: b.median, mad: b.mad)
        }
        let zHRV = rz(input.nightHRV, baselines["hrv"])
        let zRHR = rz(input.restingHR, baselines["restingHR"])
        let zResp = rz(input.nightResp, baselines["respiratory"])
        var wristOffset: Double?
        if let t = input.wristTemp, let b = baselines["wristTemp"] {
            wristOffset = t - b.median
        }
        let baselineDays = baselines.values.map(\.sampleDays).max() ?? 0
        let efficiencyZ = (input.sleepEfficiency - 0.9) / 0.05 // 目标 90%，1σ≈5%

        let recovery = RecoveryScore.compute(zHRV: zHRV, zRHR: zRHR, zResp: zResp,
                                            wristTempOffset: wristOffset,
                                            zSleepEff: efficiencyZ,
                                            energyLevel: input.energy,
                                            baselineDays: baselineDays)
        if recovery == nil { notes.append("核心输入缺失（HRV/静息心率）") }
        else if !recovery!.note.isEmpty { notes.append(recovery!.note) }

        let debt = SleepDebt.debtHours(actualHours: recentSleepHours)
        let need = SleepDebt.sleepNeedHours(debtHours: debt, trimp: input.trimp)
        let acwr = ACWRScore.acwr(last28Strain: recentStrains)
        let risk = acwr.map { ACWRScore.riskScore(of: $0) } ?? 0
        let stress = StressScore.compute(dayHRV: input.nightHRV.map { $0 * 0.95 },
                                         nightHRVMedian: baselines["hrv"]?.median,
                                         dayHR: input.restingHR.map { $0 + 3 },
                                         nightHRMedian: baselines["restingHR"]?.median)
        let readiness = ReadinessScore.compute(recovery: recovery?.total,
                                              sleepDebtHours: debt,
                                              yesterdayStrain: yesterdayStrain,
                                              acwrRisk: risk,
                                              soreness: input.soreness)
        return DayOutput(recovery: recovery?.total, strain: input.strain.rounded(toPlaces: 1),
                         acwr: acwr?.rounded(toPlaces: 2), stress: stress?.value,
                         sleepNeed: need.rounded(toPlaces: 1), sleepDebt: debt.rounded(toPlaces: 1),
                         readiness: readiness, notes: notes)
    }

    // MARK: - SwiftData 取值辅助

    func fetchBaselines(_ ctx: ModelContext) -> [String: BaselineValue] {
        let all = (try? ctx.fetch(FetchDescriptor<Baseline>())) ?? []
        var out: [String: BaselineValue] = [:]
        for b in all {
            out[b.metric] = BaselineValue(metric: b.metric, median: b.median, mad: b.mad, sampleDays: b.sampleDays)
        }
        return out
    }

    func fetchDailyMetric(_ ctx: ModelContext, dayKey: String) -> DailyMetric? {
        var d = FetchDescriptor<DailyMetric>(predicate: #Predicate { $0.dateKey == dayKey })
        d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }

    func meanValue(_ ctx: ModelContext, type: String, from: Date, to: Date) -> Double? {
        let samples = fetchRaw(ctx, type: type, from: from, to: to)
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0) { $0 + $1.value } / Double(samples.count)
    }

    /// 日间（非睡眠）均值：排除睡眠窗时段
    func dayTimeMean(_ ctx: ModelContext, type: String, day: Date, dayEnd: Date) -> Double? {
        let samples = fetchRaw(ctx, type: type, from: day, to: dayEnd)
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0) { $0 + $1.value } / Double(samples.count)
    }

    func zScore(_ value: Double?, _ baseline: BaselineValue?) -> Double? {
        guard let v = value, let b = baseline else { return nil }
        return BaselineMath.robustZ(value: v, median: b.median, mad: b.mad)
    }

    /// 睡眠效率 z：目标 90%，1σ≈5%（无独立基线时的实用近似，M3 起改用效率自身基线）
    func efficiencyZ(_ efficiency: Double) -> Double {
        (efficiency - 0.9) / 0.05
    }

    func wristTempOffset(_ value: Double?, _ baseline: BaselineValue?) -> Double? {
        guard let v = value, let b = baseline else { return nil }
        return v - b.median
    }

    func baselineDays(_ baselines: [String: BaselineValue]) -> Int {
        baselines.values.map(\.sampleDays).max() ?? 0
    }

    // MARK: - Strain / ACWR / 睡眠债 取值

    struct StrainResult {
        var trimp: Double
        var strain: Double
    }

    /// 当日 Strain：训练时段 HR 分区间 + NEAT（非训练活动能量 /10）
    func dayStrain(_ ctx: ModelContext, day: Date, dayEnd: Date) -> StrainResult {
        let maxHR = 190.0 // TODO-M3：按年龄/实测最大心率个性化
        let workouts = fetchRaw(ctx, type: HKTypeIdentifiers.workoutID, from: day, to: dayEnd)
        var trimpSum = 0.0
        var workoutKcal = 0.0
        for w in workouts {
            let hrs = fetchRaw(ctx, type: HKTypeIdentifiers.heartRateID, from: w.start, to: w.end)
                .sorted { $0.start < $1.start }
                .map { (hr: $0.value, at: $0.start) }
            let zones = StrainScore.zoneMinutes(hrSamples: hrs, maxHR: maxHR)
            trimpSum += StrainScore.trimp(zoneMinutes: zones)
            workoutKcal += w.value // workout 的 value 存 kcal（由 HKTypeRegistry 映射）
        }
        // NEAT：当日总活动能量减去训练消耗，按 /10 折算为 TRIMP 等效单位
        let totalKcal = fetchRaw(ctx, type: HKTypeIdentifiers.activeEnergyID, from: day, to: dayEnd)
            .reduce(0) { $0 + $1.value }
        let neatKcal = max(0, totalKcal - workoutKcal)
        trimpSum += neatKcal / 10 * StrainScore.neatFactor
        return StrainResult(trimp: trimpSum, strain: StrainScore.strain(trimp: trimpSum))
    }

    /// 近 28 天日 Strain（不含当日），按日期降序
    func recentStrain(_ ctx: ModelContext, before dayKey: String) -> [Double] {
        guard let day = date(from: dayKey) else { return [] }
        let cal = Calendar.current
        var out: [Double] = []
        for i in 1...28 {
            guard let d = cal.date(byAdding: .day, value: -i, to: day) else { continue }
            let key = SleepWindowBuilder.dayKey(for: d)
            out.append(fetchDailyMetric(ctx, dayKey: key)?.strain ?? 0)
        }
        return out
    }

    /// 近 14 天睡眠债（不含当日）
    func recentSleepDebt(_ ctx: ModelContext, before dayKey: String) -> Double {
        guard let day = date(from: dayKey) else { return 0 }
        let cal = Calendar.current
        var hours: [Double] = []
        for i in 1...SleepDebt.debtWindowDays {
            guard let d = cal.date(byAdding: .day, value: -i, to: day) else { continue }
            let key = SleepWindowBuilder.dayKey(for: d)
            guard let w = latestWindow(ctx, dayKey: key) else { continue }
            let segs = decodeSegments(w.segmentsJSON)
            hours.append(segs.filter { $0.isAsleep }.reduce(0) { $0 + $1.durationMin } / 60)
        }
        return SleepDebt.debtHours(actualHours: hours)
    }

    // MARK: - 概览查询（UI 用）

    /// 今日概览快照（UI 直接使用）
    public struct OverviewData: Sendable {
        public var dayKey: String
        public var recovery: Double?
        public var sleepScore: Double?
        public var strain: Double?
        public var acwr: Double?
        public var stress: Double?
        public var sleepNeed: Double?
        public var sleepDebt: Double?
        public var readiness: Double?
        public var inCalibration: Bool
        public var calibrationDaysLeft: Int
        public var recoveryNote: String
        public var sleep: SleepSummary?
    }

    /// 读今日概览（不触发重算；重算由 App 生命周期负责）
    // MARK: - 内存缓存（属性声明见 DataPipeline 主文件；ingest/rebuild 时 invalidate）

    public func invalidateCache() {
        cacheVersion &+= 1
        cacheStamp = .distantPast
        cacheOverview = nil
        cacheMetric = [:]
    }

    public func overview() async -> OverviewData {
        if Date().timeIntervalSince(cacheStamp) < Self.cacheTTL, let hit = cacheOverview {
            return hit
        }
        let ctx = ModelContext(container)
        let dayKey = SleepWindowBuilder.dayKey(for: Date())
        let m = fetchDailyMetric(ctx, dayKey: dayKey)
        let baselines = fetchBaselines(ctx)
        let days = baselineDays(baselines)
        var note = ""
        if let j = m?.confidenceJSON.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: j) as? [String: Any],
           let n = o["recoveryNote"] as? String { note = n }
        let sleep = await sleepSummary()
        let result = OverviewData(dayKey: dayKey,
                            recovery: m?.recovery,
                            sleepScore: m?.sleepScore,
                            strain: m?.strain,
                            acwr: m?.acwr,
                            stress: m?.stress,
                            sleepNeed: m?.sleepNeed,
                            sleepDebt: m?.sleepDebt,
                            readiness: m?.readiness,
                            inCalibration: days < SleepScore.calibrationDaysNeeded,
                            calibrationDaysLeft: max(0, SleepScore.calibrationDaysNeeded - days),
                            recoveryNote: note,
                            sleep: sleep)
        cacheOverview = result
        cacheStamp = Date()
        return result
    }

    // MARK: - 图表数据

    /// 单日趋势点（图表用）
    public struct DailyPoint: Sendable, Identifiable {
        public var id: String { dayKey }
        public var dayKey: String
        public var date: Date
        public var recovery: Double?
        public var sleepScore: Double?
        /// 当夜 asleep 时长（小时）
        public var sleepHours: Double?
        public var strain: Double?
        public var stress: Double?
        public var readiness: Double?
    }

    /// 最近 N 天趋势（按日期升序；缺失值保留 nil 以便图表断点显示）
    public func metricHistory(days: Int) async -> [DailyPoint] {
        if Date().timeIntervalSince(cacheStamp) < Self.cacheTTL,
           let hit = cacheMetric[days] { return hit }
        let ctx = ModelContext(container)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var out: [DailyPoint] = []
        for i in stride(from: days - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            let key = SleepWindowBuilder.dayKey(for: day)
            let m = fetchDailyMetric(ctx, dayKey: key)
            var sleepHours: Double?
            if let w = latestWindow(ctx, dayKey: key) {
                let segs = decodeSegments(w.segmentsJSON)
                sleepHours = segs.filter { $0.isAsleep }.reduce(0) { $0 + $1.durationMin } / 60
            }
            out.append(DailyPoint(dayKey: key, date: day,
                                  recovery: m?.recovery,
                                  sleepScore: m?.sleepScore,
                                  sleepHours: sleepHours,
                                  strain: m?.strain,
                                  stress: m?.stress,
                                  readiness: m?.readiness))
        }
        cacheMetric[days] = out
        cacheStamp = Date()
        return out
    }

    /// 睡眠详情（图表用）：最新窗口 + 分期段
    public struct SleepDetail: Sendable {
        public var dayKey: String
        public var start: Date
        public var end: Date
        public var segments: [SleepSegment]
        public var score: Double?
        public var source: String
        public var confidence: Double
        public var confidenceReason: String

        public var asleepMin: Double { segments.filter { $0.isAsleep }.reduce(0) { $0 + $1.durationMin } }
        public var stageMinutes: [String: Double] {
            var out: [String: Double] = [:]
            for s in segments { out[s.displayName, default: 0] += s.durationMin }
            return out
        }
    }

    /// 最新一晚睡眠详情（今日/昨日窗口）
    public func sleepDetail() async -> SleepDetail? {
        let today = SleepWindowBuilder.dayKey(for: Date())
        let yesterday = SleepWindowBuilder.dayKey(for: Date().addingTimeInterval(-24 * 3600))
        if let d = await sleepDetail(dayKey: today) { return d }
        return await sleepDetail(dayKey: yesterday)
    }

    public func sleepDetail(dayKey: String) async -> SleepDetail? {
        let ctx = ModelContext(container)
        guard let w = latestWindow(ctx, dayKey: dayKey) else { return nil }
        let m = fetchDailyMetric(ctx, dayKey: dayKey)
        return SleepDetail(dayKey: dayKey, start: w.start, end: w.end,
                           segments: decodeSegments(w.segmentsJSON),
                           score: m?.sleepScore, source: w.source,
                           confidence: w.confidence, confidenceReason: w.confidenceReason)
    }

    // MARK: - 晨间报告（design.md §11：锁定时触发，每天最多 1 条）

    func sendMorningReport(window: SleepWindow) async {
        let ctx = ModelContext(container)
        let dayKey = window.dayKey
        let m = fetchDailyMetric(ctx, dayKey: dayKey)
        // 昨日 Strain：取前一天
        let cal = Calendar.current
        let day = date(from: dayKey) ?? Date()
        let yesterdayKey = SleepWindowBuilder.dayKey(for: cal.date(byAdding: .day, value: -1, to: day)!)
        let yesterdayStrain = fetchDailyMetric(ctx, dayKey: yesterdayKey)?.strain
        // 格式化窗口 HH:mm–HH:mm
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let windowText = "\(fmt.string(from: window.start))–\(fmt.string(from: window.end))"
        await MorningReport.scheduleMorningReport(
            sleepWindow: windowText,
            sleepScore: m?.sleepScore,
            recovery: m?.recovery,
            readiness: m?.readiness,
            strain: yesterdayStrain,
            advice: m?.readiness.map { ReadinessScore.advice(readiness: $0) }
        )
    }

    /// 合并 confidenceJSON（保留已有键；nil 键不写）
    func mergeConfidence(_ json: String, _ new: [String: Any]) -> String {
        var obj: [String: Any] = [:]
        if let d = json.data(using: .utf8),
           let existing = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            obj = existing
        }
        for (k, v) in new {
            if v is NSNull { continue }
            if let d = v as? Double, d.isNaN || d.isInfinite { continue }
            obj[k] = v
        }
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj) else { return json }
        return String(data: data, encoding: .utf8) ?? json
    }
}
