// Sources/BattMate/AppController.swift
import AppKit

final class AppController {
    private let store: SettingsStore
    private let notifier: Notifying
    private let scheduler = PollScheduler()
    private let statusUI = StatusBarUI()
    private let settingsWindow = SettingsWindowController()
    private let tunnelManager = TunnelManager()

    private(set) var config: AppConfig
    private var reader: SSHBatteryReader
    private var engine = AlertEngine()

    private var lastSample: PowerSample?
    private var lastCheckedAt: Date?
    /// 配置代数：换目标后 +1，作废在途请求，防止旧目标的迟到结果污染新引擎
    private var pollGeneration = 0

    /// 轮询间隔钳制到 15~300 秒（spec Global Constraints；config.json 可能被手改越界）
    private var clampedInterval: TimeInterval {
        TimeInterval(min(300, max(15, config.intervalSeconds)))
    }

    private var reportURL: URL {
        store.fileURL.deletingLastPathComponent().appendingPathComponent("status.json")
    }

    init(store: SettingsStore = SettingsStore(), notifier: Notifying = Notifier()) {
        self.store = store
        self.notifier = notifier
        self.config = store.load()
        self.reader = SSHBatteryReader(target: config.sshTarget)
    }

    func start() {
        wireUI()
        tunnelManager.onStatusChange = { [weak self] statuses in
            self?.statusUI.updateTunnels(statuses)
        }
        scheduler.onTick = { [weak self] in
            self?.pollOnce()
            self?.tunnelManager.ensureRunning()
        }
        // 契约：start() 全生命周期只调用一次（PollScheduler 会注册 NSWorkspace 观察者，
        // 重复 start 会重复注册）；之后改间隔一律用 restart()
        scheduler.start(interval: clampedInterval)
        tunnelManager.apply(tunnels: config.tunnels, target: config.sshTarget)
        if config.sshTarget.isEmpty {
            store.save(config) // 首次启动即落盘默认配置（冒烟预期：config.json 已生成）
            statusUI.update(sample: nil, failureStreak: 0, checkedAt: nil, unconfigured: true)
            openSettings()
        } else {
            if config.autostartEnabled { _ = Autostart.setEnabled(true) }
            pollOnce()
        }
    }

    /// 正常退出前杀掉全部 autossh，避免端口被遗留进程占用
    func shutdown() {
        tunnelManager.stopAll()
    }

    private func wireUI() {
        statusUI.onRefresh = { [weak self] in self?.pollOnce() }
        statusUI.onRestartTunnels = { [weak self] in self?.tunnelManager.restartAll() }
        statusUI.onOpenSettings = { [weak self] in self?.openSettings() }
        statusUI.onQuit = { NSApp.terminate(nil) }
        statusUI.onToggleAutostart = { [weak self] enabled in
            guard let self else { return }
            self.config.autostartEnabled = enabled
            self.store.save(self.config)
        }
    }

    func openSettings() {
        settingsWindow.show(store: store, config: config) { [weak self] newConfig in
            self?.applyConfig(newConfig)
        }
    }

    func pollOnce() {
        guard !config.sshTarget.isEmpty else { return }
        let generation = pollGeneration
        lastCheckedAt = Date()
        reader.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self, generation == self.pollGeneration else { return } // 旧目标在途请求已作废
                self.handle(result)
            }
        }
    }

    private func handle(_ result: FetchResult) {
        let decisions = engine.evaluate(result, lowBatteryThreshold: config.lowBatteryThreshold)
        for d in decisions {
            notifier.deliver(title: d.title, body: d.body, sound: config.soundEnabled)
            AppLog.write("[ALERT] \(d.kind) \(d.title) \(d.body)")
        }

        switch result {
        case .success(let s):
            lastSample = s
            StatusReport.write(StatusReport(reachable: true, source: s.source, percent: s.percent,
                                            status: s.status, minutesRemaining: s.minutesRemaining,
                                            checkedAt: s.timestamp, lastError: nil),
                               to: reportURL)
            AppLog.write("OK source=\(s.source.rawValue) pct=\(s.percent.map(String.init) ?? "-")")
        case .failure(let msg):
            StatusReport.write(StatusReport(reachable: false, source: nil, percent: nil,
                                            status: nil, minutesRemaining: nil,
                                            checkedAt: Date(), lastError: msg),
                               to: reportURL)
            AppLog.write("ERR \(msg)")
        }
        statusUI.update(sample: lastSample,
                        failureStreak: engine.consecutiveFailures,
                        checkedAt: lastCheckedAt,
                        unconfigured: false)
    }

    private func applyConfig(_ c: AppConfig) {
        let targetChanged = c.sshTarget != config.sshTarget
        let tunnelsChanged = c.tunnels != config.tunnels
        config = c
        if targetChanged {
            pollGeneration += 1 // 作废换目标前的在途请求
            reader = SSHBatteryReader(target: c.sshTarget)
            engine = AlertEngine() // 换目标后重建基线
            lastSample = nil
        }
        if targetChanged || tunnelsChanged {
            tunnelManager.apply(tunnels: c.tunnels, target: c.sshTarget)
        } else {
            tunnelManager.ensureRunning()
        }
        scheduler.restart(interval: clampedInterval)
        if !c.sshTarget.isEmpty {
            pollOnce()
        } else {
            statusUI.update(sample: nil, failureStreak: 0, checkedAt: nil, unconfigured: true)
        }
    }
}
