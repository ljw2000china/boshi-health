import Foundation

/// 今日训练快照（表盘小组件与 App 共用的纯逻辑，不依赖 SwiftData/HealthKit）
public struct TrainingDaySnapshot: Sendable {
    public var title: String        // "练胸日" / "休息日"
    public var emoji: String
    public var muscles: [String]
    public var detail: String       // "胸 + 臂"
    public var subtitle: String     // 趣味副标题（按天随机）

    public var isRest: Bool { muscles.isEmpty }

    /// 休息日固定表情（跑马灯横幅用）
    public static let restDayEmoji = "😴"

    /// HealthKit 训练元数据键：记录本次训练涉及的肌群（"+", 分隔）
    public static let metadataKey = "PulseMuscleGroups"

    /// 肌群 → 可爱表情
    public static func emoji(for muscle: String) -> String {
        switch muscle {
        case "胸": return "💪"
        case "背": return "🦅"
        case "腿": return "🦵"
        case "肩": return "🤸"
        case "臂": return "🦾"
        case "核心": return "🌀"
        case "有氧": return "🏃"
        case "力量": return "🏋️"
        default: return "✨"
        }
    }

    /// 肌群 → SF Symbol（表盘圆角小组件的备用图标）
    public static func symbol(for muscle: String) -> String {
        switch muscle {
        case "胸": return "figure.strengthtraining.traditional"
        case "背": return "figure.strengthtraining.functional"
        case "腿": return "figure.step.training"
        case "肩": return "figure.flexibility"
        case "臂": return "dumbbell.fill"
        case "核心": return "figure.core.training"
        case "有氧": return "figure.run"
        default: return "figure.mixed.cardio"
        }
    }

    // MARK: - 趣味文案

    /// 休息日文案池（幽默增肌梗）
    public static let restLines: [String] = [
        "天赋好的人喝水都长肌肉",
        "今天先休息，不然无法维持薄肌",
        "肌肉在睡眠里生长，你懂我意思",
        "蛋白质在等我，沙发也在等我",
        "练太多等于没练，这是科学",
        "今天躺平，就是今天最高效的训练",
        "长肉靠睡觉，练只是个由头",
        "健身房今天想我，但我没去",
        "休息日是为了明天更狠",
        "低调一点，让肌肉自己偷偷长",
        "今天不练，等会加餐",
        "休息也是一种超负荷",
    ]

    /// 训练日按主肌群的梗文案
    public static func trainingLine(for muscle: String) -> String {
        switch muscle {
        case "胸": return "卧推架今天在发抖"
        case "背": return "引体向上不会让着任何人"
        case "腿": return "练完腿别去爬楼"
        case "肩": return "今天穿 T 恤会撑一点"
        case "臂": return "袖口在哭泣"
        case "核心": return "马甲线施工队今日开工"
        case "有氧": return "心肺才是隐藏 boss"
        case "力量": return "干就完了"
        default: return "练起来就完了"
        }
    }

    /// 依日期挑选文案（同一天稳定，跨天变化）
    public static func restLine(for seed: Int) -> String {
        restLines[abs(seed) % restLines.count]
    }

    /// 当天种子（年*400 + 年内天数）
    public static func todaySeed(calendar: Calendar = .current, now: Date = Date()) -> Int {
        let y = calendar.component(.year, from: now)
        let d = calendar.ordinality(of: .day, in: .year, for: now) ?? 1
        return y * 400 + d
    }

    /// 依据肌群列表生成快照（每个肌群 1 条即可，重复自动去重）
    public static func make(muscleGroups: [String], seed: Int = todaySeed()) -> TrainingDaySnapshot {
        var ordered: [String] = []
        for m in muscleGroups where !m.isEmpty && !ordered.contains(m) {
            ordered.append(m)
        }
        guard !ordered.isEmpty else {
            return TrainingDaySnapshot(title: "休息日", emoji: "😴",
                                       muscles: [], detail: "",
                                       subtitle: restLine(for: seed))
        }
        let primary = ordered.first ?? ""
        let focusTitle = "练" + (ordered.count >= 2
                                 ? ordered.prefix(2).joined(separator: "+")
                                 : primary) + "日"
        return TrainingDaySnapshot(title: focusTitle, emoji: emoji(for: primary),
                                   muscles: ordered,
                                   detail: ordered.joined(separator: " + "),
                                   subtitle: trainingLine(for: primary))
    }

    /// 未读到健康数据时的兜底
    public static let unknown = TrainingDaySnapshot(title: "Pulse", emoji: "⌚",
                                                    muscles: [], detail: "",
                                                    subtitle: "打开 App 同步")

    // MARK: - 本周训练点阵

    /// 近 7 天训练标记（下标 0 = 六天前 … 6 = 今天）
    public static func weekDots(dates: [Date], now: Date = Date(),
                                calendar: Calendar = .current) -> [Bool] {
        var dots = [Bool](repeating: false, count: 7)
        guard let dayStart = calendar.dateInterval(of: .day, for: now)?.start else {
            return dots
        }
        for d in dates {
            let daysAgo = Int((dayStart.timeIntervalSince(calendar.startOfDay(for: d))) / 86400)
            if daysAgo >= 0 && daysAgo < 7 { dots[6 - daysAgo] = true }
        }
        return dots
    }
}
