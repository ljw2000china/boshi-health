import WidgetKit
import SwiftUI
import HealthKit

// MARK: - 数据

struct TrainingEntry: TimelineEntry {
    let date: Date
    let snapshot: TrainingDaySnapshot
    let weekDots: [Bool]   // 近 7 天训练标记（6=今天）
}

/// 表盘小组件数据源：读取近 7 天 HealthKit 训练，推断练X日 / 休息日 + 本周点阵。
/// 力量训练的肌群来自手表回写时写入的元数据（TrainingDaySnapshot.metadataKey）。
struct TrainingProvider: TimelineProvider {

    func placeholder(in context: Context) -> TrainingEntry {
        TrainingEntry(date: Date(),
                      snapshot: .make(muscleGroups: ["胸", "臂"]),
                      weekDots: [true, false, true, true, false, false, true])
    }

    func getSnapshot(in context: Context, completion: @escaping (TrainingEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        load { snapshot, dots in
            completion(TrainingEntry(date: Date(), snapshot: snapshot, weekDots: dots))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrainingEntry>) -> Void) {
        load { snapshot, dots in
            let now = Date()
            let next = now.addingTimeInterval(15 * 60)
            let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(24 * 60 * 60))
            let refresh = min(next, midnight)
            completion(Timeline(entries: [TrainingEntry(date: now, snapshot: snapshot,
                                                        weekDots: dots)],
                                policy: .after(refresh)))
        }
    }

    // MARK: - 查询

    private func load(_ completion: @escaping (TrainingDaySnapshot, [Bool]) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.unknown, [Bool](repeating: false, count: 7))
            return
        }
        let store = HKHealthStore()
        let now = Date()
        let cal = Calendar.current
        let weekStart = cal.startOfDay(for: now.addingTimeInterval(-6 * 24 * 60 * 60))
        let predicate = HKQuery.predicateForSamples(withStart: weekStart, end: nil,
                                                    options: .strictStartDate)
        let query = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                                  predicate: predicate, limit: 50,
                                  sortDescriptors: nil) { _, samples, _ in
            let workouts = (samples as? [HKWorkout]) ?? []
            // 今日肌群（力量训练带元数据）
            let todayStart = cal.startOfDay(for: now)
            var muscles: [String] = []
            var todayCount = 0
            var dates: [Date] = []
            for w in workouts {
                dates.append(w.startDate)
                if w.startDate >= todayStart { todayCount += 1 }
                if let raw = w.metadata?[TrainingDaySnapshot.metadataKey] as? String {
                    muscles.append(contentsOf: raw.split(separator: "+").map(String.init))
                }
            }
            if todayCount > 0 && muscles.isEmpty { muscles = ["力量"] }
            completion(.make(muscleGroups: muscles),
                       TrainingDaySnapshot.weekDots(dates: dates, now: now, calendar: cal))
        }
        store.execute(query)
    }
}

// MARK: - 视图

struct TrainingDayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TrainingEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 2) {
                    Text(entry.snapshot.emoji)
                        .font(.system(size: 22))
                    if entry.snapshot.isRest {
                        Text("休")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                }
            }
        case .accessoryInline:
            Text("\(entry.snapshot.emoji) \(entry.snapshot.title)")
                .fontDesign(.rounded)
        default:
            rectangular
        }
    }

    /// 横向满宽槽位（占表盘一整条）：表情渐变徽章 + 大标题 + 趣味副标题 + 本周训练点阵
    private var rectangular: some View {
        HStack(spacing: 9) {
            // 表情徽章
            ZStack {
                Circle()
                    .fill(AngularGradient(
                        colors: entry.snapshot.isRest
                            ? [.gray.opacity(0.45), .indigo.opacity(0.4), .gray.opacity(0.45)]
                            : [.orange.opacity(0.65), .pink.opacity(0.55), .orange.opacity(0.65)],
                        center: .center))
                    .frame(width: 42, height: 42)
                Text(entry.snapshot.emoji)
                    .font(.system(size: 21))
            }
            .widgetAccentable()

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.snapshot.title)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(entry.snapshot.subtitle)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }

            Spacer(minLength: 2)

            // 本周训练点阵
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { i in
                        Circle()
                            .fill(dotColor(index: i, lit: entry.weekDots[i]))
                            .frame(width: i == 6 ? 7 : 5.5, height: i == 6 ? 7 : 5.5)
                    }
                }
                Text("本周")
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func dotColor(index: Int, lit: Bool) -> Color {
        guard lit else { return Color.secondary.opacity(0.25) }
        return index == 6 ? .orange : .pink.opacity(0.8)
    }
}

// MARK: - Widget / Bundle

struct TrainingDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PulseTrainingDay", provider: TrainingProvider()) { entry in
            TrainingDayWidgetView(entry: entry)
        }
        .configurationDisplayName("今日训练")
        .description("表盘显示今天练什么：练胸日 💪 / 休息日 😴 + 本周训练点阵")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct PulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrainingDayWidget()
    }
}
