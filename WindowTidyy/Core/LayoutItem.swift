import Foundation
import AppKit

/// 一个预设布局：在 gridX × gridY 网格上框选的矩形区域。
/// 与原版 Window Tidy 的 Layouts.data 数据模型一致，endX/endY 为排他端点。
struct LayoutItem: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var gridX: Int
    var gridY: Int
    var startX: Int
    var startY: Int
    var endX: Int // exclusive
    var endY: Int // exclusive

    /// 框选是否有效（至少 1×1 且完全落在网格内）
    var isValid: Bool {
        gridX >= 1 && gridY >= 1
            && startX >= 0 && startY >= 0
            && endX > startX && endY > startY
            && endX <= gridX && endY <= gridY
    }

    /// 布局占屏幕的宽高比例，例如「左半屏」为 (0.5, 1.0)
    var sizeRatio: CGSize {
        guard gridX >= 1, gridY >= 1 else { return .zero }
        return CGSize(width: CGFloat(endX - startX) / CGFloat(gridX),
                      height: CGFloat(endY - startY) / CGFloat(gridY))
    }

    /// 把网格区间换算到某块屏幕可用区域（AppKit 坐标，左下原点）内的实际矩形。
    /// 网格 y 轴向下增长（startY=0 是顶行），屏幕坐标向上增长，需要翻转。
    func rect(in bounds: CGRect) -> CGRect {
        guard isValid, gridX >= 1, gridY >= 1 else { return bounds }
        let width = bounds.width * sizeRatio.width
        let height = bounds.height * sizeRatio.height
        let x = bounds.minX + bounds.width * CGFloat(startX) / CGFloat(gridX)
        let y = bounds.minY + bounds.height * CGFloat(gridY - endY) / CGFloat(gridY)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// 是否 100% 覆盖网格（即「全屏」类布局）
    var isFullCoverage: Bool {
        isValid && startX == 0 && startY == 0 && endX == gridX && endY == gridY
    }

    /// 布局应用到某块屏幕的最终矩形。
    /// 统一基于 tilingBounds（整屏去掉菜单栏，无视 Dock）：
    /// 自动隐藏的 Dock 会让 visibleFrame 动态变化（伸出时底部留空、缩回又恢复），
    /// 以它为基准会导致「有时铺满有时空一截」；Dock 伸出时滑过窗口上方即可。
    func targetRect(on screen: NSScreen) -> NSRect {
        rect(in: screen.tilingBounds)
    }

    /// 将框选收缩到当前网格范围内（网格变小时调用）
    mutating func clampToBounds() {
        guard gridX >= 1, gridY >= 1 else { return }
        startX = min(max(startX, 0), gridX - 1)
        startY = min(max(startY, 0), gridY - 1)
        endX = min(max(endX, startX + 1), gridX)
        endY = min(max(endY, startY + 1), gridY)
    }

    /// 首次启动的默认布局（与原版 Window Tidy 相同的 6×6 经典四件套）
    static let defaults: [LayoutItem] = [
        LayoutItem(name: "左半屏", gridX: 6, gridY: 6, startX: 0, startY: 0, endX: 3, endY: 6),
        LayoutItem(name: "右半屏", gridX: 6, gridY: 6, startX: 3, startY: 0, endX: 6, endY: 6),
        LayoutItem(name: "居中", gridX: 6, gridY: 6, startX: 1, startY: 1, endX: 5, endY: 5),
        LayoutItem(name: "全屏", gridX: 6, gridY: 6, startX: 0, startY: 0, endX: 6, endY: 6),
    ]
}
