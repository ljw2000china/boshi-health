import XCTest
@testable import PulsePhone
import Foundation

/// 睡眠窗构建器 + L2 状态机 + 评分公式单测（design.md §6/§9）
final class SleepWindowBuilderTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
        return cal.date(from: c)!
    }

    private func seg(_ stage: String, _ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int) -> SleepSegment {
        // 结束时间早于开始时间视为跨午夜（次日）
        let crossesMidnight = (h2, m2) <= (h1, m1)
        let start = date(2024, 3, 1, h1, m1)
        let end = crossesMidnight ? date(2024, 3, 2, h2, m2) : date(2024, 3, 1, h2, m2)
        return SleepSegment(stage: stage, start: start, end: end)
    }

    // MARK: L1 合并

    func testMergeGapWithin20Min() {
        let segs = [seg("asleepCore", 22, 0, 23, 30),
                    seg("asleepCore", 23, 45, 1, 0)] // gap = 15min ≤ 20
        let windows = SleepWindowBuilder.buildL1(segments: segs)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].durationMin, 180) // 22:00 → 01:00 = 180min
    }

    func testGapOver20MinSplitsWindow() {
        let segs = [seg("asleepCore", 22, 0, 23, 0),
                    seg("asleepCore", 23, 30, 1, 0)] // gap = 30min > 20
        let windows = SleepWindowBuilder.buildL1(segments: segs)
        XCTAssertEqual(windows.count, 2)
    }

    func testAwakeUnder5MinDropped() {
        let segs = [seg("asleepCore", 22, 0, 23, 0),
                    seg("awake", 23, 0, 23, 3),
                    seg("asleepCore", 23, 3, 1, 0)]
        let windows = SleepWindowBuilder.buildL1(segments: segs)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].durationMin, 180) // awake 段被丢弃，窗口连续
    }

    func testAwake5MinOrMoreKeepsBreak() {
        let segs = [seg("asleepCore", 22, 0, 23, 0),
                    seg("awake", 23, 0, 23, 5),
                    seg("asleepCore", 23, 5, 1, 0)]
        let windows = SleepWindowBuilder.buildL1(segments: segs)
        XCTAssertEqual(windows.count, 2) // 5min awake 断窗
    }

    func testInBedExcludedFromWindow() {
        let segs = [seg("inBed", 21, 30, 22, 0),
                    seg("asleepCore", 22, 0, 1, 0)]
        let windows = SleepWindowBuilder.buildL1(segments: segs)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].start, date(2024, 3, 1, 22, 0))
    }

    func testDayKey() {
        XCTAssertEqual(SleepWindowBuilder.dayKey(for: date(2024, 3, 1, 22, 0)), "2024-03-01")
    }

    // MARK: L2 判定

    func testL2AllowedWhenAllConditionsMet() {
        XCTAssertTrue(SleepWindowBuilder.l2ExtensionAllowed(
            steps: 0, standMin: 0, kcalPerMin: 0.5, hr: 52, nightHRMedian: 50, charging: false))
    }

    func testL2RejectedWhenStepsPositive() {
        XCTAssertFalse(SleepWindowBuilder.l2ExtensionAllowed(
            steps: 5, standMin: 0, kcalPerMin: 0, hr: 52, nightHRMedian: 50, charging: false))
    }

    func testL2RejectedWhenCharging() {
        XCTAssertFalse(SleepWindowBuilder.l2ExtensionAllowed(
            steps: 0, standMin: 0, kcalPerMin: 0, hr: 52, nightHRMedian: 50, charging: true))
    }

    func testL2RejectedWhenHRTooHigh() {
        XCTAssertFalse(SleepWindowBuilder.l2ExtensionAllowed(
            steps: 0, standMin: 0, kcalPerMin: 0, hr: 60, nightHRMedian: 50, charging: false))
    }

    func testL2RejectedWhenEnergyTooHigh() {
        XCTAssertFalse(SleepWindowBuilder.l2ExtensionAllowed(
            steps: 0, standMin: 0, kcalPerMin: 1.5, hr: 52, nightHRMedian: 50, charging: false))
    }

    func testL2LocksAfter3ConsecutiveFails() {
        var tracker = SleepWindowBuilder.L2Tracker()
        XCTAssertTrue(tracker.record(allowed: false))  // fail 1
        XCTAssertTrue(tracker.record(allowed: false))  // fail 2
        XCTAssertFalse(tracker.record(allowed: false)) // fail 3 → locked
        XCTAssertTrue(tracker.locked)
        XCTAssertFalse(tracker.record(allowed: true))  // locked 后不再恢复
    }

    func testL2FailCountResetsOnSuccess() {
        var tracker = SleepWindowBuilder.L2Tracker()
        tracker.record(allowed: false)
        tracker.record(allowed: false)
        XCTAssertTrue(tracker.record(allowed: true)) // 成功 → 计数清零
        XCTAssertEqual(tracker.failCount, 0)
        XCTAssertFalse(tracker.locked)
    }

    // MARK: 置信度

    func testConfidenceHigh() {
        let c = SleepWindowBuilder.confidence(hrCoverage: 0.9, continuity: 0.9, stillnessRatio: 0.9)
        XCTAssertEqual(c.symbol, "●")
        XCTAssertEqual(c.reason, "数据完整")
    }

    func testConfidenceLowShowsReasons() {
        let c = SleepWindowBuilder.confidence(hrCoverage: 0.3, continuity: 0.6, stillnessRatio: 0.5)
        XCTAssertEqual(c.symbol, "○")
        XCTAssertTrue(c.reason.contains("心率覆盖不足"))
    }
}
