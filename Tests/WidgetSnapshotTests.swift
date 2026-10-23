// Tests/WidgetSnapshotTests.swift
import Foundation

private func sampleSnapshot(now: Date = Date(timeIntervalSince1970: 1_792_600_000),
                            historyCount: Int = 80,
                            historyLimit: Int = 60) -> WidgetSnapshot {
    let history = (0..<historyCount).map {
        WidgetSnapshot.HistoryPoint(timestamp: now.addingTimeInterval(Double($0) * 30),
                                    cpuPercent: $0 % 100,
                                    memoryPercent: ($0 * 2) % 100)
    }
    return WidgetSnapshot(reachable: true,
                          target: "ya@172.28.0.84",
                          source: "ac",
                          batteryPercent: 86,
                          chargeStatus: "charging",
                          minutesRemaining: 42,
                          cpuPercent: 23,
                          memoryPercent: 68,
                          lastError: nil,
                          updatedAt: now,
                          history: history,
                          historyLimit: historyLimit)
}

func testWidgetSnapshotRoundtrip() throws {
    let dir = tempTestDir("widget-roundtrip")
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("widget-state.json")

    let snapshot = sampleSnapshot(historyCount: 12)
    try expectTrue(WidgetSharedStore.save(snapshot, to: url), "应写入成功")
    try expectTrue(FileManager.default.fileExists(atPath: url.path))

    let loaded = try expectNotNil(WidgetSharedStore.load(from: url))
    try expectEqual(loaded, snapshot)
    try expectEqual(loaded.source, "ac")
    try expectEqual(loaded.chargeStatus, "charging")
    try expectEqual(loaded.history.count, 12)
}

func testWidgetSnapshotCapsHistory() throws {
    try expectEqual(sampleSnapshot(historyCount: 80).history.count, 60, "默认保留最近 60 条")
    try expectEqual(sampleSnapshot(historyCount: 80, historyLimit: 5).history.count, 5)
    try expectEqual(sampleSnapshot(historyCount: 3, historyLimit: 5).history.count, 3)
    try expectEqual(sampleSnapshot(historyCount: 3, historyLimit: 0).history.count, 0)

    let capped = sampleSnapshot(historyCount: 80)
    try expectEqual(capped.history.last?.cpuPercent, 79, "应保留最新采样")
    try expectEqual(capped.history.first?.cpuPercent, 20, "应剔除最旧采样")
}

func testWidgetSnapshotOfflineStateRoundtrip() throws {
    let dir = tempTestDir("widget-offline")
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("nested/dir/widget-state.json")

    let snapshot = WidgetSnapshot(reachable: false,
                                  target: "ya@172.28.0.84",
                                  lastError: "SSH 连接超时",
                                  updatedAt: Date(timeIntervalSince1970: 1_792_600_100))
    try expectTrue(WidgetSharedStore.save(snapshot, to: url), "应自动创建父目录")
    let loaded = try expectNotNil(WidgetSharedStore.load(from: url))
    try expectFalse(loaded.reachable)
    try expectEqual(loaded.lastError, "SSH 连接超时")
    try expectNil(loaded.batteryPercent)
}

func testWidgetSnapshotRejectsMissingOrCorruptFile() throws {
    let dir = tempTestDir("widget-corrupt")
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let missing = dir.appendingPathComponent("missing.json")
    try expectNil(WidgetSharedStore.load(from: missing))

    let corrupt = dir.appendingPathComponent("corrupt.json")
    try Data("not json".utf8).write(to: corrupt)
    try expectNil(WidgetSharedStore.load(from: corrupt))
}

func testWidgetSnapshotPreviewHasAllMetrics() throws {
    let preview = WidgetSnapshot.widgetPreview()
    try expectTrue(preview.reachable)
    try expectEqual(preview.history.count, 54)
    try expectTrue(preview.batteryPercent != nil)
    try expectTrue(preview.cpuPercent != nil)
    try expectTrue(preview.memoryPercent != nil)
}

func testWidgetSharedPathMatchesAppSupport() throws {
    let hostURL = try expectNotNil(WidgetSharedStore.defaultURL())
    try expectTrue(hostURL.path.hasSuffix("/Library/Application Support/BattMate/widget-state.json"),
                   "主 App 路径异常: \(hostURL.path)")

    let widgetURL = try expectNotNil(WidgetSharedStore.widgetURL())
    try expectTrue(widgetURL.path.hasSuffix("/Library/Application Support/BattMate/widget-state.json"),
                   "Widget 路径异常: \(widgetURL.path)")
}

func registerWidgetSnapshotTests() {
    registerTest("小组件：快照落盘与重载", testWidgetSnapshotRoundtrip)
    registerTest("小组件：历史裁剪到最近 60 条", testWidgetSnapshotCapsHistory)
    registerTest("小组件：离线状态与目录创建", testWidgetSnapshotOfflineStateRoundtrip)
    registerTest("小组件：缺失或损坏文件返回 nil", testWidgetSnapshotRejectsMissingOrCorruptFile)
    registerTest("小组件：预览数据包含三项指标", testWidgetSnapshotPreviewHasAllMetrics)
    registerTest("小组件：主 App 与 Widget 共享路径一致", testWidgetSharedPathMatchesAppSupport)
}
