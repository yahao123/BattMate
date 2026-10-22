// Sources/BattMateCore/Notifier.swift
import Foundation
import AppKit
import UserNotifications

public protocol Notifying {
    func deliver(title: String, body: String, sound: Bool)
}

/// osascript 命令构造（独立出来便于测试与转义验证）
public enum NotifierScript {
    public static func appleScriptString(_ s: String) -> String {
        // osascript -e 不接受正文中的裸换行（AppleScript 语法错误，告警会被 try? 静默吞掉），
        // 先把回车/换行压成单个空格（\r\n 整体替换避免出现双空格），再做反斜杠/引号转义
        let flattened = s.replacingOccurrences(of: "\r\n", with: " ")
                         .replacingOccurrences(of: "\r", with: " ")
                         .replacingOccurrences(of: "\n", with: " ")
        let escaped = flattened.replacingOccurrences(of: "\\", with: "\\\\")
                               .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    public static func command(title: String, body: String) -> String {
        "display notification \(appleScriptString(body)) with title \(appleScriptString(title))"
    }
}

public final class Notifier: Notifying {
    public init() {}

    public func deliver(title: String, body: String, sound: Bool) {
        // 未打包成 .app（如直接跑调试二进制）时 UNUserNotificationCenter 不可用
        guard Bundle.main.bundleIdentifier != nil else {
            fallback(title: title, body: body, sound: sound)
            return
        }
        deliverViaUN(title: title, body: body, sound: sound)
    }

    private func deliverViaUN(title: String, body: String, sound: Bool) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }

        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted else {
                self?.fallback(title: title, body: body, sound: sound)
                return
            }
            let request = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: content, trigger: nil)
            center.add(request) { [weak self] error in
                if error != nil {
                    self?.fallback(title: title, body: body, sound: sound)
                }
            }
        }
    }

    private func fallback(title: String, body: String, sound: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", NotifierScript.command(title: title, body: body)]
        try? process.run()
        if sound { NSSound(named: NSSound.Name("Ping"))?.play() }
    }
}
