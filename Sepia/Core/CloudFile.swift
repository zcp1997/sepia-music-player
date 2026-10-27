import Foundation

/// iCloud Drive 文件的下载状态与下载触发
enum CloudFile {
    /// 文件内容是否已完整在本机（不是 iCloud 文件时，只要存在就算）
    static func isLocal(_ url: URL) -> Bool {
        var url = url
        url.removeAllCachedResourceValues()
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard
            let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
            values.isUbiquitousItem == true,
            let status = values.ubiquitousItemDownloadingStatus
        else { return true }
        return status == .current || status == .downloaded
    }

    /// 文件是否存在（已下载，或者只有 ".名字.icloud" 占位文件）
    static func exists(_ url: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return true }
        let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
        return fm.fileExists(atPath: placeholder.path)
    }

    /// 请系统在后台下载文件；已在本机或不是 iCloud 文件时什么都不做
    @discardableResult
    static func startDownload(_ url: URL) -> Bool {
        guard !isLocal(url) else { return true }
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            return true
        } catch {
            return false
        }
    }

    /// 触发下载，并每 0.5 秒检查一次；下载完成（true）或超时（false）后回调。
    /// 在主线程调用；中途 invalidate 返回的 Timer 即取消，不会再回调。
    @discardableResult
    static func waitForDownload(_ url: URL, timeout: TimeInterval, completion: @escaping (Bool) -> Void) -> Timer {
        startDownload(url)
        let deadline = Date().addingTimeInterval(timeout)
        return Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if isLocal(url) {
                timer.invalidate()
                completion(true)
            } else if Date() > deadline {
                timer.invalidate()
                completion(false)
            }
        }
    }
}
