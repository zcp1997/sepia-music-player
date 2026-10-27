import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// 每首歌开头约 1MB 音频的本地副本：歌不在本机时先从这里起播，同时让系统下载完整文件。
/// index 和 @Published 属性只在主线程访问；文件读写在 ioQueue。
final class HeadCache: ObservableObject {
    static let shared = HeadCache()

    /// 预热进度；nil 表示没在预热
    @Published private(set) var preheatDone: Int?
    @Published private(set) var preheatTotal = 0
    @Published private(set) var totalBytes = 0
    @Published private(set) var entryCount = 0

    /// 由播放器提供：正在播或即将播的歌，预热时不释放它的本地文件
    var isInUse: (Song) -> Bool = { _ in false }

    private let directory = AppPaths.applicationSupport.appendingPathComponent("HeadCache", isDirectory: true)
    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    /// key：歌曲 ID
    private var index: [String: HeadCacheEntry] = [:]
    private let ioQueue = DispatchQueue(label: "com.zcp.sepia.head-cache", qos: .utility)
    private var isIndexSaveScheduled = false
    private var preheatTimer: Timer?
    private var isPreheatCancelled = false

    private init() {
        var directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        if let json = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([String: HeadCacheEntry].self, from: json) {
            index = saved
        }
        updateStats()
    }

    static func supports(_ song: Song) -> Bool {
        HeadCacheMath.supportedExtensions.contains(song.url.pathExtension.lowercased())
    }

    func contains(_ song: Song) -> Bool {
        index[song.id] != nil
    }

    // MARK: - 起播

    /// 歌不在本机时用：有头部缓存就返回一个可直接交给 AVPlayer 的数据源
    func makeSource(for song: Song) -> HeadCacheSource? {
        guard let entry = index[song.id],
              let head = try? Data(contentsOf: fileURL(for: song.id), options: .mappedIfSafe),
              head.count == entry.headLength
        else { return nil }
        return HeadCacheSource(song: song, entry: entry, head: head)
    }

    // MARK: - 写入

    /// 文件在本机时截取开头存起来；已有有效缓存则跳过。completion(是否有缓存) 在主线程回调
    func store(_ song: Song, completion: ((Bool) -> Void)? = nil) {
        guard Self.supports(song) else {
            completion?(false)
            return
        }
        let existing = index[song.id]
        let cacheFile = fileURL(for: song.id)
        ioQueue.async {
            if let existing, Self.isValid(existing, for: song.url) {
                DispatchQueue.main.async { completion?(true) }
                return
            }
            let entry = Self.makeEntry(from: song.url, writingTo: cacheFile)
            DispatchQueue.main.async {
                if entry != nil || existing != nil {
                    self.index[song.id] = entry
                    self.indexChanged()
                }
                completion?(entry != nil)
            }
        }
    }

    /// 扫描完成后：已在本机但还没缓存的歌，后台逐首补上
    func fillMissing(_ songs: [Song]) {
        let missing = songs.filter { Self.supports($0) && index[$0.id] == nil }
        guard !missing.isEmpty else { return }
        ioQueue.async {
            let local = missing.filter { CloudFile.isLocal($0.url) }
            DispatchQueue.main.async {
                if !local.isEmpty { Log.info("补建头部缓存：\(local.count) 首") }
                local.forEach { self.store($0) }
            }
        }
    }

    func remove(_ song: Song) {
        guard index.removeValue(forKey: song.id) != nil else { return }
        let file = fileURL(for: song.id)
        ioQueue.async { try? FileManager.default.removeItem(at: file) }
        indexChanged()
    }

    func clear() {
        cancelPreheat()
        index = [:]
        let directory = directory
        ioQueue.async {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            files.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        updateStats()
        Log.info("已清空头部缓存")
    }

    // MARK: - 预热

    /// 逐首：不在本机就先下载 → 截取头部 → 原本不在本机的再释放完整文件，只多占头部的空间
    func preheat(_ songs: [Song]) {
        guard preheatDone == nil else { return }
        let todo = songs.filter { Self.supports($0) && index[$0.id] == nil }
        guard !todo.isEmpty else { return }
        isPreheatCancelled = false
        preheatTotal = todo.count
        Log.info("开始预热：\(todo.count) 首")
        preheatNext(todo, position: 0)
    }

    func cancelPreheat() {
        isPreheatCancelled = true
        preheatTimer?.invalidate()
        preheatTimer = nil
        preheatDone = nil
    }

    private func preheatNext(_ todo: [Song], position: Int) {
        guard !isPreheatCancelled, position < todo.count else {
            if !isPreheatCancelled { Log.info("预热完成") }
            preheatDone = nil
            return
        }
        preheatDone = position
        let song = todo[position]
        let advance = { [weak self] in self?.preheatNext(todo, position: position + 1) }

        if CloudFile.isLocal(song.url) {
            store(song) { _ in advance() }
            return
        }
        preheatTimer = CloudFile.waitForDownload(song.url, timeout: 120) { [weak self] isLocal in
            guard let self, !self.isPreheatCancelled else { return }
            self.preheatTimer = nil
            guard isLocal else {
                Log.error("预热下载超时：\(song.id)")
                advance()
                return
            }
            self.store(song) { stored in
                if stored, !self.isInUse(song) {
                    do {
                        try FileManager.default.evictUbiquitousItem(at: song.url)
                    } catch {
                        Log.error("释放本地文件失败 \(song.id)：\(error)")
                    }
                }
                advance()
            }
        }
    }

    // MARK: - 内部

    private func fileURL(for songID: String) -> URL {
        directory.appendingPathComponent(HeadCacheMath.cacheKey(for: songID) + ".bin")
    }

    private func indexChanged() {
        updateStats()
        // 补建缓存时会连续改很多次，合并成一次写盘
        guard !isIndexSaveScheduled else { return }
        isIndexSaveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.isIndexSaveScheduled = false
            let snapshot = self.index
            let url = self.indexURL
            self.ioQueue.async {
                do {
                    try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
                } catch {
                    Log.error("保存头部缓存索引失败：\(error)")
                }
            }
        }
    }

    private func updateStats() {
        entryCount = index.count
        totalBytes = index.values.reduce(0) { $0 + $1.headLength }
    }

    private static func attributes(of url: URL) -> (size: Int, modified: Date)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return (size, modified)
    }

    private static func isValid(_ entry: HeadCacheEntry, for url: URL) -> Bool {
        // 不在本机时无法核对，先信任缓存；完整文件下好后数据源会再核对大小
        guard CloudFile.isLocal(url) else { return true }
        guard let current = attributes(of: url) else { return false }
        return entry.matches(fileSize: current.size, modified: current.modified)
    }

    /// 只读已在本机的文件：读未下载的文件会阻塞并触发整个文件下载
    private static func makeEntry(from url: URL, writingTo cacheFile: URL) -> HeadCacheEntry? {
        guard CloudFile.isLocal(url),
              let file = attributes(of: url), file.size > 0,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return nil }
        defer { try? handle.close() }
        do {
            let header = try handle.read(upToCount: 10) ?? Data()
            let audioStart = min(HeadCacheMath.id3TagSize(header), file.size)
            try handle.seek(toOffset: UInt64(audioStart))
            guard let head = try handle.read(upToCount: HeadCacheMath.headBudget), !head.isEmpty else { return nil }
            try head.write(to: cacheFile, options: .atomic)
            return HeadCacheEntry(fileSize: file.size, modified: file.modified, audioStart: audioStart, headLength: head.count)
        } catch {
            Log.error("建立头部缓存失败 \(url.lastPathComponent)：\(error)")
            return nil
        }
    }
}

/// 给 AVPlayer 的自定义数据源：呈现“去掉 ID3 标签的虚拟文件”，开头从缓存给，其余等完整文件下载好后从文件读。
/// pending、fullFile 只在 queue 上访问（AVFoundation 也在这个队列回调）。
final class HeadCacheSource: NSObject, AVAssetResourceLoaderDelegate {
    /// 完整文件和缓存对不上（文件在别处被改过）；在主线程回调
    var onMismatch: (() -> Void)?

    private let song: Song
    private let entry: HeadCacheEntry
    private let head: Data
    private let queue = DispatchQueue(label: "com.zcp.sepia.head-source")
    private var pending: [AVAssetResourceLoadingRequest] = []
    private var fullFile: FileHandle?
    private var loggedWaits = Set<ObjectIdentifier>()

    init(song: Song, entry: HeadCacheEntry, head: Data) {
        self.song = song
        self.entry = entry
        self.head = head
    }

    deinit {
        try? fullFile?.close()
    }

    /// 自定义 scheme 的 URL 才会走 resourceLoader；保留扩展名方便识别格式
    func makeAsset() -> AVURLAsset? {
        var components = URLComponents()
        components.scheme = "sepia-head"
        components.host = "song"
        components.path = "/" + song.id
        guard let url = components.url else { return nil }
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return asset
    }

    /// 完整文件已下载到本机（主线程调用）
    func fullFileReady() {
        queue.async {
            guard let handle = try? FileHandle(forReadingFrom: self.song.url),
                  let size = try? handle.seekToEnd(),
                  Int(size) == self.entry.fileSize
            else {
                Log.error("完整文件与头部缓存对不上：\(self.song.id)")
                self.failAll()
                DispatchQueue.main.async { self.onMismatch?() }
                return
            }
            self.fullFile = handle
            self.serve()
        }
    }

    /// 下载失败：结束所有等待中的请求，让播放器报错
    func fail() {
        queue.async { self.failAll() }
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = UTType(filenameExtension: song.url.pathExtension)?.identifier ?? UTType.mp3.identifier
            info.contentLength = Int64(entry.virtualLength)
            info.isByteRangeAccessSupported = true
        }
        pending.append(loadingRequest)
        serve()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        pending.removeAll { $0 === loadingRequest }
    }

    // MARK: - 响应

    private func serve() {
        pending.removeAll { respond(to: $0) }
    }

    /// 尽量满足一个请求；已结束（满足、出错或取消）返回 true
    private func respond(to request: AVAssetResourceLoadingRequest) -> Bool {
        if request.isCancelled { return true }
        guard let dataRequest = request.dataRequest else {
            request.finishLoading()
            return true
        }
        let start = Int(dataRequest.currentOffset)
        let end = dataRequest.requestsAllDataToEndOfResource
            ? entry.virtualLength
            : min(Int(dataRequest.requestedOffset) + dataRequest.requestedLength, entry.virtualLength)
        guard start < end else {
            request.finishLoading()
            return true
        }

        let parts = HeadCacheMath.split(start..<end, headLength: entry.headLength)
        if let headPart = parts.head {
            dataRequest.respond(with: head.subdata(in: headPart))
        }
        guard let rest = parts.rest else {
            request.finishLoading()
            return true
        }
        guard let file = fullFile else {
            // 真机验证用：看播放器起播前会不会请求头部之外的数据（比如文件末尾）
            if loggedWaits.insert(ObjectIdentifier(request)).inserted {
                Log.info("等待完整文件：\(song.id) 请求 \(rest.lowerBound)..<\(rest.upperBound)，头部 \(entry.headLength)")
            }
            return false
        }

        // 从完整文件分块读；文件里的偏移要加上跳过的 ID3 标签长度
        var offset = rest.lowerBound
        do {
            while offset < rest.upperBound {
                try file.seek(toOffset: UInt64(entry.audioStart + offset))
                guard let chunk = try file.read(upToCount: min(256 * 1024, rest.upperBound - offset)), !chunk.isEmpty else {
                    break
                }
                dataRequest.respond(with: chunk)
                offset += chunk.count
            }
            request.finishLoading()
        } catch {
            request.finishLoading(with: error)
        }
        return true
    }

    private func failAll() {
        let error = NSError(domain: "com.zcp.sepia", code: 1, userInfo: [NSLocalizedDescriptionKey: "完整文件不可用"])
        pending.forEach { $0.finishLoading(with: error) }
        pending.removeAll()
    }
}
