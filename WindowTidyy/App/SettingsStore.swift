import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

enum TriggerMode: String, Codable, CaseIterable, Identifiable {
    /// 按住修饰键 + 拖动窗口时触发
    case modifier
    /// 任意窗口拖动即触发
    case anyDrag

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .modifier: return "按住修饰键 + 拖动窗口时触发"
        case .anyDrag: return "任意拖动窗口时触发"
        }
    }
}

/// 全局快捷键组合（Carbon 键码/修饰键，便于注册）
struct HotKeyCombo: Codable, Equatable {
    /// 虚拟键码（与 NSEvent.keyCode 一致）
    var keyCode: UInt32
    /// Carbon 修饰键掩码（cmdKey / optionKey / controlKey / shiftKey 组合）
    var modifiers: UInt32

    var display: String {
        var s = ""
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        return s + KeyCodeFormatter.symbol(for: keyCode)
    }

    /// NSEvent 修饰键 → Carbon 修饰键掩码
    static func carbonMask(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }
}

enum KeyCodeFormatter {
    /// 常用虚拟键码 → 显示字符
    static func symbol(for code: UInt32) -> String {
        switch code {
        case UInt32(kVK_ANSI_A): return "A"
        case UInt32(kVK_ANSI_B): return "B"
        case UInt32(kVK_ANSI_C): return "C"
        case UInt32(kVK_ANSI_D): return "D"
        case UInt32(kVK_ANSI_E): return "E"
        case UInt32(kVK_ANSI_F): return "F"
        case UInt32(kVK_ANSI_G): return "G"
        case UInt32(kVK_ANSI_H): return "H"
        case UInt32(kVK_ANSI_I): return "I"
        case UInt32(kVK_ANSI_J): return "J"
        case UInt32(kVK_ANSI_K): return "K"
        case UInt32(kVK_ANSI_L): return "L"
        case UInt32(kVK_ANSI_M): return "M"
        case UInt32(kVK_ANSI_N): return "N"
        case UInt32(kVK_ANSI_O): return "O"
        case UInt32(kVK_ANSI_P): return "P"
        case UInt32(kVK_ANSI_Q): return "Q"
        case UInt32(kVK_ANSI_R): return "R"
        case UInt32(kVK_ANSI_S): return "S"
        case UInt32(kVK_ANSI_T): return "T"
        case UInt32(kVK_ANSI_U): return "U"
        case UInt32(kVK_ANSI_V): return "V"
        case UInt32(kVK_ANSI_W): return "W"
        case UInt32(kVK_ANSI_X): return "X"
        case UInt32(kVK_ANSI_Y): return "Y"
        case UInt32(kVK_ANSI_Z): return "Z"
        case UInt32(kVK_Space): return "空格"
        case UInt32(kVK_Return): return "↩"
        case UInt32(kVK_Tab): return "⇥"
        case UInt32(kVK_Escape): return "esc"
        default: return "键(\(code))"
        }
    }
}

struct AppSettings: Codable, Equatable {
    /// 总开关
    var enabled = true
    /// 布局库
    var layouts = LayoutItem.defaults
    /// 4 个快速槽位（引用布局库 id，nil = 未使用）
    var quickSlotIDs: [UUID?] = []
    /// 触发方式
    var triggerMode = TriggerMode.modifier
    /// 触发修饰键掩码（NSEvent.ModifierFlags 设备无关位），默认 Option
    var triggerModifierMask: UInt = NSEvent.ModifierFlags.option.deviceIndependentRawValue
    /// 瓦片上是否显示布局名称
    var showTileTitles = true
    // Quick Layout 网格直选
    var quickGridX = 6
    var quickGridY = 6
    var quickHotkey: HotKeyCombo? = HotKeyCombo(keyCode: UInt32(kVK_ANSI_G),
                                                modifiers: UInt32(controlKey | optionKey))

    init() {
        quickSlotIDs = layouts.map { $0.id }
    }

    // 自定义解码：容忍旧版本配置缺字段
    enum CodingKeys: String, CodingKey {
        case enabled, layouts, quickSlotIDs, triggerMode, triggerModifierMask
        case showTileTitles, quickGridX, quickGridY, quickHotkey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        layouts = try c.decodeIfPresent([LayoutItem].self, forKey: .layouts) ?? LayoutItem.defaults
        quickSlotIDs = try c.decodeIfPresent([UUID?].self, forKey: .quickSlotIDs) ?? layouts.map { $0.id }
        triggerMode = try c.decodeIfPresent(TriggerMode.self, forKey: .triggerMode) ?? .modifier
        triggerModifierMask = try c.decodeIfPresent(UInt.self, forKey: .triggerModifierMask)
            ?? NSEvent.ModifierFlags.option.deviceIndependentRawValue
        showTileTitles = try c.decodeIfPresent(Bool.self, forKey: .showTileTitles) ?? true
        quickGridX = try c.decodeIfPresent(Int.self, forKey: .quickGridX) ?? 6
        quickGridY = try c.decodeIfPresent(Int.self, forKey: .quickGridY) ?? 6
        quickHotkey = try c.decodeIfPresent(HotKeyCombo.self, forKey: .quickHotkey)
            ?? HotKeyCombo(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(controlKey | optionKey))
        repairQuickSlots()
    }

    /// 清理引用了已删除布局的槽位
    mutating func repairQuickSlots() {
        quickSlotIDs = quickSlotIDs.map { id in
            guard let id, layouts.contains(where: { $0.id == id }) else { return nil }
            return id
        }
    }
}

extension NSEvent.ModifierFlags {
    /// 设备无关位掩码（用于持久化与比较）
    var deviceIndependentRawValue: UInt {
        rawValue & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
    }
}

/// 配置中心：内存态 + JSON 持久化（~/Library/Application Support/WindowTidyy/settings.json）
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published private(set) var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            persist()
        }
    }

    let settingsURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("WindowTidyy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        settingsURL = dir.appendingPathComponent("settings.json")

        if let data = try? Data(contentsOf: settingsURL),
           let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = loaded
        } else {
            settings = AppSettings()
        }
    }

    // MARK: - 修改入口（主线程调用）

    func update(_ mutate: (inout AppSettings) -> Void) {
        var s = settings
        mutate(&s)
        s.repairQuickSlots()
        settings = s
    }

    /// 槽位实际生效的布局（按槽位顺序，跳过未使用）
    var quickLayouts: [LayoutItem] {
        settings.quickSlotIDs.compactMap { id in
            guard let id else { return nil }
            return settings.layouts.first(where: { $0.id == id })
        }
    }

    func addLayout() {
        update { s in
            s.layouts.append(LayoutItem(name: "新布局 \(s.layouts.count + 1)",
                                        gridX: 6, gridY: 6, startX: 0, startY: 0, endX: 3, endY: 3))
        }
    }

    func deleteLayout(id: UUID) {
        update { s in
            s.layouts.removeAll(where: { $0.id == id })
        }
    }

    func duplicateLayout(id: UUID) {
        update { s in
            guard let idx = s.layouts.firstIndex(where: { $0.id == id }) else { return }
            var copy = s.layouts[idx]
            copy.id = UUID()
            copy.name += " 副本"
            s.layouts.insert(copy, at: idx + 1)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        // 配置文件仅含布局/快捷键数据，仍统一收紧为仅本人可读写
        try? data.write(to: settingsURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: settingsURL.path)
    }
}
