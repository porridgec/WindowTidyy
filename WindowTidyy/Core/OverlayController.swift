import AppKit
import Combine
import SwiftUI

/// 瓦片条与瓦片的几何常量（控制器做命中测试、SwiftUI 画界面，两边必须一致）
enum OverlayMetrics {
    static let tileWidth: CGFloat = 108
    static let tileHeight: CGFloat = 86
    static let spacing: CGFloat = 10
    static let padding: CGFloat = 10
    static var stripHeight: CGFloat { tileHeight + padding * 2 }
    static func stripWidth(tileCount: Int) -> CGFloat {
        CGFloat(tileCount) * tileWidth + CGFloat(max(tileCount - 1, 0)) * spacing + padding * 2
    }
}

/// overlay 状态（SwiftUI 观察）
final class StripStore: ObservableObject {
    @Published var tiles: [LayoutItem]
    @Published var showTitles: Bool
    @Published var hoveredIndex: Int?

    init(tiles: [LayoutItem], showTitles: Bool) {
        self.tiles = tiles
        self.showTitles = showTitles
    }
}

/// 拖动窗口时的 overlay：屏幕顶部居中的横向瓦片条 + 整屏目标区域预览层。
/// 面板本身 ignoresMouseEvents —— 拖动期间鼠标事件属于被拖的窗口，
/// 悬停判定由 DragMonitor 用光标坐标做命中测试（与原版 Window Tidy 相同）。
final class OverlayController {
    private var stripPanel: NSPanel?
    private var zonePanel: NSPanel?
    private var store: StripStore?

    private(set) var tiles: [LayoutItem] = []
    private(set) var tileRects: [NSRect] = [] // AppKit 屏幕坐标
    private(set) var screen: NSScreen?
    private var visible = false

    // MARK: - 显示 / 更新 / 隐藏

    func show(tiles: [LayoutItem], cursorCG: CGPoint, showTitles: Bool) {
        hide()
        guard let scr = ScreenMath.screen(containingCG: cursorCG) ?? NSScreen.main,
              !tiles.isEmpty else {
            WTLog.log("WTDBG [overlay] show 被拒绝: screen=\(ScreenMath.screen(containingCG: cursorCG)?.localizedName ?? "nil") tiles=\(tiles.count)")
            return
        }
        WTLog.log("WTDBG [overlay] show on \(scr.localizedName) tiles=\(tiles.map(\.name))")

        self.tiles = tiles
        screen = scr
        visible = true

        // 顶部居中条带（visibleFrame 顶部下方留 12pt）
        let size = NSSize(width: OverlayMetrics.stripWidth(tileCount: tiles.count),
                          height: OverlayMetrics.stripHeight)
        let stripRect = NSRect(x: scr.visibleFrame.midX - size.width / 2,
                               y: scr.visibleFrame.maxY - size.height - 12,
                               width: size.width, height: size.height)

        let strip = makePanel(rect: stripRect)
        strip.level = .modalPanel
        let newStore = StripStore(tiles: tiles, showTitles: showTitles)
        strip.contentView = NSHostingView(rootView: StripView(store: newStore)
            .frame(maxWidth: .infinity, maxHeight: .infinity))
        strip.orderFrontRegardless()

        // 整屏目标区域预览层（在瓦片条之下）
        let zone = makePanel(rect: scr.frame)
        zone.level = .floating
        zone.contentView = NSHostingView(rootView: ZoneView(store: newStore, screen: scr)
            .frame(maxWidth: .infinity, maxHeight: .infinity))
        zone.orderFrontRegardless()

        stripPanel = strip
        zonePanel = zone
        store = newStore

        // 预计算瓦片命中区（与 StripView 的 HStack(spacing:)/padding 一致）
        var x = stripRect.minX + OverlayMetrics.padding
        for _ in tiles {
            tileRects.append(NSRect(x: x,
                                    y: stripRect.minY + OverlayMetrics.padding,
                                    width: OverlayMetrics.tileWidth,
                                    height: OverlayMetrics.tileHeight))
            x += OverlayMetrics.tileWidth + OverlayMetrics.spacing
        }
        updateHover(cursorCG: cursorCG)
    }

    /// 拖动中光标移动：命中测试 + 必要时把整组 overlay 搬到别的屏幕
    func updateHover(cursorCG: CGPoint) {
        guard visible else { return }
        let p = ScreenMath.appKitPoint(fromCG: cursorCG)
        if let scr = screen, !NSPointInRect(p, scr.frame),
           ScreenMath.screen(containingCG: cursorCG) != nil {
            show(tiles: tiles, cursorCG: cursorCG, showTitles: store?.showTitles ?? true)
            return
        }
        store?.hoveredIndex = tileRects.firstIndex { NSPointInRect(p, $0) }
    }

    /// 松手判定：光标落在哪个瓦片上
    func resolveDrop(cursorCG: CGPoint) -> (item: LayoutItem, screen: NSScreen)? {
        guard visible, let scr = screen else { return nil }
        let p = ScreenMath.appKitPoint(fromCG: cursorCG)
        guard let idx = tileRects.firstIndex(where: { NSPointInRect(p, $0) }),
              idx < tiles.count else {
            WTLog.log("WTDBG [overlay] drop 未命中瓦片 at appkit \(p), tiles=\(tileRects)")
            return nil
        }
        WTLog.log("WTDBG [overlay] drop 命中瓦片 \(idx) (\(tiles[idx].name))")
        return (tiles[idx], scr)
    }

    func hide() {
        stripPanel?.orderOut(nil)
        zonePanel?.orderOut(nil)
        stripPanel = nil
        zonePanel = nil
        store = nil
        tileRects = []
        tiles = []
        screen = nil
        visible = false
    }

    var isVisible: Bool { visible }

    private func makePanel(rect: NSRect) -> NSPanel {
        let panel = NSPanel(contentRect: rect,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}
