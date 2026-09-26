import SwiftUI

/// 顶部瓦片条：若干布局瓦片并排（聚合组为一个多区域瓦片），悬停高亮
struct StripView: View {
    @ObservedObject var store: StripStore

    var body: some View {
        TileRowView(tiles: store.tiles,
                    hoveredIndex: store.hoveredIndex,
                    hoveredSubIndex: store.hoveredSubIndex,
                    showTitles: store.showTitles)
            .padding(OverlayMetrics.padding)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
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
        VStack(spacing: 4) {
            TilePreview(tile: tile, hovered: hovered, activeIndex: hovered ? hoveredSubIndex : nil)
                .frame(maxWidth: .infinity)
                .frame(height: showTitle ? 50 : 66)
            if showTitle {
                Text(tile.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(8)
        .frame(width: OverlayMetrics.tileWidth, height: OverlayMetrics.tileHeight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovered ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.05)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(hovered ? Color.clear : Color.primary.opacity(0.18), lineWidth: 1)
        )
        .foregroundStyle(hovered ? .white : .primary)
        .scaleEffect(hovered ? 1.04 : 1)
        .animation(.easeOut(duration: 0.08), value: hovered)
    }
}

/// 瓦片内的网格预览：单布局高亮一块区域；聚合组绘制所有子区域，激活的子区域最亮
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

            ZStack(alignment: .topLeading) {
                // 网格线
                Path { path in
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
                .stroke(lineColor, lineWidth: 1)

                // 各子布局区域
                ForEach(Array(tile.layouts.enumerated()), id: \.element.id) { index, layout in
                    let isActive = hovered && activeIndex == index
                    let w = cw * CGFloat(layout.endX - layout.startX)
                    let h = ch * CGFloat(layout.endY - layout.startY)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isActive ? Color.white.opacity(0.95)
                              : (hovered ? Color.white.opacity(0.35) : fillColor(for: index)))
                        .frame(width: w, height: h)
                        .offset(x: cw * CGFloat(layout.startX), y: ch * CGFloat(layout.startY))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var lineColor: Color {
        hovered ? Color.white.opacity(0.55) : Color.primary.opacity(0.22)
    }

    /// 聚合组内不同子区域用不同色相区分（未悬停时）
    private func fillColor(for index: Int) -> Color {
        let bases: [Color] = [.accentColor, .orange, .teal, .indigo, .pink, .green]
        return bases[index % bases.count].opacity(0.5)
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
