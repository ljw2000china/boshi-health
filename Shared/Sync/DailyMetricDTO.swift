import Foundation

/// WCSession 跨设备同步用的纯数据对象（@Model 不支持直接 Codable）
struct DailyMetricDTO: Codable, Sendable {
    var dateKey: String
    var energy: Int?
    var soreness: Int?
}