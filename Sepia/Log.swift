import Foundation
import os

/// 日志同时写系统日志（Mac「控制台」App 连手机可看）和 Documents/sepia.log（「文件」App → 我的 iPhone → Sepia）。
enum Log {
    private static let logger = Logger(subsystem: "com.zcp.sepia", category: "app")
    private static let queue = DispatchQueue(label: "com.zcp.sepia.log")
    private static let maxFileSize = 1_000_000

    private static let fileURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("sepia.log")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        append("INFO", message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        append("ERROR", message)
    }

    private static func append(_ level: String, _ message: String) {
        let date = Date()
        queue.async {
            let line = "\(date.formatted(Date.ISO8601FormatStyle(timeZone: .current))) [\(level)] \(message)\n"
            let fm = FileManager.default
            if let size = try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int, size > maxFileSize {
                let old = fileURL.deletingPathExtension().appendingPathExtension("old.log")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: fileURL, to: old)
            }
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
