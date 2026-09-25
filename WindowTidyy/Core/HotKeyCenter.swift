import AppKit
import Carbon.HIToolbox
import Foundation

/// Carbon 全局快捷键注册（Quick Layout 用）
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var hotKeyRef: EventHotKeyRef?
    private var handler: (() -> Void)?
    private var installedEventHandler = false

    /// 注册全局快捷键；modifiers 为 0 表示注销
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        unregister()
        guard keyCode != 0, modifiers != 0 else { return }

        installEventHandlerIfNeeded()

        self.handler = handler
        var spec = EventHotKeyID(signature: OSType(0x57545959), // 'WTYY'
                                 id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, spec,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRef = ref
        } else {
            NSLog("WindowTidyy: 注册快捷键失败 (\(status))，可能与其他应用冲突")
            self.handler = nil
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        handler = nil
    }

    private func installEventHandlerIfNeeded() {
        guard !installedEventHandler else { return }
        installedEventHandler = true

        let handlerUPP: EventHandlerUPP = { _, event, userData in
            guard let userData else { return noErr }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            center.handler?()
            return noErr
        }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), handlerUPP, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), nil)
    }
}
