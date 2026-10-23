// Sources/BattMateWidget/BattMateWidgetUI.swift
import Foundation
import SwiftUI

enum BattMateWidgetSize {
    case small
    case medium
}

struct BattMateWidgetView: View {
    let snapshot: WidgetSnapshot?
    let size: BattMateWidgetSize
    let now: Date

    var body: some View {
        ZStack {
            BattMateWidgetBackground()
            switch size {
            case .small: smallLayout
            case .medium: mediumLayout
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var connectivity: WidgetConnectivity {
        guard let snapshot, !snapshot.target.isEmpty else { return .unconfigured }
        if !snapshot.reachable { return .offline }
        if now.timeIntervalSince(snapshot.updatedAt) > 900 { return .paused }
        return .online
    }

    private var batteryTint: Color {
        guard let percent = snapshot?.batteryPercent else { return .secondary }
        if snapshot?.chargeStatus == "charging" { return WPalette.aqua }
        if percent <= 20 { return WPalette.rose }
        if percent <= 40 { return WPalette.amber }
        return WPalette.emerald
    }

    private var cpuTint: Color {
        guard let cpu = snapshot?.cpuPercent else { return .secondary }
        if cpu >= 85 { return WPalette.rose }
        if cpu >= 60 { return WPalette.amber }
        return WPalette.aqua
    }

    private var batterySubtitle: String {
        guard let snapshot, snapshot.batteryPercent != nil else {
            return snapshot == nil ? "尚未连接" : "无电池数据"
        }
        if snapshot.source == "ac" {
            if snapshot.chargeStatus == "charging" { return "充电中" }
            if snapshot.chargeStatus == "charged" { return "已充满" }
            return "电源供电"
        }
        if snapshot.source == "battery" { return "电池供电" }
        return "未知电源"
    }

    private var batteryDetail: String {
        let base = batterySubtitle
        guard let snapshot, let minutes = snapshot.minutesRemaining, minutes > 0 else { return base }
        if snapshot.chargeStatus == "charging" {
            return "\(base) · \(minutes) 分后充满"
        }
        if snapshot.chargeStatus == "discharging" {
            return "\(base) · 剩余 \(minutes / 60):\(String(format: "%02d", minutes % 60))"
        }
        return base
    }

    private var ageText: String {
        guard let snapshot else { return "等待首次采样" }
        return Self.relativeAge(snapshot.updatedAt, now: now)
    }

    private var targetText: String {
        guard let target = snapshot?.target, !target.isEmpty else { return "尚未配置服务器" }
        return target
    }

    private var accessibilitySummary: String {
        guard let snapshot else { return "BattMate，尚未连接" }
        var parts = ["BattMate", connectivity.label]
        if let battery = snapshot.batteryPercent { parts.append("电量 \(battery)%") }
        parts.append(batterySubtitle)
        if let cpu = snapshot.cpuPercent { parts.append("CPU \(cpu)%") }
        if let memory = snapshot.memoryPercent { parts.append("内存 \(memory)%") }
        parts.append(ageText)
        return parts.joined(separator: "，")
    }

    // MARK: - Small

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                WidgetLogo()
                Text("BattMate")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 3)
                WidgetStatusBadge(connectivity: connectivity, compact: true)
            }

            Spacer(minLength: 7)

            HStack(alignment: .bottom, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    WidgetValue(value: snapshot?.batteryPercent,
                                unit: "%",
                                size: 33,
                                tint: batteryTint)
                    Text(batterySubtitle)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                BatteryGlyph(percent: snapshot?.batteryPercent,
                             charging: snapshot?.chargeStatus == "charging",
                             tint: batteryTint)
            }

            Spacer(minLength: 7)

            HStack(spacing: 6) {
                SmallMetricChip(icon: "cpu", label: "CPU",
                                value: snapshot?.cpuPercent, tint: WPalette.aqua)
                SmallMetricChip(icon: "memorychip", label: "内存",
                                value: snapshot?.memoryPercent, tint: WPalette.violet)
            }
        }
        .padding(13)
        .opacity(snapshot?.reachable == false ? 0.72 : 1)
    }

    // MARK: - Medium

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                WidgetLogo()
                VStack(alignment: .leading, spacing: 0) {
                    Text("BattMate")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text(targetText)
                        .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    WidgetStatusBadge(connectivity: connectivity, compact: false)
                    Text(ageText)
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 9) {
                BatteryCard(percent: snapshot?.batteryPercent,
                            detail: batteryDetail,
                            tint: batteryTint,
                            charging: snapshot?.chargeStatus == "charging")

                TrendCard(icon: "cpu",
                          label: "CPU",
                          value: snapshot?.cpuPercent,
                          tint: cpuTint,
                          history: snapshot?.history.map(\.cpuPercent) ?? [])

                TrendCard(icon: "memorychip",
                          label: "内存",
                          value: snapshot?.memoryPercent,
                          tint: WPalette.violet,
                          history: snapshot?.history.map(\.memoryPercent) ?? [])
            }
        }
        .padding(16)
        .opacity(snapshot?.reachable == false ? 0.72 : 1)
    }

    private static func relativeAge(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 45 { return "刚刚更新" }
        if seconds < 3600 { return "\(max(1, seconds / 60)) 分钟前" }
        if seconds < 86_400 { return "\(seconds / 3600) 小时前" }
        return "\(seconds / 86_400) 天前"
    }
}

// MARK: - Pieces

private enum WPalette {
    static let aqua = Color(red: 0.16, green: 0.66, blue: 0.96)
    static let violet = Color(red: 0.57, green: 0.47, blue: 0.98)
    static let emerald = Color(red: 0.16, green: 0.76, blue: 0.53)
    static let amber = Color(red: 0.98, green: 0.68, blue: 0.24)
    static let rose = Color(red: 0.95, green: 0.35, blue: 0.45)
}

private enum WidgetConnectivity {
    case online
    case paused
    case offline
    case unconfigured

    var label: String {
        switch self {
        case .online: return "在线"
        case .paused: return "已暂停"
        case .offline: return "离线"
        case .unconfigured: return "未配置"
        }
    }

    var color: Color {
        switch self {
        case .online: return WPalette.emerald
        case .paused: return WPalette.amber
        case .offline: return WPalette.rose
        case .unconfigured: return .secondary
        }
    }
}

private struct BattMateWidgetBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: scheme == .dark
                        ? [Color(red: 0.045, green: 0.065, blue: 0.105),
                           Color(red: 0.075, green: 0.115, blue: 0.175)]
                        : [Color(red: 0.975, green: 0.985, blue: 1.0),
                           Color(red: 0.925, green: 0.955, blue: 1.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(WPalette.aqua.opacity(scheme == .dark ? 0.24 : 0.16))
                    .frame(width: 230, height: 230)
                    .blur(radius: 62)
                    .offset(x: -geo.size.width * 0.35, y: -geo.size.height * 0.32)
                Circle()
                    .fill(WPalette.violet.opacity(scheme == .dark ? 0.22 : 0.14))
                    .frame(width: 190, height: 190)
                    .blur(radius: 56)
                    .offset(x: geo.size.width * 0.34, y: geo.size.height * 0.36)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

private struct WidgetLogo: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                .fill(LinearGradient(colors: [WPalette.aqua, WPalette.violet],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .frame(width: 22, height: 22)
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

private struct WidgetStatusBadge: View {
    let connectivity: WidgetConnectivity
    let compact: Bool

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(connectivity.color)
                .frame(width: 4.5, height: 4.5)
            Text(connectivity.label)
                .font(.system(size: compact ? 8 : 8.5, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(connectivity.color)
        .padding(.horizontal, compact ? 5 : 6.5)
        .padding(.vertical, compact ? 2.5 : 3)
        .background(Capsule().fill(connectivity.color.opacity(0.13)))
    }
}

private struct WidgetValue: View {
    let value: Int?
    let unit: String
    let size: CGFloat
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(value.map(String.init) ?? "—")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
            if value != nil {
                Text(unit)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(value == nil ? Color.secondary : tint)
    }
}

private struct SmallMetricChip: View {
    let icon: String
    let label: String
    let value: Int?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(value.map { "\($0)%" } ?? "—")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(value == nil ? Color.secondary : Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
    }
}

private struct BatteryGlyph: View {
    let percent: Int?
    let charging: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .stroke(Color.primary.opacity(0.22), lineWidth: 1.2)
                    .frame(width: 34, height: 16)
                if let percent {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(tint)
                        .frame(width: max(2, 29 * CGFloat(percent) / 100), height: 11)
                        .padding(.leading, 2.5)
                }
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34)
                }
            }
            Capsule()
                .fill(Color.primary.opacity(0.22))
                .frame(width: 2, height: 6)
        }
        .frame(width: 37, height: 16)
        .accessibilityHidden(true)
    }
}

private struct BatteryCard: View {
    let percent: Int?
    let detail: String
    let tint: Color
    let charging: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: charging ? "battery.100percent.bolt" : "battery.75")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                Text("电量")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            WidgetValue(value: percent, unit: "%", size: 25, tint: tint)
            Spacer(minLength: 4)
            WidgetBar(percent: percent, tint: tint)
            Text(detail)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(10)
        .background(cardBackground(tint))
    }
}

private struct TrendCard: View {
    let icon: String
    let label: String
    let value: Int?
    let tint: Color
    let history: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            WidgetValue(value: value, unit: "%", size: 25, tint: tint)
            Spacer(minLength: 4)
            WidgetSparkline(values: history, tint: tint)
                .frame(height: 19)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(10)
        .background(cardBackground(tint))
    }
}

private func cardBackground(_ tint: Color) -> some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.primary.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 0.8)
        )
}

private struct WidgetBar: View {
    let percent: Int?
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.55), tint],
                                         startPoint: .leading,
                                         endPoint: .trailing))
                    .frame(width: percent.map { max(3, geo.size.width * CGFloat(min(100, max(0, $0))) / 100) } ?? 0)
            }
        }
        .frame(height: 4)
    }
}

private struct WidgetSparkline: View {
    let values: [Int]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let points = coordinates(in: geo.size)
            ZStack {
                if points.count >= 2 {
                    area(points, height: geo.size.height)
                        .fill(
                            LinearGradient(colors: [tint.opacity(0.24), tint.opacity(0.01)],
                                           startPoint: .top,
                                           endPoint: .bottom)
                        )
                    line(points)
                        .stroke(tint.opacity(0.9),
                                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                } else {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
        }
    }

    private func coordinates(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let upper = max(20, values.max() ?? 20)
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let y = size.height - CGFloat(min(100, max(0, value))) / CGFloat(upper) * size.height
            return CGPoint(x: CGFloat(index) * step, y: y)
        }
    }

    private func line(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
        }
    }

    private func area(_ points: [CGPoint], height: CGFloat) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: height))
            path.addLine(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.addLine(to: CGPoint(x: last.x, y: height))
            path.closeSubpath()
        }
    }
}
