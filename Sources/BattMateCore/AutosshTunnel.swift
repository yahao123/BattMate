// Sources/BattMateCore/AutosshTunnel.swift
import Foundation

public enum AutosshBinary {
    /// Finder 启动的 App 不继承 shell PATH，Homebrew 的常见安装位置必须显式覆盖
    public static let candidatePaths = [
        "/opt/homebrew/bin/autossh",
        "/usr/local/bin/autossh",
        "/usr/bin/autossh",
        "/opt/local/bin/autossh"
    ]

    public static func resolve(
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        fileExists: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)
    ) -> String? {
        var candidates = candidatePaths
        if let pathEnvironment {
            for dir in pathEnvironment.split(separator: ":") where !dir.isEmpty {
                candidates.append(String(dir) + "/autossh")
            }
        }
        var seen = Set<String>()
        for path in candidates where seen.insert(path).inserted {
            if fileExists(path) { return path }
        }
        return nil
    }
}

public enum TunnelCommand {
    public static func arguments(target: String, localPort: Int, remotePort: Int) -> [String] {
        [
            "-M", "0",
            "-N",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ControlPath=none",
            "-L", "127.0.0.1:\(localPort):127.0.0.1:\(remotePort)",
            target
        ]
    }

    /// AUTOSSH_GATETIME=0 让 autossh 在首次连接失败后也持续重试；
    /// AUTOSSH_POLL=30 把内置退避上限从默认 10 分钟压到 30 秒，服务器重启后能尽快恢复。
    public static func environment() -> [String: String] {
        [
            "AUTOSSH_GATETIME": "0",
            "AUTOSSH_POLL": "30"
        ]
    }
}
