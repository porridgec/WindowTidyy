import AppKit

// 渲染 WindowTidyy 图标：蓝紫渐变 squircle + 网格 + 左上高亮选区（呼应布局编辑器）
// 参数：输出路径 [small]（small = 小尺寸简化变体：粗线、选区填满格子）
let args = CommandLine.arguments
let outPath = args[1]
let small = args.count > 2 && args[2] == "small"

let size: CGFloat = 1024
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
rep.size = NSSize(width: size, height: size)
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let g = ctx.cgContext

// 图标主体（macOS Big Sur 比例：1024 画布上 824×824 居中）
let bodyRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 186
let body = NSBezierPath(roundedRect: bodyRect, xRadius: radius, yRadius: radius)
g.saveGState()
body.addClip()

// 1) 主渐变：左上深蓝 → 右下紫
let mainGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [
                              NSColor(calibratedRed: 0.239, green: 0.427, blue: 0.961, alpha: 1).cgColor, // #3D6DF5
                              NSColor(calibratedRed: 0.545, green: 0.361, blue: 0.965, alpha: 1).cgColor, // #8B5CF6
                          ] as CFArray, locations: [0, 1])!
g.drawLinearGradient(mainGrad,
                     start: CGPoint(x: bodyRect.minX, y: bodyRect.maxY),
                     end: CGPoint(x: bodyRect.maxX, y: bodyRect.minY),
                     options: [])

// 2) 顶部柔光
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [
                          NSColor(calibratedWhite: 1, alpha: 0.35).cgColor,
                          NSColor(calibratedWhite: 1, alpha: 0).cgColor,
                      ] as CFArray, locations: [0, 1])!
g.drawRadialGradient(glow,
                     startCenter: CGPoint(x: 512, y: 890),
                     startRadius: 0,
                     endCenter: CGPoint(x: 512, y: 890),
                     endRadius: 560,
                     options: [])

// 3) 网格区域（主体内缩 96）
let gridRect = bodyRect.insetBy(dx: 96, dy: 96) // 632×632
let lineWidth: CGFloat = small ? 30 : 16
let lineAlpha: CGFloat = small ? 0.75 : 0.55

g.setStrokeColor(NSColor(calibratedWhite: 1, alpha: lineAlpha).cgColor)
g.setLineWidth(lineWidth)
g.setLineCap(.butt)
// 中竖线 + 中横线（2×2）
g.move(to: CGPoint(x: gridRect.midX, y: gridRect.minY))
g.addLine(to: CGPoint(x: gridRect.midX, y: gridRect.maxY))
g.strokePath()
g.move(to: CGPoint(x: gridRect.minX, y: gridRect.midY))
g.addLine(to: CGPoint(x: gridRect.maxX, y: gridRect.midY))
g.strokePath()

// 网格外框
let border = NSBezierPath(rect: gridRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
NSColor(calibratedWhite: 1, alpha: small ? 0.55 : 0.32).setStroke()
border.lineWidth = small ? 24 : 10
border.stroke()

// 4) 左上角选区：白色圆角矩形（= 拖选的布局区域）
let cellW = gridRect.width / 2 - lineWidth / 2
let cellH = gridRect.height / 2 - lineWidth / 2
let selRect: NSRect
let selRadius: CGFloat
if small {
    // 小尺寸：填满格子，边界即网格线，保证 16px 下可辨识
    selRect = NSRect(x: gridRect.minX + lineWidth,
                     y: gridRect.midY + lineWidth,
                     width: gridRect.width / 2 - lineWidth * 1.5,
                     height: gridRect.height / 2 - lineWidth * 1.5)
    selRadius = 24
} else {
    // 大尺寸：格子内均匀内缩 14，像一扇吸附进去的窗口
    selRect = NSRect(x: gridRect.minX + 14,
                     y: gridRect.midY + lineWidth / 2 + 14,
                     width: cellW - 28,
                     height: cellH - 28)
    selRadius = 34
}
g.saveGState()
if !small {
    g.setShadow(offset: CGSize(width: 0, height: -14), blur: 36,
                color: NSColor(calibratedWhite: 0, alpha: 0.35).cgColor)
}
let sel = NSBezierPath(roundedRect: selRect, xRadius: selRadius, yRadius: selRadius)
NSColor(calibratedWhite: 1, alpha: 0.97).setFill()
sel.fill()
g.restoreGState()

// 选区顶部微亮渐层（仅大尺寸）
if !small {
    let selGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [
                                 NSColor(calibratedWhite: 1, alpha: 0.55).cgColor,
                                 NSColor(calibratedWhite: 1, alpha: 0).cgColor,
                             ] as CFArray, locations: [0, 1])!
    g.saveGState()
    sel.addClip()
    g.drawLinearGradient(selGrad,
                         start: CGPoint(x: selRect.midX, y: selRect.maxY),
                         end: CGPoint(x: selRect.midX, y: selRect.midY),
                         options: [])
    g.restoreGState()
}
g.restoreGState() // body clip

// 5) 主体内描边
let stroke = NSBezierPath(roundedRect: bodyRect.insetBy(dx: 1.5, dy: 1.5), xRadius: radius, yRadius: radius)
NSColor(calibratedWhite: 1, alpha: 0.30).setStroke()
stroke.lineWidth = 3
stroke.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outPath))
print("icon written: \(outPath)\(small ? " (small variant)" : "")")
