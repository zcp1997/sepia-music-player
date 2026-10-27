import Foundation

func testSequentialOrder() {
    var order = PlayOrder(count: 4, current: 2, shuffled: false)
    check(order.upcoming(2) == [3, 0], "顺序：接下来是 3、0，实际 \(order.upcoming(2))")
    check(order.step(by: 1) == 3, "下一首")
    check(order.step(by: 1) == 0, "最后一首之后回到第一首")
    check(order.step(by: -1) == 3, "上一首")
    check(order.step(by: -1) == 2, "再上一首")
}

func testShuffledOrder() {
    for current in 0..<5 {
        var order = PlayOrder(count: 5, current: current, shuffled: true)
        check(order.order.first == current, "随机：当前这首排第一")
        check(order.order.sorted() == [0, 1, 2, 3, 4], "随机：每首恰好出现一次 \(order.order)")
        var played = [current]
        for _ in 1..<5 { played.append(order.step(by: 1)!) }
        check(Set(played).count == 5, "一轮内不重复：\(played)")
        check(order.step(by: 1) == current, "一轮之后回到起点")
        check(order.step(by: -1) == played.last, "随机时上一首按播放历史退回")
    }
}

func testPlayOrderEdgeCases() {
    var empty = PlayOrder(count: 0, current: 0, shuffled: true)
    check(empty.isEmpty && empty.step(by: 1) == nil && empty.upcoming(2).isEmpty, "空队列")

    var single = PlayOrder(count: 1, current: 0, shuffled: true)
    check(single.step(by: 1) == 0 && single.upcoming(2).isEmpty, "只有一首")

    let two = PlayOrder(count: 2, current: 0, shuffled: false)
    check(two.upcoming(5) == [1], "预取数量不超过其余歌曲数")
}

func testPlayModeCycle() {
    check(PlayMode.sequential.next == .repeatOne, "顺序 → 单曲循环")
    check(PlayMode.repeatOne.next == .shuffle, "单曲循环 → 随机")
    check(PlayMode.shuffle.next == .sequential, "随机 → 顺序")
}

func testFolderTags() {
    let songs = ["抒情/马灯.mp3", "说唱/皮影 4.mp3", "抒情/赛里木.mp3", "根目录.mp3", "古风/白囍.mp3", "华语/抒情/x.mp3"]
        .map { Song(id: $0, url: URL(fileURLWithPath: "/m/" + $0), lyricsURL: nil) }
    let folders = songs.folders
    check(Set(folders) == ["抒情", "说唱", "古风", "华语/抒情"], "去重、不含根目录：\(folders)")
    check(folders.count == 4, "每个文件夹只出现一次")
}
