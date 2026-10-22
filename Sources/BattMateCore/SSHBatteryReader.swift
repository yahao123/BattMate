// Sources/BattMateCore/SSHBatteryReader.swift
import Foundation

public final class SSHBatteryReader {
    public let target: String
    public let timeout: TimeInterval
    private let controlPath: String
    private let sshPath: String

    public init(target: String,
                timeout: TimeInterval = 12,
                controlPath: String = "/tmp/battmate-cm-%r@%h-%p",
                sshPath: String = "/usr/bin/ssh") {
        self.target = target
        self.timeout = timeout
        self.controlPath = controlPath
        self.sshPath = sshPath
    }

    public static func buildArguments(target: String, controlPath: String) -> [String] {
        [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlPath)",
            "-o", "ControlPersist=60",
            target,
            "pmset", "-g", "batt"
        ]
    }

    /// 后台线程执行，结果回调（线程不确定，调用方自行切主线程）
    public func fetch(completion: @escaping (FetchResult) -> Void) {
        DispatchQueue.global(qos: .utility).async { [self] in
            completion(runSync())
        }
    }

    func runSync() -> FetchResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = Self.buildArguments(target: target, controlPath: controlPath)
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return .failure("无法启动 ssh: \(error.localizedDescription)")
        }

        // 看门狗：超时强杀，防止悬挂
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
            return .failure("ssh 退出码 \(process.terminationStatus): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        guard let text = String(data: outData, encoding: .utf8) else {
            return .failure("输出不是 UTF-8")
        }
        do {
            return .success(try PMSetOutputParser.parse(text))
        } catch {
            return .failure("解析失败: \(text.prefix(120))")
        }
    }
}
