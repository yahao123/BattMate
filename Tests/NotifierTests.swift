// Tests/NotifierTests.swift
import Foundation

func testAppleScriptStringEscapes() throws {
    try expectEqual(NotifierScript.appleScriptString("hi"), "\"hi\"")
    try expectEqual(NotifierScript.appleScriptString("a\"b"), "\"a\\\"b\"")
    try expectEqual(NotifierScript.appleScriptString("a\\b"), "\"a\\\\b\"")
}

func testAppleScriptStringFlattensNewlines() throws {
    // 裸换行会让 osascript -e 报语法错误（告警被 try? 吞掉），必须压成空格
    try expectEqual(NotifierScript.appleScriptString("a\nb"), "\"a b\"")
    try expectEqual(NotifierScript.appleScriptString("a\r\nb\rc"), "\"a b c\"")
}

func testCommandContainsTitleAndBody() throws {
    let cmd = NotifierScript.command(title: "🔴 充电器已断开", body: "电量 88%")
    try expectTrue(cmd.hasPrefix("display notification"))
    try expectTrue(cmd.contains("电量 88%"))
    try expectTrue(cmd.contains("with title"))
    try expectTrue(cmd.contains("充电器已断开"))
}

func registerNotifierTests() {
    registerTest("通知：AppleScript 字符串转义", testAppleScriptStringEscapes)
    registerTest("通知：换行压成空格", testAppleScriptStringFlattensNewlines)
    registerTest("通知：命令包含标题与正文", testCommandContainsTitleAndBody)
}
