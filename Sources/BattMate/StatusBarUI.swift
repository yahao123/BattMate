// Sources/BattMate/StatusBarUI.swift（最终形态）
import AppKit

final class StatusBarUI: NSObject {
    var onRefresh: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?
    var onToggleAutostart: ((Bool) -> Void)?

    private let item: NSStatusItem
    private let menu = NSMenu()
    private var sourceItem: NSMenuItem!
    private var percentItem: NSMenuItem!
    private var remainingItem: NSMenuItem!
    private var checkedItem: NSMenuItem!
    private var autostartItem: NSMenuItem!
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
        for detail in [sourceItem!, percentItem!, remainingItem!, checkedItem!] {
            detail.isEnabled = false
            menu.addItem(detail)
        }

        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "立即刷新", action: #selector(refreshClicked), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let settings = NSMenuItem(title: "设置…", action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        autostartItem = NSMenuItem(title: "开机自启动", action: #selector(autostartClicked), keyEquivalent: "")
        autostartItem.target = self
        autostartItem.state = Autostart.isEnabled ? .on : .off
        menu.addItem(autostartItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 BattMate", action: #selector(quitClicked), keyEquivalent: "q")
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
            sourceItem.title = "电源来源：\(sourceName(s.source))"
            percentItem.title = "电量：\(s.percent.map { "\($0)%" } ?? "无电池")"
            remainingItem.title = "剩余时间：\(s.remainingText)"
        } else {
            sourceItem.title = unconfigured ? "电源来源：未配置" : "电源来源：—"
            percentItem.title = "电量：—"
            remainingItem.title = "剩余时间：—"
        }
        if let at = checkedAt {
            checkedItem.title = "最后检测：\(Self.timeFormatter.string(from: at))"
        } else {
            checkedItem.title = "最后检测：—"
        }
    }

    private func sourceName(_ s: PowerSource) -> String {
        switch s {
        case .ac: return "电源适配器 ⚡"
        case .battery: return "电池 🔋"
        case .unknown: return "未知"
        }
    }

    private func applyTitle(_ t: (text: String, color: NSColor)) {
        applyColored(text: t.text, color: t.color)
    }

    private func applyColored(text: String, color: NSColor) {
        item.button?.attributedTitle = NSAttributedString(
            string: " \(text) ",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: color
            ]
        )
    }

    private func startBlink(_ t: (text: String, color: NSColor)) {
        guard blinkTimer == nil else { return }
        var on = true
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            on.toggle()
            self?.applyColored(text: t.text, color: on ? t.color : .disabledControlTextColor)
        }
    }

    private func stopBlink() {
        blinkTimer?.invalidate()
        blinkTimer = nil
    }

    @objc private func refreshClicked() { onRefresh?() }
    @objc private func settingsClicked() { onOpenSettings?() }
    @objc private func quitClicked() { onQuit?() }

    @objc private func autostartClicked(_ sender: NSMenuItem) {
        let target = sender.state == .on ? false : true
        if let error = Autostart.setEnabled(target) {
            AppLog.write("开机自启设置失败: \(error)")
        }
        sender.state = Autostart.isEnabled ? .on : .off
        onToggleAutostart?(Autostart.isEnabled)
    }
}
