import SwiftUI

/// 网格布局小预览（布局库列表、瓦片条、快速布局模拟条复用）
struct LayoutPreviewView: View {
    let item: LayoutItem
    var lineColor: Color = Color.primary.opacity(0.22)
    var fillColor: Color = Color.accentColor.opacity(0.5)

    var body: some View {
        GeometryReader { geo in
            let cols = max(item.gridX, 1)
            let rows = max(item.gridY, 1)
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

                // 框选区域
                if item.isValid {
                    let w = cw * CGFloat(item.endX - item.startX)
                    let h = ch * CGFloat(item.endY - item.startY)
                    let x = cw * CGFloat(item.startX)
                    let y = ch * CGFloat(item.startY)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(fillColor)
                        .frame(width: w, height: h)
                        .offset(x: x, y: y)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
