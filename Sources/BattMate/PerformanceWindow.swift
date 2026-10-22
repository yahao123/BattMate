// Sources/BattMate/PerformanceWindow.swift
import SwiftUI
import AppKit

enum PerformanceMetric: String, CaseIterable, Identifiable {
    case cpu, memory

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "内存"
        }
    }

    var title: String {
        switch self {
        case .cpu: return "CPU 使用率"
        case .memory: return "内存使用率"
        }
    }

    var icon: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        }
    }

    var tint: Color {
        switch self {
        case .cpu: return Palette.aqua
        case .memory: return Palette.violet
        }
    }

    func value(in point: MetricsPoint) -> Int {
        switch self {
        case .cpu: return point.cpuPercent
        case .memory: return point.memoryPercent
        }
    }
}

final class PerformanceViewModel: ObservableObject {
    static let processLimit = 10

    @Published private(set) var selected: PerformanceMetric
    @Published private(set) var history: [MetricsPoint]
    @Published private(set) var processes: [TopProcess] = []
    @Published private(set) var error: String?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var loading = false

    let target: String
    private let reader: TopProcessReader
    private let historyStore: MetricsHistoryStore
    private var timer: Timer?
    private var inFlight = false

    init(target: String, focus: PerformanceMetric, historyStore: MetricsHistoryStore) {
        self.target = target
        self.selected = focus
        self.historyStore = historyStore
        self.history = historyStore.points
        self.reader = TopProcessReader(target: target)
    }

    var currentValue: Int? {
        history.last.map { selected.value(in: $0) }
    }

    var spanText: String {
        guard let first = history.first, let last = history.last, history.count > 1 else {
            return "刚开始"
        }
        let minutes = Int(last.timestamp.timeIntervalSince(first.timestamp) / 60)
        if minutes < 60 { return "近 \(max(1, minutes)) 分钟" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "近 \(hours) 小时" : "近 \(hours) 小时 \(rest) 分"
    }

    func select(_ metric: PerformanceMetric) {
        selected = metric
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
        refreshHistory()
        refreshProcesses()
    }

    private func refreshHistory() {
        let latest = historyStore.points
        if latest != history { history = latest }
    }

    func refreshProcesses() {
        guard !inFlight else { return }
        inFlight = true
        loading = true
        reader.fetch(limit: Self.processLimit) { [weak self] result in
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

struct PerformanceView: View {
    @ObservedObject var vm: PerformanceViewModel

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
                ScrollView {
                    HStack(alignment: .top, spacing: 14) {
                        trendCard
                            .frame(maxWidth: .infinity)
                        topCard
                            .frame(width: 350)
                    }
                    .padding(.horizontal, 26)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
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
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("服务器性能")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text("\(vm.target) · 本地保留最近趋势")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: vm.refreshProcesses) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(vm.loading ? "读取中" : "刷新 Top")
                }
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(vm.loading)
        }
        .padding(.horizontal, 26)
        .padding(.top, 42)
        .padding(.bottom, 16)
    }

    private var trendCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Text("资源趋势")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer()
                    metricPicker
                }

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(vm.currentValue.map { "\($0)%" } ?? "—")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(vm.selected.tint)
                    Text(vm.selected.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(vm.spanText)
                        Text("\(vm.history.count) 个采样")
                    }
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                }

                TrendChart(points: vm.history, metric: vm.selected)
                    .frame(height: 236)

                HStack {
                    Text("64 KB 上限 · 超出后剔除最旧")
                    Spacer()
                    Text("约 6000 条 · 30 秒采样")
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var metricPicker: some View {
        HStack(spacing: 2) {
            ForEach(PerformanceMetric.allCases) { metric in
                Button {
                    vm.select(metric)
                } label: {
                    Text(metric.label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(vm.selected == metric ? Color.white : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4.5)
                        .background(
                            Capsule().fill(vm.selected == metric ? metric.tint : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看\(metric.title)趋势")
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private var topCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Text("CPU Top \(PerformanceViewModel.processLimit)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer()
                    if vm.loading {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Palette.aqua)
                    }
                    Text("每 5 秒")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }

                if let error = vm.error {
                    InlineBanner(kind: .error, message: "进程读取失败：\(error)")
                }

                HStack(spacing: 8) {
                    Text("#").frame(width: 14, alignment: .leading)
                    Text("进程").frame(maxWidth: .infinity, alignment: .leading)
                    Text("CPU").frame(width: 64, alignment: .trailing)
                    Text("内存").frame(width: 38, alignment: .trailing)
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)

                SoftDivider()

                if vm.processes.isEmpty {
                    Group {
                        if vm.loading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Palette.aqua)
                        } else {
                            Text("暂无进程数据")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 250)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(vm.processes.enumerated()), id: \.offset) { index, process in
                            processRow(index: index, process: process)
                        }
                    }
                }
            }
        }
    }

    private func processRow(index: Int, process: TopProcess) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(rankColor(index))
                .frame(width: 14, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                Text(process.name)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("PID \(String(process.pid))")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f%%", process.cpuPercent))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(cpuTint(process.cpuPercent))
                ZStack(alignment: .trailing) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 44, height: 2)
                    Capsule()
                        .fill(cpuTint(process.cpuPercent))
                        .frame(width: max(2, 44 * min(1, process.cpuPercent / 100)), height: 2)
                }
            }
            .frame(width: 64, alignment: .trailing)

            Text(String(format: "%.1f%%", process.memoryPercent))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.vertical, 5.5)
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
                Text("进程刷新失败：\(error)")
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
            Text("历史数据仅存于本机")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 10))
        .padding(.horizontal, 26)
        .padding(.top, 2)
        .padding(.bottom, 18)
    }
}

private struct TrendChart: View {
    let points: [MetricsPoint]
    let metric: PerformanceMetric

    private static let minuteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .trailing) {
                    Text("100")
                    Spacer()
                    Text("50")
                    Spacer()
                    Text("0")
                }
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 22)
                .padding(.bottom, 1)

                GeometryReader { geo in
                    chart(in: geo.size)
                }
            }

            HStack {
                Text(timeLabel(points.first))
                Spacer()
                Text(timeLabel(points.last))
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.leading, 30)
        }
    }

    private func chart(in size: CGSize) -> some View {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let tint = metric.tint
        let coordinates = normalizedCoordinates(width: width, height: height)
        let last = coordinates.last

        return ZStack {
            ForEach(0..<3, id: \.self) { index in
                let y = height * CGFloat(index) / 2
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
                .stroke(Color.primary.opacity(index == 2 ? 0.10 : 0.06),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }

            if coordinates.count >= 2 {
                areaPath(coordinates, height: height)
                    .fill(
                        LinearGradient(colors: [tint.opacity(0.26), tint.opacity(0.01)],
                                       startPoint: .top,
                                       endPoint: .bottom)
                    )
                linePath(coordinates)
                    .stroke(
                        LinearGradient(colors: [tint.opacity(0.45), tint],
                                       startPoint: .leading,
                                       endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
            }

            if let last {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                    .shadow(color: tint.opacity(0.55), radius: 5)
                    .position(last)
            }

            if points.isEmpty {
                Text("正在积累采样…")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func normalizedCoordinates(width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard let first = points.first, let last = points.last else { return [] }
        let start = first.timestamp.timeIntervalSince1970
        let span = max(1, last.timestamp.timeIntervalSince1970 - start)
        let inset: CGFloat = 4
        let drawable = max(1, width - inset * 2)
        return points.map { point in
            let x = inset + CGFloat((point.timestamp.timeIntervalSince1970 - start) / span) * drawable
            let y = height - CGFloat(metric.value(in: point)) / 100 * height
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(_ coordinates: [CGPoint]) -> Path {
        Path { path in
            guard let first = coordinates.first else { return }
            path.move(to: first)
            for point in coordinates.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func areaPath(_ coordinates: [CGPoint], height: CGFloat) -> Path {
        Path { path in
            guard let first = coordinates.first, let last = coordinates.last else { return }
            path.move(to: CGPoint(x: first.x, y: height))
            path.addLine(to: first)
            for point in coordinates.dropFirst() {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: last.x, y: height))
            path.closeSubpath()
        }
    }

    private func timeLabel(_ point: MetricsPoint?) -> String {
        guard let point else { return "--:--" }
        return Self.minuteFormatter.string(from: point.timestamp)
    }
}

final class PerformanceWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var viewModel: PerformanceViewModel?

    func show(target: String, focus: PerformanceMetric, history: MetricsHistoryStore) {
        viewModel?.stop()
        let vm = PerformanceViewModel(target: target, focus: focus, historyStore: history)
        viewModel = vm

        if let w = window {
            w.contentView = NSHostingView(rootView: PerformanceView(vm: vm))
        } else {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.title = "服务器性能"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.titlebarSeparatorStyle = .none
            w.isMovableByWindowBackground = true
            w.backgroundColor = .clear
            w.isOpaque = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: PerformanceView(vm: vm))
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
