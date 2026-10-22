// Sources/BattMateCore/PMSetOutputParser.swift
import Foundation

public enum PMSetParserError: Error, Equatable {
    case noSourceLine
}

public enum PMSetOutputParser {
    public static func parse(_ output: String, date: Date = Date()) throws -> PowerSample {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)

        guard let sourceLine = lines.first(where: { $0.contains("Now drawing from '") }) else {
            throw PMSetParserError.noSourceLine
        }
        let source: PowerSource
        if sourceLine.contains("AC Power") {
            source = .ac
        } else if sourceLine.contains("Battery Power") || sourceLine.contains("UPS Power") {
            source = .battery
        } else {
            throw PMSetParserError.noSourceLine
        }

        var percent: Int?
        var status = ChargeStatus.unknown
        var minutes: Int?

        // 电池行：含 NNN% 与分号（桌面机无电池则无此行）
        if let batteryLine = lines.first(where: {
            $0.range(of: #"\d{1,3}%"#, options: .regularExpression) != nil && $0.contains(";")
        }) {
            if let r = batteryLine.range(of: #"\d{1,3}%"#, options: .regularExpression) {
                percent = Int(batteryLine[r].dropLast())
            }
            // 注意 "discharging" 包含 "charging" 子串，判定顺序不能换
            if batteryLine.contains("discharging") {
                status = .discharging
            } else if batteryLine.contains("charged") {
                status = .charged
            } else if batteryLine.contains("charging") {
                status = .charging
            }
            if let r = batteryLine.range(of: #"\d{1,3}:\d{2} remaining"#, options: .regularExpression) {
                let timePart = batteryLine[r].dropLast(" remaining".count)
                let parts = timePart.split(separator: ":")
                if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
                    minutes = h * 60 + m
                }
            }
        }

        return PowerSample(source: source, percent: percent, status: status,
                           minutesRemaining: minutes, timestamp: date)
    }
}
