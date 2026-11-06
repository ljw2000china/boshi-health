import Foundation
import SwiftData

/// SwiftData 容器工厂（双端共用）。
/// 表结构变更走轻量迁移；开发期如遇迁移失败可删除容器重建。
///
/// **重要**：所有 actor（DataPipeline / CheckinService / SetLogger）必须使用 `shared`
/// 单例容器，否则各自独立数据库、数据互不可见。
public enum PulseStore {

    public static let schema = Schema([
        RawSample.self,
        SleepWindow.self,
        DailyMetric.self,
        Baseline.self,
        Workout.self,
        SetLog.self,
        Exercise.self,
        Routine.self,
    ])

    /// 共享单例容器（全进程唯一，所有 service 通过此访问同一数据库）
    public static let shared: ModelContainer = {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // 迁移失败兜底：删库重建
            print("⚠️ ModelContainer 创建失败：\(error)。将清空本地存储重建。")
            try? FileManager.default.removeItem(at: Self.storeURL())
            return try! ModelContainer(for: schema, configurations: [config])
        }
    }()

    /// 测试 / preview 用内存容器
    public static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        guard inMemory else { return shared }
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    public static func storeURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("default.store")
    }
}
