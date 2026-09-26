import AppKit
import ApplicationServices
import Foundation

/// AppKit（左下原点）与 CG/AX（左上原点）全局坐标互转。
/// AX 的 kAXPosition、CGEvent 的光标位置都是左上原点；NSScreen/NSWindow 是左下原点。
enum ScreenMath {
    static var primaryMaxY: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    static func appKitPoint(fromCG p: CGPoint) -> NSPoint {
        NSPoint(x: p.x, y: primaryMaxY - p.y)
    }

    static func cgPoint(fromAppKit p: NSPoint) -> CGPoint {
        CGPoint(x: p.x, y: primaryMaxY - p.y)
    }

    static func cgRect(fromAppKit r: NSRect) -> CGRect {
        CGRect(x: r.minX, y: primaryMaxY - r.maxY, width: r.width, height: r.height)
    }

    static func appKitRect(fromCG r: CGRect) -> NSRect {
        NSRect(x: r.minX, y: primaryMaxY - r.maxY, width: r.width, height: r.height)
    }

    /// 光标（CG 坐标）所在的屏幕
    static func screen(containingCG point: CGPoint) -> NSScreen? {
        let p = appKitPoint(fromCG: point)
        return NSScreen.screens.first { NSPointInRect(p, $0.frame) }
    }

    /// 光标所在的屏幕（主线程）
    static func screenAtCursor() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSPointInRect(p, $0.frame) }
    }
}

extension NSScreen {
    /// 布局铺放的稳定基准：整屏去掉菜单栏（有菜单栏的屏），无视 Dock。
    /// 自动隐藏 Dock 会让 visibleFrame 在 Dock 伸出/缩回间动态变化，不能作为基准。
    var tilingBounds: NSRect {
        let topInset = max(0, frame.maxY - visibleFrame.maxY)
        return NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - topInset)
    }
}

/// 一次拖动跟踪的目标窗口
struct TargetWindow {
    let element: AXUIElement
    let ownerName: String?
}

/// AXUIElement 封装：取窗口、读 frame、移动缩放
final class WindowEngine {
    static let shared = WindowEngine()

    /// AXUIElement 实例非线程安全；主线程与事件 tap 线程各持一份，
    /// 共享同一实例会在 AX 运行时过度释放（实测 SIGSEV 于 CopyElementAtPosition）
    private let mainSystemWide = AXUIElementCreateSystemWide()
    private var tapSystemWide: AXUIElement?
    private let tapSystemWideLock = NSLock()
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private var systemWide: AXUIElement {
        if Thread.isMainThread { return mainSystemWide }
        tapSystemWideLock.lock()
        defer { tapSystemWideLock.unlock() }
        if tapSystemWide == nil {
            tapSystemWide = AXUIElementCreateSystemWide()
        }
        return tapSystemWide!
    }

    /// 光标点是否落在本 app 自己的窗口内。
    /// 不经 AX、只查窗口列表（CG 坐标）：点击自家 UI 时必须跳过 AX 自查询——
    /// 自家 SwiftUI 重绘繁忙时被查询会在 AX 框架内崩溃（编辑器拖选闪退的根因）。
    func isPointInsideOwnWindows(_ cgPoint: CGPoint) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
            as? [[String: Any]] else { return false }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? Int32) == ownPID,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                              width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            if rect.contains(cgPoint) { return true }
        }
        return false
    }

    // MARK: - 查找窗口

    /// 光标处的窗口：从命中的最深元素沿 kAXParent 上溯到 AXWindow，排除自身进程
    func windowUnderCursor(_ cgPoint: CGPoint) -> TargetWindow? {
        // 自家窗口直接跳过（同时省掉一次 AX IPC）
        guard !isPointInsideOwnWindows(cgPoint) else { return nil }
        var hit: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(systemWide,
                                                      Float(cgPoint.x), Float(cgPoint.y), &hit)
        guard status == .success, var node = hit else { return nil }

        for _ in 0..<16 {
            let pid = pid(of: node)
            if pid == ownPID { return nil }
            if Self.role(of: node) == kAXWindowRole {
                let name = NSRunningApplication(processIdentifier: pid)?.localizedName
                return TargetWindow(element: node, ownerName: name)
            }
            guard let parent = Self.attribute(node, kAXParentAttribute) else { return nil }
            node = unsafeBitCast(parent, to: AXUIElement.self)
        }
        return nil
    }

    /// 前台 app 的聚焦窗口（用于 Quick Layout），排除自身进程
    func frontmostWindow() -> TargetWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ownPID else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let win = Self.attribute(appElement, kAXFocusedWindowAttribute) else { return nil }
        return TargetWindow(element: unsafeBitCast(win, to: AXUIElement.self),
                            ownerName: app.localizedName)
    }

    /// 本 app 之下最靠前的其他 app 窗口（设置面板里的「应用到当前窗口」用，
    /// 因为点按钮时前台已经是本 app）
    func frontmostForeignWindow() -> TargetWindow? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pidValue = info[kCGWindowOwnerPID as String] as? Int32,
                  pidValue != ownPID,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w > 60, h > 60 else { continue }
            let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: w, height: h)
            if let win = window(owning: pidValue, near: rect) {
                let name = NSRunningApplication(processIdentifier: pidValue)?.localizedName
                return TargetWindow(element: win, ownerName: name)
            }
        }
        return nil
    }

    private func window(owning pid: pid_t, near rect: CGRect) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        guard let wins = Self.attribute(appElement, kAXWindowsAttribute) else { return nil }
        let array = unsafeBitCast(wins, to: NSArray.self)
        for case let win as CFTypeRef in array {
            let element = unsafeBitCast(win, to: AXUIElement.self)
            if let f = frame(of: element), abs(f.minX - rect.minX) < 1.5, abs(f.minY - rect.minY) < 1.5 {
                return element
            }
        }
        // 兜底：取第一个窗口
        for case let win as CFTypeRef in array {
            return unsafeBitCast(win, to: AXUIElement.self)
        }
        return nil
    }

    // MARK: - 读取

    func frame(of element: AXUIElement) -> CGRect? {
        guard let p = Self.attribute(element, kAXPositionAttribute),
              let s = Self.attribute(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    // MARK: - 应用布局

    /// 移动并缩放窗口到指定矩形（CG 左上原点坐标）。
    /// 顺序为「先位置、后尺寸」：窗口先到目标左上角、再向屏幕内扩展，避免从旧位置
    /// 扩展时边缘超出屏幕被钳制。设置后校验结果；自动隐藏 Dock 伸出时系统会把窗口
    /// 压回 Dock 上方，短暂重试等 Dock 缩回后即可落位。
    @discardableResult
    func setRect(_ cgRect: CGRect, on element: AXUIElement) -> Bool {
        var success = false
        for attempt in 0..<3 {
            success = applyOnce(cgRect, on: element)
            if success { break }
            if attempt < 2 { usleep(150_000) } // 150ms 后重试（等待自动隐藏 Dock 缩回）
        }
        return success
    }

    private func applyOnce(_ cgRect: CGRect, on element: AXUIElement) -> Bool {
        var size = cgRect.size
        var point = CGPoint(x: cgRect.minX, y: cgRect.minY)
        guard let sizeValue = AXValueCreate(.cgSize, &size),
              let pointValue = AXValueCreate(.cgPoint, &point) else { return false }
        let posOK = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString,
                                                 unsafeBitCast(pointValue, to: CFTypeRef.self)) == .success
        let sizeOK = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString,
                                                  unsafeBitCast(sizeValue, to: CFTypeRef.self)) == .success
        guard posOK && sizeOK else { return false }
        // 校验：被 Dock 钳制/应用自身约束时会偏离目标
        guard let result = frame(of: element) else { return true }
        let tolerance: CGFloat = 1.5
        let matched = abs(result.minX - cgRect.minX) <= tolerance
            && abs(result.minY - cgRect.minY) <= tolerance
            && abs(result.width - cgRect.width) <= tolerance
            && abs(result.height - cgRect.height) <= tolerance
        if !matched {
            WTLog.log("WTDBG [engine] setRect 偏离目标 result=\(result) target=\(cgRect)")
        }
        return matched
    }

    // MARK: - AX 基础

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func role(of element: AXUIElement) -> String? {
        guard let value = attribute(element, kAXRoleAttribute) else { return nil }
        return unsafeBitCast(value, to: NSString.self) as String
    }

    private func pid(of element: AXUIElement) -> pid_t {
        var pid: pid_t = -1
        AXUIElementGetPid(element, &pid)
        return pid
    }
}
