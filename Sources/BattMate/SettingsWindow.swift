// Sources/BattMate/SettingsWindow.swift
import SwiftUI
import AppKit

struct TunnelRow: Identifiable, Equatable {
    let id: UUID
    var localPort: String
    var remotePort: String
    var enabled: Bool

    init(id: UUID = UUID(), localPort: String = "", remotePort: String = "", enabled: Bool = true) {
        self.id = id
        self.localPort = localPort
        self.remotePort = remotePort
        self.enabled = enabled
    }

    init(config: TunnelConfig) {
        self.init(id: config.id,
                  localPort: String(config.localPort),
                  remotePort: String(config.remotePort),
                  enabled: config.enabled)
    }
}

enum ConnectionTestOutcome: Equatable {
    case success(String)
    case failure(String)
}

final class SettingsViewModel: ObservableObject {
    static let autosshInstallCommand = "brew install autossh"

    @Published var sshTarget: String
    @Published var intervalSeconds: Double
    @Published var lowBatteryThreshold: Double
    @Published var soundEnabled: Bool
    @Published var tunnelRows: [TunnelRow]
    @Published var testOutcome: ConnectionTestOutcome?
    @Published var testing = false
    @Published var copyableHint: String = ""
    @Published var tunnelError: String = ""
    @Published var saveMessage: String = ""
    @Published var saveSucceeded = false

    private let store: SettingsStore
    private let onChange: (AppConfig) -> Void
    let autosshPath: String?

    init(store: SettingsStore, config: AppConfig, onChange: @escaping (AppConfig) -> Void) {
        self.store = store
        self.sshTarget = config.sshTarget
        self.intervalSeconds = Double(config.intervalSeconds)
        self.lowBatteryThreshold = Double(config.lowBatteryThreshold)
        self.soundEnabled = config.soundEnabled
        self.tunnelRows = config.tunnels.map(TunnelRow.init(config:))
        self.autosshPath = AutosshBinary.resolve()
        self.onChange = onChange
    }

    var autosshHint: String {
        if let autosshPath {
            return "autossh：\(autosshPath)"
        }
        return "未找到 autossh，请先在终端执行：\(Self.autosshInstallCommand)"
    }

    var autosshAvailable: Bool { autosshPath != nil }

    func addTunnel() {
        tunnelRows.append(TunnelRow())
        tunnelError = ""
    }

    func removeTunnel(_ id: UUID) {
        tunnelRows.removeAll { $0.id == id }
        tunnelError = ""
    }

    private func buildConfig() -> AppConfig? {
        var tunnels: [TunnelConfig] = []
        for (index, row) in tunnelRows.enumerated() {
            let label = "第 \(index + 1) 条映射"
            guard let local = Int(row.localPort.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let remote = Int(row.remotePort.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                tunnelError = "\(label)端口必须是数字"
                return nil
            }
            tunnels.append(TunnelConfig(id: row.id, localPort: local, remotePort: remote, enabled: row.enabled))
        }

        let errors = TunnelValidator.errors(for: tunnels)
        guard errors.isEmpty else {
            tunnelError = errors.joined(separator: "\n")
            return nil
        }
        tunnelError = ""

        var c = AppConfig.default
        c.sshTarget = sshTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        c.intervalSeconds = Int(intervalSeconds)
        c.lowBatteryThreshold = Int(lowBatteryThreshold)
        c.soundEnabled = soundEnabled
        c.autostartEnabled = store.load().autostartEnabled // 自启由菜单管理，设置窗口不动它
        c.tunnels = tunnels
        return c
    }

    func save() {
        guard let c = buildConfig() else {
            saveSucceeded = false
            saveMessage = "配置有误，暂未保存"
            return
        }
        store.save(c)
        onChange(c)
        saveSucceeded = true
        saveMessage = "已保存并生效"
        let message = saveMessage
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            guard let self, self.saveMessage == message else { return }
            self.saveMessage = ""
        }
    }

    func testConnection() {
        let target = sshTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        testing = true
        testOutcome = nil
        copyableHint = ""
        let reader = SSHBatteryReader(target: target)
        reader.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.testing = false
                switch result {
                case .success(let s):
                    let src = s.source == .ac ? "电源供电" : (s.source == .battery ? "电池供电" : "未知")
                    let pct = s.percent.map { " · 电量 \($0)%" } ?? ""
                    self.testOutcome = .success("连接成功 · \(src)\(pct)")
                    self.copyableHint = ""
                case .failure(let msg):
                    self.testOutcome = .failure("连接失败：\(msg)")
                    self.copyableHint = "ssh-copy-id \(target)"
                }
            }
        }
    }

    func copyHint() {
        copy(copyableHint)
    }

    func copyAutosshInstall() {
        copy(Self.autosshInstallCommand)
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case connection, tunnels, alerts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection: return "远程连接"
        case .tunnels: return "SSH 隧道"
        case .alerts: return "轮询与告警"
        }
    }

    var subtitle: String {
        switch self {
        case .connection: return "通过 SSH 读取服务器机的实时电源状态"
        case .tunnels: return "把服务器端口映射到本机，保存后自动连接"
        case .alerts: return "调整检测频率、低电量阈值与提示音"
        }
    }

    var icon: String {
        switch self {
        case .connection: return "antenna.radiowaves.left.and.right"
        case .tunnels: return "network"
        case .alerts: return "bell.badge"
        }
    }

    var tint: Color {
        switch self {
        case .connection: return Palette.aqua
        case .tunnels: return Palette.violet
        case .alerts: return Palette.amber
        }
    }
}

struct SettingsView: View {
    @ObservedObject var vm: SettingsViewModel
    @State private var selection: SettingsSection

    init(vm: SettingsViewModel) {
        self.vm = vm
        _selection = State(initialValue: vm.tunnelRows.isEmpty ? .connection : .tunnels)
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            HStack(spacing: 0) {
                sidebar
                detail
            }
        }
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(colors: [Palette.mint, Palette.aqua],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                        )
                        .frame(width: 38, height: 38)
                        .shadow(color: Palette.emerald.opacity(0.30), radius: 10, x: 0, y: 4)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("BattMate")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("电量守护 · 隧道管家")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 44)
            .padding(.bottom, 24)

            VStack(spacing: 3) {
                ForEach(SettingsSection.allCases) { section in
                    SidebarButton(section: section, selected: selection == section) {
                        withAnimation(.easeOut(duration: 0.16)) {
                            selection = section
                        }
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                autosshBadge
                Text(vm.autosshAvailable ? "隧道守护已启用" : "安装 autossh 后即可建立隧道")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(width: 206)
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(width: 1)
        }
    }

    private var autosshBadge: some View {
        let ok = vm.autosshAvailable
        let tint = ok ? Palette.emerald : Palette.amber
        return HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(ok ? "autossh 就绪" : "缺少 autossh")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.12)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.24), lineWidth: 1))
        .help(vm.autosshHint)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selection.title)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                    Text(selection.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selection.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selection.tint)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selection.tint.opacity(0.12))
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 26)
            .padding(.top, 40)
            .padding(.bottom, 16)

            ScrollView {
                content
                    .padding(.horizontal, 26)
                    .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .connection:
            connectionCard
        case .tunnels:
            tunnelCard
        case .alerts:
            pollingCard
        }
    }

    private var connectionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SSH 目标")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            TextField("user@host", text: $vm.sshTarget)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .onSubmit { vm.testConnection() }
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )

                        Button {
                            vm.testConnection()
                        } label: {
                            HStack(spacing: 6) {
                                if vm.testing {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "bolt.horizontal.fill")
                                }
                                Text(vm.testing ? "测试中" : "测试连接")
                            }
                            .frame(minWidth: 80)
                        }
                        .buttonStyle(GhostButtonStyle())
                        .disabled(vm.testing || vm.sshTarget.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                testBanner

                if !vm.copyableHint.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal")
                            .font(.system(size: 11, weight: .medium))
                        Text(vm.copyableHint)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button {
                            vm.copyHint()
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.aqua)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .foregroundStyle(.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.primary.opacity(0.045))
                    )

                    Text("在终端执行上面的命令安装公钥，之后即可免密登录。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Text("测试会读取一次服务器电源状态，成功即代表免密登录可用。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var testBanner: some View {
        if let outcome = vm.testOutcome {
            switch outcome {
            case .success(let message):
                InlineBanner(kind: .success, message: message)
            case .failure(let message):
                InlineBanner(kind: .error, message: message)
            }
        }
    }

    private var tunnelCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                if vm.tunnelRows.isEmpty {
                    emptyTunnelHint
                } else {
                    VStack(spacing: 8) {
                        ForEach($vm.tunnelRows) { $row in
                            TunnelRowView(row: $row,
                                          index: (vm.tunnelRows.firstIndex(of: row) ?? 0) + 1,
                                          onDelete: { vm.removeTunnel(row.id) })
                        }
                    }
                }

                AddTunnelButton { vm.addTunnel() }

                if !vm.tunnelError.isEmpty {
                    InlineBanner(kind: .error, message: vm.tunnelError)
                }

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("本机监听 127.0.0.1:<本机端口>，转发到服务器的 127.0.0.1:<服务器端口>")
                        .lineLimit(1)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Image(systemName: vm.autosshAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(vm.autosshAvailable ? Palette.emerald : Palette.amber)
                    Text(vm.autosshHint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    if !vm.autosshAvailable {
                        Button("复制命令") { vm.copyAutosshInstall() }
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.amber)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyTunnelHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.violet)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Palette.violet.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text("还没有端口映射")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text("添加一条映射，保存后自动建立隧道")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var pollingCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SettingSliderRow(icon: "clock",
                                 title: "检测频率",
                                 value: "每 \(Int(vm.intervalSeconds)) 秒",
                                 tint: Palette.aqua,
                                 amount: $vm.intervalSeconds,
                                 range: 15...300,
                                 step: 5)

                SoftDivider()

                SettingSliderRow(icon: "battery.25",
                                 title: "低电量告警",
                                 value: "≤ \(Int(vm.lowBatteryThreshold))%",
                                 tint: Palette.amber,
                                 amount: $vm.lowBatteryThreshold,
                                 range: 5...50,
                                 step: 5)

                SoftDivider()

                HStack(spacing: 10) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.amber)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Palette.amber.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("告警声音")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("充电器断开、低电量等事件播放提示音")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $vm.soundEnabled)
                        .labelsHidden()
                        .toggleStyle(PillSwitchStyle())
                        .accessibilityLabel("告警声音")
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Group {
                if vm.saveMessage.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                        Text("更改在保存后立即生效")
                    }
                    .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: vm.saveSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        Text(vm.saveMessage)
                    }
                    .foregroundStyle(vm.saveSucceeded ? Palette.emerald : Palette.rose)
                }
            }
            .font(.system(size: 11, weight: .medium))

            Spacer()

            Button {
                vm.save()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                    Text("保存设置")
                }
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)
        }
    }
}

private struct SidebarButton: View {
    let section: SettingsSection
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: section.icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(selected ? section.tint : Color.secondary)
                    .frame(width: 18)
                Text(section.title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? section.tint.opacity(0.12) : Color.primary.opacity(hovering ? 0.04 : 0.001))
            )
            .overlay(alignment: .leading) {
                if selected {
                    Capsule()
                        .fill(section.tint)
                        .frame(width: 2.5, height: 14)
                        .offset(x: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

private struct TunnelRowView: View {
    @Binding var row: TunnelRow
    let index: Int
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $row.enabled)
                .labelsHidden()
                .toggleStyle(PillSwitchStyle())
                .accessibilityLabel("启用映射 \(index)")
                .help(row.enabled ? "停用后不再为此映射启动 autossh" : "启用后保存即自动连接")

            VStack(alignment: .leading, spacing: 3) {
                Text("映射 \(index)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                HStack(spacing: 4) {
                    Circle()
                        .fill(row.enabled ? Palette.emerald : Color.secondary.opacity(0.4))
                        .frame(width: 5, height: 5)
                    Text(row.enabled ? "自动连接" : "已停用")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)

            PortField(caption: "本机", text: portBinding($row.localPort))
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.55))
            PortField(caption: "服务器", text: portBinding($row.remotePort))

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hovering ? Palette.rose : Color.secondary.opacity(0.75))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除映射 \(index)")
            .help("删除这条映射")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.065 : 0.038))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(hovering ? 0.10 : 0.06), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }

    private func portBinding(_ source: Binding<String>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue },
            set: { source.wrappedValue = String($0.filter(\.isNumber).prefix(5)) }
        )
    }
}

private struct PortField: View {
    let caption: String
    @Binding var text: String

    var body: some View {
        VStack(spacing: 2) {
            Text(caption)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(width: 60)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .help("\(caption)端口（1–65535）")
    }
}

private struct AddTunnelButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                Text("添加端口映射")
            }
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.aqua)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Palette.aqua.opacity(hovering ? 0.13 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Palette.aqua.opacity(hovering ? 0.45 : 0.28),
                                  style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private struct SettingSliderRow: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color
    @Binding var amount: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Spacer()
                Text(value)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tint.opacity(0.12)))
            }
            GradientSlider(label: title, valueText: value, value: $amount, range: range, step: step, tint: tint)
        }
    }
}

final class SettingsWindowController {
    private var window: NSWindow?

    func show(store: SettingsStore, config: AppConfig, onChange: @escaping (AppConfig) -> Void) {
        let vm = SettingsViewModel(store: store, config: config, onChange: onChange)
        if let w = window {
            w.contentView = NSHostingView(rootView: SettingsView(vm: vm))
        } else {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false // 控制器强引用并复用该窗口，关闭时不能让 AppKit 释放
            w.title = "BattMate 设置"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.titlebarSeparatorStyle = .none
            w.isMovableByWindowBackground = true
            w.backgroundColor = .clear
            w.isOpaque = false
            w.contentView = NSHostingView(rootView: SettingsView(vm: vm))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
