import AppKit
import ApplicationServices
import Foundation

/// 全局窗口拖动监听（CGEventTap 独立线程），复刻 Window Tidy 的 DragMonitor 状态机：
/// 按下 → 判定为「正在拖动窗口」（窗口 frame 真的在变）→ 显示 overlay → 松手应用。
final class DragMonitor {
    struct Config {
        var enabled = true
        var mode = TriggerMode.modifier
        var modifierMask = NSEvent.ModifierFlags.option.deviceIndependentRawValue
    }

    private enum Phase {
        case idle
        /// 已按下（含按下瞬间解析到的候选窗口），等待出现位移
        case pendingDrag(downPoint: CGPoint, candidate: TargetWindow?, referenceFrame: CGRect?)
        /// 满足触发条件，等窗口 frame 真的移动（排除框选文字等原地拖动）
        case confirming(target: TargetWindow, referenceFrame: CGRect)
        /// overlay 已显示，正在拖动
        case active(target: TargetWindow)
    }

    // 状态机只在事件 tap 线程读写；config 跨线程用锁
    private var phase: Phase = .idle
    private let configLock = NSLock()
    private var config = Config()

    private var tap: CFMachPort?
    private var tapThread: Thread?

    // 回调统一派发到主线程
    /// 拖动确认，显示 overlay（参数：光标 CG 坐标）
    var onActivate: ((TargetWindow, CGPoint) -> Void)?
    /// 拖动过程中光标移动（overlay 命中测试/换屏）
    var onDragUpdate: ((CGPoint) -> Void)?
    /// 松手（无论是否命中瓦片，由 overlay 决定应用或忽略）
    var onDrop: ((TargetWindow, CGPoint) -> Void)?

    private let cursorMoveThreshold: CGFloat = 6
    private let windowMoveThreshold: CGFloat = 5

    private func dgLog(_ msg: String) {
        WTLog.log("WTDBG [monitor] \(msg)")
    }

    // MARK: - 生命周期

    func start() {
        guard tap == nil else { return }
        let thread = Thread { [weak self] in
            self?.installTapOnCurrentThread()
        }
        thread.name = "WindowTidyy.DragMonitor"
        thread.start()
        tapThread = thread
    }

    func stop() {
        guard let tap else { return }
        CFMachPortInvalidate(tap)
        self.tap = nil
        tapThread = nil
    }

    func applyConfig(_ newConfig: Config) {
        configLock.lock()
        config = newConfig
        configLock.unlock()
    }

    private var currentConfig: Config {
        configLock.lock()
        defer { configLock.unlock() }
        return config
    }

    // MARK: - Event Tap

    private func installTapOnCurrentThread() {
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            let monitor = Unmanaged<DragMonitor>.fromOpaque(userInfo!).takeUnretainedValue()
            monitor.handle(eventType: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                              place: .headInsertEventTap,
                                              options: .listenOnly,
                                              eventsOfInterest: mask,
                                              callback: callback,
                                              userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            WTLog.log("WTDBG [monitor] 创建 CGEventTap 失败（通常是还没有辅助功能权限）")
            return
        }
        tap = created
        guard let source = CFMachPortCreateRunLoopSource(nil, created, 0) else { return }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        WTLog.log("WTDBG [monitor] event tap 已启动")
        CFRunLoopRun()
    }

    // MARK: - 状态机

    private func handle(eventType: CGEventType, event: CGEvent) {
        switch eventType {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            break
        default:
            return
        }

        let location = event.location // CG 左上原点全局坐标

        switch eventType {
        case .leftMouseDown:
            guard case .idle = phase else { return }
            // 按下瞬间光标必然在目标窗口上（拖动由按下开始），此刻解析最可靠；
            // 拖动过程中再解析会因窗口跟随延迟跑到窗口边缘之外而失败
            let candidate = WindowEngine.shared.windowUnderCursor(location)
            let ref = candidate.flatMap { WindowEngine.shared.frame(of: $0.element) }
            dgLog("mouseDown at \(location), candidate=\(candidate?.ownerName ?? "nil")")
            phase = .pendingDrag(downPoint: location, candidate: candidate, referenceFrame: ref)

        case .leftMouseDragged:
            switch phase {
            case .idle:
                return
            case let .pendingDrag(down, candidate, referenceFrame):
                guard distance(location, down) > cursorMoveThreshold else { return }
                guard triggerSatisfied(event) else {
                    dgLog("drag detected but trigger NOT satisfied (\(currentConfig.mode))")
                    return
                }
                // 优先用按下瞬间解析到的窗口；失败才回退到光标处现解析
                var target = candidate
                var reference = referenceFrame
                if target == nil || reference == nil {
                    target = WindowEngine.shared.windowUnderCursor(location)
                    reference = target.flatMap { WindowEngine.shared.frame(of: $0.element) }
                }
                guard let resolved = target, let ref = reference else {
                    dgLog("no window under cursor \(location) — reset")
                    phase = .idle
                    return
                }
                dgLog("window resolved: \(resolved.ownerName ?? "?") ref=\(ref)")
                dgLog("confirming window movement")
                phase = .confirming(target: resolved, referenceFrame: ref)

            case let .confirming(target, reference):
                guard let frame = WindowEngine.shared.frame(of: target.element) else {
                    dgLog("lost frame while confirming — reset")
                    phase = .idle
                    return
                }
                if abs(frame.origin.x - reference.origin.x) > windowMoveThreshold
                    || abs(frame.origin.y - reference.origin.y) > windowMoveThreshold {
                    dgLog("window IS moving → ACTIVE")
                    phase = .active(target: target)
                    let cb = onActivate
                    DispatchQueue.main.async { cb?(target, location) }
                }

            case .active:
                let cb = onDragUpdate
                DispatchQueue.main.async { cb?(location) }
            }

        case .leftMouseUp:
            var droppedTarget: TargetWindow?
            if case let .active(target) = phase {
                droppedTarget = target
            }
            if let target = droppedTarget {
                dgLog("mouseUp while ACTIVE — resolving drop at \(location)")
                let cb = onDrop
                DispatchQueue.main.async { cb?(target, location) }
            }
            phase = .idle

        default:
            return
        }
    }

    private func triggerSatisfied(_ event: CGEvent) -> Bool {
        let cfg = currentConfig
        guard cfg.enabled else { return false }
        switch cfg.mode {
        case .anyDrag:
            return true
        case .modifier:
            let held = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                .intersection(.deviceIndependentFlagsMask)
            return cfg.modifierMask != 0 && held.rawValue & cfg.modifierMask == cfg.modifierMask
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
