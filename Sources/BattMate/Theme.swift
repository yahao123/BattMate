// Sources/BattMate/Theme.swift
import SwiftUI

enum Palette {
    static let emerald = Color(red: 0.16, green: 0.78, blue: 0.56)
    static let aqua = Color(red: 0.16, green: 0.66, blue: 0.88)
    static let mint = Color(red: 0.40, green: 0.92, blue: 0.76)
    static let amber = Color(red: 0.98, green: 0.64, blue: 0.26)
    static let rose = Color(red: 0.96, green: 0.38, blue: 0.42)
    static let violet = Color(red: 0.62, green: 0.53, blue: 0.96)
}

struct AuroraBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.043, green: 0.071, blue: 0.110),
                       Color(red: 0.055, green: 0.098, blue: 0.149)]
                    : [Color(red: 0.973, green: 0.980, blue: 0.992),
                       Color(red: 0.922, green: 0.953, blue: 0.973)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Palette.mint.opacity(scheme == .dark ? 0.16 : 0.24))
                .frame(width: 440, height: 440)
                .blur(radius: 130)
                .offset(x: -200, y: -280)
            Circle()
                .fill(Palette.aqua.opacity(scheme == .dark ? 0.14 : 0.18))
                .frame(width: 380, height: 380)
                .blur(radius: 120)
                .offset(x: 240, y: -100)
            Circle()
                .fill(Palette.violet.opacity(scheme == .dark ? 0.12 : 0.13))
                .frame(width: 460, height: 460)
                .blur(radius: 150)
                .offset(x: 120, y: 320)
        }
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(scheme == .dark ? 0.15 : 0.75),
                                     Color.white.opacity(scheme == .dark ? 0.03 : 0.22)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.28 : 0.07),
                    radius: 16, x: 0, y: 8)
    }
}

struct SectionHeader: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct InlineBanner: View {
    enum Kind {
        case success, error
    }

    let kind: Kind
    let message: String

    private var tint: Color {
        kind == .success ? Palette.emerald : Palette.rose
    }

    private var icon: String {
        kind == .success ? "checkmark.circle.fill" : "xmark.octagon.fill"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(tint.opacity(0.20), lineWidth: 1)
        )
    }
}

struct SoftDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
    }
}

struct GradientSlider: View {
    let label: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let ratio = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let knobX = min(max(8, width * ratio), width - 8)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: 4)
                Capsule()
                    .fill(
                        LinearGradient(colors: [tint.opacity(0.55), tint],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )
                    .frame(width: knobX, height: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(tint.opacity(0.30), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
                    .position(x: knobX, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let x = min(max(gesture.location.x, 0), width)
                        let raw = range.lowerBound
                            + Double(x / width) * (range.upperBound - range.lowerBound)
                        let stepped = (raw / step).rounded() * step
                        let clamped = min(range.upperBound, max(range.lowerBound, stepped))
                        if clamped != value { value = clamped }
                    }
            )
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(valueText))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(range.upperBound, value + step)
            case .decrement:
                value = max(range.lowerBound, value - step)
            @unknown default:
                break
            }
        }
    }
}

struct PillSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Palette.emerald : Color.primary.opacity(0.14))
                    .frame(width: 34, height: 20)
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .padding(2)
                    .shadow(color: Color.black.opacity(0.18), radius: 1.5, x: 0, y: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.16), value: configuration.isOn)
    }
}

struct GhostButtonStyle: ButtonStyle {    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.aqua)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.aqua.opacity(configuration.isPressed ? 0.20 : 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.aqua.opacity(0.22), lineWidth: 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(
                    LinearGradient(colors: [Palette.emerald, Palette.aqua],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
            )
            .shadow(color: Palette.emerald.opacity(0.32), radius: 10, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1) : 0.5)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
