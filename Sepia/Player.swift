import AVFoundation
import MediaPlayer
import UIKit

/// 播放进度单独放一个对象：每秒刷新 5 次，只让进度条、歌词这些视图跟着重绘。
final class PlaybackProgress: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
}

/// 播放引擎：一个 AVPlayer + 自己管理的队列。所有方法都在主线程调用。
final class Player: ObservableObject {
    @Published private(set) var queue: [Song] = []
    @Published private(set) var index: Int?
    /// 用户意图：正在播放（或下载完就播）
    @Published private(set) var isPlaying = false
    /// 播放页的状态提示，如“正在从 iCloud 下载…”
    @Published private(set) var status: String?

    let progress = PlaybackProgress()
    let lyrics = LyricsLoader()

    var current: Song? { index.map { queue[$0] } }

    private let player = AVPlayer()
    private var loadGeneration = 0
    private var downloadTimer: Timer?
    /// 从头部缓存起播时的数据源（AVURLAsset 只弱引用 delegate，这里要持有）
    private var cachedSource: HeadCacheSource?
    private var itemObservation: NSKeyValueObservation?
    /// 新歌加载好之后要跳到的位置（恢复上次进度、或加载前就拖了进度条）
    private var pendingStart: TimeInterval?
    private var seekGeneration = 0
    private var isSeeking = false
    private var lastSavedTime: TimeInterval = 0
    private var resumeAfterInterruption = false
    private var didRestore = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private enum Keys {
        static let lastSongID = "lastSongID"
        static let lastPosition = "lastPosition"
    }

    init() {
        configureSession()
        observePlayer()
        configureRemoteCommands()
        HeadCache.shared.isInUse = { [weak self] song in
            self?.isCurrentOrUpcoming(song) ?? false
        }
    }

    // MARK: - 控制

    func play(_ songs: [Song], at index: Int) {
        guard songs.indices.contains(index) else { return }
        queue = songs
        load(index: index, startAt: 0, autoplay: true)
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard let index else { return }
        isPlaying = true
        if let item = player.currentItem, item.status != .failed {
            // 还有待跳转的位置时，交给 readyToPlay 跳完再播，避免先从 0 秒响一下
            if pendingStart == nil {
                startPlayback()
            }
            updateNowPlaying()
        } else if downloadTimer == nil {
            // 之前加载失败或下载超时，重新加载
            load(index: index, startAt: progress.currentTime, autoplay: true)
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
        savePosition()
        updateNowPlaying()
    }

    func next() { step(by: 1) }
    func previous() { step(by: -1) }

    func seek(to seconds: TimeInterval) {
        progress.currentTime = seconds
        guard let item = player.currentItem, item.status == .readyToPlay else {
            pendingStart = seconds
            return
        }
        isSeeking = true
        seekGeneration += 1
        let generation = seekGeneration
        player.seek(to: cmTime(seconds), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, generation == self.seekGeneration else { return }
                self.isSeeking = false
                self.savePosition()
                self.updateNowPlaying()
            }
        }
    }

    /// 首次扫描完成后恢复上次播放的歌和位置（暂停状态）
    func restoreIfNeeded(from songs: [Song]) {
        guard !didRestore, !songs.isEmpty else { return }
        didRestore = true
        guard
            queue.isEmpty,
            let id = UserDefaults.standard.string(forKey: Keys.lastSongID),
            let index = songs.firstIndex(where: { $0.id == id })
        else { return }
        queue = songs
        load(index: index, startAt: UserDefaults.standard.double(forKey: Keys.lastPosition), autoplay: false)
    }

    func savePosition() {
        UserDefaults.standard.set(progress.currentTime, forKey: Keys.lastPosition)
        lastSavedTime = progress.currentTime
    }

    // MARK: - 加载

    private func step(by delta: Int) {
        guard let index, !queue.isEmpty else { return }
        let target = ((index + delta) % queue.count + queue.count) % queue.count
        load(index: target, startAt: 0, autoplay: true)
    }

    private func load(index newIndex: Int, startAt start: TimeInterval, autoplay: Bool) {
        loadGeneration += 1
        let generation = loadGeneration
        downloadTimer?.invalidate()
        downloadTimer = nil
        endBackgroundTask()
        itemObservation = nil
        player.replaceCurrentItem(with: nil)
        cachedSource = nil

        let song = queue[newIndex]
        index = newIndex
        isPlaying = autoplay
        status = nil
        pendingStart = start > 0 ? start : nil
        progress.currentTime = start
        progress.duration = 0
        UserDefaults.standard.set(song.id, forKey: Keys.lastSongID)
        savePosition()
        updateNowPlaying()
        lyrics.load(for: song)

        if CloudFile.isLocal(song.url) {
            attachItem(for: song)
            return
        }

        // 不在本机但有头部缓存：先从缓存起播，同时让系统下载完整文件
        if let source = HeadCache.shared.makeSource(for: song), let asset = source.makeAsset() {
            Log.info("从头部缓存起播：\(song.id)")
            status = "正在后台下载完整文件…"
            source.onMismatch = { [weak self] in
                self?.reloadAfterCacheMismatch(song)
            }
            cachedSource = source
            attachItem(for: song, cachedAsset: asset)
            downloadTimer = CloudFile.waitForDownload(song.url, timeout: 300) { [weak self] isLocal in
                guard let self, generation == self.loadGeneration else { return }
                self.downloadTimer = nil
                if isLocal {
                    self.status = nil
                    source.fullFileReady()
                } else {
                    self.status = "下载超时，请检查网络后重试"
                    source.fail()
                    Log.error("下载超时：\(song.id)")
                }
            }
            return
        }

        // 不在本机也没有缓存：请系统下载，下完再播
        Log.info("等待 iCloud 下载：\(song.id)")
        status = "正在从 iCloud 下载…"
        beginBackgroundTask()
        downloadTimer = CloudFile.waitForDownload(song.url, timeout: 300) { [weak self] isLocal in
            guard let self, generation == self.loadGeneration else { return }
            self.downloadTimer = nil
            self.endBackgroundTask()
            if isLocal {
                self.status = nil
                self.attachItem(for: song)
            } else {
                self.status = "下载超时，请检查网络后重试"
                self.isPlaying = false
                self.updateNowPlaying()
                Log.error("下载超时：\(song.id)")
            }
        }
    }

    /// cachedAsset 为 nil 时播放本机文件
    private func attachItem(for song: Song, cachedAsset: AVURLAsset? = nil) {
        // 本机文件开精确时长：保证 VBR MP3 拖动后时间准确（歌词对齐依赖它）。
        // 头部缓存起播时不能开，否则播放器要先读完整个文件
        let asset = cachedAsset ?? AVURLAsset(url: song.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let item = AVPlayerItem(asset: asset)
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async { self?.itemStatusChanged(item) }
        }
        player.replaceCurrentItem(with: item)
        // 有 pendingStart 时等 readyToPlay 跳到位置后再播
        if isPlaying, pendingStart == nil {
            startPlayback()
        }
        prefetchUpcoming()
        updateNowPlaying()
        // 文件在本机：顺手建立 / 核对头部缓存，以后文件被系统释放了也能秒开
        if cachedAsset == nil { HeadCache.shared.store(song) }
    }

    /// 完整文件和头部缓存对不上：丢掉缓存，改从本机文件接着播
    private func reloadAfterCacheMismatch(_ song: Song) {
        HeadCache.shared.remove(song)
        guard let index, queue[index].id == song.id else { return }
        load(index: index, startAt: progress.currentTime, autoplay: isPlaying)
    }

    private func isCurrentOrUpcoming(_ song: Song) -> Bool {
        guard let index, !queue.isEmpty else { return false }
        return (0...min(2, queue.count - 1)).contains { queue[(index + $0) % queue.count].id == song.id }
    }

    private func itemStatusChanged(_ item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            let duration = item.duration.seconds
            if duration.isFinite { progress.duration = duration }
            if let start = pendingStart {
                pendingStart = nil
                seek(to: start)
                if isPlaying {
                    startPlayback()
                }
            }
            updateNowPlaying()
        case .failed:
            Log.error("无法播放 \(current?.id ?? "?")：\(item.error?.localizedDescription ?? "未知错误")")
            status = "无法播放此文件"
            isPlaying = false
            updateNowPlaying()
        default:
            break
        }
    }

    /// 提前让系统下载队列里接下来的 2 首（连同歌词），顺序播放时不用等
    private func prefetchUpcoming() {
        guard let index, queue.count > 1 else { return }
        for offset in 1...min(2, queue.count - 1) {
            let song = queue[(index + offset) % queue.count]
            CloudFile.startDownload(song.url)
            if let lyricsURL = song.lyricsURL { CloudFile.startDownload(lyricsURL) }
        }
    }

    // MARK: - 播放器事件

    private func observePlayer() {
        player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 5), queue: .main) { [weak self] time in
            self?.tick(time)
        }
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
            self.next()
        }
    }

    private func tick(_ time: CMTime) {
        guard !isSeeking, pendingStart == nil, player.currentItem != nil else { return }
        let seconds = time.seconds
        guard seconds.isFinite else { return }
        progress.currentTime = seconds
        if progress.duration == 0, let duration = player.currentItem?.duration.seconds, duration.isFinite {
            progress.duration = duration
            updateNowPlaying()
        }
        if abs(seconds - lastSavedTime) >= 10 { savePosition() }
    }

    // MARK: - 音频会话

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
        } catch {
            Log.error("设置音频会话失败：\(error)")
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] note in
            self?.handleInterruption(note)
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] note in
            self?.handleRouteChange(note)
        }
    }

    private func startPlayback() {
        activateSession()
        if cachedSource != nil {
            // 头部缓存起播：后面的数据还没到，play() 可能判断“缓冲跟不上”而迟迟不开始；
            // playImmediately 有多少播多少，数据断了仍会自动等待再续播
            player.playImmediately(atRate: 1)
        } else {
            player.play()
        }
    }

    private func activateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Log.error("激活音频会话失败：\(error)")
        }
    }

    /// 来电等打断：开始时暂停，结束时如系统允许则继续
    private func handleInterruption(_ note: Notification) {
        guard
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }
        switch type {
        case .began:
            resumeAfterInterruption = isPlaying
            if isPlaying { pause() }
        case .ended:
            let options = AVAudioSession.InterruptionOptions(
                rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            )
            if resumeAfterInterruption, options.contains(.shouldResume) { resume() }
            resumeAfterInterruption = false
        @unknown default:
            break
        }
    }

    /// 拔耳机 / 断开蓝牙时暂停
    private func handleRouteChange(_ note: Notification) {
        guard
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
        else { return }
        pause()
    }

    // MARK: - 锁屏 / 控制中心 / 耳机

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let song = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let isRunning = isPlaying && player.currentItem != nil && pendingStart == nil
        var elapsed = progress.currentTime
        if !isSeeking, player.currentItem != nil, pendingStart == nil {
            let seconds = player.currentTime().seconds
            if seconds.isFinite { elapsed = seconds }
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isRunning ? 1.0 : 0.0,
        ]
        if !song.folder.isEmpty { info[MPMediaItemPropertyArtist] = song.folder }
        if progress.duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = progress.duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - 后台

    /// 等待下载时 App 没在出声，系统可能很快挂起它；申请一点后台时间把这首等下来
    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "iCloud download") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func cmTime(_ seconds: TimeInterval) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }
}
