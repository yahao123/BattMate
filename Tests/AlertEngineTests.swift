// Tests/AlertEngineTests.swift
import Foundation

func alertSample(_ source: PowerSource, percent: Int? = 100) -> FetchResult {
    .success(PowerSample(source: source, percent: percent, status: .charging,
                         minutesRemaining: nil, timestamp: Date()))
}

func testEngineFirstSuccessSilentBaseline() throws {
    let e = AlertEngine()
    try expectEqual(e.evaluate(alertSample(.ac), lowBatteryThreshold: 20), [])
    try expectEqual(e.consecutiveFailures, 0)
}

func testEngineChargerLostAlert() throws {
    let e = AlertEngine()
    _ = e.evaluate(alertSample(.ac), lowBatteryThreshold: 20)
    let out = e.evaluate(alertSample(.battery, percent: 88), lowBatteryThreshold: 20)
    try expectEqual(out.map(\.kind), [.chargerLost])
    try expectEqual(out[0].title, "🔴 充电器已断开")
    try expectTrue(out[0].body.contains("88%"))
}

func testEngineChargingResumedResetsLowFlag() throws {
    let e = AlertEngine()
    _ = e.evaluate(alertSample(.ac), lowBatteryThreshold: 20)
    // 断电 + 低电量：两条告警
    let out1 = e.evaluate(alertSample(.battery, percent: 15), lowBatteryThreshold: 20)
    try expectEqual(out1.map(\.kind), [.chargerLost, .lowBattery])
    // 继续掉电：不再告警
    try expectEqual(e.evaluate(alertSample(.battery, percent: 10), lowBatteryThreshold: 20), [])
    // 恢复充电：chargingResumed，且重置低电量标记
    try expectEqual(e.evaluate(alertSample(.ac), lowBatteryThreshold: 20).map(\.kind), [.chargingResumed])
    // 再次断电到低电量：两条告警重新出现
    let out2 = e.evaluate(alertSample(.battery, percent: 12), lowBatteryThreshold: 20)
    try expectEqual(out2.map(\.kind), [.chargerLost, .lowBattery])
}

func testEngineLowBatteryAboveThresholdSilent() throws {
    let e = AlertEngine()
    _ = e.evaluate(alertSample(.ac), lowBatteryThreshold: 20)
    let out = e.evaluate(alertSample(.battery, percent: 21), lowBatteryThreshold: 20)
    try expectEqual(out.map(\.kind), [.chargerLost]) // 只有没有低电量告警
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
    // 成功后：reachableAgain，计数清零
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
    registerTest("引擎：恢复充电重置低电量标记", testEngineChargingResumedResetsLowFlag)
    registerTest("引擎：电量高于阈值不告警", testEngineLowBatteryAboveThresholdSilent)
    registerTest("引擎：三次失败判失联且只报一次", testEngineUnreachableThirdFailureThenRecovery)
    registerTest("引擎：失败不足三次不告警", testEngineFailuresBelowThreeDoNotAlert)
}
