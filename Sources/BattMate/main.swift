// Sources/BattMate/main.swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // 菜单栏常驻，无 Dock 图标
let delegate = AppDelegate()
app.delegate = delegate
app.run()
