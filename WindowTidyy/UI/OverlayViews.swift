import SwiftUI

/// 顶部瓦片条：4 个布局预览并排，悬停高亮
struct StripView: View {
    @ObservedObject var store: StripStore

    var body: some View {
        HStack(spacing: OverlayMetrics.spacing) {
            ForEach(Array(store.tiles.enumerated()), id: \.element.id) { idx, item in
                TileView(item: item,
                         hovered: store.hoveredIndex == idx,
                         showTitle: store.showTitles)
            }
        }
        .padding(OverlayMetrics.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

struct TileView: View {
    let item: LayoutItem
    let hovered: Bool
    let showTitle: Bool

    var body: some View {
        VStack(spacing: 4) {
            LayoutPreviewView(item: item,
                              lineColor: hovered ? Color.white.opacity(0.55) : Color.primary.opacity(0.22),
                              fillColor: hovered ? Color.white.opacity(0.95) : Color.accentColor.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: showTitle ? 50 : 66)
            if showTitle {
                Text(item.name)
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

/// 整屏目标区域预览：悬停瓦片时，高亮该布局在当前屏幕的实际落区
struct ZoneView: View {
    @ObservedObject var store: StripStore
    let screen: NSScreen

    var body: some View {
        GeometryReader { geo in
            let full = screen.frame
            if let idx = store.hoveredIndex, idx < store.tiles.count, full.width > 0, full.height > 0 {
                let rect = store.tiles[idx].targetRect(on: screen)
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
