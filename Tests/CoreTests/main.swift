import Foundation

var failures = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if !condition() {
        failures += 1
        print("  FAIL (line \(line)) \(message)")
    }
}

let tests: [(name: String, run: () throws -> Void)] = [
    ("Song 标题与文件夹", testSongNames),
    ("iCloud 占位文件名", testVisibleName),
    ("扫描音乐文件夹", testScanner),
    ("本机文件状态", testCloudFileLocal),
    ("LRC 解析", testLRC),
    ("LRC offset", testLRCOffset),
    ("SRT 解析", testSRT),
    ("歌词编码识别", testDecode),
    ("当前歌词行", testLyricIndex),
    ("喜欢", testFavorites),
    ("歌单", testPlaylists),
    ("歌单文件编解码", testLibraryFileRoundTrip),
    ("取较新的歌单数据", testNewerLibraryData),
    ("顺序播放", testSequentialOrder),
    ("随机播放", testShuffledOrder),
    ("播放顺序边界", testPlayOrderEdgeCases),
    ("播放模式切换", testPlayModeCycle),
    ("文件夹标签", testFolderTags),
    ("波形能量缓动", testWaveEnergyEasing),
    ("波形相位连续", testWavePhaseContinuity),
    ("波形形状", testWaveOffsetShape),
]

for test in tests {
    let before = failures
    do {
        try test.run()
    } catch {
        failures += 1
        print("  FAIL 抛出错误：\(error)")
    }
    print(failures == before ? "ok   \(test.name)" : "FAIL \(test.name)")
}

if failures > 0 {
    print("\(failures) 个断言失败")
    exit(1)
}
print("全部通过")
