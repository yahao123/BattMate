// Tests/SettingsStoreTests.swift
import Foundation

func testStoreLoadReturnsDefaultWhenNoFile() throws {
    let dir = tempTestDir("store-empty")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = SettingsStore(directory: dir)
    try expectEqual(store.load(), AppConfig.default)
}

func testStoreSaveLoadRoundtrip() throws {
    let dir = tempTestDir("store-roundtrip")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = SettingsStore(directory: dir)
    var c = AppConfig.default
    c.sshTarget = "ya@192.168.1.50"
    c.intervalSeconds = 60
    store.save(c)
    try expectEqual(store.load(), c)
}

func testStoreCorruptFileFallsBackToDefault() throws {
    let dir = tempTestDir("store-corrupt")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = SettingsStore(directory: dir)
    try? Data("{ not json".utf8).write(to: store.fileURL)
    try expectEqual(store.load(), AppConfig.default)
    // 回落后文件被重写为合法配置
    let data = try Data(contentsOf: store.fileURL)
    try expectNotNil(try? JSONDecoder().decode(AppConfig.self, from: data), "损坏后应重写")
}

func testStoreDefaultValues() throws {
    let d = AppConfig.default
    try expectEqual(d.intervalSeconds, 30)
    try expectEqual(d.lowBatteryThreshold, 20)
    try expectTrue(d.soundEnabled)
    try expectFalse(d.autostartEnabled)
    try expectEqual(d.sshTarget, "")
    try expectTrue(d.tunnels.isEmpty)
}

func registerSettingsStoreTests() {
    registerTest("配置：无文件返回默认", testStoreLoadReturnsDefaultWhenNoFile)
    registerTest("配置：保存读取往返", testStoreSaveLoadRoundtrip)
    registerTest("配置：损坏回落默认", testStoreCorruptFileFallsBackToDefault)
    registerTest("配置：默认值", testStoreDefaultValues)
}
