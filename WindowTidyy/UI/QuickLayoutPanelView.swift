import SwiftUI

/// Quick Layout 全屏网格：拖选一次性区域，松手即应用
struct QuickLayoutPanelView: View {
    @ObservedObject var store: QuickStore
    let screen: NSScreen

    @State private var anchorCell: (Int, Int)?
    @State private var currentCell: (Int, Int)?

    private var selection: (sx: Int, sy: Int, ex: Int, ey: Int)? {
        guard let a = anchorCell, let c = currentCell else { return nil }
        return (min(a.0, c.0), min(a.1, c.1), max(a.0, c.0), max(a.1, c.1))
    }

    var body: some View {
        GeometryReader { geo in
            let cols = max(store.gridX, 1)
            let rows = max(store.gridY, 1)
            let cw = geo.size.width / CGFloat(cols)
            let ch = geo.size.height / CGFloat(rows)

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.22)

                // 网格
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
                .stroke(Color.white.opacity(0.35), lineWidth: 1)

                // 框选高亮
                if let s = selection {
                    let x = cw * CGFloat(s.sx)
                    let y = ch * CGFloat(s.sy)
                    let w = cw * CGFloat(s.ex - s.sx + 1)
                    let h = ch * CGFloat(s.ey - s.sy + 1)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        )
                        .frame(width: w, height: h)
                        .offset(x: x, y: y)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let cell = cellFor(value.location, cw: cw, ch: ch, cols: cols, rows: rows)
                        if anchorCell == nil { anchorCell = cell }
                        currentCell = cell
                    }
                    .onEnded { value in
                        let cell = cellFor(value.location, cw: cw, ch: ch, cols: cols, rows: rows)
                        if anchorCell == nil { anchorCell = cell }
                        currentCell = cell
                        if let s = selection {
                            // inclusive 框选 → LayoutItem（end 排他）
                            var item = LayoutItem(name: "Quick",
                                                  gridX: cols, gridY: rows,
                                                  startX: s.sx, startY: s.sy,
                                                  endX: s.ex + 1, endY: s.ey + 1)
                            item.clampToBounds()
                            store.onCommit?(item)
                        }
                        anchorCell = nil
                        currentCell = nil
                    }
            )
            .onExitCommand { store.onCancel?() }
        }
        .overlay(alignment: .top) {
            hintBar
        }
    }

    private var hintBar: some View {
        HStack(spacing: 16) {
            Label("拖动框选窗口区域", systemImage: "rectangle.dashed")
                .font(.system(size: 12, weight: .medium))
            Label("esc 取消", systemImage: "escape")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Button {
                    store.changeGrid(deltaX: -1, deltaY: 0)
                } label: {
                    Image(systemName: "minus")
                }
                Text("\(store.gridX) × \(store.gridY) 网格")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minWidth: 80)
                Button {
                    store.changeGrid(deltaX: 1, deltaY: 0)
                } label: {
                    Image(systemName: "plus")
                }
            }
            .buttonStyle(.borderless)
            .padding(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .padding(.top, 10)
        .allowsHitTesting(true)
    }

    private func cellFor(_ point: CGPoint, cw: CGFloat, ch: CGFloat, cols: Int, rows: Int) -> (Int, Int) {
        let c = min(max(Int(point.x / max(cw, 0.001)), 0), cols - 1)
        let r = min(max(Int(point.y / max(ch, 0.001)), 0), rows - 1)
        return (c, r)
    }
}
