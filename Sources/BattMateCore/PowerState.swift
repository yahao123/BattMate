// Sources/BattMateCore/PowerState.swift
import Foundation

public enum PowerSource: String, Codable, Equatable {
    case ac
    case battery
    case unknown
}

public enum ChargeStatus: String, Codable, Equatable {
    case charging
    case discharging
    case charged
    case unknown
}

public struct PowerSample: Codable, Equatable {
    public var source: PowerSource
    public var percent: Int?
    public var status: ChargeStatus
    public var minutesRemaining: Int?
    public var usage: SystemUsage?
    public var timestamp: Date

    public init(source: PowerSource, percent: Int?, status: ChargeStatus,
                minutesRemaining: Int?, usage: SystemUsage? = nil, timestamp: Date = Date()) {
        self.source = source
        self.percent = percent
        self.status = status
        self.minutesRemaining = minutesRemaining
        self.usage = usage
        self.timestamp = timestamp
    }

    public var remainingText: String {
        guard let m = minutesRemaining else { return "无估计" }
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}

public enum FetchResult: Equatable {
    case success(PowerSample)
    case failure(String)
}
