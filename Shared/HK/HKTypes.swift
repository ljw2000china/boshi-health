import Foundation
import HealthKit

/// 数值/样本的展示格式化方式。
public enum HKValueFormat {
    case decimal0        // 整数值（如心率 bpm）
    case decimal1        // 1 位小数（如 HRV ms）
    case decimal2        // 2 位小数（如腕温 ℃）
    case percent         // 百分比（血氧 0-1 → 0-100%）
    case distanceKm      // 米 → 公里
    case sleepCategory   // 睡眠分类 → 中文
    case workout         // 训练：类型 + 时长
}

/// HealthKit 类型注册项（design.md §10 读清单，M0 全量注册）。
public struct HKTypeEntry {
    /// 类型标识（HKObjectType.identifier）
    public let identifier: String
    /// 中文展示名
    public let nameZh: String
    /// 是否数量类型
    public let isQuantity: Bool
    /// 数量单位（数量类型必有）
    public let unit: HKUnit?
    /// 展示格式化方式
    public let format: HKValueFormat
    /// 首次同步回填天数（高频类型收窄）
    public let backfillDays: Int

    public init(identifier: String, nameZh: String, isQuantity: Bool,
                unit: HKUnit?, format: HKValueFormat, backfillDays: Int = 60) {
        self.identifier = identifier
        self.nameZh = nameZh
        self.isQuantity = isQuantity
        self.unit = unit
        self.format = format
        self.backfillDays = backfillDays
    }

    /// 对应的 HKSampleType（workout 为 HKWorkoutType）
    public var sampleType: HKSampleType {
        if identifier == HKTypeRegistry.workoutIdentifier {
            return HKWorkoutType.workoutType()
        }
        if identifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue {
            return HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        }
        return HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: identifier))!
    }
}

/// design.md §10 全部读类型的注册表。
public enum HKTypeRegistry {

    /// workout 类型的特殊标识（非 quantity/category identifier 体系）
    public static let workoutIdentifier = "workout"

    /// 读类型清单（顺序即调试页展示顺序）
    public static let readEntries: [HKTypeEntry] = [
        HKTypeEntry(identifier: HKQuantityTypeIdentifier.heartRate.rawValue,
                    nameZh: "心率", isQuantity: true,
                    unit: HKUnit.count().unitDivided(by: .minute()), format: .decimal0,
                    backfillDays: 3),
        HKTypeEntry(identifier: HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue,
                    nameZh: "心率变异性", isQuantity: true,
                    unit: .secondUnit(with: .milli), format: .decimal1),
        HKTypeEntry(identifier: HKQuantityTypeIdentifier.restingHeartRate.rawValue,
                    nameZh: "静息心率", isQuantity: true,
                    unit: HKUnit.count().unitDivided(by: .minute()), format: .decimal0),
        HKTypeEntry(identifier: HKQuantityTypeIdentifier.respiratoryRate.rawValue,
                    nameZh: "呼吸频率", isQuantity: true,
                    unit: HKUnit.count().unitDivided(by: .minute()), format: .decimal0),
        HKTypeEntry(identifier: HKQuantityTypeIdentifier.appleSleepingWristTemperature.rawValue,
                    nameZh: "睡眠腕温", isQuantity: true,
                    unit: .degreeCelsius(), format: .decimal2),
        HKTypeEntry(identifier: HKQuantityTypeIdentifier.oxygenSaturation.rawValue,
                    nameZh: "血氧", isQuantity: true,
                    unit: .percent(), format: .percent),
        HKTypeEntry(identifier: HKCategoryTypeIdentifier.sleepAnalysis.rawValue,
                    nameZh: "睡眠分析", isQuantity: false, unit: nil, format: .sleepCategory),
        HKTypeEntry(identifier: HKQuantityTypeIdentifier.stepCount.rawValue,
                    nameZh: "步数", isQuantity: true, unit: .count(), format: .decimal0),
        HKTypeEntry(identifier: HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
                    nameZh: "活动能量", isQuantity: true, unit: .kilocalorie(), format: .decimal0),
        HKTypeEntry(identifier: HKQuantityTypeIdentifier.appleStandTime.rawValue,
                    nameZh: "站立时间", isQuantity: true, unit: .minute(), format: .decimal0),
        HKTypeEntry(identifier: HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue,
                    nameZh: "步行+跑步距离", isQuantity: true, unit: .meter(), format: .distanceKm),
        HKTypeEntry(identifier: HKQuantityTypeIdentifier.appleExerciseTime.rawValue,
                    nameZh: "锻炼时间", isQuantity: true, unit: .minute(), format: .decimal0),
        HKTypeEntry(identifier: workoutIdentifier,
                    nameZh: "训练", isQuantity: false, unit: nil, format: .workout),
    ]

    /// 授权请求用的全部读类型集合（quantity + category + workout）
    public static var readTypes: Set<HKObjectType> {
        Set(readEntries.map(\.sampleType))
    }

    /// 写回类型：HKWorkout（design.md §7：训练回写 HealthKit）
    /// 手表侧另加睡眠分析（推测窗口回写，见 SleepWriteback；手机侧不写避免重复）
    public static var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        #if os(watchOS)
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        #endif
        return types
    }

    /// 按标识查注册项
    public static func entry(for identifier: String) -> HKTypeEntry? {
        readEntries.first { $0.identifier == identifier }
    }
}
