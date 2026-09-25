import AppKit
import SwiftUI

/// 布局编辑器：模拟屏幕画布 + 网格 + 拖拽框选（核心需求 1）
struct LayoutEditorView: View {
    @Binding var item: LayoutItem
    let screen: NSScreen?

    @State private var dragAnchor: (Int, Int)?
    @State private var dragCurrent: (Int, Int)?

    /// 实时框选（inclusive 单元格，未提交前显示）
    private var liveSelection: (sx: Int, sy: Int, ex: Int, ey: Int)? {
        guard let a = dragAnchor, let c = dragCurrent else { return nil }
        return (min(a.0, c.0), min(a.1, c.1), max(a.0, c.0), max(a.1, c.1))
    }

    /// 当前显示的框选：拖拽中用实时值，否则用已保存值
    private var displaySelection: (sx: Int, sy: Int, ex: Int, ey: Int)? {
        if let live = liveSelection { return live }
        guard item.isValid else { return nil }
        return (item.startX, item.startY, item.endX - 1, item.endY - 1)
    }

    private var aspect: CGFloat {
        let f = screen?.frame ?? NSRect(x: 0, y: 0, width: 16, height: 10)
        return f.width / f.height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("布局名称", text: $item.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Spacer()
                ApplyToCurrentWindowButton(item: item)
            }

            HStack(spacing: 20) {
                Stepper("网格 \(item.gridX) 列 × \(item.gridY) 行", value: gridXBinding, in: 1...16)
                    .frame(width: 220)
                if let s = displaySelection {
                    Text(readout(s))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            canvas
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 8)

            Text("在画布上拖拽即可框选区域；单击选中单个格子。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    // MARK: - 画布

    private var canvas: some View {
        GeometryReader { geo in
            let cols = max(item.gridX, 1)
            let rows = max(item.gridY, 1)
            let cw = geo.size.width / CGFloat(cols)
            let ch = geo.size.height / CGFloat(rows)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.03))

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
                .stroke(Color.primary.opacity(0.18), lineWidth: 1)

                if let s = displaySelection {
                    let x = cw * CGFloat(s.sx)
                    let y = ch * CGFloat(s.sy)
                    let w = cw * CGFloat(s.ex - s.sx + 1)
                    let h = ch * CGFloat(s.ey - s.sy + 1)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor.opacity(0.25))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        )
                        .frame(width: w, height: h)
                        .offset(x: x, y: y)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let cell = cellFor(value.location, cw: cw, ch: ch, cols: cols, rows: rows)
                        if dragAnchor == nil { dragAnchor = cell }
                        dragCurrent = cell
                    }
                    .onEnded { value in
                        let cell = cellFor(value.location, cw: cw, ch: ch, cols: cols, rows: rows)
                        if dragAnchor == nil { dragAnchor = cell }
                        dragCurrent = cell
                        commit()
                        dragAnchor = nil
                        dragCurrent = nil
                    }
            )
        }
    }

    private func commit() {
        guard let s = liveSelection else { return }
        item.startX = s.sx
        item.startY = s.sy
        item.endX = s.ex + 1
        item.endY = s.ey + 1
        item.clampToBounds()
    }

    private func cellFor(_ point: CGPoint, cw: CGFloat, ch: CGFloat, cols: Int, rows: Int) -> (Int, Int) {
        let c = min(max(Int(point.x / max(cw, 0.001)), 0), cols - 1)
        let r = min(max(Int(point.y / max(ch, 0.001)), 0), rows - 1)
        return (c, r)
    }

    private func readout(_ s: (sx: Int, sy: Int, ex: Int, ey: Int)) -> String {
        let wpct = Double(s.ex - s.sx + 1) / Double(max(item.gridX, 1)) * 100
        let hpct = Double(s.ey - s.sy + 1) / Double(max(item.gridY, 1)) * 100
        return String(format: "格子 (%d,%d)–(%d,%d) · %.0f%% × %.0f%%",
                      s.sx, s.sy, s.ex, s.ey, wpct, hpct)
    }

    /// 网格步进（列数变化时联动行数，保持编辑习惯为方形网格；也可以只改单个）
    private var gridXBinding: Binding<Int> {
        Binding(
            get: { item.gridX },
            set: { v in
                item.gridX = v
                item.gridY = v
                item.clampToBounds()
            })
    }
}

/// 调试/快捷用法：把布局应用到本 app 之下最靠前的窗口
struct ApplyToCurrentWindowButton: View {
    let item: LayoutItem
    @EnvironmentObject var permissions: PermissionsManager
    @State private var result: String?

    var body: some View {
        HStack(spacing: 6) {
            Button("应用到当前窗口") { apply() }
                .disabled(!permissions.isTrusted)
            if let result {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func apply() {
        guard let target = WindowEngine.shared.frontmostForeignWindow(),
              let screen = NSScreen.main ?? ScreenMath.screenAtCursor() else {
            result = "没有找到目标窗口"
            return
        }
        let ok = WindowEngine.shared.setRect(
            ScreenMath.cgRect(fromAppKit: item.targetRect(on: screen)),
            on: target.element)
        result = ok ? "已应用到 \(target.ownerName ?? "窗口")" : "应用失败"
    }
}
