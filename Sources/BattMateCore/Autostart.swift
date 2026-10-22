// Sources/BattMateCore/Autostart.swift
import Foundation
import ServiceManagement

public enum Autostart {
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// 返回 nil 表示成功；返回字符串为用户可读错误
    public static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister() // 未注册时注销会抛错，忽略即可
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
