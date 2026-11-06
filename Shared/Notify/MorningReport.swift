import Foundation
import UserNotifications

/// 晨间报告本地通知（design.md §11）：每日最多 1 条，睡眠窗锁定后触发。
public enum MorningReport {

    // MARK: - 授权

    public static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - 通知触发

    /// 在睡眠窗锁定（或早晨 X 点兜底）时调用：发一条晨间报告
    public static func scheduleMorningReport(
        sleepWindow: String,
        sleepScore: Double?,
        recovery: Double?,
        readiness: Double?,
        strain: Double?,
        advice: String?
    ) async {
        let content = UNMutableNotificationContent()
        content.title = "晨间报告"
        content.body = morningMessage(
            sleepWindow: sleepWindow,
            sleepScore: sleepScore,
            recovery: recovery,
            readiness: readiness,
            strain: strain,
            advice: advice
        )
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: morningReportID(), content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - 文案

    static func morningMessage(
        sleepWindow: String,
        sleepScore: Double?,
        recovery: Double?,
        readiness: Double?,
        strain: Double?,
        advice: String?
    ) -> String {
        var parts: [String] = ["睡眠 \(sleepWindow)"]
        if let s = sleepScore { parts.append("睡眠分 \(Int(s))") }
        if let r = recovery { parts.append("恢复 \(Int(r))") }
        if let r = readiness { parts.append("准备度 \(String(format: "%.1f", r))") }
        if let s = strain { parts.append("昨日 Strain \(String(format: "%.1f", s))") }
        if let a = advice { parts.append(a) }
        return parts.joined(separator: " · ")
    }

    /// 标识：同一天覆盖去重
    static func morningReportID() -> String {
        let dayKey = SleepWindowBuilder.dayKey(for: Date())
        return "morning.report.\(dayKey)"
    }
}
