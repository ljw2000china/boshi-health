import Foundation

/// WCSession 同步：组次记录（手表→手机 实时同步，手机编辑→手表）
struct SetLogDTO: Codable, Sendable {
    var workoutID: String
    var exerciseID: String
    var order: Int
    var reps: Int
    var weightKg: Double
    var loggedAt: Date
    var deleted: Bool
}

/// WCSession 同步：训练会话（开始/结束/删除）
struct WorkoutSessionDTO: Codable, Sendable {
    var id: String
    var dayKey: String
    var start: Date
    var end: Date
    var isActive: Bool
    var type: String
    var source: String
    var deleted: Bool
}

/// 同步消息信封（区分数据类型，避免通道混用）
struct SyncEnvelope: Codable, Sendable {
    enum Kind: String, Codable {
        case dailyMetric
        case setLog
        case session
    }
    var kind: Kind
    var payload: Data
}
