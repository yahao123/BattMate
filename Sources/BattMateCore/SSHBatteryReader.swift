// Sources/BattMateCore/SSHBatteryReader.swift
import Foundation

public final class SSHBatteryReader {
    public static let metricsDelimiter = "__BATTMATE_METRICS__"

    public let target: String
    public let timeout: TimeInterval
    private let runner: SSHCommandRunner

    public init(target: String,
                timeout: TimeInterval = 12,
                controlPath: String = "/tmp/battmate-cm-%r@%h-%p",
                sshPath: String = "/usr/bin/ssh") {
        self.target = target
        self.timeout = timeout
        self.runner = SSHCommandRunner(target: target,
                                       timeout: timeout,
                                       controlPath: controlPath,
                                       sshPath: sshPath)
    }

    public static func buildArguments(target: String, controlPath: String) -> [String] {
        SSHCommandRunner.arguments(target: target, controlPath: controlPath, command: remoteCommand)
    }

    /// 一次 SSH 会话同时取电量与资源占用；top 失败时用 `|| true` 保住电量数据
    static var remoteCommand: String {
        "pmset -g batt; echo '\(metricsDelimiter)'; top -l 2 -n 0 -s 1 | grep -E '^(CPU usage|PhysMem)' || true"
    }

    /// 后台线程执行，结果回调（线程不确定，调用方自行切主线程）
    public func fetch(completion: @escaping (FetchResult) -> Void) {
        runner.run(command: Self.remoteCommand) { result in
            completion(Self.parse(result))
        }
    }

    static func parse(_ result: Result<String, SSHCommandFailure>, date: Date = Date()) -> FetchResult {
        switch result {
        case .failure(let error):
            return .failure(error.message)
        case .success(let text):
            let sections = text.components(separatedBy: metricsDelimiter)
            do {
                var sample = try PMSetOutputParser.parse(sections[0], date: date)
                if sections.count > 1 {
                    let metrics = sections.dropFirst().joined(separator: metricsDelimiter)
                    sample.usage = try? SystemUsageParser.parse(metrics, date: date)
                }
                return .success(sample)
            } catch {
                return .failure("解析失败: \(text.prefix(120))")
            }
        }
    }
}
