import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// agent 壳：菜单栏图标、设置窗口、组件接线、权限生命周期
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore.shared
    private let permissions = PermissionsManager.shared
    private let dragMonitor = DragMonitor()
    private let overlay = OverlayController()

    private var settingsWindowController: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private var monitorStarted = false
    private var lastHotkey: HotKeyCombo?

    private weak var enabledMenuItem: NSMenuItem?
    private weak var loginMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        WTLog.log("WTDBG [app] launch trusted=\(permissions.isTrusted)")
        permissions.startPolling()
        wireMonitor()
        observeStore()
        buildStatusItem()

        if permissions.isTrusted {
            startMonitorIfNeeded()
        } else {
            showSettings(nil)
        }
        registerHotkey()

        // 截图/演示用启动参数（README 配图等）
        let args = CommandLine.arguments
        if args.contains("-openSettings") {
            showSettings(nil)
        }
        if let idx = args.firstIndex(of: "-renderShots"), idx + 1 < args.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.renderMarketingShots(to: args[idx + 1])
            }
        }
        if args.contains("-previewOverlay") || args.contains("-previewOverlayHover") {
            let hover = args.contains("-previewOverlayHover")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                let s = self.store.settings
                self.overlay.show(tiles: self.store.quickTiles,
                                  cursorCG: ScreenMath.cgPoint(fromAppKit: NSEvent.mouseLocation),
                                  showTitles: s.showTileTitles,
                                  position: CGPoint(x: s.stripPositionX, y: s.stripPositionY),
                                  simulateHover: hover)
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                    self?.overlay.hide()
                }
            }
        }
    }

    // MARK: - 组件接线

    private func wireMonitor() {
        dragMonitor.onActivate = { [weak self] _, cursor in
            guard let self else { return }
            let s = self.store.settings
            self.overlay.show(tiles: self.store.quickTiles,
                              cursorCG: cursor,
                              showTitles: s.showTileTitles,
                              position: CGPoint(x: s.stripPositionX, y: s.stripPositionY))
        }
        dragMonitor.onDragUpdate = { [weak self] cursor in
            self?.overlay.updateHover(cursorCG: cursor)
        }
        dragMonitor.onDrop = { [weak self] target, cursor in
            guard let self else { return }
            if let drop = self.overlay.resolveDrop(cursorCG: cursor) {
                let ok = WindowEngine.shared.setRect(
                    ScreenMath.cgRect(fromAppKit: drop.item.targetRect(on: drop.screen)),
                    on: target.element)
                WTLog.log("WTDBG [app] 应用布局 \(drop.item.name) → \(drop.screen.localizedName) ok=\(ok)")
            }
            self.overlay.hide()
        }
    }

    private func startMonitorIfNeeded() {
        guard !monitorStarted, permissions.isTrusted else { return }
        monitorStarted = true
        WTLog.log("WTDBG [app] monitor starting")
        dragMonitor.start()
        pushConfig()
    }

    private func pushConfig() {
        dragMonitor.applyConfig(.init(enabled: store.settings.enabled,
                                      mode: store.settings.triggerMode,
                                      modifierMask: store.settings.triggerModifierMask))
    }

    private func observeStore() {
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.pushConfig()
                self.registerHotkey()
            }
            .store(in: &cancellables)

        permissions.$isTrusted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] trusted in
                if trusted { self?.startMonitorIfNeeded() }
            }
            .store(in: &cancellables)
    }

    private func registerHotkey() {
        let combo = store.settings.quickHotkey
        guard combo != lastHotkey else { return }
        lastHotkey = combo
        if let combo {
            HotKeyCenter.shared.register(keyCode: combo.keyCode,
                                         modifiers: combo.modifiers) {
                QuickLayoutController.shared.toggle()
            }
        } else {
            HotKeyCenter.shared.unregister()
        }
    }

    // MARK: - 菜单栏

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1",
                                     accessibilityDescription: "WindowTidyy")

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let settingsItem = NSMenuItem(title: "打开设置…",
                                      action: #selector(showSettings(_:)),
                                      keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let enabledItem = NSMenuItem(title: "启用拖拽布局",
                                     action: #selector(toggleEnabled(_:)),
                                     keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)
        self.enabledMenuItem = enabledItem

        let loginItem = NSMenuItem(title: "登录时启动",
                                   action: #selector(toggleLoginItem(_:)),
                                   keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        self.loginMenuItem = loginItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 WindowTidyy",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    // MARK: - 动作

    @objc func showSettings(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.show()
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        store.update { $0.enabled.toggle() }
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("WindowTidyy: 登录项设置失败 \(error)")
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        enabledMenuItem?.state = store.settings.enabled ? .on : .off
        loginMenuItem?.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }
}

/// 设置窗口（SwiftUI 托管）
final class SettingsWindowController {
    let window: NSWindow

    init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 620),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered,
                          defer: false)
        window.title = "WindowTidyy 设置"
        window.contentMinSize = NSSize(width: 880, height: 580)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView:
            SettingsView()
                .environmentObject(SettingsStore.shared)
                .environmentObject(PermissionsManager.shared))
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}


// MARK: - README 配图渲染（离屏合成，零屏幕捕获）

extension AppDelegate {
    /// 离屏渲染营销图：桌面壁纸为底 + 落区高亮 + 瓦片条（用户的自定义位置）。
    /// 不截屏 —— 瓦片条与落区均用 ImageRenderer/矢量绘制合成，保证背景只有壁纸。
    @MainActor
    func renderMarketingShots(to dir: String) {
        guard let screen = NSScreen.main else { return }
        let size = screen.frame.size
        let tiles = store.quickTiles
        guard !tiles.isEmpty else { return }

        // 1) 壁纸底图
        let composite = NSImage(size: size)
        composite.lockFocusFlipped(false)
        if let url = NSWorkspace.shared.desktopImageURL(for: screen),
           let wallpaper = NSImage(contentsOf: url) {
            wallpaper.draw(in: NSRect(origin: .zero, size: size),
                           from: .zero, operation: .copy, fraction: 1)
        }

        // 2) 菜单栏：落区从菜单栏下沿开始，合成图必须画出它（高度 = 屏幕 topInset）
        let topInset = screen.frame.maxY - screen.visibleFrame.maxY
        if topInset > 4 {
            let barRenderer = ImageRenderer(content: MenuBarView()
                .frame(width: size.width, height: topInset))
            barRenderer.scale = 2
            if let cg = barRenderer.cgImage {
                let barImage = NSImage(cgImage: cg, size: NSSize(width: size.width, height: topInset))
                barImage.draw(in: NSRect(x: 0, y: size.height - topInset, width: size.width, height: topInset))
            }
        }

        // 3) 落区高亮：第一个瓦片的第一个子布局（左半屏，顶到菜单栏下沿）
        let first = tiles[0].layouts[0]
        let zoneRect = first.targetRect(on: screen)
        NSColor.systemBlue.withAlphaComponent(0.16).setFill()
        zoneRect.fill()
        NSColor.systemBlue.withAlphaComponent(0.85).setStroke()
        let zonePath = NSBezierPath(roundedRect: zoneRect.insetBy(dx: 1, dy: 1),
                                    xRadius: 10, yRadius: 10)
        zonePath.lineWidth = 3
        zonePath.stroke()

        // 4) 瓦片条：悬停第一个瓦片（第一个子区域激活），画在用户设置的位置
        let store = StripStore(tiles: tiles, showTitles: store.settings.showTileTitles)
        store.hoveredIndex = 0
        store.hoveredSubIndex = 0
        let stripW = OverlayMetrics.stripWidth(tileCount: tiles.count)
        let stripRect = OverlayMetrics.stripRect(in: screen.tilingBounds,
                                                 tileCount: tiles.count,
                                                 position: CGPoint(x: self.store.settings.stripPositionX,
                                                                   y: self.store.settings.stripPositionY))
        let renderer = ImageRenderer(content: StripView(store: store)
            .frame(width: stripW, height: OverlayMetrics.stripHeight))
        renderer.scale = 2
        if let cg = renderer.cgImage {
            let stripImage = NSImage(cgImage: cg, size: NSSize(width: stripW,
                                                               height: OverlayMetrics.stripHeight))
            // stripRect 是条带矩形；瓦片行透明底直接叠加
            stripImage.draw(in: stripRect)
        }
        composite.unlockFocus()

        // 5) 落盘
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        savePNG(composite, to: URL(fileURLWithPath: dir).appendingPathComponent("overlay_zone.png"))

        // 6) 特写：只渲染瓦片条（透明底 + 悬停态）
        let closeupRenderer = ImageRenderer(content: StripView(store: store)
            .frame(width: stripW, height: OverlayMetrics.stripHeight))
        closeupRenderer.scale = 2
        guard let closeupCG = closeupRenderer.cgImage else { return }
        let img = NSImage(cgImage: closeupCG, size: NSSize(width: stripW, height: OverlayMetrics.stripHeight))
        // 特写垫一层壁纸同款背景（取壁纸中心裁片），避免透明底在 README 深色模式下看不清
        let closeup = NSImage(size: NSSize(width: stripW + 60, height: OverlayMetrics.stripHeight + 60))
        closeup.lockFocusFlipped(false)
        if let url = NSWorkspace.shared.desktopImageURL(for: screen),
           let wallpaper = NSImage(contentsOf: url) {
            // 从壁纸中心裁一块与画布同比例的区域，填充特写背景
            let wpSize = wallpaper.size
            let targetAspect = (stripW + 60) / (OverlayMetrics.stripHeight + 60)
            var cropRect = CGRect(x: 0, y: 0, width: wpSize.width, height: wpSize.width / targetAspect)
            if cropRect.height > wpSize.height {
                cropRect = CGRect(x: 0, y: 0, width: wpSize.height * targetAspect, height: wpSize.height)
            }
            cropRect.origin = CGPoint(x: (wpSize.width - cropRect.width) / 2,
                                      y: (wpSize.height - cropRect.height) / 2)
            wallpaper.draw(in: NSRect(origin: .zero, size: closeup.size),
                           from: cropRect, operation: .copy, fraction: 1)
        }
        img.draw(in: NSRect(x: 30, y: 30, width: stripW, height: OverlayMetrics.stripHeight))
        closeup.unlockFocus()
        savePNG(closeup, to: URL(fileURLWithPath: dir).appendingPathComponent("overlay_hover.png"))
        WTLog.log("WTDBG [app] marketing shots rendered to \(dir)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    /// 模拟菜单栏（README 合成图用）：深色半透明底 + Finder 菜单 + 状态图标 + 时钟
    fileprivate struct MenuBarView: View {
        var body: some View {
            HStack(spacing: 0) {
                HStack(spacing: 16) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 14, weight: .medium))
                    Text("访达").fontWeight(.semibold)
                    Group {
                        Text("文件"); Text("编辑"); Text("显示"); Text("前往"); Text("窗口"); Text("帮助")
                    }
                    .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.leading, 14)
                Spacer()
                HStack(spacing: 14) {
                    Image(systemName: "battery.75percent")
                    Image(systemName: "wifi")
                    Image(systemName: "magnifyingglass")
                    Image(systemName: "switch.2")
                    Text("9月26日 周五 13:50")
                }
                .padding(.trailing, 16)
            }
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.95))
            // 撑满外部 frame（38pt 画布），背景色覆盖整条——否则色块只裹住文字高度
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.55))
        }
    }

    private func savePNG(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
