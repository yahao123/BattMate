// Sources/BattMateCore/AlertEngine.swift
import Foundation

public struct AlertDecision: Equatable {
    public enum Kind: Equatable {
        case chargerLost, lowBattery, chargingResumed, unreachable, reachableAgain
    }
    public let kind: Kind
    public let title: String
    public let body: String

    public init(kind: Kind, title: String, body: String) {
        self.kind = kind
        self.title = title
        self.body = body
    }
}

public final class AlertEngine {
    public private(set) var consecutiveFailures = 0
    private var hasBaseline = false
    private var lastSource: PowerSource?
    /// 已确认（提交）的源就是 lastSource；新源需连续 2 个样例才提交，
    /// 防止接触不良导致 AC↔电池反复抖动引发告警风暴
    private var candidateSource: PowerSource?
    private var candidateCount = 0
    private var deliveredLowBattery = false
    private var deliveredUnreachable = false

    public init() {}

    public func evaluate(_ result: FetchResult, lowBatteryThreshold: Int) -> [AlertDecision] {
        switch result {
        case .failure(let reason):
            consecutiveFailures += 1
            if consecutiveFailures >= 3 && !deliveredUnreachable {
                deliveredUnreachable = true
                return [AlertDecision(kind: .unreachable, title: "⚫ SSH 不可达",
                                      body: "连续 3 次连接失败：\(reason)")]
            }
            return []

        case .success(let s):
            consecutiveFailures = 0
            if !hasBaseline {
                hasBaseline = true
                lastSource = s.source
                return []
            }
            var out: [AlertDecision] = []
            if deliveredUnreachable {
                deliveredUnreachable = false
                out.append(AlertDecision(kind: .reachableAgain, title: "🟢 连接已恢复", body: "SSH 重新可达"))
            }
            if s.source == lastSource {
                // 与已提交源一致：抖动结束，重置候选
                candidateSource = nil
                candidateCount = 0
            } else if s.source == candidateSource {
                candidateCount += 1
            } else {
                candidateSource = s.source
                candidateCount = 1
            }
            // 连续 2 个新源样例：确认切换并提交
            if candidateCount >= 2, let confirmed = candidateSource {
                if lastSource == .ac && confirmed == .battery {
                    let pct = s.percent.map { "，电量 \($0)%" } ?? ""
                    out.append(AlertDecision(kind: .chargerLost, title: "🔴 充电器已断开",
                                             body: "服务器机已切换为电池供电\(pct)"))
                }
                if lastSource == .battery && confirmed == .ac {
                    deliveredLowBattery = false
                    out.append(AlertDecision(kind: .chargingResumed, title: "🟢 已恢复充电",
                                             body: "服务器机重新接入电源"))
                }
                lastSource = confirmed
                candidateSource = nil
                candidateCount = 0
            }
            // 低电量检查只针对已提交的电池源（防抖期间静默，保证与 chargerLost 同评估成对出现）
            if lastSource == .battery && s.source == .battery,
               let pct = s.percent, pct <= lowBatteryThreshold, !deliveredLowBattery {
                deliveredLowBattery = true
                out.append(AlertDecision(kind: .lowBattery, title: "🟠 电量偏低",
                                         body: "服务器机电量仅剩 \(pct)%，请尽快接通电源"))
            }
            return out
        }
    }
}
