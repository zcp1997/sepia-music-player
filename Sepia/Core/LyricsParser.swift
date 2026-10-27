import Foundation

struct LyricLine: Equatable {
    let time: TimeInterval
    let text: String
    /// 同一时间点的第二行（通常是翻译），多行用换行连接
    let translation: String?
}

enum LyricsParser {
    /// 按扩展名选择 SRT 或 LRC 解析；无法解码或没有任何歌词行时返回空数组
    static func parse(data: Data, fileExtension: String) -> [LyricLine] {
        guard let text = decode(data) else { return [] }
        return fileExtension.lowercased() == "srt" ? parseSRT(text) : parseLRC(text)
    }

    /// 依次尝试 UTF-8 / UTF-16（BOM）/ GB18030。中文歌词常见 GBK 编码，GB18030 是它的超集。
    static func decode(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(3))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: gb18030))
    }

    // MARK: - LRC

    /// 支持一行多个时间戳、2/3 位毫秒、[offset:]；同一时间戳的第二行当作翻译
    static func parseLRC(_ text: String) -> [LyricLine] {
        var offset: TimeInterval = 0
        var entries: [(time: TimeInterval, text: String)] = []

        for rawLine in text.components(separatedBy: .newlines) {
            var rest = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            var times: [TimeInterval] = []

            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let time = parseLRCTime(tag) {
                    times.append(time)
                } else if tag.lowercased().hasPrefix("offset:"), let ms = Double(tag.dropFirst("offset:".count).trimmingCharacters(in: .whitespaces)) {
                    // 正值让歌词提前出现
                    offset = ms / 1000
                }
                rest = rest[rest.index(after: close)...]
            }

            let lyric = stripTags(String(rest), open: "<", close: ">").trimmingCharacters(in: .whitespaces)
            guard !lyric.isEmpty else { continue }
            for time in times {
                entries.append((time, lyric))
            }
        }

        return merge(entries.map { (max(0, $0.time - offset), $0.text) })
    }

    /// "mm:ss" / "mm:ss.xx" / "mm:ss.xxx" / "mm:ss:xx"
    private static func parseLRCTime(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let minutes = Int(parts[0]), minutes >= 0,
              let seconds = Double(parts[1]), seconds >= 0, seconds < 60
        else { return nil }
        var time = TimeInterval(minutes) * 60 + seconds
        if parts.count == 3 {
            guard let fraction = Int(parts[2]), fraction >= 0 else { return nil }
            time += Double(fraction) / pow(10, Double(parts[2].count))
        }
        return time
    }

    // MARK: - SRT

    /// 字幕块：序号 / "00:01:02,345 --> 00:01:05,000" / 文本若干行；第二行起当作翻译
    static func parseSRT(_ text: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        var block: [String] = []

        func flush() {
            defer { block.removeAll() }
            guard let timingIndex = block.firstIndex(where: { $0.contains("-->") }),
                  let start = block[timingIndex].components(separatedBy: "-->").first,
                  let time = parseSRTTime(start)
            else { return }

            let textRows = block[(timingIndex + 1)...]
                .map { stripTags(stripTags($0, open: "<", close: ">"), open: "{", close: "}").trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard let first = textRows.first else { return }
            let rest = textRows.dropFirst()
            lines.append(LyricLine(time: time, text: first, translation: rest.isEmpty ? nil : rest.joined(separator: "\n")))
        }

        // 先统一换行，再按空行分隔字幕块（直接按 .newlines 拆会把 \r\n 当成两次换行）
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for row in normalized.components(separatedBy: "\n") {
            let trimmed = row.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
            } else {
                block.append(trimmed)
            }
        }
        flush()

        return lines.enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element)
    }

    /// "HH:MM:SS,mmm"，也接受 "." 作毫秒分隔和省略小时
    private static func parseSRTTime(_ string: String) -> TimeInterval? {
        let parts = string.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
            .split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var time: TimeInterval = 0
        for (index, part) in parts.enumerated() {
            let isLast = index == parts.count - 1
            guard let value = isLast ? Double(part) : Double(Int(part) ?? -1), value >= 0 else { return nil }
            time = time * 60 + value
        }
        return time
    }

    // MARK: - 公共

    /// 当前时间应高亮的行：最后一个 time <= 当前时间的行；还没到第一行时返回 nil
    static func index(at time: TimeInterval, in lines: [LyricLine]) -> Int? {
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].time <= time {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low == 0 ? nil : low - 1
    }

    /// 按时间稳定排序，并把相同时间的行合并成“原文 + 翻译”
    private static func merge(_ entries: [(time: TimeInterval, text: String)]) -> [LyricLine] {
        var order: [TimeInterval] = []
        var texts: [TimeInterval: [String]] = [:]
        for entry in entries {
            // 毫秒级对齐，避免浮点误差让同一时间戳分成两行
            let key = (entry.time * 1000).rounded() / 1000
            if texts[key] == nil { order.append(key) }
            texts[key, default: []].append(entry.text)
        }
        return order.sorted().map { time in
            let group = texts[time] ?? []
            let rest = group.dropFirst()
            return LyricLine(time: time, text: group.first ?? "", translation: rest.isEmpty ? nil : rest.joined(separator: "\n"))
        }
    }

    /// 去掉 <...>（增强 LRC 的逐字时间、SRT 的 <i>）或 {...}（ASS 样式）
    private static func stripTags(_ text: String, open: Character, close: Character) -> String {
        guard text.contains(open) else { return text }
        var result = ""
        var depth = 0
        for character in text {
            if character == open {
                depth += 1
            } else if character == close, depth > 0 {
                depth -= 1
            } else if depth == 0 {
                result.append(character)
            }
        }
        return result
    }
}
