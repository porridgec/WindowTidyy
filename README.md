# WindowTidyy

复刻经典 Window Tidy（Light Pillar Software）的 macOS 窗口布局工具。拖动任意应用窗口时，屏幕顶部弹出布局预览条，把窗口拖到预览上松手即可吸附到位。

[![Swift](https://img.shields.io/badge/Swift-5-F05138)]() [![macOS](https://img.shields.io/badge/macOS-14%2B-000000)]() [![License: MIT](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

## 功能

- **布局编辑器**：模拟屏幕的网格画布（默认 6×6，可调 1–16），拖拽框选格子生成布局，与原版 Window Tidy 的数据模型完全一致
- **快速布局组**：自由增删「组」，组内自选布局（同网格），一个组 = 一个 overlay 瓦片；组内多个布局聚合显示，拖动悬停时按光标所在区域选择子布局（瓦片内移动即切换）
- **一键自动分组**：按互补关系（左右半屏、四分屏、三等分…恰好平铺整屏）自动生成分组建议，之后可自由调整（原版 AutoGroupLayouts 的可控版）
- **拖动应用**：拖动窗口到某个瓦片上松手，窗口自动移动缩放到该布局对应的屏幕区域（辅助功能 API），悬停时全屏高亮目标落区，支持多显示器跟随
- **触发方式可配**：按住修饰键（默认 ⌥）+ 拖动触发，或任意拖动触发，修饰键可自选
- **Quick Layout 网格直选**：快捷键（默认 ⌃⌥G）弹出全屏网格，拖一个一次性区域直接应用，无需预先保存
- 菜单栏常驻（无 Dock 图标）、登录自启、布局库增删改

## 构建与运行

```bash
brew install xcodegen   # 若未安装
./build.sh debug        # Debug 构建
./build.sh install      # Release 构建并安装到 /Applications
./build.sh test         # 单元测试
```

签名说明：仓库默认 ad-hoc 签名（无个人信息）。要让重新编译后**辅助功能授权不丢**，用你自己的开发证书——把 `signing.env.example` 复制为 `signing.env`（不入库）填入身份，`./build.sh` 会自动应用。不配置则每次 rebuild 后需重新授权一次。

首次启动会打开设置窗口，请在 **系统设置 › 隐私与安全性 › 辅助功能** 中勾选 WindowTidyy（应用会自动检测授权状态）。

## 使用

1. 菜单栏图标 → 打开设置，在「布局库」里框选编辑布局
2. 在「快速布局」里为 4 个槽位挑选布局
3. 按住 ⌥ 拖动任意窗口 → 顶部出现预览条 → 拖到目标瓦片上松手
4. ⌃⌥G 弹出 Quick Layout 网格，拖框直选一次性区域

## 注意

- macOS 自带「拖到屏幕边缘平铺窗口」（Sequoia 及以后）可能在屏幕顶部与本功能叠加，如困扰可在 系统设置 › 桌面与程序坞 中关闭
- 布局铺放基于「整屏去掉菜单栏」的稳定基准，无视 Dock（自动隐藏 Dock 伸出时铺放的窗口会被系统短暂钳制，应用会自动重试落位；鼠标停在屏幕底部边缘保持 Dock 伸出时除外）

## 安全与隐私

零网络代码、零遥测；只读窗口几何不读内容；事件监听为 listen-only。完整的信任模型与审计结论见 [SECURITY.md](SECURITY.md)。

## 从源码构建（fork 者）

`./build.sh` 默认 ad-hoc 签名。要固定签名身份：复制 `signing.env.example` 为 `signing.env`（已 gitignore），填入你钥匙串里的证书名与 Team ID 即可，无需改动工程文件。

应用图标由 `scripts/render_icon.swift` 用 CoreGraphics 渲染（`swift scripts/render_icon.swift output.png [small]`），重新生成 icns 后放入 `WindowTidyy/Resources/`。

## 架构

```
WindowTidyy/
├── App/
│   ├── AppDelegate.swift        # agent 壳：菜单栏、设置窗口、组件接线
│   ├── SettingsStore.swift      # 配置模型 + JSON 持久化
│   └── PermissionsManager.swift # 辅助功能权限检测/轮询
├── Core/
│   ├── LayoutItem.swift         # 布局模型（网格 + 单元格区间，同原版）
│   ├── WindowEngine.swift       # AXUIElement 封装 + AppKit/CG 坐标换算
│   ├── DragMonitor.swift        # CGEventTap 拖动状态机
│   ├── OverlayController.swift  # 顶部瓦片条 + 目标区域预览层
│   ├── QuickLayoutController.swift # Quick Layout 面板
│   └── HotKeyCenter.swift       # Carbon 全局快捷键
└── UI/                          # SwiftUI 界面（设置/编辑器/瓦片/网格）
```

运行链路：`DragMonitor`（CGEventTap）检测到窗口被真实拖动 → `OverlayController` 在光标所在屏幕顶部显示 4 个瓦片 → 光标坐标命中测试驱动悬停高亮与落区预览 → 松手在瓦片上时经 `WindowEngine`（AX API）把窗口设为目标矩形。
