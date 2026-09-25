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
    }

    // MARK: - 组件接线

    private func wireMonitor() {
        dragMonitor.onActivate = { [weak self] _, cursor in
            guard let self else { return }
            self.overlay.show(tiles: self.store.quickLayouts,
                              cursorCG: cursor,
                              showTitles: self.store.settings.showTileTitles)
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
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered,
                          defer: false)
        window.title = "WindowTidyy 设置"
        window.contentMinSize = NSSize(width: 820, height: 580)
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
