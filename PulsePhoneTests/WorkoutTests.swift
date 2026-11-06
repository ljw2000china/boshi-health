import XCTest
@testable import PulsePhone
import Foundation

/// 训练检测 + 组次记录单测（design.md §7/§8）
final class WorkoutTests: XCTestCase {

    // MARK: - WorkoutDetector

    func testHRSignalSustained() {
        let input = WorkoutDetector.WindowInput(
            restingHR: 60,
            hrPerMin: [95, 96, 97, 95, 96],  // 5min ≥ 95 (resting+35)
            energyPerMin: [])
        let s = WorkoutDetector.hrSignal(input: input)
        XCTAssertEqual(s, 1.0) // 5min ≥ 4min
    }

    func testHRSignalInsufficient() {
        let input = WorkoutDetector.WindowInput(
            restingHR: 60,
            hrPerMin: [95, 96, 70, 95],  // only 2 consecutive
            energyPerMin: [])
        let s = WorkoutDetector.hrSignal(input: input)
        XCTAssertLessThan(s, 1.0)
    }

    func testEnergySignalSustained() {
        let input = WorkoutDetector.WindowInput(
            restingHR: 60,
            hrPerMin: [],
            energyPerMin: [5, 5, 5, 5, 5])  // 5min ≥ 4kcal/min
        let s = WorkoutDetector.energySignal(input: input)
        XCTAssertEqual(s, 1.0)
    }

    func testConfidenceSilentStart() {
        let input = WorkoutDetector.WindowInput(
            restingHR: 60,
            hrPerMin: Array(repeating: 100.0, count: 10),
            energyPerMin: Array(repeating: 6.0, count: 10),
            timePrior: 1.0,  // 下午训练时段
            motionActive: 1.0)
        let conf = WorkoutDetector.confidence(input: input)
        XCTAssertGreaterThan(conf, 0.8)
        if case .silentStart = WorkoutDetector.decide(input: input) {} else { XCTFail("应静默启动") }
    }

    func testConfidenceIgnore() {
        let input = WorkoutDetector.WindowInput(
            restingHR: 60,
            hrPerMin: [70, 72, 68, 70],
            energyPerMin: [0.5, 0.3, 0.2, 0.1],
            timePrior: 0, motionActive: 0)
        let conf = WorkoutDetector.confidence(input: input)
        XCTAssertLessThan(conf, 0.5)
        XCTAssertEqual(WorkoutDetector.decide(input: input), .ignore)
    }

    func testTypeInferenceRunning() {
        let input = WorkoutDetector.WindowInput(
            restingHR: 60,
            hrPerMin: Array(repeating: 160.0, count: 10),  // 高心率
            energyPerMin: Array(repeating: 10.0, count: 10), // 高能量
            timePrior: 0.5, motionActive: 0.5)
        let type = WorkoutDetector.inferType(input: input)
        XCTAssertEqual(type, .running)
    }

    func testTypeInferenceStrength() {
        let input = WorkoutDetector.WindowInput(
            restingHR: 60,
            hrPerMin: Array(repeating: 100.0, count: 10),  // 中高心率
            energyPerMin: Array(repeating: 5.0, count: 10),  // 中高能量
            timePrior: 0.5, motionActive: 0.5)
        let type = WorkoutDetector.inferType(input: input)
        XCTAssertEqual(type, .strength)
    }

    func testShouldEnd() {
        let input = WorkoutDetector.EndWindowInput(
            restingHR: 60,
            hrPerMin: [70, 68, 72, 69, 71],  // all ≤ 75 (resting+15)
            energyPerMin: [0.5, 0.3, 0.8, 0.2, 0.1]) // all < 1.5
        XCTAssertTrue(WorkoutDetector.shouldEnd(input: input))
    }

    func testShouldNotEnd() {
        let input = WorkoutDetector.EndWindowInput(
            restingHR: 60,
            hrPerMin: [70, 100, 68, 69, 71],  // one spike
            energyPerMin: [0.5, 5.0, 0.3, 0.2, 0.1])
        XCTAssertFalse(WorkoutDetector.shouldEnd(input: input))
    }

    // MARK: - WorkoutSession 状态机

    func testSessionLifecycle() {
        var s = WorkoutSession()
        XCTAssertEqual(s.state, .idle)
        s.start(at: Date(), type: .strength, auto: true)
        XCTAssertEqual(s.state, .active)
        XCTAssertTrue(s.autoStarted)
        s.beginEnding()
        XCTAssertEqual(s.state, .ending)
        s.end(at: Date())
        XCTAssertEqual(s.state, .ended)
        XCTAssertGreaterThan(s.durationSec, 0)
    }

    func testSessionCancel() {
        var s = WorkoutSession()
        s.start(at: Date(), type: .strength, auto: false)
        s.cancel()
        XCTAssertEqual(s.state, .idle)
        XCTAssertNil(s.startTime)
    }

    // MARK: - ExerciseLibrary

    func testSeedCount() {
        XCTAssertGreaterThanOrEqual(ExerciseLibrary.seeds.count, 60)
    }

    func testSeedGroups() {
        let groups = ExerciseLibrary.groupedSeeds()
        XCTAssertEqual(groups.count, 7) // 胸/背/腿/肩/臂/核心/有氧
        XCTAssertTrue(groups.allSatisfy { !$0.exercises.isEmpty })
    }

    func testSeedUniqueIDs() {
        let ids = ExerciseLibrary.seeds.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - SleepDebt level（M3 补充）

    func testSleepDebtMild() {
        XCTAssertEqual(SleepDebt.level(of: 1.5), .mild)
    }
}
