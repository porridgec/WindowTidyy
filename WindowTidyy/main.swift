import AppKit

// 常驻后台 agent（LSUIElement，无 Dock 图标），手动驱动 NSApplication
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
