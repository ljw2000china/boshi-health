import XCTest
@testable import PulsePhone
import Foundation

/// 评分引擎单测（design.md §9）：Recovery / Strain / ACWR / SleepDebt / Stress / Readiness
final class ScoringTests: XCTestCase {

    // MARK: - Recovery

    func testRecoveryHighHRVLowRHR() {
        let c = RecoveryScore.compute(zHRV: 1.5, zRHR: -1.0, zResp: 0,
                                      wristTempOffset: 0, zSleepEff: 1.0,
                                      energyLevel: 5, baselineDays: 20)
        XCTAssertNotNil(c)
        XCTAssertGreaterThan(c!.total!, 70)
    }

    func testRecoveryLowHRVHighRHR() {
        let c = RecoveryScore.compute(zHRV: -1.5, zRHR: 1.5, zResp: 0,
                                      wristTempOffset: 0, zSleepEff: 0,
                                      energyLevel: 1, baselineDays: 20)
        XCTAssertNotNil(c)
        XCTAssertLessThan(c!.total!, 40)
    }

    func testRecoveryMissingCoreReturnsNil() {
        let c = RecoveryScore.compute(zHRV: nil, zRHR: nil, baselineDays: 20)
        XCTAssertNil(c)
    }

    func testRecoveryCalibrationNoTotal() {
        let c = RecoveryScore.compute(zHRV: 1.0, zRHR: -0.5, baselineDays: 5)
        XCTAssertNotNil(c)
        XCTAssertNil(c!.total)
        XCTAssertTrue(c!.inCalibration)
    }

    func testRecoveryWristTempPenalty() {
        let c = RecoveryScore.compute(zHRV: 0, zRHR: 0, wristTempOffset: 2.0,
                                      baselineDays: 20)
        // 偏移 2℃ → 惩罚 0.10·(2/1.5)=0.133
        XCTAssertLessThan(c!.total!, 55)
    }

    // MARK: - Strain

    func testStrainZero() {
        XCTAssertEqual(StrainScore.strain(trimp: 0), 0)
    }

    func testStrainSaturatesAt21() {
        let s = StrainScore.strain(trimp: 1000)
        XCTAssertGreaterThan(s, 20)
        XCTAssertLessThanOrEqual(s, 21)
    }

    func testTrimpZoneWeights() {
        // 10min in zone5 (weight 5) = 50
        let t = StrainScore.trimp(zoneMinutes: [0, 0, 0, 0, 10])
        XCTAssertEqual(t, 50)
    }

    func testTrimpWithNEAT() {
        // 10min zone3 (30) + 100 kcal NEAT * 0.3 = 30
        let t = StrainScore.trimp(zoneMinutes: [0, 0, 10, 0, 0], neatKcal: 100)
        XCTAssertEqual(t, 30 + 30)
    }

    func testZoneClassification() {
        XCTAssertEqual(StrainScore.zone(hr: 100, maxHR: 200), 1) // 50% < 55% → zone1
        XCTAssertEqual(StrainScore.zone(hr: 120, maxHR: 200), 2) // 60% → zone2
        XCTAssertEqual(StrainScore.zone(hr: 140, maxHR: 200), 3) // 70% → zone3
        XCTAssertEqual(StrainScore.zone(hr: 160, maxHR: 200), 4) // 80% → zone4
        XCTAssertEqual(StrainScore.zone(hr: 195, maxHR: 200), 5) // 97.5% → zone5
    }

    // MARK: - ACWR

    func testACWRSweetZone() {
        // 7d avg = 10, 28d avg = 10 → 1.0
        let v = ACWRScore.acwr(last28Strain: Array(repeating: 10.0, count: 28))
        XCTAssertEqual(v!, 1.0, accuracy: 0.01)
        XCTAssertEqual(ACWRScore.status(of: v!), .sweet)
    }

    func testACWRRisk() {
        // 前 7 天全 20，后 21 天全 5 → acute=20, chronic=(140+105)/28=8.75 → 2.28
        var strains = Array(repeating: 20.0, count: 7) + Array(repeating: 5.0, count: 21)
        let v = ACWRScore.acwr(last28Strain: strains)
        XCTAssertGreaterThan(v!, 1.5)
        XCTAssertEqual(ACWRScore.status(of: v!), .risk)
    }

    func testACWRInsufficientData() {
        XCTAssertNil(ACWRScore.acwr(last28Strain: Array(repeating: 5.0, count: 10)))
    }

    func testACWRZeroChronic() {
        XCTAssertNil(ACWRScore.acwr(last28Strain: Array(repeating: 0.0, count: 28)))
    }

    // MARK: - SleepDebt

    func testSleepDebtNoDebt() {
        let d = SleepDebt.debtHours(actualHours: Array(repeating: 8.0, count: 14))
        XCTAssertEqual(d, 0)
    }

    func testSleepDebtAccumulates() {
        // 14 天每天少睡 1h → 14h，但上限 10h
        let d = SleepDebt.debtHours(actualHours: Array(repeating: 6.5, count: 14))
        XCTAssertEqual(d, 10)
    }

    func testSleepNeedIncreasesWithStrain() {
        let need0 = SleepDebt.sleepNeedHours(debtHours: 0, trimp: 0)
        let need100 = SleepDebt.sleepNeedHours(debtHours: 0, trimp: 100)
        XCTAssertGreaterThan(need100, need0)
    }

    func testSleepNeedIncreasesWithDebt() {
        let need0 = SleepDebt.sleepNeedHours(debtHours: 0, trimp: 0)
        let need5 = SleepDebt.sleepNeedHours(debtHours: 5, trimp: 0)
        XCTAssertGreaterThan(need5, need0)
    }

    func testSleepDebtLevel() {
        XCTAssertEqual(SleepDebt.level(of: 0.5), .none)
        XCTAssertEqual(SleepDebt.level(of: 2), .mild)
        XCTAssertEqual(SleepDebt.level(of: 4), .moderate)
        XCTAssertEqual(SleepDebt.level(of: 7), .severe)
    }

    // MARK: - Stress

    func testStressCalm() {
        let c = StressScore.compute(dayHRV: 50, nightHRVMedian: 50,
                                    dayHR: 60, nightHRMedian: 60)
        XCTAssertLessThan(c!.value, 35)
        XCTAssertEqual(StressScore.level(value: c!.value), .calm)
    }

    func testStressHigh() {
        let c = StressScore.compute(dayHRV: 10, nightHRVMedian: 50,
                                    dayHR: 90, nightHRMedian: 60)
        XCTAssertGreaterThan(c!.value, 65)
        XCTAssertEqual(StressScore.level(value: c!.value), .high)
    }

    func testStressMissingHRVReturnsNil() {
        XCTAssertNil(StressScore.compute(dayHRV: nil, nightHRVMedian: 50,
                                         dayHR: 60, nightHRMedian: 60))
    }

    // MARK: - Readiness

    func testReadinessHighRecovery() {
        let r = ReadinessScore.compute(recovery: 90, sleepDebtHours: 0,
                                       yesterdayStrain: 5, acwrRisk: 1, soreness: 1)
        XCTAssertGreaterThan(r!, 7)
    }

    func testReadinessLowRecoveryHighDebt() {
        let r = ReadinessScore.compute(recovery: 30, sleepDebtHours: 8,
                                       yesterdayStrain: 20, acwrRisk: 8, soreness: 5)
        XCTAssertLessThan(r!, 4)
    }

    func testReadinessNilRecovery() {
        XCTAssertNil(ReadinessScore.compute(recovery: nil, sleepDebtHours: 0,
                                            yesterdayStrain: 0, acwrRisk: 0))
    }

    func testReadinessAdvice() {
        XCTAssertTrue(ReadinessScore.advice(readiness: 9).contains("状态好"))
        XCTAssertTrue(ReadinessScore.advice(readiness: 3).contains("恢复"))
    }

    // MARK: - DataPipeline.computeDay（纯函数集成）

    func testComputeDayFull() {
        let baselines: [String: BaselineValue] = [
            "hrv": BaselineValue(metric: "hrv", median: 45, mad: 10, sampleDays: 20),
            "restingHR": BaselineValue(metric: "restingHR", median: 55, mad: 5, sampleDays: 20),
            "respiratory": BaselineValue(metric: "respiratory", median: 15, mad: 2, sampleDays: 20),
            "wristTemp": BaselineValue(metric: "wristTemp", median: 36.5, mad: 0.3, sampleDays: 20),
        ]
        let out = DataPipeline.computeDay(
            input: .init(dayKey: "2024-03-01", nightHRV: 55, restingHR: 50,
                         nightResp: 14, wristTemp: 36.5,
                         sleepEfficiency: 0.92, sleepAsleepHours: 7.5,
                         strain: 10, trimp: 100, energy: 4, soreness: 2),
            baselines: baselines,
            recentStrains: Array(repeating: 10.0, count: 28),
            recentSleepHours: Array(repeating: 7.5, count: 14),
            yesterdayStrain: 10)
        XCTAssertNotNil(out.recovery)
        XCTAssertNotNil(out.readiness)
        XCTAssertNotNil(out.acwr)
        XCTAssertEqual(out.strain, 10, accuracy: 0.1)
    }

    func testComputeDayMissingCore() {
        let out = DataPipeline.computeDay(
            input: .init(dayKey: "2024-03-01", nightHRV: nil, restingHR: nil,
                         nightResp: nil, wristTemp: nil,
                         sleepEfficiency: 0.9, sleepAsleepHours: 7,
                         strain: 5, trimp: 50, energy: nil, soreness: nil),
            baselines: [:], recentStrains: [], recentSleepHours: [],
            yesterdayStrain: 0)
        XCTAssertNil(out.recovery)
        XCTAssertNil(out.readiness)
        XCTAssertFalse(out.notes.isEmpty)
    }

    // MARK: - MorningReport

    func testMorningMessageFull() {
        let msg = MorningReport.morningMessage(
            sleepWindow: "23:00–07:00", sleepScore: 85,
            recovery: 72, readiness: 8.0, strain: 12.5,
            advice: "状态好，可正常或加量训练")
        XCTAssertTrue(msg.contains("睡眠 23:00–07:00"))
        XCTAssertTrue(msg.contains("睡眠分 85"))
        XCTAssertTrue(msg.contains("恢复 72"))
        XCTAssertTrue(msg.contains("准备度 8.0"))
    }

    func testMorningMessageMinimal() {
        let msg = MorningReport.morningMessage(
            sleepWindow: "23:00–06:30", sleepScore: nil,
            recovery: nil, readiness: nil, strain: nil, advice: nil)
        XCTAssertEqual(msg, "睡眠 23:00–06:30")
    }

    func testMorningReportIDUniquePerDay() {
        let id = MorningReport.morningReportID()
        XCTAssertTrue(id.contains(SleepWindowBuilder.dayKey(for: Date())))
    }
}
