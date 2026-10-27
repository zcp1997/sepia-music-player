import Foundation

func testID3TagSize() {
    // "ID3" v2.3，无标志，syncsafe 长度 0x00 0x00 0x02 0x01 = 2 << 7 | 1 = 257
    let header = Data([0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x02, 0x01])
    check(HeadCacheMath.id3TagSize(header) == 267, "10 字节头 + 257")

    var withFooter = header
    withFooter[5] = 0x10
    check(HeadCacheMath.id3TagSize(withFooter) == 277, "有 footer 再加 10")

    check(HeadCacheMath.id3TagSize(Data([0xFF, 0xFB, 0x90, 0x64, 0, 0, 0, 0, 0, 0])) == 0, "直接是 MP3 帧，没有标签")
    check(HeadCacheMath.id3TagSize(Data([0x49, 0x44, 0x33])) == 0, "数据不足 10 字节")
    check(HeadCacheMath.id3TagSize(Data([0x49, 0x44, 0x33, 3, 0, 0, 0x80, 0, 0, 0])) == 0, "长度字节不合法")
}

func testHeadCacheSplit() {
    let headLength = 1000
    var parts = HeadCacheMath.split(0..<500, headLength: headLength)
    check(parts.head == 0..<500 && parts.rest == nil, "全在头部")

    parts = HeadCacheMath.split(800..<1500, headLength: headLength)
    check(parts.head == 800..<1000 && parts.rest == 1000..<1500, "跨越头部末尾")

    parts = HeadCacheMath.split(2000..<3000, headLength: headLength)
    check(parts.head == nil && parts.rest == 2000..<3000, "全在头部之后")

    parts = HeadCacheMath.split(0..<1000, headLength: headLength)
    check(parts.head == 0..<1000 && parts.rest == nil, "正好等于头部")
}

func testHeadCacheEntry() {
    let date = Date(timeIntervalSince1970: 1_800_000_000.25)
    let entry = HeadCacheEntry(fileSize: 5000, modified: date, audioStart: 267, headLength: 1000)
    check(entry.virtualLength == 4733, "虚拟文件长度 = 原文件 - ID3 标签")
    check(entry.matches(fileSize: 5000, modified: date.addingTimeInterval(0.5)), "亚秒差异算同一个文件")
    check(!entry.matches(fileSize: 5001, modified: date), "大小变了")
    check(!entry.matches(fileSize: 5000, modified: date.addingTimeInterval(60)), "修改时间变了")
}

func testCacheKey() {
    check(HeadCacheMath.cacheKey(for: "") == "cbf29ce484222325", "FNV-1a 空串")
    check(HeadCacheMath.cacheKey(for: "a") == "af63dc4c8601ec8c", "FNV-1a 标准测试向量")
    check(HeadCacheMath.cacheKey(for: "华语/晴天.mp3") == HeadCacheMath.cacheKey(for: "华语/晴天.mp3"), "稳定")
    check(HeadCacheMath.cacheKey(for: "a.mp3") != HeadCacheMath.cacheKey(for: "b.mp3"), "不同 ID 不同 key")
}
