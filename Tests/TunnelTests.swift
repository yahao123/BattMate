// Tests/TunnelTests.swift
import Foundation

func testTunnelCommandArguments() throws {
    let args = TunnelCommand.arguments(target: "ya@192.168.1.50", localPort: 8080, remotePort: 3306)

    try expectEqual(args[0], "-M")
    try expectEqual(args[1], "0")
    try expectTrue(args.contains("-N"))
    try expectTrue(args.contains("BatchMode=yes"))
    try expectTrue(args.contains("ExitOnForwardFailure=yes"))
    try expectTrue(args.contains("ServerAliveInterval=30"))
    try expectTrue(args.contains("ServerAliveCountMax=3"))
    try expectTrue(args.contains("StrictHostKeyChecking=accept-new"))
    try expectTrue(args.contains("ControlPath=none"))
    try expectTrue(args.contains("127.0.0.1:8080:127.0.0.1:3306"))
    try expectEqual(args.last, "ya@192.168.1.50")
}

func testTunnelCommandEnvironment() throws {
    let env = TunnelCommand.environment()
    try expectEqual(env["AUTOSSH_GATETIME"], "0")
    try expectEqual(env["AUTOSSH_POLL"], "30")
}

func testAutosshResolvePrefersHomebrew() throws {
    let both = AutosshBinary.resolve(pathEnvironment: nil) {
        $0 == "/opt/homebrew/bin/autossh" || $0 == "/usr/local/bin/autossh"
    }
    try expectEqual(both, "/opt/homebrew/bin/autossh")

    let fallback = AutosshBinary.resolve(pathEnvironment: nil) {
        $0 == "/usr/local/bin/autossh"
    }
    try expectEqual(fallback, "/usr/local/bin/autossh")

    try expectNil(AutosshBinary.resolve(pathEnvironment: nil) { _ in false })
}

func testAutosshResolveUsesPATH() throws {
    let path = AutosshBinary.resolve(pathEnvironment: "/custom/bin:/other/bin") {
        $0 == "/custom/bin/autossh"
    }
    try expectEqual(path, "/custom/bin/autossh")
}

func testTunnelValidationAcceptsValidMapping() throws {
    let tunnels = [
        TunnelConfig(localPort: 8080, remotePort: 80),
        TunnelConfig(localPort: 5432, remotePort: 5432)
    ]
    try expectTrue(TunnelValidator.errors(for: tunnels).isEmpty)
}

func testTunnelValidationRejectsInvalidPortsAndDuplicates() throws {
    let tunnels = [
        TunnelConfig(localPort: 0, remotePort: 80),
        TunnelConfig(localPort: 70000, remotePort: 80),
        TunnelConfig(localPort: 8080, remotePort: 1),
        TunnelConfig(localPort: 8080, remotePort: 2)
    ]
    let errors = TunnelValidator.errors(for: tunnels)
    try expectTrue(errors.contains { $0.contains("本机端口 0 无效") })
    try expectTrue(errors.contains { $0.contains("本机端口 70000 无效") })
    try expectTrue(errors.contains { $0.contains("本机端口 8080 与第 3 条重复") })
}

func testTunnelConfigDecodeDefaults() throws {
    let json = #"{"localPort":8080,"remotePort":80}"#
    let tunnel = try JSONDecoder().decode(TunnelConfig.self, from: Data(json.utf8))
    try expectEqual(tunnel.localPort, 8080)
    try expectEqual(tunnel.remotePort, 80)
    try expectTrue(tunnel.enabled, "缺省应视为启用")
}

func testTunnelConfigDecodeExplicitValues() throws {
    let id = UUID()
    let json = #"{"id":"\#(id.uuidString)","localPort":9000,"remotePort":5432,"enabled":false}"#
    let tunnel = try JSONDecoder().decode(TunnelConfig.self, from: Data(json.utf8))
    try expectEqual(tunnel.id, id)
    try expectFalse(tunnel.enabled)
}

func testAppConfigDecodeLegacyWithoutTunnels() throws {
    let json = """
    {
      "sshTarget": "ya@192.168.1.50",
      "intervalSeconds": 60,
      "lowBatteryThreshold": 25,
      "soundEnabled": false,
      "autostartEnabled": true
    }
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    try expectEqual(config.sshTarget, "ya@192.168.1.50")
    try expectEqual(config.intervalSeconds, 60)
    try expectEqual(config.lowBatteryThreshold, 25)
    try expectFalse(config.soundEnabled)
    try expectTrue(config.autostartEnabled)
    try expectTrue(config.tunnels.isEmpty, "旧配置应兼容为空隧道列表")
}

func testStoreRoundtripWithTunnels() throws {
    let dir = tempTestDir("store-tunnels")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = SettingsStore(directory: dir)

    var config = AppConfig.default
    config.sshTarget = "ya@192.168.1.50"
    config.tunnels = [
        TunnelConfig(localPort: 8080, remotePort: 80),
        TunnelConfig(localPort: 5432, remotePort: 5432, enabled: false)
    ]
    store.save(config)
    try expectEqual(store.load(), config)
}

func testTunnelStderrReasonMapping() throws {
    try expectEqual(
        TunnelManager.reason(fromSSHStderr: "Permission denied (publickey)."),
        "免密登录未配置或被拒（Permission denied）"
    )
    try expectEqual(
        TunnelManager.reason(fromSSHStderr: "bind [127.0.0.1]:8080: Address already in use"),
        "本机端口已被占用"
    )
    try expectNil(TunnelManager.reason(fromSSHStderr: "Warning: Permanently added 'host' to the list of known hosts."))
}

private func writeFakeAutossh(in dir: URL) throws -> String {
    let url = dir.appendingPathComponent("autossh")
    try "#!/bin/sh\nexec /bin/sleep 60\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url.path
}

private func spinRunLoop(until condition: () -> Bool, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return condition()
}

func testTunnelManagerLifecycle() throws {
    let dir = tempTestDir("tunnel-manager")
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let fakeAutossh = try writeFakeAutossh(in: dir)

    let manager = TunnelManager(binaryResolver: { fakeAutossh })
    manager.apply(tunnels: [TunnelConfig(localPort: 18080, remotePort: 80)],
                  target: "ya@192.168.1.50")

    let running = spinRunLoop(until: {
        manager.statuses.first?.state == .running
    }, timeout: 5)
    try expectTrue(running, "启动约 2 秒后应进入运行中，实际 \(manager.statuses.map(\.state))")

    manager.stopAll()
    try expectEqual(manager.statuses.first?.state, .stopped)
}

func testTunnelManagerSkipsDisabledAndUnconfigured() throws {
    let manager = TunnelManager(binaryResolver: { nil })
    let disabled = TunnelConfig(localPort: 18081, remotePort: 81, enabled: false)
    manager.apply(tunnels: [disabled], target: "ya@192.168.1.50")
    try expectEqual(manager.statuses.first?.state, .disabled)

    manager.apply(tunnels: [TunnelConfig(localPort: 18082, remotePort: 82)], target: "")
    try expectEqual(manager.statuses.first?.state, .stopped)

    manager.apply(tunnels: [TunnelConfig(localPort: 18083, remotePort: 83)], target: "ya@192.168.1.50")
    try expectEqual(manager.statuses.first?.state,
                    .failed("未找到 autossh，请先安装（brew install autossh）"))
}

func registerTunnelTests() {
    registerTest("隧道：构造 autossh 参数", testTunnelCommandArguments)
    registerTest("隧道：autossh 环境变量", testTunnelCommandEnvironment)
    registerTest("隧道：优先探测 Homebrew autossh", testAutosshResolvePrefersHomebrew)
    registerTest("隧道：从 PATH 探测 autossh", testAutosshResolveUsesPATH)
    registerTest("隧道：合法映射校验", testTunnelValidationAcceptsValidMapping)
    registerTest("隧道：非法端口与重复端口", testTunnelValidationRejectsInvalidPortsAndDuplicates)
    registerTest("隧道：配置缺省字段解码", testTunnelConfigDecodeDefaults)
    registerTest("隧道：配置显式字段解码", testTunnelConfigDecodeExplicitValues)
    registerTest("隧道：旧配置无 tunnels 字段兼容", testAppConfigDecodeLegacyWithoutTunnels)
    registerTest("隧道：含映射配置往返", testStoreRoundtripWithTunnels)
    registerTest("隧道：ssh 错误翻译", testTunnelStderrReasonMapping)
    registerTest("隧道：管理器启动与停止", testTunnelManagerLifecycle)
    registerTest("隧道：停用/未配置/缺 autossh", testTunnelManagerSkipsDisabledAndUnconfigured)
}
