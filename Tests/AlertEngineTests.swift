// Tests/AlertEngineTests.swift
import Foundation

func alertSample(_ source: PowerSource, percent: Int? = 100) -> FetchResult {
    .success(PowerSample(source: source, percent: percent, status: .charging,
                         minutesRemaining: nil, timestamp: Date()))
}

// 源切换防抖：新源需连续 2 个样例才确认（首个样例只进候选，不告警）

func testEngineFirstSuccessSilentBaseline() throws {
    let e = AlertEngine()
    try expectEqual(e.evaluate(alertSample(.ac), lowBatteryThreshold: 20), [])
    try expectEqual(e.consecutiveFailures, 0)
}

func testEngineChargerLostAlert() throws {
    let e = AlertEngine()
    _ = e.evaluate(alertSample(.ac), lowBatteryThreshold: 20)
    // 第 1 个电池样例只进防抖候选，不告警
    try expectEqual(e.evaluate(alertSample(.battery, percent: 88), lowBatteryThreshold: 20), [])
    // 第 2 个连续电池样例才确认断电
    let out = e.evaluate(alertSample(.battery, percent: 88), lowBatteryThreshold: 20)
    try expectEqual(out.map(\.kind), [.chargerLost])
    try expectEqual(out[0].title, "🔴 充电器已断开")
    try expectTrue(out[0].body.contains("88%"))
}

func testEngineSingleFlapResetsDebounce() throws {
    let e = AlertEngine()
    _ = e.evaluate(alertSample(.ac), lowBatteryThreshold: 20)
    // 单个电池样例后翻回 AC：防抖被重置，翻回不告警
    _ = e.evaluate(alertSample(.battery, percent: 90), lowBatteryThreshold: 20)
    try expectEqual(e.evaluate(alertSample(.ac), lowBatteryThreshold: 20), [])
    // 稳定 AC 继续静默（lastSource 从未离开 AC）
    try expectEqual(e.evaluate(alertSample(.ac), lowBatteryThreshold: 20), [])
    try expectEqual(e.evaluate(alertSample(.ac), lowBatteryThreshold: 20), [])
    // 连续 2 个电池样例确认断电
    _ = e.evaluate(alertSample(.battery, percent: 80), lowBatteryThreshold: 20)
    try expectEqual(e.evaluate(alertSample(.battery, percent: 80), lowBatteryThreshold: 20).map(\.kind), [.chargerLost])
    // 单个 AC 样例（抖动）不触发 chargingResumed
    try expectEqual(e.evaluate(alertSample(.ac), lowBatteryThreshold: 20), [])
    // 翻回电池重置 AC 候选；再连续 2 个 AC 样例才报 chargingResumed
    try expectEqual(e.evaluate(alertSample(.battery, percent: 80), lowBatteryThreshold: 20), [])
    try expectEqual(e.evaluate(alertSample(.ac), lowBatteryThreshold: 20), [])
    let out = e.evaluate(alertSample(.ac), lowBatteryThreshold: 20)
    try expectEqual(out.map(\.kind), [.chargingResumed])
}

func testEngineChargingResumedResetsLowFlag() throws {
    let e = AlertEngine()
    _ = e.evaluate(alertSample(.ac), lowBatteryThreshold: 20)
    // 断电确认 + 低电量：同一次评估出两条告警
    _ = e.evaluate(alertSample(.battery, percent: 15), lowBatteryThreshold: 20) // 防抖第 1 发，静默
    let out1 = e.evaluate(alertSample(.battery, percent: 15), lowBatteryThreshold: 20) // 第 2 发确认
    try expectEqual(out1.map(\.kind), [.chargerLost, .lowBattery])
    // 继续掉电：不再告警
    try expectEqual(e.evaluate(alertSample(.battery, percent: 10), lowBatteryThreshold: 20), [])
    // 恢复充电需连续 2 个 AC 样例：第 1 发静默，第 2 发 chargingResumed 且重置低电量标记
    try expectEqual(e.evaluate(alertSample(.ac), lowBatteryThreshold: 20), [])
    try expectEqual(e.evaluate(alertSample(.ac), lowBatteryThreshold: 20).map(\.kind), [.chargingResumed])
    // 再次断电到低电量（连续 2 个电池样例确认）：两条告警重新成对出现
    _ = e.evaluate(alertSample(.battery, percent: 12), lowBatteryThreshold: 20)
    let out2 = e.evaluate(alertSample(.battery, percent: 12), lowBatteryThreshold: 20)
    try expectEqual(out2.map(\.kind), [.chargerLost, .lowBattery])
}

func testEngineLowBatteryAboveThresholdSilent() throws {
    let e = AlertEngine()
    _ = e.evaluate(alertSample(.ac), lowBatteryThreshold: 20)
    _ = e.evaluate(alertSample(.battery, percent: 21), lowBatteryThreshold: 20) // 防抖第 1 发，静默
    let out = e.evaluate(alertSample(.battery, percent: 21), lowBatteryThreshold: 20)
    try expectEqual(out.map(\.kind), [.chargerLost]) // 确认断电，但没有低电量告警
}

func testEngineUnreachableThirdFailureThenRecovery() throws {
    let e = AlertEngine()
    _ = e.evaluate(alertSample(.ac), lowBatteryThreshold: 20)
    try expectEqual(e.evaluate(.failure("timeout"), lowBatteryThreshold: 20), [])
    try expectEqual(e.evaluate(.failure("timeout"), lowBatteryThreshold: 20), [])
    let out = e.evaluate(.failure("timeout"), lowBatteryThreshold: 20)
    try expectEqual(out.map(\.kind), [.unreachable])
    // 第 4 次失败不重复报
    try expectEqual(e.evaluate(.failure("timeout"), lowBatteryThreshold: 20), [])
    // 成功后：reachableAgain，计数清零（恢复通知不参与防抖）
    let rec = e.evaluate(alertSample(.ac), lowBatteryThreshold: 20)
    try expectEqual(rec.map(\.kind), [.reachableAgain])
    try expectEqual(e.consecutiveFailures, 0)
    // 之后成功不再报
    try expectEqual(e.evaluate(alertSample(.ac), lowBatteryThreshold: 20), [])
}

func testEngineFailuresBelowThreeDoNotAlert() throws {
    let e = AlertEngine()
    _ = e.evaluate(alertSample(.ac), lowBatteryThreshold: 20)
    try expectEqual(e.evaluate(.failure("x"), lowBatteryThreshold: 20), [])
    try expectEqual(e.evaluate(.failure("x"), lowBatteryThreshold: 20), [])
    try expectEqual(e.evaluate(alertSample(.ac), lowBatteryThreshold: 20), []) // 未报过 unreachable，恢复不报
}

func registerAlertEngineTests() {
    registerTest("引擎：首次成功只建基线", testEngineFirstSuccessSilentBaseline)
    registerTest("引擎：断电告警", testEngineChargerLostAlert)
    registerTest("引擎：单次抖动重置防抖", testEngineSingleFlapResetsDebounce)
    registerTest("引擎：恢复充电重置低电量标记", testEngineChargingResumedResetsLowFlag)
    registerTest("引擎：电量高于阈值不告警", testEngineLowBatteryAboveThresholdSilent)
    registerTest("引擎：三次失败判失联且只报一次", testEngineUnreachableThirdFailureThenRecovery)
    registerTest("引擎：失败不足三次不告警", testEngineFailuresBelowThreeDoNotAlert)
}
