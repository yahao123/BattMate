// Sources/BattMateCore/TopProcess.swift
import Foundation

public struct TopProcess: Equatable {
    public var pid: Int
    public var executablePath: String
    public var cpuPercent: Double
    public var memoryPercent: Double

    public init(pid: Int, executablePath: String, cpuPercent: Double, memoryPercent: Double) {
        self.pid = pid
        self.executablePath = executablePath
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
    }

    public var name: String {
        (executablePath as NSString).lastPathComponent
    }
}

public enum TopProcessParser {
    /// 解析 `ps -Ao pid=,pcpu=,pmem=,comm=` 的输出，进程名中的空格并入最后一列
    public static func parse(_ output: String, limit: Int = 12) -> [TopProcess] {
        let all = output.split(whereSeparator: \.isNewline).compactMap { line -> TopProcess? in
            let parts = line.split(maxSplits: 3, whereSeparator: \.isWhitespace)
            guard parts.count == 4,
                  let pid = Int(parts[0]),
                  let cpu = Double(parts[1]),
                  let mem = Double(parts[2]) else { return nil }
            return TopProcess(pid: pid,
                              executablePath: String(parts[3]),
                              cpuPercent: cpu,
                              memoryPercent: mem)
        }
        return Array(all.prefix(max(0, limit)))
    }
}

public final class TopProcessReader {
    private let runner: SSHCommandRunner

    public init(target: String,
                timeout: TimeInterval = 10,
                controlPath: String = "/tmp/battmate-cm-%r@%h-%p",
                sshPath: String = "/usr/bin/ssh") {
        self.runner = SSHCommandRunner(target: target,
                                       timeout: timeout,
                                       controlPath: controlPath,
                                       sshPath: sshPath)
    }

    public static func remoteCommand(limit: Int) -> String {
        "ps -Ao pid=,pcpu=,pmem=,comm= -r | head -n \(max(1, limit))"
    }

    public func fetch(limit: Int = 12, completion: @escaping (Result<[TopProcess], SSHCommandFailure>) -> Void) {
        runner.run(command: Self.remoteCommand(limit: limit)) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let text):
                let processes = TopProcessParser.parse(text, limit: limit)
                if processes.isEmpty {
                    completion(.failure(SSHCommandFailure("未读取到进程信息")))
                } else {
                    completion(.success(processes))
                }
            }
        }
    }
}
