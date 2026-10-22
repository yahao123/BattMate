// Sources/BattMateCore/SSHCommandRunner.swift
import Foundation

public struct SSHCommandFailure: Error, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

/// 复用 ControlMaster 连接执行远程命令，并带超时看门狗，防止 SSH 悬挂。
public final class SSHCommandRunner {
    public let target: String
    public let timeout: TimeInterval
    public let controlPath: String
    public let sshPath: String

    public init(target: String,
                timeout: TimeInterval = 12,
                controlPath: String = "/tmp/battmate-cm-%r@%h-%p",
                sshPath: String = "/usr/bin/ssh") {
        self.target = target
        self.timeout = timeout
        self.controlPath = controlPath
        self.sshPath = sshPath
    }

    public static func arguments(target: String, controlPath: String, command: String) -> [String] {
        [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlPath)",
            "-o", "ControlPersist=60",
            target,
            command
        ]
    }

    /// 后台线程执行，结果回调（线程不确定，调用方自行切主线程）
    public func run(command: String, completion: @escaping (Result<String, SSHCommandFailure>) -> Void) {
        DispatchQueue.global(qos: .utility).async { [self] in
            completion(runSync(command: command))
        }
    }

    func runSync(command: String) -> Result<String, SSHCommandFailure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = Self.arguments(target: target, controlPath: controlPath, command: command)
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return .failure(SSHCommandFailure("无法启动 ssh: \(error.localizedDescription)"))
        }

        let watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        watchdog.schedule(deadline: .now() + timeout)
        watchdog.setEventHandler { [weak process] in
            if let p = process, p.isRunning { p.terminate() }
        }
        watchdog.resume()
        defer { watchdog.cancel() }

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: errData, encoding: .utf8) ?? ""
            return .failure(SSHCommandFailure("ssh 退出码 \(process.terminationStatus): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"))
        }
        guard let text = String(data: outData, encoding: .utf8) else {
            return .failure(SSHCommandFailure("输出不是 UTF-8"))
        }
        return .success(text)
    }
}
