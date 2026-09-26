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

// MARK: - 快速布局（自定义组：一组 = 一个瓦片）

struct QuickSlotsTab: View {
    @EnvironmentObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("拖动窗口时，屏幕顶部按以下顺序显示瓦片。一个「组」即一个瓦片：组内放一个布局就是普通瓦片，放多个布局则聚合显示，拖动悬停时按光标所在区域选择子布局。")
                .font(.callout)
                .foregroundStyle(.secondary)

            // 模拟瓦片条（与拖动时的 overlay 完全一致）
            Group {
                if store.quickTiles.isEmpty {
                    Text("暂无瓦片 — 点击下方「添加组」并在组内勾选布局")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    TileRowView(tiles: store.quickTiles,
                                hoveredIndex: nil,
                                hoveredSubIndex: 0,
                                showTitles: true)
                }
            }
            .padding(OverlayMetrics.padding)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            StripPositionEditor()

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(store.settings.groups.enumerated()), id: \.element.id) { index, group in
                        GroupEditorCard(index: index, group: group)
                    }
                }
            }

            HStack {
                Button {
                    store.addGroup()
                } label: {
                    Label("添加组", systemImage: "plus")
                }
                Button {
                    store.autoGroup()
                } label: {
                    Label("按互补自动分组", systemImage: "wand.and.stars")
                }
                Spacer()
                Text("自动分组会按互补关系重建所有组，之后可自由调整")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }
}

/// 单个组的编辑卡片：成员预览 + 排序/删除 + 布局库勾选（同一网格的布局才能进同一组）
struct GroupEditorCard: View {
    let index: Int
    let group: QuickGroup

    @EnvironmentObject var store: SettingsStore

    private var members: [LayoutItem] {
        group.layouts(in: store.settings.layouts)
    }

    /// 组内首个成员的网格（约束后续只能勾选同网格布局）
    private var memberGrid: (x: Int, y: Int)? {
        members.first.map { ($0.gridX, $0.gridY) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("组 \(index + 1)")
                    .font(.headline)
                Text(members.isEmpty ? "未选择布局" : members.map(\.name).joined(separator: "+"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                // 瓦片条顺序 = 组顺序
                Button {
                    store.moveGroup(id: group.id, delta: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(index == 0)
                .help("上移")
                Button {
                    store.moveGroup(id: group.id, delta: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(index == store.settings.groups.count - 1)
                .help("下移")
                Button {
                    store.deleteGroup(id: group.id)
                } label: {
                    Image(systemName: "trash")
                }
                .help("删除组")
            }

            if members.count > 1 {
                TilePreview(tile: .group(members), hovered: false, activeIndex: nil)
                    .frame(width: 108, height: 62)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: TileStyle.cornerRadius, style: .continuous)
                            .fill(TileStyle.background.opacity(TileStyle.backgroundOpacity))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: TileStyle.cornerRadius, style: .continuous)
                            .strokeBorder(TileStyle.border, lineWidth: 1)
                    )
                    .help("瓦片预览：拖动悬停时按光标所在区域选择子布局")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 6)], spacing: 6) {
                ForEach(store.settings.layouts) { layout in
                    chip(layout)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func chip(_ layout: LayoutItem) -> some View {
        let selected = group.layoutIDs.contains(layout.id)
        // 同组布局需同网格，否则瓦片内区域/命中无法对齐
        let gridMismatch = memberGrid != nil
            && (layout.gridX != memberGrid!.x || layout.gridY != memberGrid!.y)
        let disabled = !selected && gridMismatch

        return Button {
            store.toggleLayout(layout.id, in: group)
        } label: {
            HStack(spacing: 5) {
                LayoutPreviewView(item: layout)
                    .frame(width: 30, height: 20)
                Text(layout.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                Capsule().fill(selected ? Color.accentColor.opacity(0.85)
                                        : Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule().strokeBorder(selected ? Color.clear : Color.primary.opacity(0.12),
                                       lineWidth: 1)
            )
            .foregroundStyle(selected ? .white : .primary)
            .opacity(disabled ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(disabled ? "网格尺寸（\(layout.gridX)×\(layout.gridY)）与本组（\(memberGrid!.x)×\(memberGrid!.y)）不同" : "")
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
                Text("瓦片的分组与顺序在「快速布局」页配置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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


/// 瓦片条位置编辑：模拟屏幕的预览画布，自由拖动迷你瓦片条（原版 PositionPreviewView 的自由拖动版）
struct StripPositionEditor: View {
    @EnvironmentObject var store: SettingsStore

    /// 迷你瓦片条相对画布的宽度比例（按 1800pt 宽屏幕估算）
    private var stripWidthRatio: CGFloat {
        min(max(OverlayMetrics.stripWidth(tileCount: max(store.quickTiles.count, 1)) / 1800.0, 0.12), 0.9)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("瓦片条显示位置")
                .font(.headline)
            Text("拖动画布中的瓦片条调整其出现位置（拖动窗口时按此位置显示）")
                .font(.caption)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let sw = geo.size.width * stripWidthRatio
                let sh = sw * (OverlayMetrics.stripHeight / max(OverlayMetrics.stripWidth(tileCount: max(store.quickTiles.count, 1)), 1))

                ZStack(alignment: .topLeading) {
                    // 屏幕画布
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                        )

                    // 迷你瓦片条（按当前组数画小方块）
                    miniStrip(count: store.quickTiles.count)
                        .frame(width: sw, height: sh)
                        .offset(x: min(max(geo.size.width * pos.x - sw / 2, 0), geo.size.width - sw),
                                y: min(max(geo.size.height * pos.y - sh / 2, 0), geo.size.height - sh))
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let cx = min(max(value.location.x, sw / 2), geo.size.width - sw / 2)
                            let cy = min(max(value.location.y, sh / 2), geo.size.height - sh / 2)
                            store.update { s in
                                s.stripPositionX = Double(cx / geo.size.width)
                                s.stripPositionY = Double(cy / geo.size.height)
                            }
                        }
                )
            }
            .aspectRatio(1.6, contentMode: .fit)
            .frame(maxWidth: .infinity)

            HStack {
                Text(String(format: "水平 %.0f%% · 距顶部 %.0f%%", pos.x * 100, pos.y * 100))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("重置到顶部居中") {
                    store.update { s in
                        s.stripPositionX = 0.5
                        s.stripPositionY = 0.06
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var pos: CGPoint {
        CGPoint(x: store.settings.stripPositionX, y: store.settings.stripPositionY)
    }

    private func miniStrip(count: Int) -> some View {
        let tiles = max(min(count, 8), 1)
        return HStack(spacing: 2) {
            ForEach(0..<tiles, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.32))
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(TileStyle.background.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(TileStyle.border, lineWidth: 1)
        )
    }
}
