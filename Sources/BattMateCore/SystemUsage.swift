// Sources/BattMateCore/SystemUsage.swift
import Foundation

/// 服务器侧 CPU / 内存占用快照
public struct SystemUsage: Codable, Equatable {
    public var cpuPercent: Int
    public var memoryPercent: Int
    public var memoryUsedBytes: UInt64
    public var memoryTotalBytes: UInt64
    public var sampledAt: Date

    public init(cpuPercent: Int,
                memoryPercent: Int,
                memoryUsedBytes: UInt64,
                memoryTotalBytes: UInt64,
                sampledAt: Date = Date()) {
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.sampledAt = sampledAt
    }

    public var memoryUsedText: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryUsedBytes), countStyle: .memory)
    }

    public var memoryTotalText: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryTotalBytes), countStyle: .memory)
    }
}

public enum SystemUsageParserError: Error, Equatable {
    case missingMetrics
}

public enum SystemUsageParser {
    /// 解析 `top -l 2 -n 0 -s 1` 的 CPU usage 与 PhysMem 行；取最后一次采样（第二次更准确）。
    public static func parse(_ output: String, date: Date = Date()) throws -> SystemUsage {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard let cpuLine = lines.last(where: { $0.hasPrefix("CPU usage:") }),
              let memLine = lines.last(where: { $0.hasPrefix("PhysMem:") }),
              let cpu = cpuUsage(from: cpuLine),
              let memory = memoryUsage(from: memLine) else {
            throw SystemUsageParserError.missingMetrics
        }
        return SystemUsage(cpuPercent: cpu,
                           memoryPercent: memory.percent,
                           memoryUsedBytes: memory.used,
                           memoryTotalBytes: memory.used + memory.free,
                           sampledAt: date)
    }

    static func cpuUsage(from line: String) -> Int? {
        guard let idle = firstMatch(#"([\d.]+)%\s+idle"#, in: line),
              let percent = Double(idle) else { return nil }
        return min(100, max(0, Int((100 - percent).rounded())))
    }

    static func memoryUsage(from line: String) -> (used: UInt64, free: UInt64, percent: Int)? {
        guard let groups = groups(#"PhysMem:\s*([\d.]+)([KMGTB]?)\s+used.*?([\d.]+)([KMGTB]?)\s+unused"#,
                                  in: line),
              groups.count == 4,
              let used = bytes(value: groups[0], unit: groups[1]),
              let free = bytes(value: groups[2], unit: groups[3]),
              used + free > 0 else { return nil }
        let percent = min(100, max(0, Int((Double(used) / Double(used + free) * 100).rounded())))
        return (used, free, percent)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        groups(pattern, in: text)?.first
    }

    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }

    private static func bytes(value: String, unit: String) -> UInt64? {
        guard let number = Double(value) else { return nil }
        let multiplier: Double
        switch unit.uppercased() {
        case "K": multiplier = 1024
        case "M": multiplier = 1024 * 1024
        case "G": multiplier = 1024 * 1024 * 1024
        case "T": multiplier = 1024 * 1024 * 1024 * 1024
        default: multiplier = 1
        }
        return UInt64((number * multiplier).rounded())
    }
}
