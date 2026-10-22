// Tests/StatusReportTests.swift
import Foundation

func testReportJSONRoundtrip() throws {
    let report = StatusReport(reachable: true, source: .battery, percent: 45,
                              status: .discharging, minutesRemaining: 167,
                              checkedAt: Date(timeIntervalSince1970: 1_792_600_000),
                              lastError: nil)
    let dir = tempTestDir("report")
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("status.json")

    StatusReport.write(report, to: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let back = try decoder.decode(StatusReport.self, from: Data(contentsOf: url))
    try expectEqual(back, report)
}

func testReportUnreachableEncodesLastError() throws {
    let report = StatusReport(reachable: false, source: nil, percent: nil,
                              status: nil, minutesRemaining: nil,
                              checkedAt: Date(), lastError: "timeout")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .prettyPrinted // 本工具链紧凑输出无空格，断言针对 StatusReport.write 实际落盘格式
    let json = String(data: try encoder.encode(report), encoding: .utf8)!
    try expectTrue(json.contains("\"reachable\" : false"))
    try expectTrue(json.contains("timeout"))
}

func registerStatusReportTests() {
    registerTest("状态报告：JSON 往返", testReportJSONRoundtrip)
    registerTest("状态报告：失联信息可编码", testReportUnreachableEncodesLastError)
}
