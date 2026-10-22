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
    // 命令尾部是 pmset -g batt
    try expectEqual(Array(args.suffix(3)), ["pmset", "-g", "batt"])
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
    registerTest("读取器：非零退出包装为失败", testReaderFailureOnNonZeroExit)
    registerTest("读取器：不可达主机失败", testReaderFailureWhenHostUnreachable)
}
