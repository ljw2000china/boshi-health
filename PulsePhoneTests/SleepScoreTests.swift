import XCTest
@testable import PulsePhone
import Foundation

/// 睡眠评分公式（design.md §9）与基线数学（MAD 稳健化）单测
final class SleepScoreTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    // MARK: 评分公式

    func testPerfectSleepScores100() {
        let c = SleepScore.compute(durationHours: 7.5, efficiency: 1.0,
                                   structureDeviation: 1.0,
                                   sleepMidpoints: stableMidpoints(),
                                   baselineDays: 20)
        XCTAssertEqual(c.total, 100)
    }

    func testZeroSleepScores0() {
        let c = SleepScore.compute(durationHours: 0, efficiency: 0,
                                   structureDeviation: 0,
                                   sleepMidpoints: [],
                                   baselineDays: 20)
        XCTAssertEqual(c.total, 0)
    }

    func testCalibrationPeriodNoTotal() {
        let c = SleepScore.compute(durationHours: 7.0, efficiency: 0.9,
                                   structureDeviation: nil,
                                   sleepMidpoints: [],
                                   baselineDays: 5)
        XCTAssertNil(c.total)
        XCTAssertTrue(c.inCalibration)
        XCTAssertTrue(c.note.contains("标定期"))
    }

    func testDurationCappedAtTarget() {
        let c = SleepScore.compute(durationHours: 10, efficiency: 1.0,
                                   structureDeviation: 1.0,
                                   sleepMidpoints: stableMidpoints(),
                                   baselineDays: 20)
        // 时长分封顶 1.0 → 40 分
        XCTAssertEqual(c.duration, 1.0)
        XCTAssertEqual(c.durationContribution, 40, accuracy: 0.01)
    }

    func testPlaceholderScoresWhenNoHistory() {
        let c = SleepScore.compute(durationHours: 7.0, efficiency: 0.8,
                                   structureDeviation: nil,
                                   sleepMidpoints: [],
                                   baselineDays: 20)
        XCTAssertEqual(c.structure, 0.5)    // 占位
        XCTAssertEqual(c.regularity, 0.5)   // 占位
        XCTAssertFalse(c.note.isEmpty)
    }

    // MARK: 规律性

    func testRegularityStableMidpointsHigh() {
        let s = SleepScore.regularityScore(midpoints: stableMidpoints())
        XCTAssertGreaterThan(s, 0.9)
    }

    func testRegularityVariedMidpointsLower() {
        var midpoints: [Date] = []
        for (h, m) in [(23, 0), (1, 30), (23, 15), (22, 45), (0, 45)] {
            var c = DateComponents()
            c.year = 2024; c.month = 3; c.day = 10; c.hour = h; c.minute = m
            midpoints.append(cal.date(from: c)!)
        }
        let s = SleepScore.regularityScore(midpoints: midpoints)
        XCTAssertLessThan(s, 0.6)
    }

    /// 跨午夜边界：23:59 与 00:01 只差 2 分钟，规律性必须很高
    func testRegularityCrossMidnightBoundary() {
        var midpoints: [Date] = []
        for (d, h, m) in [(1, 23, 59), (2, 0, 1), (3, 23, 58), (4, 0, 2)] {
            var c = DateComponents()
            c.year = 2024; c.month = 3; c.day = d; c.hour = h; c.minute = m
            midpoints.append(cal.date(from: c)!)
        }
        let s = SleepScore.regularityScore(midpoints: midpoints)
        XCTAssertGreaterThan(s, 0.9)
    }

    // MARK: Baseline 数学

    func testMedianOdd() {
        XCTAssertEqual(BaselineMath.median([1, 5, 3]), 3)
    }

    func testMedianEven() {
        XCTAssertEqual(BaselineMath.median([1, 2, 3, 10]), 2.5)
    }

    func testMADScaling() {
        // [50, 52, 54] median=52, |dev|=[2,0,2] median=2 → MAD=2*1.4826
        let mad = BaselineMath.mad([50, 52, 54])
        XCTAssertEqual(mad!, 2 * 1.4826, accuracy: 0.0001)
    }

    func testRobustZ() {
        let z = BaselineMath.robustZ(value: 58, median: 50, mad: 4)
        XCTAssertEqual(z!, 2.0, accuracy: 0.0001)
        XCTAssertNil(BaselineMath.robustZ(value: 58, median: 50, mad: 0))
    }

    func testBaselineValueBuild() {
        let bv = BaselineValue.build(metric: "restingHR", dailyValues: [50, 52, 54, 51, 53])
        XCTAssertNotNil(bv)
        XCTAssertEqual(bv!.sampleDays, 5)
    }

    // MARK: 辅助

    private func stableMidpoints() -> [Date] {
        var result: [Date] = []
        for d in 1...7 {
            var c = DateComponents()
            c.year = 2024; c.month = 3; c.day = d; c.hour = 23; c.minute = 15
            result.append(cal.date(from: c)!)
        }
        return result
    }
}
