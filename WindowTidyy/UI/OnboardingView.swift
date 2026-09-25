import SwiftUI

/// 辅助功能权限引导横幅（未授权时显示在设置窗口顶部）
struct PermissionBannerView: View {
    @EnvironmentObject var permissions: PermissionsManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("需要「辅助功能」权限才能监听拖动并移动窗口")
                    .font(.headline)
                Text("在 系统设置 › 隐私与安全性 › 辅助功能 中勾选 WindowTidyy，勾选后自动生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("打开系统设置") {
                PermissionsManager.openAccessibilitySettings()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .padding([.horizontal, .top], 12)
    }
}
