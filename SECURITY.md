# 安全与隐私

## 信任模型

WindowTidyy 是一款窗口平铺工具，与 Rectangle / Magnet / Window Tidy 同类，其能力来自你手动授予的**辅助功能（Accessibility）权限**。应用刻意**不做沙盒**——沙盒应用无法控制其他应用的窗口，这是此类工具的固有前提。

你能授予什么，它就只能做什么；撤回权限（系统设置 › 隐私与安全性 › 辅助功能）后它立即失去全部能力。

## 数据面（截至 2026-09-26 的安全审计结论）

| 维度 | 结论 |
|---|---|
| 网络 | **零网络代码**，运行时经 `lsof` 验证无任何连接；无遥测、无崩溃上报、无更新检查 |
| 进程/脚本 | 不执行子进程、不调用 AppleScript / shell |
| AX 读取范围 | 只读窗口**几何**（位置/尺寸）、角色、进程 ID；**不读取窗口标题或任何文本内容** |
| CGWindowList | 只读图层 / PID / 边界；不读 `kCGWindowName`（不触发屏幕录制权限） |
| 事件监听 | CGEventTap 为 **listen-only**，只能观察不能注入/拦截/篡改输入事件 |
| 本地数据 | `settings.json`（布局与快捷键）与 `debug.log`（app 名 + 窗口几何）存于 `~/Library/Application Support/WindowTidyy/`，权限 0600，不出本机；日志超过 2MB 自动轮转 |
| 签名 | Release 启用 Hardened Runtime（库校验/JIT 禁用/环境加固），Apple Development 证书签名 |

## 已知权衡

- **不沙盒**：控制其他应用窗口所必需（见信任模型）。
- **辅助功能权限天然强大**：该权限理论上允许读取其他应用的界面内容；本项目代码自律地只访问几何信息，但请始终从本仓库源码自行构建，不要安装来路不明的二进制。
- **开发迭代与 TCC**：仓库默认 ad-hoc 签名（不含任何个人信息）；开发者可通过 gitignore 的 `signing.env` 固定自己的签名身份（`./build.sh` 自动应用），以保证重新编译后授权不丢。换签名身份或 ad-hoc 构建首次运行需重新授权一次。

## 报告漏洞

请开 [GitHub Issue](https://github.com/porridgec/WindowTidyy/issues) 或私下联系仓库所有者。请勿在公开 issue 中粘贴 `debug.log` 中涉及他人窗口的条目。
