// Sources/BattMateCore/StatusTitleFormatter.swift
import AppKit

public enum StatusTitleFormatter {
    public static func title(sample: PowerSample?, failureStreak: Int) -> (text: String, color: NSColor) {
        // 失联优先判定：连续失败时在途样例只是上次成功的过期数据，
        // 图标必须置灰告警，不能沿用旧健康状态误导用户
        if failureStreak > 0 {
            return ("⚠︎--", .systemGray)
        }
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
        return ("…", .systemGray)
    }
}
