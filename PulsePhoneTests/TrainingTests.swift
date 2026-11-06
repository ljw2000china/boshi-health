import XCTest
@testable import PulsePhone

final class TrainingTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        c.firstWeekday = 2
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 20) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h
        return cal.date(from: c)!
    }

    private func set(_ day: Int, _ muscle: String, weight: Double, reps: Int,
                     exercise: String = "bench_press", order: Int = 1) -> TrainingSummary.TrainingSet {
        TrainingSummary.TrainingSet(workoutID: "w1", exerciseID: exercise,
                                    exerciseName: exercise, muscleGroup: muscle,
                                    reps: reps, weightKg: weight, order: order,
                                    date: date(2025, 4, day))
    }

    // MARK: - RestRules

    func testRestCompoundChestIs3Min() {
        XCTAssertEqual(RestRules.recommended(exerciseID: "bench_press", muscleGroup: "胸"), 180)
    }

    func testRestIsolationChestIs2Min() {
        XCTAssertEqual(RestRules.recommended(exerciseID: "db_fly", muscleGroup: "胸"), 120)
    }

    func testRestArmsIs90s() {
        XCTAssertEqual(RestRules.recommended(exerciseID: "db_curl", muscleGroup: "臂"), 90)
    }

    func testRestHeavyWeightAddsTime() {
        XCTAssertEqual(RestRules.recommended(exerciseID: "squat", muscleGroup: "腿", weightKg: 120), 240)
        XCTAssertEqual(RestRules.recommended(exerciseID: "squat", muscleGroup: "腿", weightKg: 160), 270)
    }

    // MARK: - 练X日

    func testFocusSingleMuscle() {
        let f = TrainingSummary.focus(from: ["胸": 10, "腿": 2])
        XCTAssertEqual(f.title, "练胸日")
    }

    func testFocusTwoMusclesWhenSecondaryLarge() {
        let f = TrainingSummary.focus(from: ["胸": 10, "臂": 6])
        XCTAssertEqual(f.title, "练胸+臂日")
    }

    func testFocusEmptyIsRest() {
        XCTAssertEqual(TrainingSummary.focus(from: [:]).title, "休息日")
    }

    // MARK: - 日总结

    func testDaySummaryTotals() {
        let s1: TrainingSummary.TrainingSet = set(2, "胸", weight: 60, reps: 10)
        let s2: TrainingSummary.TrainingSet = set(2, "胸", weight: 60, reps: 8, order: 2)
        let s3: TrainingSummary.TrainingSet = set(2, "臂", weight: 15, reps: 12)
        let sets: [TrainingSummary.TrainingSet] = [s1, s2, s3]
        let s = TrainingSummary.summarizeDay(dayKey: "2025-04-02", sets: sets)
        XCTAssertEqual(s.totalSets, 3)
        let expectedVolume: Double = 600 + 480 + 180
        XCTAssertEqual(s.volumeKg, expectedVolume)
        XCTAssertEqual(s.muscleSets["胸"], 2)
        XCTAssertEqual(s.exerciseOrder, ["bench_press"])
    }

    // MARK: - 周汇总

    func testWeekIntervalStartsMonday() {
        let (start, end) = TrainingSummary.weekInterval(containing: date(2025, 4, 2), calendar: cal)
        XCTAssertEqual(TrainingSummary.dayKey(for: start, calendar: cal), "2025-03-31")
        XCTAssertEqual(cal.dateComponents([.day], from: start, to: end).day, 7)
    }

    func testWeekSummaryAggregates() {
        let chestSets: [TrainingSummary.TrainingSet] = [set(1, "胸", weight: 60, reps: 10),
                                                        set(3, "胸", weight: 60, reps: 10)]
        let backSet: TrainingSummary.TrainingSet = set(2, "背", weight: 80, reps: 8)
        let sets: [TrainingSummary.TrainingSet] = chestSets + [backSet]
        let interval = TrainingSummary.weekInterval(containing: date(2025, 4, 2), calendar: cal)
        let w = TrainingSummary.summarizeWeek(sets: sets, interval: interval, calendar: cal)
        XCTAssertEqual(w.totalSets, 3)
        XCTAssertEqual(w.trainedDays, 3)
        XCTAssertEqual(w.muscleSets["胸"], 2)
        let expectedVolume: Double = 1200 + 640
        XCTAssertEqual(w.volumeKg, expectedVolume)
        let expectedIntensity: Double = 2.0 / TrainingSummary.WeekSummary.intensityCapSets
        XCTAssertEqual(w.intensity(for: "胸"), expectedIntensity, accuracy: 1e-9)
    }

    func testComparisonPercent() {
        let thisW = TrainingSummary.WeekSummary(start: date(2025, 4, 7), end: date(2025, 4, 14),
                                                totalSets: 30, volumeKg: 3000, trainedDays: 4,
                                                muscleSets: ["胸": 12], muscleVolume: ["胸": 3000],
                                                dayFocus: [])
        let lastW = TrainingSummary.WeekSummary(start: date(2025, 3, 31), end: date(2025, 4, 7),
                                                totalSets: 20, volumeKg: 2000, trainedDays: 3,
                                                muscleSets: ["胸": 8], muscleVolume: ["胸": 2000],
                                                dayFocus: [])
        let c = TrainingSummary.compare(thisWeek: thisW, lastWeek: lastW)
        XCTAssertEqual(c.setDelta, 10)
        XCTAssertEqual(c.volumeDeltaPct ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(c.muscleSetDelta("胸"), 4)
    }

    // MARK: - 进步曲线

    func testProgressMilestonesAndHeldDays() {
        let sets: [TrainingSummary.TrainingSet] = [set(1, "胸", weight: 60, reps: 5),
                                                   set(8, "胸", weight: 62.5, reps: 3),
                                                   set(15, "胸", weight: 60, reps: 6)]
        let p = TrainingSummary.progress(exerciseID: "bench_press", sets: sets,
                                         now: date(2025, 4, 18), calendar: cal)
        XCTAssertEqual(p.points.count, 3)
        XCTAssertEqual(p.personalBest, 62.5)
        XCTAssertEqual(p.milestones.count, 2)
        XCTAssertEqual(p.milestones[0].weightKg, 60)
        XCTAssertEqual(p.milestones[0].heldDays, 7)   // 4/1 → 4/8
        XCTAssertEqual(p.heldDays, 10)                // 4/8 → 4/18
    }

    func testEstOneRM() {
        // Epley：60kg × 10 → 80
        XCTAssertEqual(TrainingSummary.estOneRM(weightKg: 60, reps: 10), 80, accuracy: 0.001)
        XCTAssertEqual(TrainingSummary.estOneRM(weightKg: 0, reps: 10), 0)
    }

    func testProgressEmpty() {
        let p = TrainingSummary.progress(exerciseID: "squat", sets: [], now: Date(), calendar: cal)
        XCTAssertTrue(p.points.isEmpty)
        XCTAssertEqual(p.personalBest, 0)
    }
}

// MARK: - 表盘小组件数据

final class TrainingDaySnapshotTests: XCTestCase {

    func testRestDayWhenNoMuscles() {
        let s = TrainingDaySnapshot.make(muscleGroups: [])
        XCTAssertTrue(s.isRest)
        XCTAssertEqual(s.title, "休息日")
        XCTAssertEqual(s.emoji, "😴")
    }

    func testChestDayEmoji() {
        let s = TrainingDaySnapshot.make(muscleGroups: ["胸"])
        XCTAssertEqual(s.title, "练胸日")
        XCTAssertEqual(s.emoji, "💪")
        XCTAssertEqual(s.detail, "胸")
    }

    func testDeduplicatesAndTakesTwoMuscles() {
        let s = TrainingDaySnapshot.make(muscleGroups: ["胸", "胸", "臂", "背"])
        XCTAssertEqual(s.title, "练胸+臂日")
        XCTAssertEqual(s.muscles, ["胸", "臂", "背"])
    }

    func testGenericStrengthDay() {
        let s = TrainingDaySnapshot.make(muscleGroups: ["力量"])
        XCTAssertEqual(s.title, "练力量日")
        XCTAssertEqual(s.emoji, "🏋️")
    }

    func testRestSubtitleComesFromPoolAndIsDayStable() {
        let a = TrainingDaySnapshot.make(muscleGroups: [], seed: 42)
        let b = TrainingDaySnapshot.make(muscleGroups: [], seed: 42)
        XCTAssertTrue(TrainingDaySnapshot.restLines.contains(a.subtitle))
        XCTAssertEqual(a.subtitle, b.subtitle)
        XCTAssertNotEqual(TrainingDaySnapshot.restLines.isEmpty, true)
    }

    func testTrainingSubtitleIsMuscleFunLine() {
        let s = TrainingDaySnapshot.make(muscleGroups: ["腿"])
        XCTAssertEqual(s.title, "练腿日")
        XCTAssertEqual(s.subtitle, "练完腿别去爬楼")
    }

    func testWeekDotsMapRecentDays() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var c = DateComponents(); c.year = 2025; c.month = 4; c.day = 10; c.hour = 20
        let now = cal.date(from: c)!
        var c2 = DateComponents(); c2.year = 2025; c2.month = 4; c2.day = 8; c2.hour = 10
        let twoDaysAgo = cal.date(from: c2)!
        let dots = TrainingDaySnapshot.weekDots(dates: [now, twoDaysAgo], now: now, calendar: cal)
        XCTAssertEqual(dots.count, 7)
        XCTAssertTrue(dots[6])   // 今天
        XCTAssertTrue(dots[4])   // 两天前
        XCTAssertFalse(dots[5])
    }
}
