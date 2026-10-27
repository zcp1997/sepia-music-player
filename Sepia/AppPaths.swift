import Foundation

enum AppPaths {
    /// Application Support：不出现在「文件」App 里，删除 App 前一直保留
    static let applicationSupport: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}
