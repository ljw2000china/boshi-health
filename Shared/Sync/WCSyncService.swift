import Foundation
import WatchConnectivity

/// 手表↔手机 双向同步（design.md §2：无 App Groups/iCloud，纯 WCSession）。
///
/// 两端的 HealthKit 独立读取（手表数据由系统镜像到手机 HK），
/// WCSession 仅同步 SwiftData 独有的数据：每日打卡 + 当日指标快照。
@MainActor
public final class WCSyncService: NSObject, ObservableObject {

    public static let shared = WCSyncService()

    @Published public private(set) var reachable = false
    @Published public private(set) var lastReceived: Date?

    private var pendingDailyMetric: Data?
    private var pendingSetPayloads: [(SyncEnvelope.Kind, Data)] = []

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - 发送

    /// 发送当日指标快照（手表→手机 或 手机→手表）
    public func sendDailyMetric(_ data: Data) {
        guard let envelope = try? JSONEncoder().encode(
            SyncEnvelope(kind: .dailyMetric, payload: data)) else { return }
        sendRaw(envelope, userInfoKey: "dailyMetric")
    }

    /// 发送组次/会话数据（实时同步训练记录）
    func sendSetLogPayload(_ data: Data, kind: SyncEnvelope.Kind) {
        guard let envelope = try? JSONEncoder().encode(SyncEnvelope(kind: kind, payload: data))
        else { return }
        guard WCSession.default.activationState == .activated else {
            pendingSetPayloads.append((kind, data))
            return
        }
        sendRaw(envelope, userInfoKey: kind == .setLog ? "setLog" : "session")
    }

    private func sendRaw(_ envelope: Data, userInfoKey: String) {
        guard WCSession.default.activationState == .activated else {
            pendingDailyMetric = envelope
            return
        }
        if WCSession.default.isReachable {
            WCSession.default.sendMessageData(envelope, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo([userInfoKey: envelope])
            }
        } else {
            WCSession.default.transferUserInfo([userInfoKey: envelope])
        }
    }

    public func flushPending() {
        if let d = pendingDailyMetric {
            sendRaw(d, userInfoKey: "dailyMetric")
            pendingDailyMetric = nil
        }
        for (kind, data) in pendingSetPayloads { sendSetLogPayload(data, kind: kind) }
        pendingSetPayloads = []
    }

    // MARK: - 接收回调

    public var onDailyMetricReceived: ((Data) -> Void)?
    public var onSetLogReceived: ((Data) -> Void)?
    public var onSessionReceived: ((Data) -> Void)?

    private func dispatchReceived(_ data: Data) {
        lastReceived = Date()
        if let envelope = try? JSONDecoder().decode(SyncEnvelope.self, from: data) {
            switch envelope.kind {
            case .dailyMetric: onDailyMetricReceived?(envelope.payload)
            case .setLog: onSetLogReceived?(envelope.payload)
            case .session: onSessionReceived?(envelope.payload)
            }
        } else {
            // 兼容旧版本：无信封 → 视为 dailyMetric
            onDailyMetricReceived?(data)
        }
    }
}

extension WCSyncService: WCSessionDelegate {
    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_: WCSession) {}
    nonisolated public func sessionDidDeactivate(_: WCSession) {
        Task { @MainActor in WCSession.default.activate() }
    }
    #endif

    nonisolated public func session(_: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            reachable = WCSession.default.isReachable
            if state == .activated { flushPending() }
        }
    }

    nonisolated public func sessionReachabilityDidChange(_: WCSession) {
        Task { @MainActor in
            reachable = WCSession.default.isReachable
        }
    }

    nonisolated public func session(_: WCSession, didReceiveMessageData data: Data) {
        Task { @MainActor in dispatchReceived(data) }
    }

    nonisolated public func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let data = (userInfo["dailyMetric"] as? Data) ?? (userInfo["setLog"] as? Data)
            ?? (userInfo["session"] as? Data)
        guard let data else { return }
        Task { @MainActor in dispatchReceived(data) }
    }
}