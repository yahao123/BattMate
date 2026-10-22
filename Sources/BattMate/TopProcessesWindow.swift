// Sources/BattMate/TopProcessesWindow.swift
import SwiftUI
import AppKit

final class TopProcessesViewModel: ObservableObject {
    static let limit = 10

    @Published private(set) var processes: [TopProcess] = []
    @Published private(set) var error: String?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var loading = false

    let target: String
    private let reader: TopProcessReader
    private var timer: Timer?
    private var inFlight = false

    init(target: String) {
        self.target = target
        self.reader = TopProcessReader(target: target)
    }

    func start() {
        stop()
        refresh()
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !inFlight else { return }
        inFlight = true
        loading = true
        reader.fetch(limit: Self.limit) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                self.loading = false
                switch result {
                case .success(let processes):
                    self.processes = processes
                    self.error = nil
                    self.updatedAt = Date()
                case .failure(let failure):
                    self.error = failure.message
                }
            }
        }
    }
}

struct TopProcessesView: View {
    @ObservedObject var vm: TopProcessesViewModel

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 0) {
                header
                content
                footer
            }
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Palette.aqua, Palette.violet],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
                    .frame(width: 38, height: 38)
                    .shadow(color: Palette.aqua.opacity(0.30), radius: 10, x: 0, y: 4)
                Image(systemName: "cpu")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("CPU 占用 Top \(TopProcessesViewModel.limit)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("\(vm.target) · 每 5 秒自动刷新")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: vm.refresh) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(vm.loading ? "读取中" : "刷新")
                }
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(vm.loading)
        }
        .padding(.horizontal, 24)
        .padding(.top, 42)
        .padding(.bottom, 16)
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let error = vm.error {
                    InlineBanner(kind: .error, message: "读取失败：\(error)")
                }

                if vm.processes.isEmpty {
                    if vm.loading {
                        VStack(spacing: 9) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Palette.aqua)
                            Text("正在读取服务器进程…")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        Text("暂无进程数据")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 260)
                    }
                } else {
                    GlassCard {
                        processList
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    private var processList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("#").frame(width: 18, alignment: .leading)
                Text("进程").frame(maxWidth: .infinity, alignment: .leading)
                Text("CPU").frame(width: 108, alignment: .trailing)
                Text("内存").frame(width: 46, alignment: .trailing)
            }
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)

            SoftDivider()
                .padding(.vertical, 8)

            let maxCPU = max(10, vm.processes.map(\.cpuPercent).max() ?? 10)
            ForEach(Array(vm.processes.enumerated()), id: \.offset) { index, process in
                processRow(index: index, process: process, maxCPU: maxCPU)
                if index < vm.processes.count - 1 {
                    SoftDivider()
                        .padding(.leading, 28)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func processRow(index: Int, process: TopProcess, maxCPU: Double) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(rankColor(index))
                .frame(width: 18, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(process.name)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("PID \(String(process.pid))")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(cpuTint(process.cpuPercent))
                            .frame(width: max(2, geo.size.width * min(1, process.cpuPercent / maxCPU)))
                    }
                }
                .frame(width: 50, height: 4)

                Text(String(format: "%.1f%%", process.cpuPercent))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(cpuTint(process.cpuPercent))
                    .frame(width: 48, alignment: .trailing)
            }
            .frame(width: 108, alignment: .trailing)

            Text(String(format: "%.1f%%", process.memoryPercent))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(index + 1). \(process.name)，PID \(process.pid)，CPU \(String(format: "%.1f", process.cpuPercent))%，内存 \(String(format: "%.1f", process.memoryPercent))%"))
    }

    private func rankColor(_ index: Int) -> Color {
        switch index {
        case 0: return Palette.amber
        case 1: return Palette.aqua
        case 2: return Palette.violet
        default: return Color.secondary.opacity(0.55)
        }
    }

    private func cpuTint(_ value: Double) -> Color {
        if value >= 50 { return Palette.rose }
        if value >= 20 { return Palette.amber }
        return Palette.aqua
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(vm.error == nil ? Palette.emerald : Palette.amber)
                .frame(width: 6, height: 6)
            if let error = vm.error {
                Text("刷新失败：\(error)")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            } else if let updatedAt = vm.updatedAt {
                Text("最后更新 \(Self.timeFormatter.string(from: updatedAt))")
                    .foregroundStyle(.secondary)
            } else {
                Text("等待首次采样…")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("数据来自 ps -r")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 10))
        .padding(.horizontal, 26)
        .padding(.top, 2)
        .padding(.bottom, 18)
    }
}

final class TopProcessesWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var viewModel: TopProcessesViewModel?

    func show(target: String) {
        viewModel?.stop()
        let vm = TopProcessesViewModel(target: target)
        viewModel = vm

        if let w = window {
            w.contentView = NSHostingView(rootView: TopProcessesView(vm: vm))
        } else {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.title = "服务器进程"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.titlebarSeparatorStyle = .none
            w.isMovableByWindowBackground = true
            w.backgroundColor = .clear
            w.isOpaque = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: TopProcessesView(vm: vm))
            w.center()
            window = w
        }

        vm.start()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        viewModel?.stop()
    }

    func close() {
        viewModel?.stop()
        window?.close()
    }
}
