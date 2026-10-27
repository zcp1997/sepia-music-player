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
    @Published private(set) var mode: PlayMode

    let progress = PlaybackProgress()
    let lyrics = LyricsLoader()

    var current: Song? { index.map { queue[$0] } }

    private let player = AVPlayer()
    /// 上一首 / 下一首按它走；随机模式下是打乱后的顺序
    private var order = PlayOrder(count: 0, current: 0, shuffled: false)
    private var loadGeneration = 0
    private var downloadTimer: Timer?
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
        static let playMode = "playMode"
    }

    init() {
        mode = UserDefaults.standard.string(forKey: Keys.playMode).flatMap(PlayMode.init(rawValue:)) ?? .sequential
        configureSession()
        observePlayer()
        configureRemoteCommands()
    }

    // MARK: - 控制

    func play(_ songs: [Song], at index: Int) {
        guard songs.indices.contains(index) else { return }
        queue = songs
        rebuildOrder(current: index)
        load(index: index, startAt: 0, autoplay: true)
    }

    /// 顺序 → 单曲循环 → 随机 → 顺序
    func cycleMode() {
        mode = mode.next
        UserDefaults.standard.set(mode.rawValue, forKey: Keys.playMode)
        Log.info("播放模式：\(mode.rawValue)")
        if let index { rebuildOrder(current: index) }
        prefetchUpcoming()
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
        rebuildOrder(current: index)
        load(index: index, startAt: UserDefaults.standard.double(forKey: Keys.lastPosition), autoplay: false)
    }

    func savePosition() {
        UserDefaults.standard.set(progress.currentTime, forKey: Keys.lastPosition)
        lastSavedTime = progress.currentTime
    }

    // MARK: - 加载

    private func step(by delta: Int) {
        guard index != nil, let target = order.step(by: delta) else { return }
        load(index: target, startAt: 0, autoplay: true)
    }

    /// 队列或模式变了：从当前这首重新排顺序（随机时其余歌重新打乱）
    private func rebuildOrder(current: Int) {
        order = PlayOrder(count: queue.count, current: current, shuffled: mode == .shuffle)
    }

    /// 一首播完：单曲循环从头再播，其他模式下一首
    private func playbackDidEnd() {
        guard mode == .repeatOne else {
            next()
            return
        }
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.isPlaying else { return }
                self.startPlayback()
                self.updateNowPlaying()
            }
        }
    }

    private func load(index newIndex: Int, startAt start: TimeInterval, autoplay: Bool) {
        loadGeneration += 1
        let generation = loadGeneration
        downloadTimer?.invalidate()
        downloadTimer = nil
        endBackgroundTask()
        itemObservation = nil
        player.replaceCurrentItem(with: nil)

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

        // 不在本机：请系统下载，下完再播
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

    private func attachItem(for song: Song) {
        // 精确时长：保证 VBR MP3 拖动后时间准确（歌词对齐依赖它）
        let asset = AVURLAsset(url: song.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
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

    /// 提前让系统下载接下来要播的 2 首（连同歌词；随机模式按打乱后的顺序），切歌时不用等
    private func prefetchUpcoming() {
        for index in order.upcoming(2) {
            let song = queue[index]
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
            self.playbackDidEnd()
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
        player.play()
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
