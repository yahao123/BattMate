// Sources/BattMateCore/StatusReport.swift
import Foundation

/// status.json 落盘结构：为将来通知中心小组件（WidgetKit）预留的数据接口
public struct StatusReport: Codable, Equatable {
    public var reachable: Bool
    public var source: PowerSource?
    public var percent: Int?
    public var status: ChargeStatus?
    public var minutesRemaining: Int?
    public var checkedAt: Date
    public var lastError: String?
    public var usage: SystemUsage?

    public init(reachable: Bool, source: PowerSource?, percent: Int?,
                status: ChargeStatus?, minutesRemaining: Int?,
                checkedAt: Date, lastError: String?, usage: SystemUsage? = nil) {
        self.reachable = reachable
        self.source = source
        self.percent = percent
        self.status = status
        self.minutesRemaining = minutesRemaining
        self.checkedAt = checkedAt
        self.lastError = lastError
        self.usage = usage
    }

    public static func write(_ report: StatusReport, to url: URL) {
        // 父目录不存在时原子写入会静默失败，先建目录（与 SettingsStore 一致）
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
