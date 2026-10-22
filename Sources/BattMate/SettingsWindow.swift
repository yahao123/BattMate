// Sources/BattMate/SettingsWindow.swift
import SwiftUI
import AppKit

final class SettingsViewModel: ObservableObject {
    @Published var sshTarget: String
    @Published var intervalSeconds: Double
    @Published var lowBatteryThreshold: Double
    @Published var soundEnabled: Bool
    @Published var testResult: String = ""
    @Published var testing = false
    @Published var copyableHint: String = ""

    private let store: SettingsStore
    private let onChange: (AppConfig) -> Void

    init(store: SettingsStore, config: AppConfig, onChange: @escaping (AppConfig) -> Void) {
        self.store = store
        self.sshTarget = config.sshTarget
        self.intervalSeconds = Double(config.intervalSeconds)
        self.lowBatteryThreshold = Double(config.lowBatteryThreshold)
        self.soundEnabled = config.soundEnabled
        self.onChange = onChange
    }

    private func buildConfig() -> AppConfig {
        var c = AppConfig.default
        c.sshTarget = sshTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        c.intervalSeconds = Int(intervalSeconds)
        c.lowBatteryThreshold = Int(lowBatteryThreshold)
        c.soundEnabled = soundEnabled
        c.autostartEnabled = store.load().autostartEnabled // 自启由菜单管理，设置窗口不动它
        return c
    }

    func save() {
        let c = buildConfig()
        store.save(c)
        onChange(c)
        testResult = "已保存并生效"
    }

    func testConnection() {
        let target = sshTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        testing = true
        testResult = "测试中…"
        let reader = SSHBatteryReader(target: target)
        reader.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.testing = false
                switch result {
                case .success(let s):
                    let src = s.source == .ac ? "电源供电" : (s.source == .battery ? "电池供电" : "未知")
                    let pct = s.percent.map { "，电量 \($0)%" } ?? ""
                    self.testResult = "✅ 连接成功：\(src)\(pct)"
                    self.copyableHint = ""
                case .failure:
                    self.testResult = "❌ 连接失败（若从未配置过免密登录，先执行下面命令）"
                    self.copyableHint = "ssh-copy-id \(target)"
                }
            }
        }
    }

    func copyHint() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyableHint, forType: .string)
    }
}

struct SettingsView: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Form {
            Section("远程连接") {
                TextField("SSH 目标（如 ya@192.168.1.50）", text: $vm.sshTarget)
                Button(vm.testing ? "测试中…" : "测试连接") { vm.testConnection() }
                    .disabled(vm.testing || vm.sshTarget.trimmingCharacters(in: .whitespaces).isEmpty)
                if !vm.testResult.isEmpty {
                    Text(vm.testResult).font(.caption)
                }
                if !vm.copyableHint.isEmpty {
                    HStack {
                        Text(vm.copyableHint).font(.caption.monospaced())
                        Button("复制") { vm.copyHint() }
                    }
                    Text("在终端执行该命令把本机公钥装到服务器机，即可免密登录").font(.caption2).foregroundColor(.secondary)
                }
            }
            Section("轮询与告警") {
                Slider(value: $vm.intervalSeconds, in: 15...300, step: 5)
                Text("每 \(Int(vm.intervalSeconds)) 秒检测一次").font(.caption)
                Slider(value: $vm.lowBatteryThreshold, in: 5...50, step: 5)
                Text("电量低于 \(Int(vm.lowBatteryThreshold))% 时告警").font(.caption)
                Toggle("告警声音", isOn: $vm.soundEnabled)
            }
            HStack {
                Spacer()
                Button("保存") { vm.save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 440)
    }
}

final class SettingsWindowController {
    private var window: NSWindow?

    func show(store: SettingsStore, config: AppConfig, onChange: @escaping (AppConfig) -> Void) {
        let vm = SettingsViewModel(store: store, config: config, onChange: onChange)
        if let w = window {
            w.contentView = NSHostingView(rootView: SettingsView(vm: vm))
        } else {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
                             styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = "BattMate 设置"
            w.contentView = NSHostingView(rootView: SettingsView(vm: vm))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
