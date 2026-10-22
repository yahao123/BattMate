// Sources/BattMate/StatusBarUI.swift
import AppKit

final class StatusBarUI: NSObject {
    var onRefresh: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?
    var onToggleAutostart: ((Bool) -> Void)?
    var onRestartTunnels: (() -> Void)?
    var onShowPerformance: ((PerformanceMetric) -> Void)?

    private let item: NSStatusItem
    private let menu = NSMenu()
    private var sourceItem: NSMenuItem!
    private var percentItem: NSMenuItem!
    private var remainingItem: NSMenuItem!
    private var checkedItem: NSMenuItem!
    private var cpuItem: NSMenuItem!
    private var memoryItem: NSMenuItem!
    private var autostartItem: NSMenuItem!
    private var tunnelHeaderItem: NSMenuItem!
    private var tunnelRestartItem: NSMenuItem!
    private var tunnelStatusItems: [NSMenuItem] = []
    private var blinkTimer: Timer?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        buildMenu()
        item.menu = menu
        applyTitle(StatusTitleFormatter.title(sample: nil, failureStreak: 0))
    }

    private func buildMenu() {
        menu.autoenablesItems = false

        sourceItem = NSMenuItem(title: "电源来源：—", action: nil, keyEquivalent: "")
        percentItem = NSMenuItem(title: "电量：—", action: nil, keyEquivalent: "")
        remainingItem = NSMenuItem(title: "剩余时间：—", action: nil, keyEquivalent: "")
        checkedItem = NSMenuItem(title: "最后检测：—", action: nil, keyEquivalent: "")
        sourceItem.image = symbolImage("powerplug.fill", pointSize: 12, weight: .regular)
        percentItem.image = symbolImage("battery.100", pointSize: 12, weight: .regular)
        remainingItem.image = symbolImage("hourglass", pointSize: 12, weight: .regular)
        checkedItem.image = symbolImage("clock", pointSize: 12, weight: .regular)
        for detail in [sourceItem!, percentItem!, remainingItem!, checkedItem!] {
            detail.isEnabled = false
            menu.addItem(detail)
        }

        cpuItem = NSMenuItem(title: "CPU 使用率 —", action: #selector(cpuClicked), keyEquivalent: "")
        cpuItem.image = symbolImage("cpu", pointSize: 12, weight: .regular)
        cpuItem.target = self
        cpuItem.isEnabled = false
        cpuItem.toolTip = "点击查看 CPU 趋势与 Top 进程"
        menu.addItem(cpuItem)

        memoryItem = NSMenuItem(title: "内存使用率 —", action: #selector(memoryClicked), keyEquivalent: "")
        memoryItem.image = symbolImage("memorychip", pointSize: 12, weight: .regular)
        memoryItem.target = self
        memoryItem.isEnabled = false
        memoryItem.toolTip = "点击查看内存使用率趋势"
        menu.addItem(memoryItem)

        menu.addItem(.separator())

        tunnelHeaderItem = NSMenuItem(title: "SSH 隧道：未配置", action: nil, keyEquivalent: "")
        tunnelHeaderItem.image = symbolImage("network", pointSize: 12, weight: .regular)
        tunnelHeaderItem.isEnabled = false
        menu.addItem(tunnelHeaderItem)

        tunnelRestartItem = NSMenuItem(title: "重启全部隧道", action: #selector(restartTunnelsClicked), keyEquivalent: "")
        tunnelRestartItem.image = symbolImage("arrow.clockwise", pointSize: 12, weight: .regular)
        tunnelRestartItem.target = self
        tunnelRestartItem.isEnabled = false
        menu.addItem(tunnelRestartItem)

        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "立即刷新", action: #selector(refreshClicked), keyEquivalent: "r")
        refresh.image = symbolImage("arrow.clockwise", pointSize: 12, weight: .regular)
        refresh.target = self
        menu.addItem(refresh)

        let settings = NSMenuItem(title: "设置…", action: #selector(settingsClicked), keyEquivalent: ",")
        settings.image = symbolImage("gearshape", pointSize: 12, weight: .regular)
        settings.target = self
        menu.addItem(settings)

        autostartItem = NSMenuItem(title: "开机自启动", action: #selector(autostartClicked), keyEquivalent: "")
        autostartItem.image = symbolImage("power", pointSize: 12, weight: .regular)
        autostartItem.target = self
        autostartItem.state = Autostart.isEnabled ? .on : .off
        menu.addItem(autostartItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 BattMate", action: #selector(quitClicked), keyEquivalent: "q")
        quit.image = symbolImage("xmark.circle", pointSize: 12, weight: .regular)
        quit.target = self
        menu.addItem(quit)
    }

    func update(sample: PowerSample?, failureStreak: Int, checkedAt: Date?, unconfigured: Bool) {
        let title = StatusTitleFormatter.title(sample: sample, failureStreak: failureStreak)
        applyTitle(title)

        // 失败 1~2 次期间闪烁；达到 3（已判定失联）或恢复后停止
        if failureStreak > 0 && failureStreak < 3 {
            startBlink(title)
        } else {
            stopBlink()
        }

        if let s = sample {
            sourceItem.title = sourceName(s.source)
            sourceItem.image = symbolImage(sourceSymbol(s.source), pointSize: 12, weight: .regular)
            percentItem.title = s.percent.map { "电量 \($0)%" } ?? "无电池"
            percentItem.image = symbolImage(Self.batterySymbol(percent: s.percent), pointSize: 12, weight: .regular)
            remainingItem.title = "剩余 \(s.remainingText)"
        } else {
            sourceItem.title = unconfigured ? "尚未配置服务器" : "电源状态 —"
            sourceItem.image = symbolImage("powerplug", pointSize: 12, weight: .regular)
            percentItem.title = "电量 —"
            percentItem.image = symbolImage("battery.100", pointSize: 12, weight: .regular)
            remainingItem.title = "剩余 —"
        }
        remainingItem.image = symbolImage("hourglass", pointSize: 12, weight: .regular)
        if let at = checkedAt {
            checkedItem.title = "最后检测 \(Self.timeFormatter.string(from: at))"
        } else {
            checkedItem.title = "最后检测 —"
        }
        checkedItem.image = symbolImage("clock", pointSize: 12, weight: .regular)

        if let usage = sample?.usage {
            cpuItem.title = "CPU 使用率 \(usage.cpuPercent)%"
            cpuItem.isEnabled = true
            cpuItem.toolTip = "点击查看 CPU 趋势与 Top 进程"
            cpuItem.image = symbolImage("cpu", pointSize: 12, weight: .regular,
                                        color: loadColor(usage.cpuPercent))
            memoryItem.title = "内存使用率 \(usage.memoryPercent)%"
            memoryItem.isEnabled = true
            memoryItem.toolTip = "已用 \(usage.memoryUsedText) / \(usage.memoryTotalText) · 点击查看趋势"
            memoryItem.image = symbolImage("memorychip", pointSize: 12, weight: .regular,
                                           color: loadColor(usage.memoryPercent))
        } else if unconfigured {
            cpuItem.title = "CPU 使用率 —"
            cpuItem.isEnabled = false
            cpuItem.toolTip = "配置服务器后可用"
            memoryItem.title = "内存使用率 —"
            memoryItem.isEnabled = false
            memoryItem.toolTip = "配置服务器后可用"
            cpuItem.image = symbolImage("cpu", pointSize: 12, weight: .regular)
            memoryItem.image = symbolImage("memorychip", pointSize: 12, weight: .regular)
        } else {
            cpuItem.title = "CPU 使用率 —"
            cpuItem.isEnabled = false
            cpuItem.toolTip = "尚未取到资源数据"
            memoryItem.title = "内存使用率 —"
            memoryItem.isEnabled = false
            memoryItem.toolTip = "尚未取到资源数据"
            cpuItem.image = symbolImage("cpu", pointSize: 12, weight: .regular)
            memoryItem.image = symbolImage("memorychip", pointSize: 12, weight: .regular)
        }
    }

    private func loadColor(_ percent: Int) -> NSColor {
        switch percent {
        case 85...: return .systemRed
        case 60...: return .systemOrange
        default: return .systemGreen
        }
    }

    func updateTunnels(_ statuses: [TunnelStatus]) {
        for old in tunnelStatusItems {
            menu.removeItem(old)
        }
        tunnelStatusItems.removeAll()

        tunnelHeaderItem.title = statuses.isEmpty ? "SSH 隧道：未配置" : "SSH 隧道（本机 → 服务器）"
        tunnelRestartItem.isEnabled = statuses.contains {
            $0.config.enabled && $0.state != .stopped && $0.state != .disabled
        }

        var index = menu.index(of: tunnelRestartItem)
        if index < 0 { index = menu.numberOfItems }
        for status in statuses {
            let menuItem = NSMenuItem(title: "\(status.config.localPort) → \(status.config.remotePort) · \(status.state.conciseLabel)",
                                      action: nil,
                                      keyEquivalent: "")
            menuItem.image = symbolImage("circle.fill",
                                         pointSize: 7,
                                         weight: .bold,
                                         color: dotColor(for: status.state))
            menuItem.isEnabled = false
            menuItem.toolTip = "\(status.config.forwardDescription)\n状态：\(status.state.label)"
            menu.insertItem(menuItem, at: index)
            tunnelStatusItems.append(menuItem)
            index += 1
        }
    }

    private func dotColor(for state: TunnelRunState) -> NSColor {
        switch state {
        case .running: return .systemGreen
        case .connecting, .retrying: return .systemOrange
        case .failed: return .systemRed
        case .disabled, .stopped: return .tertiaryLabelColor
        }
    }

    private func sourceName(_ s: PowerSource) -> String {
        switch s {
        case .ac: return "电源适配器"
        case .battery: return "电池供电"
        case .unknown: return "未知电源"
        }
    }

    private func sourceSymbol(_ s: PowerSource) -> String {
        switch s {
        case .ac: return "powerplug.fill"
        case .battery: return "battery.100"
        case .unknown: return "questionmark.circle"
        }
    }

    private static func batterySymbol(percent: Int?) -> String {
        guard let percent else { return "battery.50" }
        switch percent {
        case 88...: return "battery.100"
        case 63...: return "battery.75"
        case 38...: return "battery.50"
        case 13...: return "battery.25"
        default: return "battery.0"
        }
    }

    private func symbolImage(_ name: String,
                             pointSize: CGFloat,
                             weight: NSFont.Weight,
                             color: NSColor? = nil) -> NSImage? {
        var configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        if let color {
            configuration = configuration.applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        image.isTemplate = color == nil
        return image
    }

    private func applyTitle(_ t: (text: String, color: NSColor)) {
        applyColored(text: t.text, color: t.color)
    }

    private func applyColored(text: String, color: NSColor, dimmed: Bool = false) {
        item.button?.attributedTitle = renderedTitle(text: text, color: color, dimmed: dimmed)
    }

    private func renderedTitle(text: String, color: NSColor, dimmed: Bool) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let tint = dimmed ? NSColor.tertiaryLabelColor : color
        let result = NSMutableAttributedString()

        var symbolName: String?
        var value = text
        if text.hasPrefix("⚡") {
            symbolName = "bolt.fill"
            value = String(text.dropFirst())
        } else if text.hasPrefix("🔋") {
            symbolName = Self.batterySymbol(percent: Int(text.dropFirst()))
            value = String(text.dropFirst())
        } else if text.hasPrefix("⚠︎") {
            symbolName = "exclamationmark.triangle.fill"
            value = String(text.dropFirst())
        }

        if let symbolName,
           let image = symbolImage(symbolName, pointSize: 12, weight: .semibold, color: tint) {
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = CGRect(x: 0, y: -2, width: image.size.width, height: image.size.height)
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: " " + value,
                                             attributes: [.font: font, .foregroundColor: tint]))
        } else {
            result.append(NSAttributedString(string: " " + value,
                                             attributes: [.font: font, .foregroundColor: tint]))
        }
        result.append(NSAttributedString(string: " ", attributes: [.font: font]))
        return result
    }

    private func startBlink(_ t: (text: String, color: NSColor)) {
        guard blinkTimer == nil else { return }
        var on = true
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            on.toggle()
            self?.applyColored(text: t.text, color: t.color, dimmed: !on)
        }
    }

    private func stopBlink() {
        blinkTimer?.invalidate()
        blinkTimer = nil
    }

    @objc private func refreshClicked() { onRefresh?() }
    @objc private func settingsClicked() { onOpenSettings?() }
    @objc private func quitClicked() { onQuit?() }
    @objc private func restartTunnelsClicked() { onRestartTunnels?() }
    @objc private func cpuClicked() { onShowPerformance?(.cpu) }
    @objc private func memoryClicked() { onShowPerformance?(.memory) }

    @objc private func autostartClicked(_ sender: NSMenuItem) {
        let target = sender.state == .on ? false : true
        if let error = Autostart.setEnabled(target) {
            AppLog.write("开机自启设置失败: \(error)")
        }
        sender.state = Autostart.isEnabled ? .on : .off
        onToggleAutostart?(Autostart.isEnabled)
    }
}
