import XCTest
@testable import PulsePhone

/// L0 活动信号睡眠推测（SleepInference）
final class SleepInferenceTests: XCTestCase {

    private var calendar: Calendar { Calendar.current }

    /// 推断范围：D 12:00 → D+1 12:00（一夜窗口）
    private lazy var rangeStart: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 5; c.hour = 12
        return calendar.date(from: c)!
    }()
    private lazy var rangeEnd: Date = rangeStart.addingTimeInterval(24 * 3600)
    /// 正午为 0 点的分钟偏移（13:00 → 780min，次日 08:00 → 1920min）
    private let midnight: Double = 12 * 60

    /// 构造样本：minFromMidnight = 距当日零点的分钟数（13:00 → 780，次日 08:00 → 1920）
    private func span(_ minFromMidnight: Double, _ durationMin: Double, _ value: Double) -> SleepInference.Span {
        let start = rangeStart.addingTimeInterval((minFromMidnight - midnight) * 60)
        return SleepInference.Span(start: start,
                                   end: start.addingTimeInterval(durationMin * 60),
                                   value: value)
    }

    /// 全程佩戴：覆盖整个推断范围，每 30 分钟一个 HR 样本（贴近手表后台采样间隔）
    private func continuousHR() -> [SleepInference.Span] {
        (0...48).map { span(midnight + Double($0) * 30, 5, 62) }
    }

    /// 日间活动步数：12:00–22:30 与 次日 07:30–11:30 每 30 分钟一次
    private func daytimeSteps() -> [SleepInference.Span] {
        var out: [SleepInference.Span] = []
        var h = 12.0
        while h <= 22.5 { out.append(span(h * 60, 10, 30)); h += 0.5 }
        h = 31.5
        while h <= 35.5 { out.append(span(h * 60, 10, 25)); h += 0.5 }
        return out
    }

    /// 夜间窗口的分钟位置（距零点分钟）：23:00 → 1380
    private func minOfDay(_ date: Date) -> Double {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return Double(comps.hour! * 60 + comps.minute!)
    }

    // MARK: - 基本推断

    func testDetectsNightSleepFromInactivity() {
        let signals = SleepInference.Signals(steps: daytimeSteps(), stand: [], energy: [],
                                             heartRate: continuousHR())
        let windows = SleepInference.infer(signals: signals, range: (rangeStart, rangeEnd))
        XCTAssertEqual(windows.count, 1)
        let w = windows[0]
        // 入睡应在 22:40–23:30 之间，起床在 07:00–07:50 之间
        XCTAssertLessThanOrEqual(minOfDay(w.start), 23 * 60 + 40)
        XCTAssertGreaterThanOrEqual(minOfDay(w.start), 22 * 60)
        XCTAssertGreaterThanOrEqual(minOfDay(w.end), 7 * 60)
        XCTAssertLessThanOrEqual(minOfDay(w.end), 8 * 60)
        XCTAssertGreaterThanOrEqual(w.durationMin, 450)
        XCTAssertLessThanOrEqual(w.durationMin, 560)
        XCTAssertGreaterThanOrEqual(w.hrCoverage, 0.9)
    }

    func testShortAwakeWithin30MinMerges() {
        // 02:30 起床走动 10 分钟（步数 40）→ 空档 ≤ 20min 并入
        var steps = daytimeSteps()
        steps.append(span(26 * 60 + 30, 10, 40))
        let signals = SleepInference.Signals(steps: steps, stand: [], energy: [],
                                             heartRate: continuousHR())
        let windows = SleepInference.infer(signals: signals, range: (rangeStart, rangeEnd))
        XCTAssertEqual(windows.count, 1)
        XCTAssertGreaterThanOrEqual(windows[0].durationMin, 450)
    }

    func testAwakeOver30MinSplitsWindow() {
        // 01:00–02:00 活动 60 分钟（步数计入总量）→ 断为两段
        var steps = daytimeSteps()
        steps.append(span(25 * 60, 60, 6000))
        let signals = SleepInference.Signals(steps: steps, stand: [], energy: [],
                                             heartRate: continuousHR())
        let windows = SleepInference.infer(signals: signals, range: (rangeStart, rangeEnd))
        XCTAssertEqual(windows.count, 2)
    }

    func testStillnessUnder30MinDiscarded() {
        // 白天 13:10–13:35 静止 25 分钟（如短暂休息）→ 小于 30min 阈值，不视为小睡
        var steps = daytimeSteps().filter { s -> Bool in
            let m = s.start.timeIntervalSince(rangeStart) / 60 + midnight
            let inQuiet = m >= 13 * 60 && m < 13 * 60 + 30
            return !inQuiet
        }
        steps.append(span(13 * 60, 10, 40))
        steps.append(span(13 * 60 + 35, 10, 40))
        let signals = SleepInference.Signals(steps: steps, stand: [], energy: [],
                                             heartRate: continuousHR())
        let windows = SleepInference.infer(signals: signals, range: (rangeStart, rangeEnd))
        XCTAssertEqual(windows.count, 1)
        XCTAssertGreaterThanOrEqual(windows[0].durationMin, 400)
    }

    func testNapOver30MinDetected() {
        // 13:00、13:30 的活动缺席 → 12:40–14:00 静止约 80 分钟 = 午睡，应被识别
        let steps = daytimeSteps().filter { s -> Bool in
            let m = s.start.timeIntervalSince(rangeStart) / 60 + midnight
            return !(m >= 12 * 60 + 60 && m < 14 * 60)
        }
        let signals = SleepInference.Signals(steps: steps, stand: [], energy: [],
                                             heartRate: continuousHR())
        let windows = SleepInference.infer(signals: signals, range: (rangeStart, rangeEnd))
        XCTAssertEqual(windows.count, 2) // 夜间主睡眠 + 午睡
        let nap = windows.first { $0.durationMin < 180 }
        XCTAssertNotNil(nap)
        XCTAssertGreaterThanOrEqual(nap?.durationMin ?? 0, 40)
        XCTAssertLessThanOrEqual(nap?.durationMin ?? 0, 100)
    }

    func testNoHRDataMeansNoInference() {
        // 无 HR 样本（摘表）→ 不可判定 → 无窗口
        let signals = SleepInference.Signals(steps: daytimeSteps(), stand: [], energy: [],
                                             heartRate: [])
        let windows = SleepInference.infer(signals: signals, range: (rangeStart, rangeEnd))
        XCTAssertTrue(windows.isEmpty)
    }

    func testEmptySignalsReturnEmpty() {
        let signals = SleepInference.Signals()
        let windows = SleepInference.infer(signals: signals, range: (rangeStart, rangeEnd))
        XCTAssertTrue(windows.isEmpty)
    }

    func testDraftConversion() {
        let w = SleepInference.InferredWindow(start: rangeStart,
                                              end: rangeStart.addingTimeInterval(7 * 3600),
                                              stillness: 0.98, hrCoverage: 0.95)
        let d = SleepInference.draft(from: w)
        XCTAssertEqual(d.segments.count, 1)
        XCTAssertEqual(d.segments[0].stage, "asleepUnspecified")
        XCTAssertEqual(d.efficiency, SleepInference.assumedEfficiency, accuracy: 0.001)
        XCTAssertEqual(d.durationMin, 420, accuracy: 0.1)
    }

    func testConfidenceReflectsHRCoverage() {
        let good = SleepInference.InferredWindow(start: rangeStart,
                                                 end: rangeStart.addingTimeInterval(7 * 3600),
                                                 stillness: 1, hrCoverage: 0.95)
        let poor = SleepInference.InferredWindow(start: rangeStart,
                                                 end: rangeStart.addingTimeInterval(7 * 3600),
                                                 stillness: 1, hrCoverage: 0.4)
        let cg = SleepInference.confidence(for: good)
        let cp = SleepInference.confidence(for: poor)
        XCTAssertGreaterThan(cg.value, cp.value)
    }
}
