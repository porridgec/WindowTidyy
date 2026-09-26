import SwiftUI

/// 瓦片视觉规格（按原版实拍复刻：深灰半透明 HUD 底 + 淡蓝白区域填充 + 最上层浅色网格线）
enum TileStyle {
    /// 原版瓦片底色：近黑的深灰（rgba(20,20,25,~0.8)），不用系统蓝整块高亮
    static let background = Color(red: 0.08, green: 0.08, blue: 0.10)
    static let backgroundOpacity = 0.80
    /// 原版选中区域填充：淡蓝白 rgba(150,180,220,~0.4)（磨砂亮块）
    static let zoneFill = Color(red: 0.59, green: 0.71, blue: 0.86).opacity(0.42)
    /// 悬停激活区域：同一淡蓝白，更实
    static let zoneActiveFill = Color(red: 0.59, green: 0.71, blue: 0.86).opacity(0.78)
    /// 网格线：单层、最上层、半透白（穿过填充区时因对比降低显更淡，与原版一致）
    static let gridLine = Color.white.opacity(0.50)
    static let gridLineActive = Color.white.opacity(0.65)
    /// 边框：1px 浅灰白勾勒，悬停稍亮（原版悬停不变蓝、不放大）
    static let border = Color.white.opacity(0.30)
    static let borderActive = Color.white.opacity(0.55)
    static let cornerRadius: CGFloat = 5
}

/// 顶部瓦片条：各瓦片独立分散（无共享容器框，与原版一致）
struct StripView: View {
    @ObservedObject var store: StripStore

    var body: some View {
        TileRowView(tiles: store.tiles,
                    hoveredIndex: store.hoveredIndex,
                    hoveredSubIndex: store.hoveredSubIndex,
                    showTitles: store.showTitles)
    }
}

/// 瓦片行（overlay 与设置中心的模拟条带复用）
struct TileRowView: View {
    let tiles: [OverlayTile]
    let hoveredIndex: Int?
    let hoveredSubIndex: Int
    let showTitles: Bool

    var body: some View {
        HStack(spacing: OverlayMetrics.spacing) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { idx, tile in
                TileView(tile: tile,
                         hovered: hoveredIndex == idx,
                         hoveredSubIndex: hoveredIndex == idx ? hoveredSubIndex : 0,
                         showTitle: showTitles)
            }
        }
    }
}

struct TileView: View {
    let tile: OverlayTile
    let hovered: Bool
    let hoveredSubIndex: Int
    let showTitle: Bool

    var body: some View {
        VStack(spacing: 3) {
            TilePreview(tile: tile, hovered: hovered, activeIndex: hovered ? hoveredSubIndex : nil)
                .frame(maxWidth: .infinity)
                .frame(height: showTitle ? 58 : 74)
            if showTitle {
                Text(tile.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(hovered ? 1.0 : 0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: OverlayMetrics.tileWidth, height: OverlayMetrics.tileHeight)
        .background(
            RoundedRectangle(cornerRadius: TileStyle.cornerRadius, style: .continuous)
                .fill(TileStyle.background.opacity(TileStyle.backgroundOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TileStyle.cornerRadius, style: .continuous)
                .strokeBorder(hovered ? TileStyle.borderActive : TileStyle.border, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.08), value: hovered)
    }
}

/// 瓦片内的网格预览（按原版实拍）：
/// - 网格线单层画在最上面（半透白），填充块从下面透出
/// - 单布局瓦片恒显示其区域淡蓝填充（悬停提亮）
/// - 聚合瓦片平时纯网格分割线；悬停时光标所在子区域出现填充
struct TilePreview: View {
    let tile: OverlayTile
    let hovered: Bool
    /// 悬停聚合瓦片时激活的子布局下标；nil = 无悬停
    var activeIndex: Int?

    var body: some View {
        GeometryReader { geo in
            let grid = tile.grid
            let cols = max(grid.x, 1)
            let rows = max(grid.y, 1)
            let cw = geo.size.width / CGFloat(cols)
            let ch = geo.size.height / CGFloat(rows)

            // 网格线（单层、最上）
            let gridLines = Path { path in
                for c in 1..<max(cols, 1) {
                    let x = cw * CGFloat(c)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                }
                for r in 1..<max(rows, 1) {
                    let y = ch * CGFloat(r)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }

            ZStack(alignment: .topLeading) {
                // 区域填充（在网格线之下）
                if tile.layouts.count > 1 {
                    // 聚合瓦片：仅悬停激活的子区域填充
                    if hovered, let activeIndex,
                       activeIndex < tile.layouts.count {
                        zoneFill(tile.layouts[activeIndex], cw: cw, ch: ch,
                                 color: TileStyle.zoneActiveFill)
                    }
                } else if let layout = tile.layouts.first {
                    // 单布局瓦片：恒显区域填充，悬停提亮
                    zoneFill(layout, cw: cw, ch: ch,
                             color: hovered ? TileStyle.zoneActiveFill : TileStyle.zoneFill)
                }

                gridLines
                    .stroke(hovered ? TileStyle.gridLineActive : TileStyle.gridLine, lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private func zoneFill(_ layout: LayoutItem, cw: CGFloat, ch: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(color)
            .frame(width: cw * CGFloat(layout.endX - layout.startX),
                   height: ch * CGFloat(layout.endY - layout.startY))
            .offset(x: cw * CGFloat(layout.startX), y: ch * CGFloat(layout.startY))
    }
}

/// 整屏目标区域预览：悬停瓦片（聚合瓦片取激活子布局）时，高亮该布局在当前屏幕的实际落区
struct ZoneView: View {
    @ObservedObject var store: StripStore
    let screen: NSScreen

    var body: some View {
        GeometryReader { geo in
            let full = screen.frame
            if let item = store.activeLayout, full.width > 0, full.height > 0 {
                let rect = item.targetRect(on: screen)
                let width = rect.width / full.width * geo.size.width
                let height = rect.height / full.height * geo.size.height
                let x = (rect.minX - full.minX) / full.width * geo.size.width
                let yTop = (full.maxY - rect.maxY) / full.height * geo.size.height
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    )
                    .frame(width: width, height: height)
                    .offset(x: x, y: yTop)
                    .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }
}
