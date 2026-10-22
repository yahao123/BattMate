// Sources/BattMateCore/AppConfig.swift
import Foundation

public struct AppConfig: Codable, Equatable {
    public var sshTarget: String
    public var intervalSeconds: Int
    public var lowBatteryThreshold: Int
    public var soundEnabled: Bool
    public var autostartEnabled: Bool

    public static let `default` = AppConfig(
        sshTarget: "",
        intervalSeconds: 30,
        lowBatteryThreshold: 20,
        soundEnabled: true,
        autostartEnabled: false
    )
}
