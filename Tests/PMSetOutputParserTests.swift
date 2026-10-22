// Tests/PMSetOutputParserTests.swift
import Foundation

enum PMSetFixtures {
    static let acCharging = """
    Now drawing from 'AC Power'
     -InternalBattery-0 (id=5400300)\t98%; charging; 0:41 remaining until full; (no estimate) 5:07 present
    """

    static let batteryDischarging = """
    Now drawing from 'Battery Power'
     -InternalBattery-0 (id=5400300)\t45%; discharging; 2:47 remaining on battery; (no estimate) 5:07 present
    """

    static let acCharged = """
    Now drawing from 'AC Power'
     -InternalBattery-0 (id=5400300)\t100%; charged; 0:00 remaining
    """

    static let noEstimate = """
    Now drawing from 'Battery Power'
     -InternalBattery-0 (id=5400300)\t45%; discharging; (no estimate) 5:07 present
    """

    static let desktopNoBattery = "Now drawing from 'AC Power'"
}

func testParseACCharging() throws {
    let s = try PMSetOutputParser.parse(PMSetFixtures.acCharging)
    try expectEqual(s.source, .ac)
    try expectEqual(s.percent, 98)
    try expectEqual(s.status, .charging)
    try expectEqual(s.minutesRemaining, 41)
}

func testParseBatteryDischarging() throws {
    let s = try PMSetOutputParser.parse(PMSetFixtures.batteryDischarging)
    try expectEqual(s.source, .battery)
    try expectEqual(s.percent, 45)
    try expectEqual(s.status, .discharging)
    try expectEqual(s.minutesRemaining, 167)
}

func testParseCharged() throws {
    let s = try PMSetOutputParser.parse(PMSetFixtures.acCharged)
    try expectEqual(s.source, .ac)
    try expectEqual(s.percent, 100)
    try expectEqual(s.status, .charged)
    try expectEqual(s.minutesRemaining, 0)
}

func testParseNoEstimate() throws {
    let s = try PMSetOutputParser.parse(PMSetFixtures.noEstimate)
    try expectEqual(s.source, .battery)
    try expectEqual(s.status, .discharging)
    try expectNil(s.minutesRemaining)
}

func testParseDesktopNoBattery() throws {
    let s = try PMSetOutputParser.parse(PMSetFixtures.desktopNoBattery)
    try expectEqual(s.source, .ac)
    try expectNil(s.percent)
    try expectEqual(s.status, .unknown)
}

func testParseGarbageThrows() throws {
    try expectThrows("垃圾输入", PMSetOutputParser.parse("ssh: connect refused"))
}

func testParseIdDigitsNotPercent() throws {
    // (id=5400300) 里的数字不能被当成百分比
    let s = try PMSetOutputParser.parse(PMSetFixtures.acCharging)
    try expectEqual(s.percent, 98)
}

func testParseRemainingText() throws {
    let s = try PMSetOutputParser.parse(PMSetFixtures.batteryDischarging)
    try expectEqual(s.remainingText, "2:47")
    let n = try PMSetOutputParser.parse(PMSetFixtures.noEstimate)
    try expectEqual(n.remainingText, "无估计")
}

func registerPMSetOutputParserTests() {
    registerTest("解析：AC 充电中", testParseACCharging)
    registerTest("解析：电池放电", testParseBatteryDischarging)
    registerTest("解析：已充满", testParseCharged)
    registerTest("解析：无时间估计", testParseNoEstimate)
    registerTest("解析：桌面机无电池", testParseDesktopNoBattery)
    registerTest("解析：垃圾输入抛错", testParseGarbageThrows)
    registerTest("解析：id 数字不算百分比", testParseIdDigitsNotPercent)
    registerTest("解析：剩余时间文本", testParseRemainingText)
}
