// Tests/SystemUsageParserTests.swift
import Foundation

func testUsageParserUsesLastSample() throws {
    let output = """
    CPU usage: 5.36% user, 15.14% sys, 79.49% idle 
    PhysMem: 10G used (2000M wired), 6G unused.
    CPU usage: 30.00% user, 20.00% sys, 50.00% idle 
    PhysMem: 8G used (2000M wired), 8G unused.
    """
    let usage = try SystemUsageParser.parse(output)
    try expectEqual(usage.cpuPercent, 50)
    try expectEqual(usage.memoryPercent, 50)
    try expectEqual(usage.memoryTotalBytes, 16 * 1024 * 1024 * 1024)
}

func testUsageParserSupportsByteUnits() throws {
    let output = """
    CPU usage: 0.00% user, 0.00% sys, 100.00% idle
    PhysMem: 512M used, 512M unused.
    """
    let usage = try SystemUsageParser.parse(output)
    try expectEqual(usage.cpuPercent, 0)
    try expectEqual(usage.memoryPercent, 50)
    try expectEqual(usage.memoryUsedBytes, 512 * 1024 * 1024)
}

func testUsageParserRejectsMissingMetrics() throws {
    try expectThrows("缺少指标", SystemUsageParser.parse("CPU usage: nope"))
}

func registerSystemUsageParserTests() {
    registerTest("资源解析：取最后一次采样", testUsageParserUsesLastSample)
    registerTest("资源解析：支持内存单位", testUsageParserSupportsByteUnits)
    registerTest("资源解析：缺失指标报错", testUsageParserRejectsMissingMetrics)
}
