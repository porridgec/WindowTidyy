import AppKit
import SwiftUI

/// 全局快捷键录制控件：点击进入录制，按下「修饰键 + 字符键」完成，esc 取消
struct HotKeyRecorder: View {
    @Binding var combo: HotKeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? cancelRecording() : startRecording()
            } label: {
                Text(recording ? "按下新组合键…" : (combo?.display ?? "未设置"))
                    .frame(minWidth: 120)
                    .monospaced()
            }
            if combo != nil {
                Button {
                    combo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: recording) { _, active in
            if !active, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
        .onDisappear {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard recording else { return event }
            // esc 取消录制
            if event.keyCode == 53 {
                DispatchQueue.main.async { cancelRecording() }
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let carbonMask = HotKeyCombo.carbonMask(from: flags)
            // 至少一个修饰键，避免单键全局热键
            if carbonMask == 0 {
                NSSound.beep()
                return nil
            }
            combo = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: carbonMask)
            DispatchQueue.main.async {
                recording = false
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
            }
            return nil
        }
    }

    private func cancelRecording() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
