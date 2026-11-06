import Foundation
import SwiftData

/// 数据管道：RawSample 落库 → L1/L5 窗口重建 → 评分 → DailyMetric；基线维护。
/// 全程在独立 actor 的后台 ModelContext 执行，不阻塞 UI。
public actor DataPipeline {

    public static let shared = DataPipeline()

    let container = PulseStore.shared
    private var context: ModelContext { ModelContext(container) }

    public static let sleepTypeID = HKTypeIdentifiers.sleepAnalysisID

    // MARK: - 内存缓存（30s 新鲜度，Tab 切换秒开；ingest/rebuild 时 invalidate）

    var cacheVersion = 0
    var cacheStamp = Date.distantPast
    var cacheOverview: OverviewData?
    var cacheMetric: [Int: [DailyPoint]] = [:]
    static let cacheTTL: TimeInterval = 30

    private init() {}

    // MARK: - 摄入

    /// 批量落库（去重 hkUUID）+ 受影响日期窗口重算（L5 追溯）
    public func ingest(samples: [RawSamplePayload], deletedUUIDs: [UUID]) async {
        let ctx = context
        var deletedStarts: [Date] = []
        for uuid in deletedUUIDs {
            let id = uuid.uuidString
            var d = FetchDescriptor<RawSample>(predicate: #Predicate { $0.hkUUID == id })
            d.fetchLimit = 1
            if let s = try? ctx.fetch(d).first {
                deletedStarts.append(s.start)
                ctx.delete(s)
            }
        }
        // 去重
        var newSamples: [RawSample] = []
        var existing = Set<String>()
        for p in samples {
            if !existing.contains(p.hkUUID) {
                let r = RawSample(hkUUID: p.hkUUID, type: p.type, subtype: p.subtype,
                                  value: p.value, start: p.start, end: p.end, source: p.source)
                ctx.insert(r)
                newSamples.append(r)
                existing.insert(p.hkUUID)
            }
        }
        guard !newSamples.isEmpty || !deletedUUIDs.isEmpty else { return }
        try? ctx.save()
        PulseLog.write("  ingest saved=\(newSamples.count) to DB")
        invalidateCache()
        let affected = newSamples.map(\.start) + deletedStarts
        await recomputeAffectedDays(from: affected)
        // 评分：受影响日 + 当日（概览卡读取）
        for k in Set(affected.map { SleepWindowBuilder.dayKey(for: $0) }) {
            await recomputeDayScoring(dayKey: k)
        }
        await recomputeDayScoring(dayKey: SleepWindowBuilder.dayKey(for: Date()))
    }

    /// 增量同步入口（供 UI/后台任务触发）
    public func syncNow() async {
        await HKSyncEngine.shared.syncAll()
    }

    /// 强制修复：重置 HealthKit anchor → 重拉回填窗口 → 重算近 N 天睡眠窗与评分。
    /// 用于「睡眠一直空」的排查修复（例如早期授权前 anchor 已推进导致历史样本永久跳过）。
    public func forceRebuild(days: Int = 60) async {
        await HKSyncEngine.shared.resyncAll()
        invalidateCache()
        await rebuildBaseline()          // 恢复/压力/准备度依赖基线，必须先建
        await rebuildRecent(days: days)
        await recomputeDayScoring(dayKey: SleepWindowBuilder.dayKey(for: Date()))
        invalidateCache()
    }

    /// 当前有无任一睡眠窗口（睡眠页空态判断用）
    public func hasAnySleepWindow() async -> Bool {
        let ctx = context
        var d = FetchDescriptor<SleepWindow>()
        d.fetchLimit = 1
        return ((try? ctx.fetchCount(d)) ?? 0) > 0
    }

    /// 管道算法版本（结构/算法变更时递增，触发补算）
    public static let pipelineVersion = 2 // 2 = 引入 L0 活动信号睡眠推测

    /// 算法升级补算：重算最近 N 天的睡眠窗与评分（首次安装或版本升级时执行一次）
    public func ensurePipelineUpToDate(days: Int = 14) async {
        let key = "pulse.pipeline.version"
        let stored = UserDefaults.standard.integer(forKey: key)
        guard stored < Self.pipelineVersion else { return }
        await rebuildRecent(days: days)
        UserDefaults.standard.set(Self.pipelineVersion, forKey: key)
    }

    /// 重算最近 N 天（睡眠窗重建 + 当日评分）
    public func rebuildRecent(days: Int = 14) async {
        invalidateCache()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for i in stride(from: days - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            let key = SleepWindowBuilder.dayKey(for: day)
            await rebuildNight(dayKey: key)
            await recomputeDayScoring(dayKey: key)
        }
    }

    // MARK: - L5：受影响日期窗口重建

    private func recomputeAffectedDays(from dates: [Date]) async {
        let keys = Set(dates.map { SleepWindowBuilder.dayKey(for: $0) })
        for k in keys {
            await rebuildNight(dayKey: k)
        }
    }

    /// 重算某一归属日的窗口 + 评分 + DailyMetric（version 递增，历史保留）。
    /// 若最新版本与新结果完全一致则跳过（避免无限 version+1）。
    public func rebuildNight(dayKey: String) async {
        let ctx = context
        guard let day = date(from: dayKey) else { return }
        // 拉取窗口构建所需样本：前一日 18:00 至次日 12:00 的睡眠样本
        let rangeStart = Calendar.current.date(byAdding: .hour, value: -6, to: day)!
        let rangeEnd = Calendar.current.date(byAdding: .hour, value: 36, to: day)!
        let segs = fetchSleepSegments(ctx, from: rangeStart, to: rangeEnd)

        var drafts = SleepWindowBuilder.buildL1(segments: segs)
        drafts.sort { $0.start < $1.start }
        // 只保留归属日为 dayKey 的窗口
        drafts = drafts.filter { $0.dayKey == dayKey }

        // 该日的信号推断范围：前后各扩 6h，避免跨零点的夜间窗口被截断
        let dayStart = Calendar.current.startOfDay(for: day)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let inferRange = (start: Calendar.current.date(byAdding: .hour, value: -6, to: dayStart)!,
                          end: Calendar.current.date(byAdding: .hour, value: 6, to: dayEnd)!)
        // 系统分期缺失时，用活动信号 L0 兜底（支持 24h 自动识别，含小睡）
        let l0Windows: [SleepInference.InferredWindow]
        if drafts.isEmpty {
            l0Windows = inferWindows(ctx, range: inferRange).filter { $0.dayKey == dayKey }
            drafts = l0Windows.map(SleepInference.draft(from:))
        } else {
            l0Windows = []
        }
        let isInferred = !l0Windows.isEmpty
        // 主睡眠取当日最长窗口
        guard let draftIndex = drafts.indices.max(by: { drafts[$0].durationMin < drafts[$1].durationMin }) else { return }
        let draft = drafts[draftIndex]

        let latest = latestWindow(ctx, dayKey: dayKey)
        let segmentsJSON = (try? JSONEncoder().encode(draft.segments)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        // L2 延伸不可被 L1 重算回滚：若最新版本来自延伸，则继承其 end
        let extendedEnd: Date? = (latest?.source == SampleSource.extended.rawValue) ? latest?.end : nil
        let effectiveEnd = max(draft.end, extendedEnd ?? draft.end)
        let effectiveDraft = SleepWindowDraft(start: draft.start, end: effectiveEnd,
                                              segments: draft.segments,
                                              stageMinutes: draft.stageMinutes,
                                              efficiency: draft.efficiency)

        // 无变化判定：与「最近一个同来源非延伸版本」比对（source 一致才比较，避免 L1/L0 来回插版本）
        let source = isInferred ? SampleSource.inferred.rawValue : SampleSource.system.rawValue
        let latestSameSource = latestWindowBySource(ctx, dayKey: dayKey, source: source)
        if let latestSameSource,
           latestSameSource.start == draft.start, latestSameSource.end == effectiveEnd,
           latestSameSource.segmentsJSON == segmentsJSON {
            await updateDailyMetric(dayKey: dayKey, draft: effectiveDraft)
            // 窗口没变化也要确保已回写健康（升级后补写；已写过同版本会直接跳过）
            #if os(watchOS)
            if isInferred {
                _ = await SleepWriteback.shared.write(dayKey: dayKey, start: draft.start,
                                                      end: effectiveEnd,
                                                      version: latestSameSource.version)
            }
            #endif
            return
        }

        // 系统分期窗口优先于 L0 推测：已有 system 窗时不被 inferred 覆盖
        if isInferred, latestWindowBySource(ctx, dayKey: dayKey, source: SampleSource.system.rawValue) != nil {
            return
        }

        let version = (latest?.version ?? 0) + 1
        let conf: SleepWindowBuilder.Confidence
        if isInferred {
            conf = SleepInference.confidence(for: l0Windows[draftIndex])
        } else {
            conf = windowConfidence(ctx, draft: effectiveDraft)
        }
        let window = SleepWindow(dayKey: dayKey, start: draft.start, end: effectiveEnd,
                                 segmentsJSON: segmentsJSON, source: source,
                                 confidence: conf.value, confidenceReason: conf.reason,
                                 version: version)
        if let latest { window.l2Locked = latest.l2Locked; window.l2FailCount = latest.l2FailCount }
        ctx.insert(window)
        try? ctx.save()
        await updateDailyMetric(dayKey: dayKey, draft: effectiveDraft)

        // 睡眠回写健康（仅手表侧）：推测窗口写入；系统分期出现后删除我们的回写（让位原生数据）
        #if os(watchOS)
        if isInferred {
            _ = await SleepWriteback.shared.write(dayKey: dayKey, start: draft.start,
                                                  end: effectiveEnd, version: version)
        } else if latestWindowBySource(ctx, dayKey: dayKey, source: SampleSource.inferred.rawValue) != nil {
            await SleepWriteback.shared.delete(dayKey: dayKey)
        }
        #endif
    }

    /// 某来源的最新窗口
    func latestWindowBySource(_ ctx: ModelContext, dayKey: String, source: String) -> SleepWindow? {
        let d = FetchDescriptor<SleepWindow>(
            predicate: #Predicate { $0.dayKey == dayKey && $0.source == source },
            sortBy: [SortDescriptor(\.version, order: .reverse)])
        return try? ctx.fetch(d).first
    }

    /// L0 活动信号推测（steps/stand/energy/HR → 睡眠候选窗口）
    private func inferWindows(_ ctx: ModelContext, range: (start: Date, end: Date)) -> [SleepInference.InferredWindow] {
        func spans(_ type: String) -> [SleepInference.Span] {
            fetchRaw(ctx, type: type, from: range.start, to: range.end)
                .map { SleepInference.Span(start: $0.start, end: $0.end, value: $0.value) }
        }
        let signals = SleepInference.Signals(
            steps: spans(HKTypeIdentifiers.stepCountID),
            stand: spans(HKTypeIdentifiers.standTimeID),
            energy: spans(HKTypeIdentifiers.activeEnergyID),
            heartRate: spans(HKTypeIdentifiers.heartRateID))
        return SleepInference.infer(signals: signals, range: range)
    }

    // MARK: - 诊断（页面显示「卡在哪一步」）

    public struct SleepPipelineRow: Sendable {
        public var dayKey: String
        public var rawSleepSamples: Int
        public var segments: Int
        public var drafts: Int
        public var l0Candidates: Int
        public var windowSource: String
        public var windowMin: Double
        public var windowVersion: Int
    }

    /// 逐日睡眠管线状态：原始样本 → 分段 → 草稿 → 最终窗口
    public func sleepPipelineReport(days: Int = 7) async -> [SleepPipelineRow] {
        let ctx = context
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var rows: [SleepPipelineRow] = []
        for i in stride(from: days - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            let key = SleepWindowBuilder.dayKey(for: day)
            let rangeStart = cal.date(byAdding: .hour, value: -6, to: day)!
            let rangeEnd = cal.date(byAdding: .hour, value: 36, to: day)!
            let rawCount = fetchRaw(ctx, type: Self.sleepTypeID, from: rangeStart, to: rangeEnd).count
            let segs = fetchSleepSegments(ctx, from: rangeStart, to: rangeEnd)
            let drafts = SleepWindowBuilder.buildL1(segments: segs)
            var l0 = 0
            if drafts.filter({ $0.dayKey == key }).isEmpty {
                let dayStart = cal.startOfDay(for: day)
                let infer = (start: cal.date(byAdding: .hour, value: -6, to: dayStart)!,
                             end: cal.date(byAdding: .hour, value: 6,
                                           to: cal.date(byAdding: .day, value: 1, to: dayStart)!)!)
                l0 = inferWindows(ctx, range: infer).count
            }
            let w = latestWindow(ctx, dayKey: key)
            rows.append(SleepPipelineRow(dayKey: key,
                                         rawSleepSamples: rawCount,
                                         segments: segs.count,
                                         drafts: drafts.count,
                                         l0Candidates: l0,
                                         windowSource: w?.source ?? "—",
                                         windowMin: w.map { $0.end.timeIntervalSince($0.start) / 60 } ?? 0,
                                         windowVersion: w?.version ?? 0))
        }
        return rows
    }

    // MARK: - L2 延伸（后台任务调用）

    /// 对最新未锁定窗口执行一次 L2 判定。
    /// 返回：.extended(新end) / .rejected / .locked / .noWindow
    @discardableResult
    public func runL2Check(now: Date = Date(),
                           stepsSinceEnd: Double,
                           standMinSinceEnd: Double,
                           kcalPerMin: Double,
                           hr: Double,
                           charging: Bool) async -> L2Result {
        let ctx = context
        guard let dayKey = recentWindowDayKey(ctx, now: now),
              let latest = latestWindow(ctx, dayKey: dayKey) else { return .noWindow }
        var tracker = SleepWindowBuilder.L2Tracker()
        tracker.failCount = latest.l2FailCount
        tracker.locked = latest.l2Locked
        // 结构性硬约束（时间上限 + 锁定态）
        guard tracker.canExtend(now: now, windowEnd: latest.end) else { return .locked }

        let nightMedian = nightHRMedian(ctx, window: latest) ?? hr
        let allowed = SleepWindowBuilder.l2ExtensionAllowed(steps: stepsSinceEnd,
                                                            standMin: standMinSinceEnd,
                                                            kcalPerMin: kcalPerMin,
                                                            hr: hr,
                                                            nightHRMedian: nightMedian,
                                                            charging: charging)
        let stillOpen = tracker.record(allowed: allowed)

        if allowed {
            // 延伸：新版本窗口 end=now，source=.extended
            let conf = windowConfidence(ctx, draft: SleepWindowDraft(
                start: latest.start, end: now, segments: decodeSegments(latest.segmentsJSON),
                stageMinutes: [:], efficiency: 0))
            let extended = SleepWindow(dayKey: latest.dayKey, start: latest.start, end: now,
                                       segmentsJSON: latest.segmentsJSON,
                                       source: SampleSource.extended.rawValue,
                                       confidence: conf.value, confidenceReason: conf.reason,
                                       version: latest.version + 1)
            ctx.insert(extended)
            try? ctx.save()
            // 推测窗口被延伸后仍需同步健康（延伸改变了 end）
            #if os(watchOS)
            let hasSystem = latestWindowBySource(ctx, dayKey: latest.dayKey,
                                                 source: SampleSource.system.rawValue) != nil
            if !hasSystem {
                _ = await SleepWriteback.shared.write(dayKey: latest.dayKey, start: latest.start,
                                                      end: now, version: extended.version)
            }
            #endif
            return .extended(newEnd: now)
        } else {
            // 失败：更新计数/锁定（不重开窗口）
            latest.l2FailCount = tracker.failCount
            latest.l2Locked = tracker.locked
            try? ctx.save()
            if tracker.locked {
                await sendMorningReport(window: latest)
            }
            return tracker.locked ? .locked : .rejected
        }
    }

    public enum L2Result: Equatable {
        case extended(newEnd: Date)
        case rejected
        case locked
        case noWindow
    }

    // MARK: - DailyMetric / 评分

    private func updateDailyMetric(dayKey: String, draft: SleepWindowDraft) async {
        let ctx = context
        let days = distinctSleepDays(ctx, withinDays: 30)
        let midpoints = sleepMidpoints(ctx, last: 14)
        let comps = SleepScore.compute(durationHours: draft.durationMin / 60,
                                       efficiency: draft.efficiency,
                                       structureDeviation: nil,
                                       sleepMidpoints: midpoints,
                                       baselineDays: days)
        var d = FetchDescriptor<DailyMetric>(predicate: #Predicate { $0.dateKey == dayKey })
        d.fetchLimit = 1
        let metric = (try? ctx.fetch(d).first) ?? DailyMetric(dateKey: dayKey)
        metric.sleepScore = comps.total
        let confJSON: [String: Any] = [
            "duration": comps.duration, "efficiency": comps.efficiency,
            "structure": comps.structure, "regularity": comps.regularity,
            "inCalibration": comps.inCalibration, "note": comps.note]
        metric.confidenceJSON = (try? JSONSerialization.data(withJSONObject: confJSON))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        ctx.insert(metric)
        try? ctx.save()
    }

    // MARK: - 基线维护

    /// 28 天滚动基线重算（restingHR/hrv/respiratory/wristTemp 每日均值 → median+MAD）
    public func rebuildBaseline() async {
        let ctx = context
        let since = Calendar.current.date(byAdding: .day, value: -28, to: Date())!
        for metric in ["restingHR", "hrv", "respiratory", "wristTemp"] {
            let id: String
            switch metric {
            case "restingHR": id = HKTypeIdentifiers.restingHRID
            case "hrv": id = HKTypeIdentifiers.hrvID
            case "respiratory": id = HKTypeIdentifiers.respiratoryID
            default: id = HKTypeIdentifiers.wristTempID
            }
            let samples = fetchRaw(ctx, type: id, from: since, to: Date())
            // 按日聚合均值
            var byDay: [String: [Double]] = [:]
            for s in samples { byDay[SleepWindowBuilder.dayKey(for: s.start), default: []].append(s.value) }
            let daily = byDay.values.compactMap { $0.isEmpty ? nil : $0.reduce(0,+) / Double($0.count) }
            guard let bv = BaselineValue.build(metric: metric, dailyValues: daily) else { continue }
            var d = FetchDescriptor<Baseline>(predicate: #Predicate { $0.metric == metric })
            d.fetchLimit = 1
            let model = (try? ctx.fetch(d).first) ?? Baseline(metric: metric, median: 0, mad: 0, sampleDays: 0, computedAt: Date())
            model.median = bv.median; model.mad = bv.mad; model.sampleDays = bv.sampleDays; model.computedAt = Date()
            ctx.insert(model)
        }
        try? ctx.save()
    }

    // MARK: - 查询工具

    /// 睡眠摘要（调试/后续产品 UI 共用）
    public struct SleepSummary: Sendable {
        public var dayKey: String
        public var start: Date
        public var end: Date
        public var durationMin: Double
        public var asleepMin: Double
        public var efficiency: Double
        public var source: String
        public var confidence: Double
        public var confidenceReason: String
        public var version: Int
        public var score: Double?
        public var note: String
        public var l2Locked: Bool
        public var l2FailCount: Int
    }

    /// 今日/昨夜晚最新窗口摘要（找不到返回 nil）
    public func sleepSummary() async -> SleepSummary? {
        let ctx = context
        let today = SleepWindowBuilder.dayKey(for: Date())
        let yesterday = SleepWindowBuilder.dayKey(for: Date().addingTimeInterval(-24 * 3600))
        for key in [today, yesterday] {
            guard let w = latestWindow(ctx, dayKey: key) else { continue }
            let segs = decodeSegments(w.segmentsJSON)
            let asleepMin = segs.filter { $0.isAsleep }.reduce(0) { $0 + $1.durationMin }
            let dur = w.end.timeIntervalSince(w.start) / 60
            var d = FetchDescriptor<DailyMetric>(predicate: #Predicate { $0.dateKey == key })
            d.fetchLimit = 1
            let m = try? ctx.fetch(d).first
            var note = ""
            if let json = m?.confidenceJSON.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
               let n = obj["note"] as? String { note = n }
            return SleepSummary(dayKey: key, start: w.start, end: w.end, durationMin: dur,
                                asleepMin: asleepMin,
                                efficiency: dur > 0 ? asleepMin / dur : 0,
                                source: w.source, confidence: w.confidence,
                                confidenceReason: w.confidenceReason, version: w.version,
                                score: m?.sleepScore, note: note,
                                l2Locked: w.l2Locked, l2FailCount: w.l2FailCount)
        }
        return nil
    }

    public func latestSleepWindow(dayKey: String) async -> (start: Date, end: Date, source: String, confidence: Double, reason: String, version: Int)? {
        guard let w = latestWindow(context, dayKey: dayKey) else { return nil }
        return (w.start, w.end, w.source, w.confidence, w.confidenceReason, w.version)
    }

    func latestWindow(_ ctx: ModelContext, dayKey: String) -> SleepWindow? {
        var d = FetchDescriptor<SleepWindow>(predicate: #Predicate { $0.dayKey == dayKey },
                                             sortBy: [SortDescriptor(\.version, order: .reverse)])
        d.fetchLimit = 1
        return try? ctx.fetch(d).first
    }

    func recentWindowDayKey(_ ctx: ModelContext, now: Date) -> String? {
        // 找最近 3h 内结束的最新窗口
        let since = now.addingTimeInterval(-SleepWindowBuilder.L2Tracker.extensionLimitSec)
        var d = FetchDescriptor<SleepWindow>(sortBy: [SortDescriptor(\.end, order: .reverse)])
        d.fetchLimit = 5
        guard let w = (try? ctx.fetch(d))?.first(where: { $0.end >= since }) else { return nil }
        return w.dayKey
    }

    func fetchSleepSegments(_ ctx: ModelContext, from: Date, to: Date) -> [SleepSegment] {
        fetchRaw(ctx, type: Self.sleepTypeID, from: from, to: to)
            .compactMap { s in
                guard !s.subtype.isEmpty else { return nil }
                return SleepSegment(stage: s.subtype, start: s.start, end: s.end)
            }
    }

    func fetchRaw(_ ctx: ModelContext, type: String, from: Date, to: Date) -> [RawSample] {
        let f = from, t = to
        let d = FetchDescriptor<RawSample>(predicate: #Predicate {
            $0.type == type && $0.start < t && $0.end > f
        })
        return (try? ctx.fetch(d)) ?? []
    }

    /// 窗口置信度：HR 覆盖率 + 连续性 + 静止比例
    private func windowConfidence(_ ctx: ModelContext, draft: SleepWindowDraft) -> SleepWindowBuilder.Confidence {
        let totalMin = max(draft.durationMin, 1)
        let hrSamples = fetchRaw(ctx, type: HKTypeIdentifiers.heartRateID,
                                 from: draft.start, to: draft.end)
        var covered = Set<Int>()
        for s in hrSamples {
            let a = Int(s.start.timeIntervalSince(draft.start) / 60)
            let b = Int(s.end.timeIntervalSince(draft.start) / 60)
            for m in max(a, 0)...min(b, Int(totalMin)) { covered.insert(m) }
        }
        let hrCoverage = min(1, Double(covered.count) / totalMin)
        // 静止比例：无活动能量的分钟占比
        let energySamples = fetchRaw(ctx, type: HKTypeIdentifiers.activeEnergyID,
                                     from: draft.start, to: draft.end)
        var activeMin = Set<Int>()
        for s in energySamples where s.value > 0 {
            let a = Int(s.start.timeIntervalSince(draft.start) / 60)
            let b = Int(s.end.timeIntervalSince(draft.start) / 60)
            for m in max(a, 0)...min(b, Int(totalMin)) { activeMin.insert(m) }
        }
        let stillness = max(0, 1 - Double(activeMin.count) / totalMin)
        // 连续性：1 − 被丢弃/缺失的 awake 缺口分钟占比（以 ≥5min awake 缺口近似）
        var gapMin = 0.0
        let segs = draft.segments.sorted { $0.start < $1.start }
        for i in segs.dropFirst().indices {
            gapMin += segs[i].start.timeIntervalSince(segs[i-1].end) / 60
        }
        let continuity = max(0, 1 - gapMin / totalMin)
        return SleepWindowBuilder.confidence(hrCoverage: hrCoverage, continuity: continuity, stillnessRatio: stillness)
    }

    private func nightHRMedian(_ ctx: ModelContext, window: SleepWindow) -> Double? {
        let samples = fetchRaw(ctx, type: HKTypeIdentifiers.heartRateID, from: window.start, to: window.end)
        guard !samples.isEmpty else { return nil }
        return BaselineMath.median(samples.map(\.value))
    }

    private func distinctSleepDays(_ ctx: ModelContext, withinDays: Int) -> Int {
        let since = Calendar.current.date(byAdding: .day, value: -withinDays, to: Date())!
        let samples = fetchRaw(ctx, type: Self.sleepTypeID, from: since, to: Date())
        return Set(samples.map { SleepWindowBuilder.dayKey(for: $0.start) }).count
    }

    private func sleepMidpoints(_ ctx: ModelContext, last: Int) -> [Date] {
        let since = Calendar.current.date(byAdding: .day, value: -last, to: Date())!
        let samples = fetchRaw(ctx, type: Self.sleepTypeID, from: since, to: Date())
        var byDay: [String: (start: Date, end: Date)] = [:]
        for s in samples where s.subtype.hasPrefix("asleep") {
            let k = SleepWindowBuilder.dayKey(for: s.start)
            if let cur = byDay[k] {
                byDay[k] = (min(cur.start, s.start), max(cur.end, s.end))
            } else { byDay[k] = (s.start, s.end) }
        }
        return byDay.values.map { $0.start.addingTimeInterval($0.end.timeIntervalSince($0.start) / 2) }
    }

    // MARK: - 跨设备同步（WCSession）

    /// 接收配对设备发来的 DailyMetric 快照，合并用户录入项（精力/酸痛）到本地。
    public func importRemoteMetric(_ data: Data) async {
        guard let dto = try? JSONDecoder().decode(DailyMetricDTO.self, from: data) else { return }
        let ctx = context
        var d = FetchDescriptor<DailyMetric>(predicate: #Predicate { $0.dateKey == dto.dateKey })
        d.fetchLimit = 1
        let local = (try? ctx.fetch(d).first) ?? DailyMetric(dateKey: dto.dateKey)
        // 仅同步用户录入项（评分各自从 HK 独立计算，不互相覆盖）
        if let e = dto.energy { local.energy = e }
        if let s = dto.soreness { local.soreness = s }
        ctx.insert(local)
        try? ctx.save()
    }

    func date(from dayKey: String) -> Date? {
        var c = DateComponents()
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        return Calendar.current.date(from: c)
    }

    func decodeSegments(_ json: String) -> [SleepSegment] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SleepSegment].self, from: data)) ?? []
    }
}
