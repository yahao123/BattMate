// Sources/BattMate/AppController.swift
import AppKit
import WidgetKit

final class AppController {
    private let store: SettingsStore
    private let notifier: Notifying
    private let scheduler = PollScheduler()
    private let statusUI = StatusBarUI()
    private let settingsWindow = SettingsWindowController()
    private let tunnelManager = TunnelManager()
    private let performanceWindow = PerformanceWindowController()
    private let historyStore: MetricsHistoryStore

    private(set) var config: AppConfig
    private var reader: SSHBatteryReader
    private var engine = AlertEngine()

    private var lastSample: PowerSample?
    private var lastCheckedAt: Date?
    /// 配置代数：换目标后 +1，作废在途请求，防止旧目标的迟到结果污染新引擎
    private var pollGeneration = 0

    private var lastWidgetReloadAt: Date?
    private var widgetStoreUnavailableLogged = false
    /// WidgetKit 有自己的刷新预算，主 App 侧再限制为最多每 5 分钟请求一次
    private static let widgetReloadInterval: TimeInterval = 300

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
        self.historyStore = MetricsHistoryStore(
            fileURL: store.fileURL.deletingLastPathComponent()
                .appendingPathComponent("metrics-history.txt")
        )
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
            writeWidgetSnapshot(sample: nil, reachable: false, error: nil, forceReload: true)
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
        statusUI.onShowPerformance = { [weak self] metric in self?.showPerformance(metric) }
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

    private func showPerformance(_ metric: PerformanceMetric) {
        guard !config.sshTarget.isEmpty else {
            openSettings()
            return
        }
        performanceWindow.show(target: config.sshTarget, focus: metric, history: historyStore)
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
            if let usage = s.usage {
                historyStore.append(MetricsPoint(timestamp: usage.sampledAt,
                                                 cpuPercent: usage.cpuPercent,
                                                 memoryPercent: usage.memoryPercent))
            }
            StatusReport.write(StatusReport(reachable: true, source: s.source, percent: s.percent,
                                            status: s.status, minutesRemaining: s.minutesRemaining,
                                            checkedAt: s.timestamp, lastError: nil, usage: s.usage),
                               to: reportURL)
            writeWidgetSnapshot(sample: s, reachable: true, error: nil)
            AppLog.write("OK source=\(s.source.rawValue) pct=\(s.percent.map(String.init) ?? "-")")
        case .failure(let msg):
            StatusReport.write(StatusReport(reachable: false, source: nil, percent: nil,
                                            status: nil, minutesRemaining: nil,
                                            checkedAt: Date(), lastError: msg),
                               to: reportURL)
            writeWidgetSnapshot(sample: lastSample, reachable: false, error: msg)
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
            historyStore.clear()
            performanceWindow.close()
        }
        if targetChanged || tunnelsChanged {
            tunnelManager.apply(tunnels: c.tunnels, target: c.sshTarget)
        } else {
            tunnelManager.ensureRunning()
        }
        scheduler.restart(interval: clampedInterval)
        if !c.sshTarget.isEmpty {
            if targetChanged {
                // 先清掉旧目标的数据，避免新目标首个采样返回前小组件仍显示旧服务器
                writeWidgetSnapshot(sample: nil, reachable: false, error: nil, forceReload: true)
            }
            pollOnce()
        } else {
            statusUI.update(sample: nil, failureStreak: 0, checkedAt: nil, unconfigured: true)
            writeWidgetSnapshot(sample: nil, reachable: false, error: nil, forceReload: true)
        }
    }

    private func writeWidgetSnapshot(sample: PowerSample?, reachable: Bool,
                                     error: String?, forceReload: Bool = false) {
        guard let url = WidgetSharedStore.defaultURL() else {
            if !widgetStoreUnavailableLogged {
                widgetStoreUnavailableLogged = true
                AppLog.write("[WIDGET] 无法访问 Application Support 共享目录，小组件数据未写入")
            }
            return
        }
        let history = historyStore.points.suffix(60).map {
            WidgetSnapshot.HistoryPoint(timestamp: $0.timestamp,
                                        cpuPercent: $0.cpuPercent,
                                        memoryPercent: $0.memoryPercent)
        }
        let snapshot = WidgetSnapshot(reachable: reachable,
                                      target: config.sshTarget,
                                      source: sample?.source.rawValue,
                                      batteryPercent: sample?.percent,
                                      chargeStatus: sample?.status.rawValue,
                                      minutesRemaining: sample?.minutesRemaining,
                                      cpuPercent: sample?.usage?.cpuPercent,
                                      memoryPercent: sample?.usage?.memoryPercent,
                                      lastError: error,
                                      updatedAt: sample?.timestamp ?? Date(),
                                      history: Array(history),
                                      historyLimit: 60)
        WidgetSharedStore.save(snapshot, to: url)
        reloadWidgets(force: forceReload)
    }

    private func reloadWidgets(force: Bool) {
        let now = Date()
        if !force, let last = lastWidgetReloadAt,
           now.timeIntervalSince(last) < Self.widgetReloadInterval { return }
        lastWidgetReloadAt = now
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedStore.widgetKind)
    }
}
