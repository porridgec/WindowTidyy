import SwiftUI

/// 瓦片视觉规格（复刻原版 Window Tidy：HUD 深灰蓝 + 系统蓝高亮 + 独立分散瓦片）
enum TileStyle {
    /// 原版瓦片底色 #2a3540（深灰蓝 HUD）
    static let background = Color(red: 0.165, green: 0.208, blue: 0.251)
    static let backgroundOpacity = 0.78
    /// 原版悬停高亮 #4a90d9（系统蓝）
    static let activeBackground = Color(red: 0.29, green: 0.565, blue: 0.851)
    static let activeBackgroundOpacity = 0.92
    /// 区域填充：统一单色，激活区实白、其余半透白（原版无多色）
    static let zoneFill = Color.white.opacity(0.32)
    static let zoneActiveFill = Color.white.opacity(0.95)
    /// 网格线：比边框更淡的浅白
    static let gridLine = Color.white.opacity(0.28)
    static let gridLineActive = Color.white.opacity(0.55)
    /// 区域内分割线：浅色填充块之间用深色细线分割（叠在填充之上、裁剪到区域范围）
    static let zoneDivider = Color(red: 0.07, green: 0.09, blue: 0.12).opacity(0.6)
    /// 边框
    static let border = Color.white.opacity(0.35)
    static let borderActive = Color.white.opacity(0.8)
    static let cornerRadius: CGFloat = 8
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
                .fill(hovered
                      ? TileStyle.activeBackground.opacity(TileStyle.activeBackgroundOpacity)
                      : TileStyle.background.opacity(TileStyle.backgroundOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TileStyle.cornerRadius, style: .continuous)
                .strokeBorder(hovered ? TileStyle.borderActive : TileStyle.border, lineWidth: 1)
        )
        .scaleEffect(hovered ? 1.05 : 1)
        .animation(.easeOut(duration: 0.08), value: hovered)
    }
}

/// 瓦片内的网格预览：所有区域统一单色填充、浅色网格线分割（原版风格，无多色）；
/// 激活子区域为实白高亮
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

            // 浅色网格线（铺满整格）
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
            // 区域并集（作为区域内分割线的蒙版）
            let zoneUnion = Path { path in
                for layout in tile.layouts where layout.isValid {
                    let rect = CGRect(x: cw * CGFloat(layout.startX),
                                      y: ch * CGFloat(layout.startY),
                                      width: cw * CGFloat(layout.endX - layout.startX),
                                      height: ch * CGFloat(layout.endY - layout.startY))
                    path.addRect(rect)
                }
            }

            ZStack(alignment: .topLeading) {
                gridLines
                    .stroke(hovered ? TileStyle.gridLineActive : TileStyle.gridLine, lineWidth: 1)

                // 各子布局区域（统一色）
                ForEach(Array(tile.layouts.enumerated()), id: \.element.id) { index, layout in
                    let isActive = hovered && activeIndex == index
                    let w = cw * CGFloat(layout.endX - layout.startX)
                    let h = ch * CGFloat(layout.endY - layout.startY)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isActive ? TileStyle.zoneActiveFill : TileStyle.zoneFill)
                        .frame(width: w, height: h)
                        .offset(x: cw * CGFloat(layout.startX), y: ch * CGFloat(layout.startY))
                }

                // 区域内分割线：浅色块（含激活块）之间/内部始终可见的深色细线
                gridLines
                    .stroke(TileStyle.zoneDivider, lineWidth: 1)
                    .mask(zoneUnion.fill())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
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
