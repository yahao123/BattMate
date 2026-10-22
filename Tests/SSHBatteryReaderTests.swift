// Tests/SSHBatteryReaderTests.swift
import Foundation

func testReaderBuildArguments() throws {
    let args = SSHBatteryReader.buildArguments(target: "ya@192.168.1.50",
                                               controlPath: "/tmp/battmate-cm-%r@%h-%p")
    try expectTrue(args.contains("-o"))
    try expectTrue(args.contains("BatchMode=yes"))
    try expectTrue(args.contains("ConnectTimeout=5"))
    try expectTrue(args.contains("ControlMaster=auto"))
    try expectTrue(args.contains("ControlPath=/tmp/battmate-cm-%r@%h-%p"))
    try expectTrue(args.contains("ControlPersist=60"))
    try expectTrue(args.contains("StrictHostKeyChecking=accept-new"))
    try expectTrue(args.contains("ya@192.168.1.50"))
    // 最后一项是一条合并命令：pmset + CPU/内存采样
    let command = try expectNotNil(args.last)
    try expectEqual(args.suffix(2).first, "ya@192.168.1.50")
    try expectTrue(command.contains("pmset -g batt"))
    try expectTrue(command.contains("top -l 2 -n 0 -s 1"))
}

func testReaderParsesBatteryAndUsage() throws {
    let output = """
    Now drawing from 'AC Power'
     -InternalBattery-0 (id=5439587)\t100%; charged; 0:00 remaining present: true
    __BATTMATE_METRICS__
    CPU usage: 5.36% user, 15.14% sys, 79.49% idle 
    PhysMem: 12G used (2737M wired, 884M compressor), 4409M unused.
    """
    let date = Date(timeIntervalSince1970: 1_792_600_000)
    guard case .success(let sample) = SSHBatteryReader.parse(.success(output), date: date) else {
        throw TestFailure(message: "应解析成功")
    }
    try expectEqual(sample.percent, 100)
    try expectEqual(sample.source, .ac)
    let usage = try expectNotNil(sample.usage)
    try expectEqual(usage.cpuPercent, 21)
    try expectEqual(usage.memoryPercent, 74)
    try expectEqual(usage.sampledAt, date)
}

func testReaderKeepsBatteryWhenMetricsMissing() throws {
    let output = """
    Now drawing from 'Battery Power'
     -InternalBattery-0 (id=5439587)\t45%; discharging; 2:47 remaining present: true
    __BATTMATE_METRICS__
    """
    guard case .success(let sample) = SSHBatteryReader.parse(.success(output)) else {
        throw TestFailure(message: "缺少资源采样时仍应返回电量")
    }
    try expectEqual(sample.percent, 45)
    try expectNil(sample.usage)
}

func testReaderFailureOnNonZeroExit() throws {
    // /usr/bin/false 以退出码 1 结束，验证 ssh 调用管线与错误包装
    let reader = SSHBatteryReader(target: "nobody@127.0.0.1", sshPath: "/usr/bin/false")
    var message: String?
    let sem = DispatchSemaphore(value: 0)
    reader.fetch { result in
        if case .failure(let msg) = result { message = msg }
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 10)
    let m = try expectNotNil(message, "应为 .failure")
    try expectTrue(m.contains("退出码"))
}

func testReaderFailureWhenHostUnreachable() throws {
    // BatchMode + ConnectTimeout=5 对不存在域名快速失败（NXDOMAIN）
    let reader = SSHBatteryReader(target: "nobody@battmate-test-invalid.invalid")
    var message: String?
    let sem = DispatchSemaphore(value: 0)
    reader.fetch { result in
        if case .failure(let msg) = result { message = msg }
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 45)
    try expectNotNil(message, "不可达域名应失败")
}

func registerSSHBatteryReaderTests() {
    registerTest("读取器：构造 ssh 参数", testReaderBuildArguments)
    registerTest("读取器：解析电量与资源采样", testReaderParsesBatteryAndUsage)
    registerTest("读取器：缺少资源采样仍返回电量", testReaderKeepsBatteryWhenMetricsMissing)
    registerTest("读取器：非零退出包装为失败", testReaderFailureOnNonZeroExit)
    registerTest("读取器：不可达主机失败", testReaderFailureWhenHostUnreachable)
}
