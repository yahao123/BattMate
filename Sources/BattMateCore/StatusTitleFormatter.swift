// Sources/BattMateCore/StatusTitleFormatter.swift
import AppKit

public enum StatusTitleFormatter {
    public static func title(sample: PowerSample?, failureStreak: Int) -> (text: String, color: NSColor) {
        if let s = sample {
            switch s.source {
            case .ac:
                return ("⚡\(s.percent.map(String.init) ?? "--")", .systemGreen)
            case .battery:
                return ("🔋\(s.percent.map(String.init) ?? "--")", .systemOrange)
            case .unknown:
                return ("·--", .systemGray)
            }
        }
        if failureStreak > 0 {
            return ("⚠︎--", .systemGray)
        }
        return ("…", .systemGray)
    }
}
