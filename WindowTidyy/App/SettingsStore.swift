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

/// 快速瓦片组：组内自选若干布局（建议同一网格尺寸），一个组在 overlay 里即一个瓦片；
/// 组内多个布局时，拖动悬停按光标所在区域选择子布局。
struct QuickGroup: Codable, Equatable, Identifiable {
    var id = UUID()
    /// 组内布局（引用布局库 id，顺序即瓦片内子布局顺序）
    var layoutIDs: [UUID] = []

    /// 组内实际布局（过滤已删除引用）
    func layouts(in library: [LayoutItem]) -> [LayoutItem] {
        layoutIDs.compactMap { id in library.first(where: { $0.id == id }) }
    }
}

struct AppSettings: Codable, Equatable {
    /// 总开关
    var enabled = true
    /// 布局库
    var layouts = LayoutItem.defaults
    /// 快速瓦片组（一个组 = 一个 overlay 瓦片；替代旧版固定 4 槽位）
    var groups: [QuickGroup] = []
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
        groups = layouts.map { QuickGroup(layoutIDs: [$0.id]) }
    }

    // 自定义解码：容忍旧版本配置缺字段
    enum CodingKeys: String, CodingKey {
        case enabled, layouts, groups, triggerMode, triggerModifierMask
        case showTileTitles, quickGridX, quickGridY, quickHotkey
    }

    /// 旧版（固定 4 槽位）字段，仅用于迁移读取
    private enum LegacyKeys: String, CodingKey {
        case quickSlotIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        layouts = try c.decodeIfPresent([LayoutItem].self, forKey: .layouts) ?? LayoutItem.defaults
        triggerMode = try c.decodeIfPresent(TriggerMode.self, forKey: .triggerMode) ?? .modifier
        triggerModifierMask = try c.decodeIfPresent(UInt.self, forKey: .triggerModifierMask)
            ?? NSEvent.ModifierFlags.option.deviceIndependentRawValue
        showTileTitles = try c.decodeIfPresent(Bool.self, forKey: .showTileTitles) ?? true
        quickGridX = try c.decodeIfPresent(Int.self, forKey: .quickGridX) ?? 6
        quickGridY = try c.decodeIfPresent(Int.self, forKey: .quickGridY) ?? 6
        quickHotkey = try c.decodeIfPresent(HotKeyCombo.self, forKey: .quickHotkey)
            ?? HotKeyCombo(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(controlKey | optionKey))

        if let loaded = try c.decodeIfPresent([QuickGroup].self, forKey: .groups) {
            groups = loaded
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            if let legacySlots = try legacy.decodeIfPresent([UUID?].self, forKey: .quickSlotIDs) {
                // 旧版（固定 4 槽位）迁移：每个非空槽位 → 单成员组
                groups = legacySlots.compactMap { $0 }.map { QuickGroup(layoutIDs: [$0]) }
            } else {
                groups = layouts.map { QuickGroup(layoutIDs: [$0.id]) }
            }
        }
        repairGroups()
    }

    /// 清理引用了已删除布局的组成员
    mutating func repairGroups() {
        for i in groups.indices {
            groups[i].layoutIDs = groups[i].layoutIDs.filter { id in
                layouts.contains(where: { $0.id == id })
            }
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
        s.repairGroups()
        settings = s
    }

    /// overlay 实际显示的瓦片：一个组 → 一个瓦片（空组跳过）
    var quickTiles: [OverlayTile] {
        settings.groups.compactMap { group in
            let members = group.layouts(in: settings.layouts)
            if members.isEmpty { return nil }
            return members.count == 1 ? .single(members[0]) : .group(members)
        }
    }

    // MARK: - 布局库

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

    // MARK: - 快速组

    func addGroup() {
        update { $0.groups.append(QuickGroup(layoutIDs: [])) }
    }

    func deleteGroup(id: UUID) {
        update { $0.groups.removeAll(where: { $0.id == id }) }
    }

    /// 组排序（瓦片条顺序）
    func moveGroup(id: UUID, delta: Int) {
        update { s in
            guard let idx = s.groups.firstIndex(where: { $0.id == id }) else { return }
            let target = idx + delta
            guard s.groups.indices.contains(target) else { return }
            s.groups.swapAt(idx, target)
        }
    }

    /// 组内布局勾选
    func toggleLayout(_ layoutID: UUID, in group: QuickGroup) {
        update { s in
            guard let idx = s.groups.firstIndex(where: { $0.id == group.id }) else { return }
            if let memberIdx = s.groups[idx].layoutIDs.firstIndex(of: layoutID) {
                s.groups[idx].layoutIDs.remove(at: memberIdx)
            } else {
                s.groups[idx].layoutIDs.append(layoutID)
            }
        }
    }

    /// 一键按互补自动分组（替换现有分组；互补算法仅为初始建议，之后完全手动可控）
    func autoGroup() {
        update { s in
            let tiles = LayoutGrouping.overlayTiles(from: s.layouts)
            s.groups = tiles.map { QuickGroup(layoutIDs: $0.layouts.map(\.id)) }
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
