import Foundation

/// 训练自动检测信号（design.md §7，10min 滚动窗）。
/// 纯函数 + 值类型，无 HK/SwiftData 依赖，便于单测。
public enum WorkoutDetector {

    // MARK: - 信号权重

    public static let wHR: Double = 0.35
    public static let wEnergy: Double = 0.30
    public static let wTimePrior: Double = 0.20
    public static let wMotion: Double = 0.15

    // MARK: - 阈值

    public static let hrThresholdBPM: Double = 35   // HR ≥ 静息+35
    public static let hrSustainMin: Double = 4      // 持续 4min
    public static let energyThresholdKcalMin: Double = 4 // ≥4kcal/min
    public static let energySustainMin: Double = 5  // 持续 5min
    public static let endHRThresholdBPM: Double = 15 // HR ≤ 静息+15
    public static let endEnergyThreshold: Double = 1.5 // <1.5kcal/min
    public static let endSustainMin: Double = 5     // 持续 5min

    // MARK: - 信号输入

    /// 10min 窗口内的采样摘要
    public struct WindowInput: Equatable {
        public var restingHR: Double
        /// 每分钟 HR 数组（最近 10min）
        public var hrPerMin: [Double]
        /// 每分钟活动能量 kcal/min
        public var energyPerMin: [Double]
        /// 时段先验 0–1（如下午训练时段 = 1，深夜 = 0）
        public var timePrior: Double
        /// 运动类型先验 0–1（CMMotionActivity: stationary=false → 1）
        public var motionActive: Double

        public init(restingHR: Double, hrPerMin: [Double], energyPerMin: [Double],
                    timePrior: Double = 0.5, motionActive: Double = 0.5) {
            self.restingHR = restingHR
            self.hrPerMin = hrPerMin
            self.energyPerMin = energyPerMin
            self.timePrior = timePrior
            self.motionActive = motionActive
        }
    }

    // MARK: - 单信号判定

    /// HR 信号：HR ≥ 静息+35 持续 ≥4min → 1，否则按比例
    public static func hrSignal(input: WindowInput) -> Double {
        let threshold = input.restingHR + hrThresholdBPM
        var consecutive = 0
        var maxConsecutive = 0
        for hr in input.hrPerMin {
            if hr >= threshold {
                consecutive += 1
                maxConsecutive = max(maxConsecutive, consecutive)
            } else {
                consecutive = 0
            }
        }
        return min(1, Double(maxConsecutive) / hrSustainMin)
    }

    /// 能量信号：≥4kcal/min 持续 ≥5min → 1
    public static func energySignal(input: WindowInput) -> Double {
        var consecutive = 0
        var maxConsecutive = 0
        for e in input.energyPerMin {
            if e >= energyThresholdKcalMin {
                consecutive += 1
                maxConsecutive = max(maxConsecutive, consecutive)
            } else {
                consecutive = 0
            }
        }
        return min(1, Double(maxConsecutive) / energySustainMin)
    }

    // MARK: - 置信度

    public static func confidence(input: WindowInput) -> Double {
        let hr = hrSignal(input: input)
        let energy = energySignal(input: input)
        return wHR * hr + wEnergy * energy + wTimePrior * input.timePrior + wMotion * input.motionActive
    }

    // MARK: - 决策

    public enum Decision: Equatable {
        case silentStart(WorkoutType)
        case ask(WorkoutType)
        case ignore
    }

    public static func decide(input: WindowInput) -> Decision {
        let conf = confidence(input: input)
        let type = inferType(input: input)
        if conf >= 0.8 { return .silentStart(type) }
        if conf >= 0.5 { return .ask(type) }
        return .ignore
    }

    // MARK: - 类型推断

    public enum WorkoutType: String, Equatable, CaseIterable {
        case strength = "力量"
        case running = "跑步"
        case elliptical = "椭圆机"
        case traditionalStrength = "传统力量"
        case mixed = "综合"

        public var hkActivityType: String {
            switch self {
            case .strength, .traditionalStrength: return "HKWorkoutActivityTypeTraditionalStrengthTraining"
            case .running: return "HKWorkoutActivityTypeRunning"
            case .elliptical: return "HKWorkoutActivityTypeElliptical"
            case .mixed: return "HKWorkoutActivityTypeMixed"
            }
        }
    }

    /// 步频高+位移→跑步；步频低+HR高+能量高→力量；步频中+无位移→椭圆机
    public static func inferType(input: WindowInput) -> WorkoutType {
        // 简化版：用能量/HR 比值近似
        let avgHR = input.hrPerMin.isEmpty ? 0 : input.hrPerMin.reduce(0, +) / Double(input.hrPerMin.count)
        let avgEnergy = input.energyPerMin.isEmpty ? 0 : input.energyPerMin.reduce(0, +) / Double(input.energyPerMin.count)
        let hrRatio = avgHR / max(input.restingHR, 1)

        if hrRatio > 1.6 && avgEnergy > 8 {
            return .running // 高心率 + 高能量 → 跑步
        }
        if avgEnergy > 4 && hrRatio > 1.3 {
            return .strength // 中高心率 + 中高能量 → 力量
        }
        if avgEnergy > 3 {
            return .elliptical
        }
        return .mixed
    }

    // MARK: - 结束检测

    public struct EndWindowInput: Equatable {
        public var restingHR: Double
        public var hrPerMin: [Double]
        public var energyPerMin: [Double]

        public init(restingHR: Double, hrPerMin: [Double], energyPerMin: [Double]) {
            self.restingHR = restingHR
            self.hrPerMin = hrPerMin
            self.energyPerMin = energyPerMin
        }
    }

    /// HR≤静息+15 持续 5min 且 能量率<1.5kcal/min → true
    public static func shouldEnd(input: EndWindowInput) -> Bool {
        let hrThreshold = input.restingHR + endHRThresholdBPM
        var hrConsec = 0
        var hrMaxConsec = 0
        for hr in input.hrPerMin {
            if hr <= hrThreshold {
                hrConsec += 1
                hrMaxConsec = max(hrMaxConsec, hrConsec)
            } else { hrConsec = 0 }
        }
        var energyConsec = 0
        var energyMaxConsec = 0
        for e in input.energyPerMin {
            if e < endEnergyThreshold {
                energyConsec += 1
                energyMaxConsec = max(energyMaxConsec, energyConsec)
            } else { energyConsec = 0 }
        }
        return Double(hrMaxConsec) >= endSustainMin && Double(energyMaxConsec) >= endSustainMin
    }
}
