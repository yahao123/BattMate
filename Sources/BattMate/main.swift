// Sources/BattMate/main.swift（重写占位）
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // 菜单栏常驻，无 Dock 图标
let controller = AppController()
controller.start()
app.run()
