import Foundation

/// 当前歌曲的歌词：歌词文件不在本机时先等 iCloud 下载，再在后台解析
final class LyricsLoader: ObservableObject {
    enum State: Equatable {
        /// 这首歌没有同名歌词文件
        case none
        case loading
        case loaded([LyricLine])
        /// 下载超时、读不到文件或解析不出任何歌词行；参数是给用户看的原因
        case failed(String)
    }

    @Published private(set) var state: State = .none

    private var song: Song?
    private var generation = 0
    private var downloadTimer: Timer?

    func load(for song: Song) {
        self.song = song
        generation += 1
        let token = generation
        downloadTimer?.invalidate()
        downloadTimer = nil

        guard let url = song.lyricsURL else {
            state = .none
            return
        }
        state = .loading
        if CloudFile.isLocal(url) {
            read(url, token: token)
            return
        }
        downloadTimer = CloudFile.waitForDownload(url, timeout: 60) { [weak self] isLocal in
            guard let self, token == self.generation else { return }
            self.downloadTimer = nil
            if isLocal {
                self.read(url, token: token)
            } else {
                self.state = .failed("歌词下载超时，请检查网络")
                Log.error("歌词下载超时：\(url.lastPathComponent)")
            }
        }
    }

    /// 失败后用户点「重新加载」
    func retry() {
        guard let song else { return }
        Log.info("重新加载歌词：\(song.id)")
        load(for: song)
    }

    private func read(_ url: URL, token: Int) {
        DispatchQueue.global(qos: .userInitiated).async {
            let data = try? Data(contentsOf: url)
            let lines = data.map { LyricsParser.parse(data: $0, fileExtension: url.pathExtension) } ?? []
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                if data == nil {
                    self.state = .failed("读取不到歌词文件")
                    Log.error("读取歌词失败：\(url.lastPathComponent)")
                } else if lines.isEmpty {
                    self.state = .failed("歌词文件里没有可用的时间轴")
                    Log.error("歌词解析失败：\(url.lastPathComponent)")
                } else {
                    self.state = .loaded(lines)
                }
            }
        }
    }
}
