import Foundation

func testSongNames() {
    let song = Song(id: "华语/晴天.flac", url: URL(fileURLWithPath: "/x/华语/晴天.flac"), lyricsURL: nil)
    check(song.title == "晴天", "title = \(song.title)")
    check(song.folder == "华语", "folder = \(song.folder)")

    let rootSong = Song(id: "a.mp3", url: URL(fileURLWithPath: "/x/a.mp3"), lyricsURL: nil)
    check(rootSong.folder.isEmpty, "根目录歌曲的 folder 应为空")
}

func testVisibleName() {
    check(LibraryScanner.visibleName(of: "晴天.mp3") == "晴天.mp3", "普通文件名不变")
    check(LibraryScanner.visibleName(of: ".晴天.mp3.icloud") == "晴天.mp3", "还原 iCloud 占位文件名")
    check(LibraryScanner.visibleName(of: ".DS_Store") == nil, "跳过隐藏文件")
    check(LibraryScanner.visibleName(of: "..icloud") == nil, "名字为空的占位文件")
}

func testScanner() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("sepia-scan-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: root) }

    let files = [
        "b.mp3", "b.lrc", "b.srt",              // 同名时 SRT 优先
        "a.MP3", "a.LRC",                       // 扩展名大小写
        "华语/晴天.flac", "华语/.晴天.lrc.icloud", // 歌词还在 iCloud
        "华语/.七里香.mp3.icloud",                // 歌还在 iCloud
        "track 10.mp3", "track 2.mp3",          // 数字自然排序
        "notes.txt", ".DS_Store",
        ".hidden/c.mp3",                        // 隐藏目录整体跳过
    ]
    for path in files {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }

    let songs = LibraryScanner.scan(root: root)
    let ids = songs.map(\.id)
    check(
        Set(ids) == ["a.MP3", "b.mp3", "track 2.mp3", "track 10.mp3", "华语/七里香.mp3", "华语/晴天.flac"],
        "歌曲列表 = \(ids)"
    )
    // 中英文谁先取决于系统语言，只检查同类之间的顺序
    func position(_ id: String) -> Int { ids.firstIndex(of: id) ?? -1 }
    check(position("a.MP3") < position("b.mp3"), "a 应排在 b 前")
    check(position("track 2.mp3") < position("track 10.mp3"), "track 2 应排在 track 10 前（数字自然排序）")

    func lyrics(_ id: String) -> String? {
        songs.first { $0.id == id }?.lyricsURL?.lastPathComponent
    }
    check(lyrics("b.mp3") == "b.srt", "b 应匹配 srt，实际 \(lyrics("b.mp3") ?? "nil")")
    check(lyrics("a.MP3") == "a.LRC", "a 应匹配 a.LRC，实际 \(lyrics("a.MP3") ?? "nil")")
    check(lyrics("华语/晴天.flac") == "晴天.lrc", "占位歌词应还原为真实文件名")
    check(lyrics("华语/七里香.mp3") == nil, "七里香没有歌词")

    let placeholderSong = songs.first { $0.id == "华语/七里香.mp3" }
    check(placeholderSong?.url.lastPathComponent == "七里香.mp3", "占位歌曲的 url 指向真实文件名")
}

func testCloudFileLocal() throws {
    let fm = FileManager.default
    let file = fm.temporaryDirectory.appendingPathComponent("sepia-local-\(UUID().uuidString).mp3")
    defer { try? fm.removeItem(at: file) }
    try Data([1, 2, 3]).write(to: file)

    check(CloudFile.isLocal(file), "存在的普通文件算在本机")
    check(!CloudFile.isLocal(file.deletingLastPathComponent().appendingPathComponent("missing.mp3")), "不存在的文件不算在本机")
}
