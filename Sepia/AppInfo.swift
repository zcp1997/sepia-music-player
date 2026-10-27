import Foundation

/// 从 Info.plist 读取版本信息，用来确认手机上装的是哪一次构建。
enum AppInfo {
    static var version: String { value(for: "CFBundleShortVersionString") }
    static var build: String { value(for: "CFBundleVersion") }
    static var commit: String { value(for: "SepiaCommit") }

    static var summary: String { "v\(version) (\(build)) · \(commit)" }

    private static func value(for key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "?"
    }
}
