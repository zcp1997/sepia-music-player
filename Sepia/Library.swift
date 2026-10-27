import Foundation

/// 音乐文件夹：授权、书签、扫描，以及喜欢 / 歌单的读写。@Published 属性只在主线程修改。
final class Library: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var songs: [Song] = [] {
        didSet { songsByID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
    }
    @Published private(set) var isScanning = false
    @Published private(set) var data = LibraryData.empty
    /// 音乐文件夹里的 sepia-library.json 读完（或确认读不到）之前不允许修改，避免用旧数据覆盖它
    @Published private(set) var isDataReady = false

    private var songsByID: [String: Song] = [:]
    private var dataLoadTimer: Timer?
    private let saveQueue = DispatchQueue(label: "com.zcp.sepia.library-save")
    private let bookmarkKey = "folderBookmark"
    private static let mirrorURL = AppPaths.applicationSupport.appendingPathComponent("library-mirror.json")

    init() {
        restoreFolder()
    }

    // MARK: - 文件夹

    /// 用户在文件选择器里选了文件夹。安全作用域访问在 App 生命周期内一直保持。
    func setFolder(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            Log.error("无法访问所选文件夹：\(url.path)")
            return
        }
        do {
            let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            Log.error("保存文件夹书签失败：\(error)")
        }
        rootURL?.stopAccessingSecurityScopedResource()
        rootURL = url
        songs = []
        Log.info("选择文件夹：\(url.path)")
        rescan()
        loadData(root: url)
    }

    func rescan(completion: (() -> Void)? = nil) {
        guard let root = rootURL else {
            completion?()
            return
        }
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let songs = LibraryScanner.scan(root: root)
            DispatchQueue.main.async {
                // 扫描期间换了文件夹，丢弃旧结果
                if root == self.rootURL {
                    self.songs = songs
                    Log.info("扫描完成：\(songs.count) 首")
                    HeadCache.shared.fillMissing(songs)
                }
                self.isScanning = false
                completion?()
            }
        }
    }

    /// 给下拉刷新用
    @MainActor
    func rescan() async {
        await withCheckedContinuation { continuation in
            rescan { continuation.resume() }
        }
    }

    private func restoreFolder() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            guard url.startAccessingSecurityScopedResource() else {
                Log.error("文件夹授权已失效，需要重新选择")
                return
            }
            if isStale, let fresh = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
            rootURL = url
            rescan()
            loadData(root: url)
        } catch {
            Log.error("恢复文件夹失败：\(error)")
        }
    }

    // MARK: - 喜欢与歌单

    var favoriteSongs: [Song] {
        data.favorites.compactMap { songsByID[$0] }
    }

    /// 歌单里文件已不存在的歌不显示（数据里仍保留，文件找回来后会重新出现）
    func songs(in playlist: Playlist) -> [Song] {
        playlist.songs.compactMap { songsByID[$0] }
    }

    func isFavorite(_ song: Song) -> Bool {
        data.isFavorite(song.id)
    }

    func toggleFavorite(_ song: Song) {
        edit { $0.toggleFavorite(song.id) }
    }

    func removeFavorites(_ songs: [Song]) {
        edit { $0.removeFavorites(songs.map(\.id)) }
    }

    @discardableResult
    func createPlaylist(named name: String) -> UUID? {
        var id: UUID?
        edit { id = $0.createPlaylist(named: name) }
        return id
    }

    func renamePlaylist(_ id: UUID, to name: String) {
        edit { $0.renamePlaylist(id, to: name) }
    }

    func deletePlaylist(_ id: UUID) {
        edit { $0.deletePlaylist(id) }
    }

    func add(_ song: Song, to playlistID: UUID) {
        edit { $0.add(song.id, toPlaylist: playlistID) }
    }

    func remove(_ songs: [Song], from playlistID: UUID) {
        edit { $0.removeSongs(songs.map(\.id), fromPlaylist: playlistID) }
    }

    func reorder(_ playlistID: UUID, to songs: [Song]) {
        edit { $0.reorderPlaylist(playlistID, visibleOrder: songs.map(\.id)) }
    }

    private func edit(_ change: (inout LibraryData) -> Void) {
        guard isDataReady else { return }
        var updated = data
        change(&updated)
        guard updated != data else { return }
        updated.updatedAt = Date()
        data = updated
        save(updated)
    }

    // MARK: - 读写 sepia-library.json

    /// 先用沙盒副本立即显示，再读音乐文件夹里的文件，两份取较新的
    private func loadData(root: URL) {
        dataLoadTimer?.invalidate()
        dataLoadTimer = nil
        isDataReady = false
        let mirror = readMirror(for: root)
        data = mirror ?? .empty

        let fileURL = root.appendingPathComponent(LibraryFile.fileName)
        if !CloudFile.exists(fileURL) {
            finishLoading(mirror: mirror, folder: nil)
        } else if CloudFile.isLocal(fileURL) {
            readFolderFile(fileURL, root: root, mirror: mirror)
        } else {
            dataLoadTimer = CloudFile.waitForDownload(fileURL, timeout: 30) { [weak self] isLocal in
                guard let self, root == self.rootURL else { return }
                self.dataLoadTimer = nil
                if isLocal {
                    self.readFolderFile(fileURL, root: root, mirror: mirror)
                } else {
                    // 读不到就先用本机副本，之后的修改会写回文件夹
                    Log.error("\(LibraryFile.fileName) 下载超时，先使用本机副本")
                    self.finishLoading(mirror: mirror, folder: nil, writeBack: false)
                }
            }
        }
    }

    private func readFolderFile(_ url: URL, root: URL, mirror: LibraryData?) {
        DispatchQueue.global(qos: .userInitiated).async {
            var folder: LibraryData?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
                folder = (try? Data(contentsOf: url)).flatMap { try? LibraryFile.decode(LibraryData.self, from: $0) }
            }
            DispatchQueue.main.async {
                guard root == self.rootURL else { return }
                if folder == nil {
                    Log.error("读取 \(LibraryFile.fileName) 失败：\(coordinationError?.localizedDescription ?? "格式不对")")
                }
                self.finishLoading(mirror: mirror, folder: folder)
            }
        }
    }

    private func finishLoading(mirror: LibraryData?, folder: LibraryData?, writeBack: Bool = true) {
        let chosen = LibraryFile.newer(mirror, folder) ?? .empty
        data = chosen
        isDataReady = true
        Log.info("歌单数据就绪：喜欢 \(chosen.favorites.count) 首，歌单 \(chosen.playlists.count) 个")
        if chosen == folder {
            saveMirror(chosen)
        } else if writeBack, chosen != .empty {
            // 本机副本更新（例如上次写文件夹失败）：补写回音乐文件夹
            save(chosen)
        }
    }

    private func readMirror(for root: URL) -> LibraryData? {
        guard
            let json = try? Data(contentsOf: Self.mirrorURL),
            let mirror = try? LibraryFile.decode(LibraryMirror.self, from: json),
            mirror.folderPath == root.path
        else { return nil }
        return mirror.data
    }

    private func saveMirror(_ data: LibraryData) {
        guard let root = rootURL else { return }
        let mirror = LibraryMirror(folderPath: root.path, data: data)
        saveQueue.async {
            do {
                try LibraryFile.encode(mirror).write(to: Self.mirrorURL, options: .atomic)
            } catch {
                Log.error("保存本机副本失败：\(error)")
            }
        }
    }

    /// 写沙盒副本 + 音乐文件夹里的 sepia-library.json（按顺序在串行队列执行）
    private func save(_ data: LibraryData) {
        guard let root = rootURL else { return }
        saveMirror(data)
        let fileURL = root.appendingPathComponent(LibraryFile.fileName)
        saveQueue.async {
            do {
                let json = try LibraryFile.encode(data)
                var coordinationError: NSError?
                var writeError: Error?
                NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinationError) { url in
                    do {
                        try json.write(to: url, options: .atomic)
                    } catch {
                        writeError = error
                    }
                }
                if let error = coordinationError ?? writeError {
                    Log.error("写入 \(LibraryFile.fileName) 失败：\(error)")
                }
            } catch {
                Log.error("编码歌单数据失败：\(error)")
            }
        }
    }
}
