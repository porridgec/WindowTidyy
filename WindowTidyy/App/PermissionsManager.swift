import AppKit
import ApplicationServices
import Combine

/// 辅助功能权限的检测与轮询
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()

    private var timer: Timer?
    private var didPrompt = false

    func startPolling() {
        guard timer == nil else { return }
        // 未授权时弹一次系统授权引导（把 app 加进辅助功能列表，用户勾选即可）
        if !isTrusted { promptSystemOnce() }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = AXIsProcessTrusted()
            if trusted != self.isTrusted {
                self.isTrusted = trusted
            }
        }
    }

    func promptSystemOnce() {
        guard !didPrompt else { return }
        didPrompt = true
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
