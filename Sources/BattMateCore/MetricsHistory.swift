// Sources/BattMateCore/MetricsHistory.swift
import Foundation

public struct MetricsPoint: Equatable {
    public let timestamp: Date
    public let cpuPercent: Int
    public let memoryPercent: Int

    public init(timestamp: Date, cpuPercent: Int, memoryPercent: Int) {
        self.timestamp = timestamp
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
    }
}

/// 紧凑文本历史：首行存基准时间，后续行只存秒偏移与两个百分比。
/// 严格限制文件不超过 maxBytes（默认 64 KB），超限时从最旧的采样开始剔除。
public final class MetricsHistoryStore {
    public static let defaultMaxBytes = 64 * 1024

    public let fileURL: URL
    public let maxBytes: Int
    public private(set) var points: [MetricsPoint] = []

    private let fileManager = FileManager.default

    public init(fileURL: URL, maxBytes: Int = MetricsHistoryStore.defaultMaxBytes) {
        self.fileURL = fileURL
        self.maxBytes = max(64, maxBytes)
        load()
    }

    @discardableResult
    public func append(_ point: MetricsPoint) -> [MetricsPoint] {
        if let last = points.last,
           abs(point.timestamp.timeIntervalSince(last.timestamp)) < 1 {
            points[points.count - 1] = point
        } else {
            points.append(point)
        }
        points.sort { $0.timestamp < $1.timestamp }
        trimAndPersist()
        return points
    }

    public func clear() {
        points = []
        try? fileManager.removeItem(at: fileURL)
    }

    private func load() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let header = lines.first, header.hasPrefix("v1,"),
              let epoch = TimeInterval(header.dropFirst(3)) else { return }
        let base = Date(timeIntervalSince1970: epoch)
        points = lines.dropFirst().compactMap { line in
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count == 3,
                  let offset = TimeInterval(fields[0]),
                  let cpu = Int(fields[1]),
                  let memory = Int(fields[2]) else { return nil }
            return MetricsPoint(timestamp: base.addingTimeInterval(offset),
                                cpuPercent: min(100, max(0, cpu)),
                                memoryPercent: min(100, max(0, memory)))
        }
        points.sort { $0.timestamp < $1.timestamp }
        if !points.isEmpty { trimAndPersist() }
    }

    private func trimAndPersist() {
        guard !points.isEmpty else { return }
        var encoded = encode()
        while encoded.utf8.count > maxBytes, points.count > 1 {
            points.removeFirst()
            encoded = encode()
        }
        // 极端情况下单条也超限时只保留一行，仍保证文件不超过上限
        if encoded.utf8.count > maxBytes {
            points = Array(points.suffix(1))
            encoded = encode()
        }
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
        try? encoded.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func encode() -> String {
        guard let base = points.first?.timestamp else { return "" }
        let baseEpoch = Int(base.timeIntervalSince1970)
        var lines = ["v1,\(baseEpoch)"]
        for point in points {
            let offset = max(0, Int(point.timestamp.timeIntervalSince1970) - baseEpoch)
            lines.append("\(offset),\(min(100, max(0, point.cpuPercent))),\(min(100, max(0, point.memoryPercent)))")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
