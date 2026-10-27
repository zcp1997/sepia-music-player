import Foundation

/// 当前歌曲的歌词：歌词文件不在本机时先等 iCloud 下载，再在后台解析
final class LyricsLoader: ObservableObject {
    enum State: Equatable {
        /// 这首歌没有同名歌词文件
        case none
        case loading
        case loaded([LyricLine])
        /// 下载超时或解析不出任何歌词行
        case failed
    }

    @Published private(set) var state: State = .none

    private var generation = 0
    private var downloadTimer: Timer?

    func load(for song: Song) {
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
                self.state = .failed
                Log.error("歌词下载超时：\(url.lastPathComponent)")
            }
        }
    }

    private func read(_ url: URL, token: Int) {
        DispatchQueue.global(qos: .userInitiated).async {
            let lines = (try? Data(contentsOf: url))
                .map { LyricsParser.parse(data: $0, fileExtension: url.pathExtension) } ?? []
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                if lines.isEmpty {
                    self.state = .failed
                    Log.error("歌词解析失败：\(url.lastPathComponent)")
                } else {
                    self.state = .loaded(lines)
                }
            }
        }
    }
}
