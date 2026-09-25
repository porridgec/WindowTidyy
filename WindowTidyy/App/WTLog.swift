import Foundation

/// 调试日志：写文件（绕过统一日志的隐私过滤），方便排查拖动状态机。
/// 安全约束：仅本机诊断用，含 app 名与窗口几何 → 文件权限 0600，且限制大小防止无限增长。
enum WTLog {
    private static let queue = DispatchQueue(label: "WindowTidyy.WTLog")
    private static var handle: FileHandle?
    private static let maxBytes = 2 * 1024 * 1024 // 2MB，超出即轮转重写

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WindowTidyy", isDirectory: true)
        return dir.appendingPathComponent("debug.log")
    }

    static func log(_ message: String) {
        queue.sync {
            if handle == nil {
                let url = fileURL
                let fm = FileManager.default
                let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
                if size > maxBytes {
                    try? fm.removeItem(at: url)
                }
                fm.createFile(atPath: url.path, contents: nil,
                              attributes: [.posixPermissions: 0o600])
                handle = FileHandle(forWritingAtPath: url.path)
            }
            let df = DateFormatter()
            df.dateFormat = "HH:mm:ss.SSS"
            let line = "\(df.string(from: Date())) \(message)\n"
            handle?.seekToEndOfFile()
            handle?.write(line.data(using: .utf8)!)
        }
    }
}
