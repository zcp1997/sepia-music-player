import Foundation

enum LibraryScanner {
    static let audioExtensions: Set<String> = ["mp3", "m4a", "flac", "wav", "aac"]
    /// 按优先级排列：同名时 SRT 胜过 LRC
    static let lyricsExtensions = ["srt", "lrc"]

    /// 递归扫描音乐文件夹，返回按路径排序的歌曲。调用方需已开启 root 的安全作用域访问。
    static func scan(root: URL) -> [Song] {
        var songs: [Song] = []
        var coordinationError: NSError?
        // 只读目录元数据，不会触发 iCloud 下载文件内容
        NSFileCoordinator().coordinate(
            readingItemAt: root,
            options: .immediatelyAvailableMetadataOnly,
            error: &coordinationError
        ) { url in
            songs = collect(listing: url.path, root: root)
        }
        return songs
    }

    private static func collect(listing path: String, root: URL) -> [Song] {
        guard let enumerator = FileManager.default.enumerator(atPath: path) else { return [] }

        var audioPaths: [String] = []
        // key: 去掉扩展名的相对路径（小写），value: [扩展名: 相对路径]
        var lyricsByBase: [String: [String: String]] = [:]

        while let relative = enumerator.nextObject() as? String {
            let isDirectory = enumerator.fileAttributes?[.type] as? FileAttributeType == .typeDirectory
            let name = (relative as NSString).lastPathComponent

            if isDirectory {
                if name.hasPrefix(".") { enumerator.skipDescendants() }
                continue
            }
            guard let realName = visibleName(of: name) else { continue }

            let directory = (relative as NSString).deletingLastPathComponent
            let realPath = directory.isEmpty ? realName : directory + "/" + realName
            let ext = (realName as NSString).pathExtension.lowercased()

            if audioExtensions.contains(ext) {
                audioPaths.append(realPath)
            } else if lyricsExtensions.contains(ext) {
                let base = (realPath as NSString).deletingPathExtension.lowercased()
                lyricsByBase[base, default: [:]][ext] = realPath
            }
        }

        // 下载过程中可能同时看到占位文件和真实文件，去重
        return Set(audioPaths)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { path in
                let base = (path as NSString).deletingPathExtension.lowercased()
                let lyricsPath = lyricsByBase[base].flatMap { candidates in
                    lyricsExtensions.lazy.compactMap { candidates[$0] }.first
                }
                return Song(
                    id: path,
                    url: root.appendingPathComponent(path),
                    lyricsURL: lyricsPath.map { root.appendingPathComponent($0) }
                )
            }
    }

    /// iCloud 未下载的文件在目录里显示为 ".晴天.mp3.icloud"，还原成 "晴天.mp3"；其他隐藏文件返回 nil
    static func visibleName(of name: String) -> String? {
        guard name.hasPrefix(".") else { return name }
        let suffix = ".icloud"
        guard name.hasSuffix(suffix), name.count > 1 + suffix.count else { return nil }
        return String(name.dropFirst().dropLast(suffix.count))
    }
}
