// Tests/NotifierTests.swift
import Foundation

func testAppleScriptStringEscapes() throws {
    try expectEqual(NotifierScript.appleScriptString("hi"), "\"hi\"")
    try expectEqual(NotifierScript.appleScriptString("a\"b"), "\"a\\\"b\"")
    try expectEqual(NotifierScript.appleScriptString("a\\b"), "\"a\\\\b\"")
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
    registerTest("通知：命令包含标题与正文", testCommandContainsTitleAndBody)
}
