import Foundation

/// 头部缓存里一首歌的元数据
struct HeadCacheEntry: Codable, Equatable {
    /// 原文件大小与修改时间：文件变了缓存就作废
    var fileSize: Int
    var modified: Date
    /// 音频数据在原文件里的起点（跳过开头的 ID3v2 标签，内嵌封面可能就有几百 KB）
    var audioStart: Int
    /// 缓存了多少字节音频
    var headLength: Int

    /// 呈现给播放器的“虚拟文件”= 原文件去掉开头的 ID3v2 标签
    var virtualLength: Int { fileSize - audioStart }

    func matches(fileSize: Int, modified: Date) -> Bool {
        // JSON 往返会损失亚秒精度
        self.fileSize == fileSize && abs(self.modified.timeIntervalSince(modified)) < 1
    }
}

enum HeadCacheMath {
    /// 每首歌缓存的音频字节数：320kbps 约 25 秒，128kbps 约 60 秒
    static let headBudget = 1_000_000

    /// 这些格式的数据从头到尾顺序排列，有开头就能起播；m4a 的索引可能在文件末尾，不缓存
    static let supportedExtensions: Set<String> = ["mp3", "aac", "flac"]

    /// ID3v2 标签总长度（10 字节头 + 内容 + 可选 10 字节尾）；没有标签返回 0
    static func id3TagSize(_ header: Data) -> Int {
        let bytes = [UInt8](header.prefix(10))
        // "ID3"
        guard bytes.count == 10, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 else { return 0 }
        // 长度是 4 个 syncsafe 字节，每字节只用低 7 位
        let sizeBytes = bytes[6...9]
        guard sizeBytes.allSatisfy({ $0 < 0x80 }) else { return 0 }
        let size = sizeBytes.reduce(0) { ($0 << 7) | Int($1) }
        let hasFooter = bytes[5] & 0x10 != 0
        return 10 + size + (hasFooter ? 10 : 0)
    }

    /// 把播放器请求的虚拟区间拆成“头部缓存能给的”和“要等完整文件的”两段
    static func split(_ range: Range<Int>, headLength: Int) -> (head: Range<Int>?, rest: Range<Int>?) {
        let head = range.lowerBound < headLength ? range.lowerBound..<min(range.upperBound, headLength) : nil
        let restStart = max(range.lowerBound, headLength)
        let rest = restStart < range.upperBound ? restStart..<range.upperBound : nil
        return (head, rest)
    }

    /// 缓存文件名：歌曲 ID 的 FNV-1a 64 位哈希（Swift 的 hashValue 每次启动都不同，不能用）
    static func cacheKey(for songID: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in songID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }
}
