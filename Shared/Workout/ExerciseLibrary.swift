import Foundation
import SwiftData

/// 力量训练动作种子库（design.md §8：~60 个，胸/背/腿/肩/臂/核心 + 有氧）。
/// 首次启动时写入 SwiftData；用户可添加自定义（isDefault=false）。
public enum ExerciseLibrary {

    /// 种子动作列表（id, 中文名, 英文名, 肌群, 类型）
    public static let seeds: [(id: String, zh: String, en: String, muscle: String, type: String)] = [
        // 胸
        ("bench_press", "杠铃卧推", "Barbell Bench Press", "胸", "strength"),
        ("db_bench_press", "哑铃卧推", "Dumbbell Bench Press", "胸", "strength"),
        ("incline_bench", "上斜卧推", "Incline Bench Press", "胸", "strength"),
        ("db_fly", "哑铃飞鸟", "Dumbbell Fly", "胸", "strength"),
        ("cable_fly", "绳索夹胸", "Cable Fly", "胸", "strength"),
        ("dips", "双杠臂屈伸", "Dips", "胸", "strength"),
        ("pushup", "俯卧撑", "Push-up", "胸", "strength"),
        ("machine_press", "坐姿推胸", "Machine Chest Press", "胸", "strength"),
        // 背
        ("deadlift", "硬拉", "Deadlift", "背", "strength"),
        ("pullup", "引体向上", "Pull-up", "背", "strength"),
        ("lat_pulldown", "高位下拉", "Lat Pulldown", "背", "strength"),
        ("barbell_row", "杠铃划船", "Barbell Row", "背", "strength"),
        ("db_row", "哑铃划船", "Dumbbell Row", "背", "strength"),
        ("seated_row", "坐姿划船", "Seated Cable Row", "背", "strength"),
        ("tbar_row", "T杠划船", "T-Bar Row", "背", "strength"),
        ("face_pull", "面拉", "Face Pull", "背", "strength"),
        ("straight_arm_pulldown", "直臂下压", "Straight Arm Pulldown", "背", "strength"),
        ("rack_pull", "架拉", "Rack Pull", "背", "strength"),
        // 腿
        ("squat", "杠铃深蹲", "Barbell Squat", "腿", "strength"),
        ("front_squat", "前蹲", "Front Squat", "腿", "strength"),
        ("leg_press", "腿举", "Leg Press", "腿", "strength"),
        ("leg_extension", "腿屈伸", "Leg Extension", "腿", "strength"),
        ("leg_curl", "腿弯举", "Leg Curl", "腿", "strength"),
        ("romanian_deadlift", "罗马尼亚硬拉", "Romanian Deadlift", "腿", "strength"),
        ("lunges", "箭步蹲", "Lunges", "腿", "strength"),
        ("calf_raise", "提踵", "Calf Raise", "腿", "strength"),
        ("goblet_squat", "高脚杯深蹲", "Goblet Squat", "腿", "strength"),
        ("hip_thrust", "臀推", "Hip Thrust", "腿", "strength"),
        ("bulgarian_split", "保加利亚分腿蹲", "Bulgarian Split Squat", "腿", "strength"),
        // 肩
        ("ohp", "杠铃推举", "Overhead Press", "肩", "strength"),
        ("db_shoulder_press", "哑铃推举", "Dumbbell Shoulder Press", "肩", "strength"),
        ("lateral_raise", "侧平举", "Lateral Raise", "肩", "strength"),
        ("front_raise", "前平举", "Front Raise", "肩", "strength"),
        ("rear_delt_fly", "后束飞鸟", "Rear Delt Fly", "肩", "strength"),
        ("arnold_press", "阿诺德推举", "Arnold Press", "肩", "strength"),
        ("upright_row", "直立划船", "Upright Row", "肩", "strength"),
        // 臂
        ("barbell_curl", "杠铃弯举", "Barbell Curl", "臂", "strength"),
        ("db_curl", "哑铃弯举", "Dumbbell Curl", "臂", "strength"),
        ("hammer_curl", "锤式弯举", "Hammer Curl", "臂", "strength"),
        ("preacher_curl", "牧师椅弯举", "Preacher Curl", "臂", "strength"),
        ("tricep_pushdown", "三头下压", "Tricep Pushdown", "臂", "strength"),
        ("skull_crusher", "仰卧三头屈伸", "Skull Crusher", "臂", "strength"),
        ("overhead_tricep", "颈后三头屈伸", "Overhead Tricep Extension", "臂", "strength"),
        ("close_grip_bench", "窄距卧推", "Close Grip Bench Press", "臂", "strength"),
        ("concentration_curl", "集中弯举", "Concentration Curl", "臂", "strength"),
        // 核心
        ("plank", "平板支撑", "Plank", "核心", "strength"),
        ("hanging_leg_raise", "悬垂举腿", "Hanging Leg Raise", "核心", "strength"),
        ("cable_crunch", "绳索卷腹", "Cable Crunch", "核心", "strength"),
        ("russian_twist", "俄罗斯转体", "Russian Twist", "核心", "strength"),
        ("ab_wheel", "腹肌轮", "Ab Wheel", "核心", "strength"),
        ("side_plank", "侧平板", "Side Plank", "核心", "strength"),
        ("mountain_climber", "登山跑", "Mountain Climber", "核心", "strength"),
        // 有氧
        ("treadmill_run", "跑步机", "Treadmill Run", "有氧", "cardio"),
        ("elliptical", "椭圆机", "Elliptical", "有氧", "cardio"),
        ("row_machine", "划船机", "Rowing Machine", "有氧", "cardio"),
        ("bike", "动感单车", "Stationary Bike", "有氧", "cardio"),
        ("jump_rope", "跳绳", "Jump Rope", "有氧", "cardio"),
        ("stair_climber", "爬楼梯", "Stair Climber", "有氧", "cardio"),
        ("rowing", "赛艇", "Rowing", "有氧", "cardio"),
        ("burpee", "波比跳", "Burpee", "有氧", "cardio"),
        ("box_jump", "跳箱", "Box Jump", "有氧", "cardio"),
    ]

    /// 查动作（用于历史展示；SwiftData 之外轻量兜底）
    public static func exercise(id: String) -> (zh: String, muscle: String)? {
        if let e = seeds.first(where: { $0.id == id }) { return (e.zh, e.muscle) }
        return nil
    }

    /// 首次启动写入种子库
    public static func seedIfNeeded(in container: ModelContainer) {
        let ctx = ModelContext(container)
        let existing = (try? ctx.fetch(FetchDescriptor<Exercise>())) ?? []
        guard existing.isEmpty else { return }
        for s in seeds {
            ctx.insert(Exercise(id: s.id, nameZh: s.zh, nameEn: s.en,
                                muscleGroup: s.muscle, type: s.type, isDefault: true))
        }
        try? ctx.save()
    }

    /// 按肌群分组
    public static func groupedSeeds() -> [(muscle: String, exercises: [(id: String, zh: String, en: String)])] {
        let groups = ["胸", "背", "腿", "肩", "臂", "核心", "有氧"]
        return groups.map { g in
            (g, seeds.filter { $0.muscle == g }.map { ($0.id, $0.zh, $0.en) })
        }
    }
}
