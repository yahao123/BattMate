// Tests/TopProcessParserTests.swift
import Foundation

func testTopProcessParserReadsRows() throws {
    let output = """
      133   3.3  0.1 /usr/sbin/bluetoothd
    67380   2.8  3.7 Paseo Daemon
    89962   2.9  0.0 sshd: wangyahao [priv]
    """
    let processes = TopProcessParser.parse(output)
    try expectEqual(processes.count, 3)
    try expectEqual(processes[0].pid, 133)
    try expectEqual(processes[0].name, "bluetoothd")
    try expectEqual(processes[1].name, "Paseo Daemon")
    try expectEqual(processes[1].cpuPercent, 2.8)
    try expectEqual(processes[1].memoryPercent, 3.7)
    try expectEqual(processes[2].name, "sshd: wangyahao [priv]")
}

func testTopProcessParserHonorsLimitAndSkipsJunk() throws {
    let output = """
    header row
      1  10.0  0.5 /bin/first
      2   5.0  0.3 /bin/second
      3   1.0  0.1 /bin/third
    """
    let processes = TopProcessParser.parse(output, limit: 2)
    try expectEqual(processes.map(\.pid), [1, 2])
}

func registerTopProcessParserTests() {
    registerTest("Top 进程：解析进程行", testTopProcessParserReadsRows)
    registerTest("Top 进程：限制条数并跳过无效行", testTopProcessParserHonorsLimitAndSkipsJunk)
}
