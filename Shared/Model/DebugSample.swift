import Foundation

/// 调试页用纯值模型：单个类型最近 24h 的汇总行。
public struct DebugTypeSummary: Identifiable, Hashable {
    /// 类型标识（HKQuantityTypeIdentifier / HKCategoryTypeIdentifier / workout）
    public let typeIdentifier: String
    /// 中文展示名
    public let displayName: String
    /// 最新样本的格式化值（无数据时为空串）
    public let latestValueText: String
    /// 最新样本结束时间（无数据时为 nil）
    public let latestDate: Date?
    /// 最近 24h 样本计数（截断上限见 HKService.debugCountLimit，超限展示「≥N」）
    public let last24hCount: Int
    /// 24h 计数是否被截断（实际样本数超过 last24hCount）
    public let last24hTruncated: Bool

    public var id: String { typeIdentifier }

    public init(typeIdentifier: String, displayName: String, latestValueText: String, latestDate: Date?, last24hCount: Int, last24hTruncated: Bool = false) {
        self.typeIdentifier = typeIdentifier
        self.displayName = displayName
        self.latestValueText = latestValueText
        self.latestDate = latestDate
        self.last24hCount = last24hCount
        self.last24hTruncated = last24hTruncated
    }
}

/// 调试页用纯值模型：一条样本明细（手机端点入查看）。
public struct DebugSample: Identifiable, Hashable {
    public let id: UUID
    /// 类型标识
    public let typeIdentifier: String
    /// 中文展示名
    public let displayName: String
    /// 格式化值
    public let valueText: String
    /// 样本起始时间
    public let startDate: Date
    /// 样本结束时间
    public let endDate: Date
    /// 样本来源 App/设备名（HKSource.name）
    public let sourceName: String

    public init(id: UUID, typeIdentifier: String, displayName: String, valueText: String, startDate: Date, endDate: Date, sourceName: String) {
        self.id = id
        self.typeIdentifier = typeIdentifier
        self.displayName = displayName
        self.valueText = valueText
        self.startDate = startDate
        self.endDate = endDate
        self.sourceName = sourceName
    }
}
