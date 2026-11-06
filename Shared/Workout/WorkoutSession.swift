import Foundation

/// 训练会话状态机（design.md §7）。
/// idle → detected(置信度≥0.8) → active → ending(结束条件满足) → ended
public struct WorkoutSession: Equatable {

    public enum State: String, Equatable {
        case idle
        case detected
        case active
        case ending
        case ended
    }

    public var state: State = .idle
    public var startTime: Date?
    public var endTime: Date?
    public var type: WorkoutDetector.WorkoutType = .mixed
    public var confidence: Double = 0
    /// 是否为自动检测启动（true = 事后通知可改/取消；false = 用户手动）
    public var autoStarted: Bool = false

    public init() {}

    public mutating func start(at time: Date, type: WorkoutDetector.WorkoutType, auto: Bool) {
        state = .active
        startTime = time
        self.type = type
        autoStarted = auto
    }

    public mutating func beginEnding() {
        guard state == .active else { return }
        state = .ending
    }

    public mutating func end(at time: Date) {
        state = .ended
        endTime = time
    }

    public mutating func cancel() {
        state = .idle
        startTime = nil
        endTime = nil
        confidence = 0
    }

    /// 会话时长（秒）
    public var durationSec: Double {
        guard let s = startTime else { return 0 }
        let e = endTime ?? Date()
        return e.timeIntervalSince(s)
    }
}
