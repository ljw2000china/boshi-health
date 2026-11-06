import Foundation
import HealthKit

/// 常用类型 identifier 快捷常量（避免到处硬编码字符串）。
public enum HKTypeIdentifiers {
    public static let heartRateID = HKQuantityTypeIdentifier.heartRate.rawValue
    public static let hrvID = HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue
    public static let restingHRID = HKQuantityTypeIdentifier.restingHeartRate.rawValue
    public static let respiratoryID = HKQuantityTypeIdentifier.respiratoryRate.rawValue
    public static let wristTempID = HKQuantityTypeIdentifier.appleSleepingWristTemperature.rawValue
    public static let oxygenID = HKQuantityTypeIdentifier.oxygenSaturation.rawValue
    public static let sleepAnalysisID = HKCategoryTypeIdentifier.sleepAnalysis.rawValue
    public static let stepCountID = HKQuantityTypeIdentifier.stepCount.rawValue
    public static let activeEnergyID = HKQuantityTypeIdentifier.activeEnergyBurned.rawValue
    public static let standTimeID = HKQuantityTypeIdentifier.appleStandTime.rawValue
    public static let distanceID = HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue
    public static let exerciseTimeID = HKQuantityTypeIdentifier.appleExerciseTime.rawValue
    public static let workoutID = "workout"
}
