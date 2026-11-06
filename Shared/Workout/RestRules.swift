import Foundation

/// 组间休息建议（力量训练文献实践共识）：
/// - 复合大重量（深蹲/硬拉/卧推/划船等）：研究建议 3–5 分钟以保证输出（Schoenfeld et al. 2016）
/// - 肌肥大取向的大肌群孤立/辅助动作：1.5–2 分钟
/// - 小肌群孤立（手臂/肩/核心）：60–90 秒
///
/// 本实现按「动作类型（复合/孤立）× 肌群」给出默认建议，用户可在休息页临时跳过。
public enum RestRules {

    /// 复合动作 id 集（用于区分复合/孤立）
    public static let compoundExerciseIDs: Set<String> = [
        "squat", "front_squat", "deadlift", "romanian_deadlift", "hip_thrust",
        "rack_pull", "bench_press", "incline_bench", "db_bench_press",
        "ohp", "db_shoulder_press", "arnold_press",
        "barbell_row", "tbar_row", "pullup", "lat_pulldown", "seated_row",
        "leg_press", "lunges", "bulgarian_split", "goblet_squat",
        "dips", "close_grip_bench", "machine_press"
    ]

    /// 建议休息秒数
    /// - parameter muscleGroup: 胸/背/腿/肩/臂/核心/有氧
    /// - parameter weightKg: 当前组重量（≥1RM 85% 等价强度额外 +30s）
    public static func recommended(exerciseID: String, muscleGroup: String,
                                   weightKg: Double = 0) -> Int {
        let compound = compoundExerciseIDs.contains(exerciseID)
        var sec: Int
        switch muscleGroup {
        case "腿":
            sec = compound ? 210 : 120
        case "背":
            sec = compound ? 210 : 120
        case "胸":
            sec = compound ? 180 : 120
        case "肩":
            sec = compound ? 180 : 90
        case "臂":
            sec = 90
        case "核心":
            sec = 60
        case "有氧":
            sec = 60
        default:
            sec = compound ? 180 : 120
        }
        // 重量大时适当延长（粗粒度：≥100kg +30s，≥150kg +60s）
        if weightKg >= 150 { sec += 60 }
        else if weightKg >= 100 { sec += 30 }
        return sec
    }
}
