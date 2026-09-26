import AppKit
import Combine
import SwiftUI

/// 瓦片条与瓦片的几何常量（控制器做命中测试、SwiftUI 画界面，两边必须一致）。
/// 尺寸/间距复刻原版：瓦片 ~133×106，瓦片间大间距分散排列（无共享容器框）。
enum OverlayMetrics {
    static let tileWidth: CGFloat = 168
    static let tileHeight: CGFloat = 92
    static let spacing: CGFloat = 72
    static let padding: CGFloat = 8
    static var stripHeight: CGFloat { tileHeight + padding * 2 }
    static func stripWidth(tileCount: Int) -> CGFloat {
        CGFloat(tileCount) * tileWidth + CGFloat(max(tileCount - 1, 0)) * spacing + padding * 2
    }

    /// 依据归一化位置（中心点，y 从顶部算，相对 bounds）计算瓦片条矩形，
    /// 自动夹紧保证完整可见。设置页的预览画布与 overlay 共用此逻辑。
    static func stripRect(in bounds: CGRect, tileCount: Int, position: CGPoint) -> NSRect {
        let size = NSSize(width: stripWidth(tileCount: tileCount), height: stripHeight)
        let cx = bounds.minX + bounds.width * position.x
        let yTopFromBounds = bounds.height * position.y
        let x = min(max(cx - size.width / 2, bounds.minX), bounds.maxX - size.width)
        let yTop = min(max(yTopFromBounds - size.height / 2, 0), bounds.height - size.height)
        return NSRect(x: x, y: bounds.maxY - yTop - size.height, width: size.width, height: size.height)
    }
}

/// overlay 状态（SwiftUI 观察）
final class StripStore: ObservableObject {
    @Published var tiles: [OverlayTile]
    @Published var showTitles: Bool
    /// 悬停的瓦片下标
    @Published var hoveredIndex: Int?
    /// 聚合瓦片内悬停的子布局下标（单瓦片恒为 0）
    @Published var hoveredSubIndex: Int = 0

    init(tiles: [OverlayTile], showTitles: Bool) {
        self.tiles = tiles
        self.showTitles = showTitles
    }

    /// 当前实际生效（高亮/将被应用）的布局
    var activeLayout: LayoutItem? {
        guard let idx = hoveredIndex, idx < tiles.count else { return nil }
        let sub = min(max(hoveredSubIndex, 0), tiles[idx].layouts.count - 1)
        return tiles[idx].layouts[sub]
    }
}

/// 拖动窗口时的 overlay：屏幕顶部居中的横向瓦片条 + 整屏目标区域预览层。
/// 面板本身 ignoresMouseEvents —— 拖动期间鼠标事件属于被拖的窗口，
/// 悬停判定由 DragMonitor 用光标坐标做命中测试（与原版 Window Tidy 相同）。
/// 聚合瓦片（互补布局合并显示）内按光标所在格子选中子布局，
/// 在瓦片内左右/上下移动即可在 左半屏/右半屏 等子布局间切换。
final class OverlayController {
    private var stripPanel: NSPanel?
    private var zonePanel: NSPanel?
    private var store: StripStore?

    private(set) var tiles: [OverlayTile] = []
    private(set) var tileRects: [NSRect] = [] // AppKit 屏幕坐标
    private(set) var screen: NSScreen?
    private var position = CGPoint(x: 0.5, y: 0.06)
    private var visible = false

    // MARK: - 显示 / 更新 / 隐藏

    func show(tiles: [OverlayTile], cursorCG: CGPoint, showTitles: Bool,
              position: CGPoint = CGPoint(x: 0.5, y: 0.06),
              simulateHover: Bool = false) {
        hide()
        guard let scr = ScreenMath.screen(containingCG: cursorCG) ?? NSScreen.main,
              !tiles.isEmpty else {
            WTLog.log("WTDBG [overlay] show 被拒绝: screen=\(ScreenMath.screen(containingCG: cursorCG)?.localizedName ?? "nil") tiles=\(tiles.count)")
            return
        }
        WTLog.log("WTDBG [overlay] show on \(scr.localizedName) tiles=\(tiles.map(\.title))")

        self.tiles = tiles
        self.screen = scr
        self.position = position
        visible = true

        // 瓦片条位置：设置的预览画布可调（归一化中心点，相对屏幕铺放区域）
        let stripRect = OverlayMetrics.stripRect(in: scr.tilingBounds,
                                                 tileCount: tiles.count,
                                                 position: position)

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
        if simulateHover {
            // 演示/截图：模拟悬停第一个瓦片（含落区预览）
            store?.hoveredIndex = tiles.isEmpty ? nil : 0
            store?.hoveredSubIndex = 0
        }
    }

    /// 拖动中光标移动：命中测试（瓦片 + 聚合瓦片内子区域）+ 必要时换屏
    func updateHover(cursorCG: CGPoint) {
        guard visible else { return }
        let p = ScreenMath.appKitPoint(fromCG: cursorCG)
        if let scr = screen, !NSPointInRect(p, scr.frame),
           ScreenMath.screen(containingCG: cursorCG) != nil {
            show(tiles: tiles, cursorCG: cursorCG,
                 showTitles: store?.showTitles ?? true, position: position)
            return
        }
        guard let idx = tileRects.firstIndex(where: { NSPointInRect(p, $0) }), idx < tiles.count else {
            store?.hoveredIndex = nil
            store?.hoveredSubIndex = 0
            return
        }
        store?.hoveredIndex = idx
        store?.hoveredSubIndex = subIndex(tile: tiles[idx], in: tileRects[idx], point: p)
    }

    /// 松手判定：光标落在哪个瓦片的哪个子布局上
    func resolveDrop(cursorCG: CGPoint) -> (item: LayoutItem, screen: NSScreen)? {
        guard visible, let scr = screen else { return nil }
        let p = ScreenMath.appKitPoint(fromCG: cursorCG)
        guard let idx = tileRects.firstIndex(where: { NSPointInRect(p, $0) }),
              idx < tiles.count else {
            WTLog.log("WTDBG [overlay] drop 未命中瓦片 at appkit \(p), tiles=\(tileRects)")
            return nil
        }
        let sub = subIndex(tile: tiles[idx], in: tileRects[idx], point: p)
        let item = tiles[idx].layouts[min(max(sub, 0), tiles[idx].layouts.count - 1)]
        WTLog.log("WTDBG [overlay] drop 命中瓦片 \(idx) [\(tiles[idx].title)] 子布局 \(sub) (\(item.name))")
        return (item, scr)
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

    // MARK: - 内部

    /// 光标在瓦片内命中的子布局下标。网格 y 轴向下（顶行 startY=0），
    /// 与瓦片绘制方向一致；AppKit 点需翻转到"距瓦片顶部"的坐标。
    private func subIndex(tile: OverlayTile, in rect: NSRect, point: NSPoint) -> Int {
        let layouts = tile.layouts
        guard layouts.count > 1, let first = layouts.first else { return 0 }
        let localX = point.x - rect.minX
        let localYFromTop = rect.maxY - point.y
        let cw = rect.width / CGFloat(max(first.gridX, 1))
        let ch = rect.height / CGFloat(max(first.gridY, 1))
        let cellX = min(max(Int(localX / max(cw, 0.001)), 0), first.gridX - 1)
        let cellY = min(max(Int(localYFromTop / max(ch, 0.001)), 0), first.gridY - 1)
        let hit = layouts.firstIndex {
            cellX >= $0.startX && cellX < $0.endX && cellY >= $0.startY && cellY < $0.endY
        }
        return hit ?? 0
    }

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
