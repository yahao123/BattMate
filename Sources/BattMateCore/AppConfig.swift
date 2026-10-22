// Sources/BattMateCore/AppConfig.swift
import Foundation

public struct AppConfig: Codable, Equatable {
    public var sshTarget: String
    public var intervalSeconds: Int
    public var lowBatteryThreshold: Int
    public var soundEnabled: Bool
    public var autostartEnabled: Bool
    public var tunnels: [TunnelConfig]

    public init(sshTarget: String,
                intervalSeconds: Int,
                lowBatteryThreshold: Int,
                soundEnabled: Bool,
                autostartEnabled: Bool,
                tunnels: [TunnelConfig] = []) {
        self.sshTarget = sshTarget
        self.intervalSeconds = intervalSeconds
        self.lowBatteryThreshold = lowBatteryThreshold
        self.soundEnabled = soundEnabled
        self.autostartEnabled = autostartEnabled
        self.tunnels = tunnels
    }

    public static let `default` = AppConfig(
        sshTarget: "",
        intervalSeconds: 30,
        lowBatteryThreshold: 20,
        soundEnabled: true,
        autostartEnabled: false
    )

    private enum CodingKeys: String, CodingKey {
        case sshTarget, intervalSeconds, lowBatteryThreshold, soundEnabled, autostartEnabled, tunnels
    }

    /// 逐字段容错解码：旧版本 config.json 没有 tunnels 字段时保留其余配置，而不是回落默认。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sshTarget = try c.decodeIfPresent(String.self, forKey: .sshTarget) ?? ""
        intervalSeconds = try c.decodeIfPresent(Int.self, forKey: .intervalSeconds) ?? 30
        lowBatteryThreshold = try c.decodeIfPresent(Int.self, forKey: .lowBatteryThreshold) ?? 20
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        autostartEnabled = try c.decodeIfPresent(Bool.self, forKey: .autostartEnabled) ?? false
        tunnels = try c.decodeIfPresent([TunnelConfig].self, forKey: .tunnels) ?? []
    }
}
