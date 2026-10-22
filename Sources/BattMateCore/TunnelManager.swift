// Sources/BattMateCore/TunnelManager.swift
import Foundation

public enum TunnelRunState: Equatable {
    case disabled
    case stopped
    case connecting
    case running
    case retrying(String)
    case failed(String)

    public var label: String {
        switch self {
        case .disabled: return "已停用"
        case .stopped: return "未启动"
        case .connecting: return "连接中…"
        case .running: return "运行中"
        case .retrying(let reason): return "重连中：\(reason)"
        case .failed(let reason): return "失败：\(reason)"
        }
    }

    public var conciseLabel: String {
        switch self {
        case .disabled: return "已停用"
        case .stopped: return "未启动"
        case .connecting: return "连接中…"
        case .running: return "运行中"
        case .retrying: return "重连中"
        case .failed: return "失败"
        }
    }

    public var detail: String? {
        switch self {
        case .retrying(let reason), .failed(let reason): return reason
        default: return nil
        }
    }
}

public struct TunnelStatus: Equatable {
    public let config: TunnelConfig
    public let state: TunnelRunState

    public init(config: TunnelConfig, state: TunnelRunState) {
        self.config = config
        self.state = state
    }
}

/// 每条启用的映射对应一个常驻 autossh 进程。autossh 自身负责 SSH 掉线重连；
/// 本类负责进程生命周期、异常退出后的退避重启，以及可展示的状态。
public final class TunnelManager {
    public private(set) var statuses: [TunnelStatus] = []
    public var onStatusChange: (([TunnelStatus]) -> Void)?

    private final class Session {
        let config: TunnelConfig
        var state: TunnelRunState
        var process: Process?
        var errorPipe: Pipe?
        var stderrBuffer = ""
        var retryAttempt = 0
        var retryWork: DispatchWorkItem?
        var confirmationWork: DispatchWorkItem?
        var recoveryWork: DispatchWorkItem?

        init(config: TunnelConfig) {
            self.config = config
            self.state = config.enabled ? .stopped : .disabled
        }
    }

    private let binaryResolver: () -> String?
    private var autosshPath: String?
    private var target = ""
    private var appliedTunnels: [TunnelConfig] = []
    private var sessions: [UUID: Session] = [:]

    private static let retryDelays: [TimeInterval] = [5, 10, 20, 30, 60]

    public init(binaryResolver: @escaping () -> String? = { AutosshBinary.resolve() }) {
        self.binaryResolver = binaryResolver
    }

    deinit {
        for session in sessions.values {
            session.retryWork?.cancel()
            session.confirmationWork?.cancel()
            session.recoveryWork?.cancel()
            session.errorPipe?.fileHandleForReading.readabilityHandler = nil
            let process = session.process
            session.process = nil
            process?.terminationHandler = nil
            if let process, process.isRunning { process.terminate() }
        }
    }

    public func apply(tunnels: [TunnelConfig], target: String) {
        apply(tunnels: tunnels, target: target, force: false)
    }

    /// 菜单里的“重启全部隧道”：忽略配置是否变化，强制重建全部进程
    public func restartAll() {
        apply(tunnels: appliedTunnels, target: target, force: true)
    }

    public func stopAll() {
        stopSessions()
        for session in sessions.values where session.config.enabled {
            session.state = .stopped
        }
        publish()
    }

    /// 睡眠唤醒/周期体检：只拉起已经完全不存在的进程（autossh 存活时由其自行重连）
    public func ensureRunning() {
        guard !appliedTunnels.isEmpty, !target.isEmpty else { return }
        if autosshPath == nil {
            autosshPath = binaryResolver()
        }
        guard autosshPath != nil else { return }
        for session in sessions.values where session.config.enabled && session.process == nil {
            session.retryWork?.cancel()
            session.retryWork = nil
            start(session)
        }
    }

    private func apply(tunnels: [TunnelConfig], target: String, force: Bool) {
        if !force && tunnels == appliedTunnels && target == self.target {
            return
        }
        stopSessions()
        self.target = target
        self.appliedTunnels = tunnels
        self.autosshPath = binaryResolver()
        self.sessions = [:]

        for config in tunnels {
            let session = Session(config: config)
            sessions[config.id] = session
            if !config.enabled {
                session.state = .disabled
            } else if target.isEmpty {
                session.state = .stopped
            } else if autosshPath == nil {
                session.state = .failed("未找到 autossh，请先安装（brew install autossh）")
            }
        }
        publish()

        guard !target.isEmpty, autosshPath != nil else { return }
        for config in tunnels where config.enabled {
            if let session = sessions[config.id] { start(session) }
        }
    }

    private func start(_ session: Session) {
        guard let autosshPath, !target.isEmpty, session.config.enabled, session.process == nil else { return }

        session.retryWork?.cancel()
        session.retryWork = nil
        session.confirmationWork?.cancel()
        session.recoveryWork?.cancel()
        session.recoveryWork = nil
        session.stderrBuffer = ""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: autosshPath)
        process.arguments = TunnelCommand.arguments(target: target,
                                                    localPort: session.config.localPort,
                                                    remotePort: session.config.remotePort)
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in TunnelCommand.environment() {
            environment[key] = value
        }
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        let errPipe = Pipe()
        process.standardError = errPipe

        process.terminationHandler = { [weak self, weak session] proc in
            DispatchQueue.main.async {
                guard let self, let session, session.process === proc else { return }
                self.handleExit(session, status: proc.terminationStatus)
            }
        }

        session.process = process
        session.errorPipe = errPipe
        setState(session, .connecting)

        do {
            try process.run()
        } catch {
            session.process = nil
            session.errorPipe = nil
            setState(session, .failed("无法启动 autossh：\(error.localizedDescription)"))
            scheduleRetry(session)
            return
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self, weak session] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                guard let self, let session, session.process === process else { return }
                self.consumeStderr(text, session: session)
            }
        }

        // 进程挺过启动窗口且没有报错，视为隧道已建立；autossh 自身会继续守护 SSH
        let confirmation = DispatchWorkItem { [weak self, weak session] in
            guard let self, let session, session.process === process, process.isRunning else { return }
            if session.state == .connecting {
                session.retryAttempt = 0
                self.setState(session, .running)
            }
        }
        session.confirmationWork = confirmation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: confirmation)
    }

    private func stopSessions() {
        for session in sessions.values {
            session.retryWork?.cancel()
            session.retryWork = nil
            session.confirmationWork?.cancel()
            session.confirmationWork = nil
            session.recoveryWork?.cancel()
            session.recoveryWork = nil
            session.errorPipe?.fileHandleForReading.readabilityHandler = nil
            session.errorPipe = nil

            let process = session.process
            session.process = nil
            process?.terminationHandler = nil
            if let process, process.isRunning {
                process.terminate()
            }
            if session.config.enabled {
                session.state = .stopped
            }
        }
    }

    private func handleExit(_ session: Session, status: Int32) {
        session.errorPipe?.fileHandleForReading.readabilityHandler = nil
        session.errorPipe = nil
        session.process = nil
        session.confirmationWork?.cancel()
        session.confirmationWork = nil
        session.recoveryWork?.cancel()
        session.recoveryWork = nil

        let reason: String
        if case .retrying(let lastReason) = session.state {
            reason = "autossh 已退出（\(lastReason)）"
        } else if status == 0 {
            reason = "autossh 已退出"
        } else {
            reason = "autossh 异常退出（状态码 \(status)）"
        }
        setState(session, .failed(reason))

        guard session.config.enabled, !target.isEmpty else { return }
        scheduleRetry(session)
    }

    private func scheduleRetry(_ session: Session) {
        guard session.config.enabled, !target.isEmpty, autosshPath != nil else { return }
        session.retryWork?.cancel()
        let delay = Self.retryDelays[min(session.retryAttempt, Self.retryDelays.count - 1)]
        session.retryAttempt += 1
        let work = DispatchWorkItem { [weak self, weak session] in
            guard let self, let session else { return }
            session.retryWork = nil
            self.start(session)
        }
        session.retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func consumeStderr(_ text: String, session: Session) {
        session.stderrBuffer.append(text)
        if session.stderrBuffer.count > 16384 {
            session.stderrBuffer = String(session.stderrBuffer.suffix(4096))
        }

        let lines = session.stderrBuffer.components(separatedBy: "\n")
        session.stderrBuffer = lines.last ?? ""
        for line in lines.dropLast() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                handleStderrLine(trimmed, session: session)
            }
        }
    }

    private func handleStderrLine(_ line: String, session: Session) {
        guard let reason = Self.reason(fromSSHStderr: line) else { return }
        switch session.state {
        case .disabled, .stopped, .failed:
            return
        case .connecting, .running, .retrying:
            break
        }

        session.confirmationWork?.cancel()
        session.confirmationWork = nil
        setState(session, .retrying(reason))

        // autossh 只在失败时输出 ssh stderr；安静 20 秒且进程仍在，按已恢复处理
        session.recoveryWork?.cancel()
        let recovery = DispatchWorkItem { [weak self, weak session] in
            guard let self, let session, let process = session.process, process.isRunning else { return }
            if case .retrying = session.state {
                session.retryAttempt = 0
                self.setState(session, .running)
            }
        }
        session.recoveryWork = recovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: recovery)
    }

    /// 把 ssh 的典型 stderr 翻译成用户能理解的原因；未知输出（如 known_hosts 警告）直接忽略
    static func reason(fromSSHStderr line: String) -> String? {
        let lower = line.lowercased()
        if lower.contains("permission denied") { return "免密登录未配置或被拒（Permission denied）" }
        if lower.contains("host key verification failed") { return "服务器主机密钥校验失败" }
        if lower.contains("address already in use") { return "本机端口已被占用" }
        if lower.contains("could not resolve hostname") { return "无法解析服务器地址" }
        if lower.contains("connection refused") { return "服务器拒绝连接" }
        if lower.contains("connection closed") { return "连接被服务器关闭" }
        if lower.contains("connection timed out") || lower.contains("operation timed out") { return "连接超时" }
        if lower.contains("no route to host") || lower.contains("network is unreachable") { return "网络不可达" }
        if lower.contains("ssh exited with error") { return "SSH 连接中断" }
        return nil
    }

    private func setState(_ session: Session, _ state: TunnelRunState) {
        session.state = state
        publish()
    }

    private func publish() {
        statuses = appliedTunnels.map { config in
            TunnelStatus(config: config, state: sessions[config.id]?.state ?? .stopped)
        }
        onStatusChange?(statuses)
    }
}
