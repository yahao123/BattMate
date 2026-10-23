// Sources/BattMateCore/WidgetSnapshot.swift
import Darwin
import Foundation

/// 主 App 写入 App Group、Widget 扩展读取的最小状态快照。
public struct WidgetSnapshot: Codable, Equatable {
    public struct HistoryPoint: Codable, Equatable {
        public var timestamp: Date
        public var cpuPercent: Int
        public var memoryPercent: Int

        public init(timestamp: Date, cpuPercent: Int, memoryPercent: Int) {
            self.timestamp = timestamp
            self.cpuPercent = cpuPercent
            self.memoryPercent = memoryPercent
        }
    }

    public var reachable: Bool
    public var target: String
    public var source: String?
    public var batteryPercent: Int?
    public var chargeStatus: String?
    public var minutesRemaining: Int?
    public var cpuPercent: Int?
    public var memoryPercent: Int?
    public var lastError: String?
    public var updatedAt: Date
    public var history: [HistoryPoint]

    public init(reachable: Bool,
                target: String,
                source: String? = nil,
                batteryPercent: Int? = nil,
                chargeStatus: String? = nil,
                minutesRemaining: Int? = nil,
                cpuPercent: Int? = nil,
                memoryPercent: Int? = nil,
                lastError: String? = nil,
                updatedAt: Date = Date(),
                history: [HistoryPoint] = [],
                historyLimit: Int = 60) {
        self.reachable = reachable
        self.target = target
        self.source = source
        self.batteryPercent = batteryPercent
        self.chargeStatus = chargeStatus
        self.minutesRemaining = minutesRemaining
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.lastError = lastError
        self.updatedAt = updatedAt
        self.history = Array(history.suffix(max(0, historyLimit)))
    }
}

public enum WidgetSharedStore {
    public static let widgetKind = "BattMateWidget"
    public static let fileName = "widget-state.json"
    public static let appSupportSubdirectory = "BattMate"

    /// 主 App（未沙盒）写入 `~/Library/Application Support/BattMate/widget-state.json`。
    public static func defaultURL(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(appSupportSubdirectory, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// 沙盒内的 Widget 看到的家目录是容器路径，需要从账户记录取真实家目录。
    public static func widgetURL() -> URL? {
        guard let home = realHomeDirectory else { return nil }
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(appSupportSubdirectory, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    public static var realHomeDirectory: String? {
        guard let entry = getpwuid(getuid()) else { return nil }
        return String(cString: entry.pointee.pw_dir)
    }

    public static func load(from url: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    public static func loadFromSharedFile() -> WidgetSnapshot? {
        guard let url = widgetURL() else { return nil }
        return load(from: url)
    }

    @discardableResult
    public static func save(_ snapshot: WidgetSnapshot, to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

extension WidgetSnapshot {
    /// Widget 画廊与占位状态使用的示例数据。
    public static func widgetPreview(reachable: Bool = true, now: Date = Date()) -> WidgetSnapshot {
        let history = (0..<54).map { index -> WidgetSnapshot.HistoryPoint in
            let step = Double(index)
            let cpu = Int((27 + 17 * sin(step / 5.5) + Double(index % 6)).rounded())
            let memory = Int((66 + 6 * sin(step / 8.5) + Double(index % 4)).rounded())
            return WidgetSnapshot.HistoryPoint(timestamp: now.addingTimeInterval(-Double(53 - index) * 30),
                                               cpuPercent: min(100, max(0, cpu)),
                                               memoryPercent: min(100, max(0, memory)))
        }
        return WidgetSnapshot(reachable: reachable,
                              target: "172.28.0.84",
                              source: "ac",
                              batteryPercent: 86,
                              chargeStatus: "charging",
                              minutesRemaining: 42,
                              cpuPercent: 23,
                              memoryPercent: 68,
                              updatedAt: now.addingTimeInterval(-38),
                              history: history)
    }
}
