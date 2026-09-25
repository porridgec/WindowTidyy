import AppKit
import Combine
import SwiftUI

/// Quick Layout 面板状态
final class QuickStore: ObservableObject {
    @Published var gridX: Int
    @Published var gridY: Int

    var onCommit: ((LayoutItem) -> Void)?
    var onCancel: (() -> Void)?
    var onGridChange: ((Int, Int) -> Void)?

    init(gridX: Int, gridY: Int) {
        self.gridX = gridX
        self.gridY = gridY
    }

    func changeGrid(deltaX: Int, deltaY: Int) {
        gridX = min(max(gridX + deltaX, 1), 24)
        gridY = min(max(gridY + deltaY, 1), 24)
        onGridChange?(gridX, gridY)
    }
}

/// Quick Layout 网格直选（原版 Window Tidy 同款进阶玩法）：
/// 快捷键弹出盖满屏幕的网格，拖出一个一次性区域，直接应用到之前的前台窗口。
final class QuickLayoutController {
    static let shared = QuickLayoutController()

    private var panel: NSPanel?
    private var store: QuickStore?
    private var target: TargetWindow?
    private var screen: NSScreen?

    var isVisible: Bool { panel != nil }

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            present()
        }
    }

    func present() {
        guard panel == nil else { return }
        guard AXIsProcessTrusted() else {
            NSSound.beep()
            return
        }
        guard let target = WindowEngine.shared.frontmostWindow() else {
            NSSound.beep()
            return
        }
        let settings = SettingsStore.shared.settings
        guard let scr = ScreenMath.screenAtCursor() ?? NSScreen.main else { return }

        let p = NSPanel(contentRect: scr.visibleFrame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.level = .modalPanel

        let st = QuickStore(gridX: settings.quickGridX, gridY: settings.quickGridY)
        let capturedScreen = scr
        let capturedTarget = target
        st.onCommit = { [weak self] item in
            WindowEngine.shared.setRect(
                ScreenMath.cgRect(fromAppKit: item.targetRect(on: capturedScreen)),
                on: capturedTarget.element)
            self?.dismiss()
        }
        st.onCancel = { [weak self] in self?.dismiss() }
        st.onGridChange = { gx, gy in
            SettingsStore.shared.update { s in
                s.quickGridX = gx
                s.quickGridY = gy
            }
        }

        p.contentView = NSHostingView(rootView: QuickLayoutPanelView(store: st, screen: scr)
            .frame(maxWidth: .infinity, maxHeight: .infinity))
        // 面板需要接收鼠标拖选与 esc 键（borderless panel 可成为 key）
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)

        panel = p
        store = st
        self.target = target
        screen = scr
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        store = nil
        target = nil
        screen = nil
    }
}
