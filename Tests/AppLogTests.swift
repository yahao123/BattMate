// Tests/AppLogTests.swift
import Foundation

func testLogWriteAppendsLine() throws {
    let original = AppLog.directory
    let tmp = tempTestDir("log")
    AppLog.directory = tmp
    defer { AppLog.directory = original }

    AppLog.write("第一条")
    AppLog.write("第二条")
    let data = try Data(contentsOf: tmp.appendingPathComponent("battmate.log"))
    let text = String(data: data, encoding: .utf8) ?? ""
    try expectTrue(text.contains("第一条"))
    try expectTrue(text.contains("第二条"))
    try expectTrue(text.contains("[20")) // 时间戳前缀
}

func registerAppLogTests() {
    registerTest("日志：追加写入两行", testLogWriteAppendsLine)
}
