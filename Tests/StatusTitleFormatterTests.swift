// Tests/StatusTitleFormatterTests.swift
import Foundation
import AppKit

func fmtSample(_ source: PowerSource, percent: Int?) -> PowerSample {
    PowerSample(source: source, percent: percent, status: .charging,
                minutesRemaining: nil, timestamp: Date())
}

func testTitleACShowsBoltAndGreen() throws {
    let t = StatusTitleFormatter.title(sample: fmtSample(.ac, percent: 98), failureStreak: 0)
    try expectEqual(t.text, "⚡98")
    try expectEqual(t.color, NSColor.systemGreen)
}

func testTitleBatteryShowsEmojiAndOrange() throws {
    let t = StatusTitleFormatter.title(sample: fmtSample(.battery, percent: 45), failureStreak: 0)
    try expectEqual(t.text, "🔋45")
    try expectEqual(t.color, NSColor.systemOrange)
}

func testTitleUnknownSourceShowsDash() throws {
    let t = StatusTitleFormatter.title(sample: fmtSample(.unknown, percent: nil), failureStreak: 0)
    try expectEqual(t.text, "·--")
    try expectEqual(t.color, NSColor.systemGray)
}

func testTitleNoSampleNoFailureShowsEllipsis() throws {
    let t = StatusTitleFormatter.title(sample: nil, failureStreak: 0)
    try expectEqual(t.text, "…")
    try expectEqual(t.color, NSColor.systemGray)
}

func testTitleFailureStreakShowsWarning() throws {
    let t = StatusTitleFormatter.title(sample: nil, failureStreak: 3)
    try expectEqual(t.text, "⚠︎--")
    try expectEqual(t.color, NSColor.systemGray)
}

func testTitleFailureStreakOverridesStaleSample() throws {
    // 失联时残留的上次成功样例不应再展示健康图标
    let t = StatusTitleFormatter.title(sample: fmtSample(.ac, percent: 98), failureStreak: 2)
    try expectEqual(t.text, "⚠︎--")
    try expectEqual(t.color, NSColor.systemGray)
}

func registerStatusTitleFormatterTests() {
    registerTest("图标：AC 绿色闪电", testTitleACShowsBoltAndGreen)
    registerTest("图标：电池橙色", testTitleBatteryShowsEmojiAndOrange)
    registerTest("图标：未知来源", testTitleUnknownSourceShowsDash)
    registerTest("图标：无样例省略号", testTitleNoSampleNoFailureShowsEllipsis)
    registerTest("图标：失败警告", testTitleFailureStreakShowsWarning)
    registerTest("图标：失联时旧样例置灰", testTitleFailureStreakOverridesStaleSample)
}
