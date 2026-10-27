import Foundation

func testFavorites() {
    var data = LibraryData.empty
    data.toggleFavorite("a.mp3")
    data.toggleFavorite("b.mp3")
    check(data.favorites == ["b.mp3", "a.mp3"], "最近喜欢的在前：\(data.favorites)")
    data.toggleFavorite("a.mp3")
    check(data.favorites == ["b.mp3"], "再点一次取消喜欢")
    data.removeFavorites(["b.mp3", "x.mp3"])
    check(data.favorites.isEmpty, "批量移除")
}

func testPlaylists() {
    var data = LibraryData.empty
    let id = data.createPlaylist(named: "  通勤 ")
    check(data.playlists.first?.name == "通勤", "歌单名去掉首尾空格")
    let unnamed = data.createPlaylist(named: " ")
    check(data.playlists.last?.name == "新歌单", "空名字用默认名")
    data.deletePlaylist(unnamed)

    data.add("a.mp3", toPlaylist: id)
    data.add("b.mp3", toPlaylist: id)
    data.add("a.mp3", toPlaylist: id)
    data.add("c.mp3", toPlaylist: id)
    check(data.playlists[0].songs == ["a.mp3", "b.mp3", "c.mp3"], "不重复添加：\(data.playlists[0].songs)")

    // b.mp3 文件已不存在，界面上只看得到 a、c
    data.reorderPlaylist(id, visibleOrder: ["c.mp3", "a.mp3"])
    check(data.playlists[0].songs == ["c.mp3", "a.mp3", "b.mp3"], "看不到的歌留在末尾：\(data.playlists[0].songs)")

    data.removeSongs(["a.mp3"], fromPlaylist: id)
    check(data.playlists[0].songs == ["c.mp3", "b.mp3"], "移除歌曲")

    data.renamePlaylist(id, to: "健身")
    check(data.playlists[0].name == "健身", "重命名")

    data.deletePlaylist(id)
    check(!data.playlists.contains { $0.id == id }, "删除歌单")
}

func testLibraryFileRoundTrip() throws {
    var data = LibraryData(updatedAt: Date(timeIntervalSince1970: 1_800_000_000), favorites: ["华语/晴天.mp3"], playlists: [])
    data.createPlaylist(named: "通勤")
    let json = try LibraryFile.encode(data)
    let text = String(data: json, encoding: .utf8) ?? ""
    check(text.contains("\"华语/晴天.mp3\""), "路径里的 / 不转义，中文原样保存")
    let roundTrip = try LibraryFile.decode(LibraryData.self, from: json)
    check(roundTrip == data, "编码后能原样解码")

    let mirror = LibraryMirror(folderPath: "/x/Music", data: data)
    let decoded = try LibraryFile.decode(LibraryMirror.self, from: LibraryFile.encode(mirror))
    check(decoded.folderPath == "/x/Music" && decoded.data == data, "镜像文件往返")
}

func testNewerLibraryData() {
    let old = LibraryData(updatedAt: Date(timeIntervalSince1970: 100), favorites: ["old"], playlists: [])
    let new = LibraryData(updatedAt: Date(timeIntervalSince1970: 200), favorites: ["new"], playlists: [])
    check(LibraryFile.newer(old, new) == new, "取较新的")
    check(LibraryFile.newer(new, old) == new, "顺序无关")
    check(LibraryFile.newer(nil, old) == old, "只有一份时用那一份")
    check(LibraryFile.newer(nil, nil) == nil, "两份都没有")
}
