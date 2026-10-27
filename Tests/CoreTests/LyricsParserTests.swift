import Foundation

func testLRC() {
    let lrc = """
    [ti:晴天]
    [ar:周杰伦]
    [00:01.00]故事的小黄花
    [00:05.50][01:30.25]从出生那年就飘着
    [00:10.123]童年的荡秋千
    [00:10.123]Childhood swing
    [00:12:50]冒号分隔的毫秒
    [00:15.00]
    [00:20.00]<00:20.00>逐<00:20.50>字
    """
    let lines = LyricsParser.parseLRC(lrc)
    check(lines.map(\.time) == [1, 5.5, 10.123, 12.5, 20, 90.25], "时间 = \(lines.map(\.time))")
    check(lines.first?.text == "故事的小黄花", "第一行文本")
    check(lines[2].text == "童年的荡秋千" && lines[2].translation == "Childhood swing", "同时间戳合并为翻译")
    check(lines.last?.text == "从出生那年就飘着", "多时间戳的行出现两次")
    check(lines.contains { $0.text == "逐字" }, "去掉增强 LRC 的逐字时间")
    check(!lines.contains { $0.text.isEmpty }, "跳过空歌词行")
}

func testLRCOffset() {
    let lines = LyricsParser.parseLRC("[offset:+500]\n[00:00.20]a\n[00:02.00]b")
    check(lines.map(\.time) == [0, 1.5], "offset 正值让歌词提前，且不小于 0：\(lines.map(\.time))")
}

func testSRT() {
    let srt = "1\r\n00:00:01,000 --> 00:00:03,000\r\n<i>第一句</i>\r\nFirst line\r\n\r\n"
        + "3\n00:01:02.500 --> 00:01:04,000\n{\\an8}第三句\n\n"
        + "2\n00:00:05,250 --> 00:00:07,000\n第二句\n\n"
        + "4\n00:00:09,000 --> 00:00:10,000\n\n"
    let lines = LyricsParser.parseSRT(srt)
    check(lines.map(\.time) == [1, 5.25, 62.5], "按时间排序：\(lines.map(\.time))")
    check(lines.first?.text == "第一句" && lines.first?.translation == "First line", "去 <i> 标签，第二行为翻译")
    check(lines.last?.text == "第三句", "去 {} 样式标签")
}

func testDecode() {
    let text = "[00:01.00]你好"
    let gb18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    let gbData = text.data(using: String.Encoding(rawValue: gb18030))!
    check(LyricsParser.decode(gbData) == text, "GBK/GB18030 编码")
    check(LyricsParser.decode(Data([0xEF, 0xBB, 0xBF]) + text.data(using: .utf8)!) == text, "UTF-8 BOM")
    check(LyricsParser.decode(Data([0xFF, 0xFE]) + text.data(using: .utf16LittleEndian)!) == text, "UTF-16 LE BOM")
    check(LyricsParser.parse(data: gbData, fileExtension: "LRC").first?.text == "你好", "按扩展名走 LRC 解析")
}

func testLyricIndex() {
    let lines = [0.5, 2, 4].map { LyricLine(time: $0, text: "x", translation: nil) }
    check(LyricsParser.index(at: 0.1, in: lines) == nil, "第一行之前")
    check(LyricsParser.index(at: 0.5, in: lines) == 0, "正好在第一行")
    check(LyricsParser.index(at: 3.9, in: lines) == 1, "两行之间")
    check(LyricsParser.index(at: 100, in: lines) == 2, "最后一行之后")
    check(LyricsParser.index(at: 1, in: []) == nil, "空歌词")
}
