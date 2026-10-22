// Tests/MetricsHistoryTests.swift
import Foundation

private func makeHistoryStore(_ label: String) -> (MetricsHistoryStore, URL, URL) {
    let dir = tempTestDir(label)
    let url = dir.appendingPathComponent("metrics-history.txt")
    return (MetricsHistoryStore(fileURL: url), dir, url)
}

func testHistoryRoundtrip() throws {
    let (store, dir, url) = makeHistoryStore("history-roundtrip")
    defer { try? FileManager.default.removeItem(at: dir) }

    let base = Date(timeIntervalSince1970: 1_792_600_000)
    for i in 0..<10 {
        store.append(MetricsPoint(timestamp: base.addingTimeInterval(Double(i * 30)),
                                  cpuPercent: i * 3,
                                  memoryPercent: 50 + i))
    }
    try expectEqual(store.points.count, 10)

    let reloaded = MetricsHistoryStore(fileURL: url)
    try expectEqual(reloaded.points, store.points)
}

func testHistoryCapsFileAtDefaultLimit() throws {
    let (_, dir, url) = makeHistoryStore("history-cap")
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let baseEpoch = 1_792_600_000
    var lines = ["v1,\(baseEpoch)"]
    for i in 0..<7000 {
        lines.append("\(i * 30),\((i * 7) % 100),\((i * 3) % 100)")
    }
    try (lines.joined(separator: "\n") + "\n")
        .write(to: url, atomically: true, encoding: .utf8)

    let store = MetricsHistoryStore(fileURL: url)

    try expectEqual(MetricsHistoryStore.defaultMaxBytes, 64 * 1024)
    let bytes = try Data(contentsOf: url).count
    try expectTrue(bytes <= MetricsHistoryStore.defaultMaxBytes, "文件应不超过 64KB，实际 \(bytes)")
    try expectTrue(store.points.count > 5000, "64KB 应能容纳至少 5000 条，实际 \(store.points.count)")
    try expectTrue(store.points.count < 7000, "超限后应剔除最旧采样")
    try expectEqual(store.points.last?.cpuPercent, (6999 * 7) % 100)
    try expectTrue(store.points.first!.timestamp > Date(timeIntervalSince1970: TimeInterval(baseEpoch)),
                   "最旧采样应已被剔除")

    let reloaded = MetricsHistoryStore(fileURL: url)
    try expectEqual(reloaded.points, store.points)
}

func testHistoryReplacesSampleWithinSameSecond() throws {
    let (store, dir, _) = makeHistoryStore("history-dedupe")
    defer { try? FileManager.default.removeItem(at: dir) }

    let now = Date(timeIntervalSince1970: 1_792_600_000.2)
    store.append(MetricsPoint(timestamp: now, cpuPercent: 10, memoryPercent: 50))
    store.append(MetricsPoint(timestamp: now.addingTimeInterval(0.3), cpuPercent: 12, memoryPercent: 51))
    try expectEqual(store.points.count, 1)
    try expectEqual(store.points[0].cpuPercent, 12)
}

func testHistoryClearRemovesFile() throws {
    let (store, dir, url) = makeHistoryStore("history-clear")
    defer { try? FileManager.default.removeItem(at: dir) }

    store.append(MetricsPoint(timestamp: Date(), cpuPercent: 1, memoryPercent: 2))
    try expectTrue(FileManager.default.fileExists(atPath: url.path))
    store.clear()
    try expectTrue(store.points.isEmpty)
    try expectFalse(FileManager.default.fileExists(atPath: url.path))
}

func registerMetricsHistoryTests() {
    registerTest("历史：落盘与重载", testHistoryRoundtrip)
    registerTest("历史：64KB 上限并剔除最旧", testHistoryCapsFileAtDefaultLimit)
    registerTest("历史：同秒采样覆盖", testHistoryReplacesSampleWithinSameSecond)
    registerTest("历史：清空删除文件", testHistoryClearRemovesFile)
}
