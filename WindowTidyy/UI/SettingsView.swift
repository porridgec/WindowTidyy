import AppKit
import SwiftUI

/// 设置中心：权限引导横幅 + 三个标签页
struct SettingsView: View {
    @EnvironmentObject var store: SettingsStore
    @EnvironmentObject var permissions: PermissionsManager

    var body: some View {
        VStack(spacing: 0) {
            if !permissions.isTrusted {
                PermissionBannerView()
            }
            TabView {
                LayoutLibraryTab()
                    .tabItem { Label("布局库", systemImage: "square.grid.3x3") }
                QuickSlotsTab()
                    .tabItem { Label("快速布局", systemImage: "bolt.horizontal") }
                TriggerTab()
                    .tabItem { Label("触发与显示", systemImage: "slider.horizontal.3") }
            }
            .padding(12)
        }
        .frame(minWidth: 820, minHeight: 580)
    }
}

// MARK: - 布局库

struct LayoutLibraryTab: View {
    @EnvironmentObject var store: SettingsStore
    @State private var selectedID: UUID?

    private var selected: LayoutItem? {
        store.settings.layouts.first(where: { $0.id == selectedID })
            ?? store.settings.layouts.first
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(store.settings.layouts) { item in
                        HStack(spacing: 8) {
                            LayoutPreviewView(item: item)
                                .frame(width: 46, height: 30)
                            Text(item.name).lineLimit(1)
                        }
                        .padding(.vertical, 2)
                        .tag(item.id)
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 230)

                HStack(spacing: 4) {
                    Button {
                        store.addLayout()
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button {
                        if let id = selected?.id { store.duplicateLayout(id: id) }
                    } label: {
                        Image(systemName: "plus.square.on.square")
                    }
                    Button {
                        if let id = selected?.id { store.deleteLayout(id: id) }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(store.settings.layouts.count <= 1)
                    Spacer()
                }
                .padding(8)
            }

            if let item = selected {
                LayoutEditorView(item: layoutBinding(item), screen: NSScreen.main)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("选择或新建一个布局")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func layoutBinding(_ item: LayoutItem) -> Binding<LayoutItem> {
        Binding(
            get: { store.settings.layouts.first(where: { $0.id == item.id }) ?? item },
            set: { newValue in
                store.update { s in
                    if let idx = s.layouts.firstIndex(where: { $0.id == newValue.id }) {
                        s.layouts[idx] = newValue
                    }
                }
            })
    }
}

// MARK: - 快速布局

struct QuickSlotsTab: View {
    @EnvironmentObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("拖动窗口时，屏幕顶部将按以下顺序显示布局预览；把窗口拖到某个预览上松手即可应用。")
                .font(.callout)
                .foregroundStyle(.secondary)

            // 模拟瓦片条
            HStack(spacing: OverlayMetrics.spacing) {
                ForEach(Array(store.quickLayouts.enumerated()), id: \.element.id) { idx, item in
                    VStack(spacing: 4) {
                        LayoutPreviewView(item: item)
                            .frame(width: OverlayMetrics.tileWidth - 16,
                                   height: 46)
                        Text(item.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: OverlayMetrics.tileWidth - 16, height: 74)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                    )
                    .opacity(idx == 0 ? 1 : 0.85)
                }
                if store.quickLayouts.isEmpty {
                    Text("没有可用的布局 — 请先在「布局库」选择")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .padding(OverlayMetrics.padding)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { i in
                    Picker("槽位 \(i + 1)", selection: slotBinding(i)) {
                        Text("未使用").tag(UUID?.none)
                        ForEach(store.settings.layouts) { item in
                            Text(item.name).tag(UUID?.some(item.id))
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(24)
    }

    private func slotBinding(_ index: Int) -> Binding<UUID?> {
        Binding(
            get: {
                store.settings.quickSlotIDs.indices.contains(index)
                    ? store.settings.quickSlotIDs[index] : nil
            },
            set: { value in
                store.update { s in
                    while s.quickSlotIDs.count < 4 { s.quickSlotIDs.append(nil) }
                    s.quickSlotIDs[index] = value
                }
            })
    }
}

// MARK: - 触发与显示

struct TriggerTab: View {
    @EnvironmentObject var store: SettingsStore
    @EnvironmentObject var permissions: PermissionsManager

    var body: some View {
        Form {
            Section("拖拽触发") {
                Picker("触发方式", selection: modeBinding) {
                    ForEach(TriggerMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                if store.settings.triggerMode == .modifier {
                    HStack {
                        Text("触发修饰键")
                        Spacer()
                        modifierToggle(.command, "⌘ Command")
                        modifierToggle(.option, "⌥ Option")
                        modifierToggle(.control, "⌃ Control")
                        modifierToggle(.shift, "⇧ Shift")
                    }
                    Text("拖动窗口过程中按住/松开修饰键可随时显示或隐藏预览条。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("启用拖拽布局（总开关）", isOn: enabledBinding)
            }

            Section("瓦片条显示") {
                Toggle("在预览瓦片上显示布局名称", isOn: titlesBinding)
            }

            Section("Quick Layout 网格直选") {
                HStack {
                    Text("快捷键")
                    HotKeyRecorder(combo: hotkeyBinding)
                }
                HStack {
                    Stepper("网格 \(store.settings.quickGridX) 列",
                            value: Binding(
                                get: { store.settings.quickGridX },
                                set: { v in store.update { $0.quickGridX = min(max(v, 1), 24) } }),
                            in: 1...24)
                    Stepper("\(store.settings.quickGridY) 行",
                            value: Binding(
                                get: { store.settings.quickGridY },
                                set: { v in store.update { $0.quickGridY = min(max(v, 1), 24) } }),
                            in: 1...24)
                }
                Text("按下快捷键弹出全屏网格，拖出一个一次性区域，直接应用到当前窗口 — 无需预先保存布局。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("提示：macOS 自带的「拖到屏幕边缘平铺窗口」可能在屏幕顶部与本功能叠加。如需关闭，请前往 系统设置 › 桌面与程序坞 › 将窗口拖到屏幕边缘时平铺。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var modeBinding: Binding<TriggerMode> {
        Binding(get: { store.settings.triggerMode },
                set: { v in store.update { $0.triggerMode = v } })
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { store.settings.enabled },
                set: { v in store.update { $0.enabled = v } })
    }

    private var titlesBinding: Binding<Bool> {
        Binding(get: { store.settings.showTileTitles },
                set: { v in store.update { $0.showTileTitles = v } })
    }

    private var hotkeyBinding: Binding<HotKeyCombo?> {
        Binding(get: { store.settings.quickHotkey },
                set: { v in store.update { $0.quickHotkey = v } })
    }

    private func modifierToggle(_ flag: NSEvent.ModifierFlags, _ title: String) -> some View {
        let mask = flag.deviceIndependentRawValue
        return Toggle(title, isOn: Binding(
            get: { store.settings.triggerModifierMask & mask != 0 },
            set: { on in
                store.update { s in
                    var newMask = s.triggerModifierMask
                    if on {
                        newMask |= mask
                    } else {
                        newMask &= ~mask
                    }
                    // 至少保留一个修饰键，否则 Option 拖动模式无法触发
                    if newMask != 0 { s.triggerModifierMask = newMask }
                }
            }))
        .toggleStyle(.button)
    }
}
