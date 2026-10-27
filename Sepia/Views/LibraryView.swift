import SwiftUI

enum LibraryTab: CaseIterable {
    case all, favorites, playlists

    var title: String {
        switch self {
        case .all: return "全部"
        case .favorites: return "喜欢"
        case .playlists: return "歌单"
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: Player
    @State private var tab = LibraryTab.all
    /// 「全部」页选中的文件夹标签；nil 表示不筛选
    @State private var folder: String?
    @State private var isShowingPlayer = false
    @State private var isShowingSettings = false

    var body: some View {
        // 播放条放在 NavigationStack 下方而不是叠在上面：iOS 16 不会把 NavigationStack 外层的
        // safeAreaInset 传给里面的列表，列表最后一首会被播放条挡住
        VStack(spacing: 0) {
            navigation
            if let song = player.current {
                MiniPlayerBar(
                    song: song,
                    isPlaying: player.isPlaying,
                    progress: player.progress,
                    onOpen: { isShowingPlayer = true },
                    onTogglePlay: player.togglePlayPause,
                    onNext: player.next
                )
            }
        }
        // 新建歌单的输入框弹出键盘时，播放条不跟着顶上来
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // 排查「偶尔切分页没反应」：和 SegmentedTabs 里的「点击分页」对照，看点击送到了没有、状态更新了没有
        .onChange(of: tab) { Log.info("已切到分页：\($0.title)") }
        .onChange(of: isShowingPlayer) { Log.info($0 ? "打开播放页" : "收起播放页") }
        .onChange(of: isShowingSettings) { Log.info($0 ? "打开设置" : "关闭设置") }
        .sheet(isPresented: $isShowingPlayer) {
            PlayerView()
                .environmentObject(library)
                .environmentObject(player)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .environmentObject(library)
                .environmentObject(player)
        }
    }

    private var navigation: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SegmentedTabs(selection: $tab)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                switch tab {
                case .all:
                    if !library.folders.isEmpty {
                        FolderFilterBar(folders: library.folders, selection: $folder)
                    }
                    // 点歌时队列就是筛选后的列表
                    SongList(
                        songs: folder.map { selected in library.songs.filter { $0.folder == selected } } ?? library.songs,
                        emptyText: library.isScanning ? nil : "这个文件夹里没有找到音乐"
                    )
                    .refreshable { await library.rescan() }
                case .favorites:
                    SongList(
                        songs: library.favoriteSongs,
                        emptyText: "还没有喜欢的歌",
                        onDelete: { library.removeFavorites($0) }
                    )
                case .playlists:
                    PlaylistsView()
                }
            }
            .background(Theme.background)
            .onChange(of: library.folders) { folders in
                // 重新扫描后选中的文件夹没了，回到不筛选
                if let selected = folder, !folders.contains(selected) { folder = nil }
            }
            .navigationTitle(library.rootURL?.lastPathComponent ?? "Sepia")
            .navigationBarTitleDisplayMode(.inline)
            .themedNavigationBar()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }
}

/// [全部 | 喜欢 | 歌单]，自己画而不用系统分段控件，好配合主题色和深色模式
struct SegmentedTabs: View {
    @Binding var selection: LibraryTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LibraryTab.allCases, id: \.self) { tab in
                let isSelected = tab == selection
                Button {
                    Log.info("点击分页：\(tab.title)")
                    selection = tab
                } label: {
                    Text(tab.title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? Theme.textPrimary : Theme.chipText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(isSelected ? Theme.segmentSelected : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.chipBackground))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

/// 文件夹标签：横向滑动，单选；再点一次选中的标签取消筛选
private struct FolderFilterBar: View {
    let folders: [String]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            FolderChips(folders: folders, selection: $selection)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }
}

struct FolderChips: View {
    let folders: [String]
    @Binding var selection: String?

    var body: some View {
        HStack(spacing: 8) {
            chip("全部", isSelected: selection == nil) { selection = nil }
            ForEach(folders, id: \.self) { folder in
                chip(folder, isSelected: selection == folder) {
                    selection = selection == folder ? nil : folder
                }
            }
        }
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundColor(isSelected ? Theme.onAccent : Theme.chipText)
                .background(Capsule().fill(isSelected ? Theme.accent : Theme.chipBackground))
        }
        .buttonStyle(.plain)
    }
}

/// 歌曲列表：点击播放（队列 = 这个列表），长按可喜欢 / 加入歌单
struct SongList: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: Player

    let songs: [Song]
    /// 列表为空时的提示；nil 表示还在加载，显示转圈
    var emptyText: String?
    var onDelete: (([Song]) -> Void)?
    /// 参数是拖动排序后的新顺序
    var onMove: (([Song]) -> Void)?

    @State private var songToAdd: Song?

    var body: some View {
        List {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                Button {
                    player.play(songs, at: index)
                } label: {
                    let isCurrent = song.id == player.current?.id
                    SongRow(
                        song: song,
                        isCurrent: isCurrent,
                        isPlaying: isCurrent && player.isPlaying,
                        isFavorite: library.isFavorite(song),
                        // 只对屏幕上可见的行计算（List 是懒加载的）
                        isInCloud: !CloudFile.isLocal(song.url)
                    )
                }
                .themedRow()
                .contextMenu {
                    Group {
                        Button {
                            Log.info("长按菜单：\(library.isFavorite(song) ? "取消喜欢" : "喜欢") \(song.id)")
                            library.toggleFavorite(song)
                        } label: {
                            if library.isFavorite(song) {
                                Label("取消喜欢", systemImage: "heart.slash")
                            } else {
                                Label("喜欢", systemImage: "heart")
                            }
                        }
                        Button {
                            Log.info("长按菜单：加入歌单 \(song.id)")
                            songToAdd = song
                        } label: {
                            Label("加入歌单…", systemImage: "text.badge.plus")
                        }
                    }
                    .disabled(!library.isDataReady)
                }
            }
            .onDelete(perform: deleteAction)
            .onMove(perform: moveAction)
        }
        .listStyle(.plain)
        .themedListBackground()
        .overlay {
            if songs.isEmpty {
                if let emptyText {
                    Text(emptyText)
                        .foregroundColor(Theme.textSecondary)
                } else {
                    ProgressView("正在扫描…")
                }
            }
        }
        .sheet(item: $songToAdd) { song in
            PlaylistPicker(song: song)
                .environmentObject(library)
        }
    }

    private var deleteAction: ((IndexSet) -> Void)? {
        guard let onDelete else { return nil }
        return { offsets in
            let removed = offsets.map { songs[$0] }
            Log.info("左滑删除：\(removed.map(\.id).joined(separator: "、"))")
            onDelete(removed)
        }
    }

    private var moveAction: ((IndexSet, Int) -> Void)? {
        guard let onMove else { return nil }
        return { source, destination in
            var reordered = songs
            reordered.move(fromOffsets: source, toOffset: destination)
            onMove(reordered)
        }
    }
}

struct SongRow: View {
    let song: Song
    let isCurrent: Bool
    /// 正在出声：音波动起来；暂停时静止
    let isPlaying: Bool
    let isFavorite: Bool
    /// 还不在本机：点了要先等 iCloud 下载
    let isInCloud: Bool

    var body: some View {
        HStack(spacing: 12) {
            SongTile(title: song.title, folder: song.folder, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .foregroundColor(isCurrent ? Theme.accent : Theme.textPrimary)
                    .lineLimit(1)
                if !song.folder.isEmpty {
                    Text(song.folder)
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isCurrent {
                NowPlayingBars(isAnimating: isPlaying)
            }
            if isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundColor(Theme.heart)
            }
            if song.lyricsURL != nil {
                Image(systemName: "text.quote")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            if isInCloud {
                Image(systemName: "icloud")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// 没有封面时的占位：歌名第一个字，底色按文件夹
struct SongTile: View {
    let title: String
    let folder: String
    let size: CGFloat

    var body: some View {
        let colors = Theme.tile(for: folder)
        Text(title.first.map { String($0).uppercased() } ?? "♪")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundColor(colors.foreground)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.24).fill(colors.background))
    }
}

/// 正在播放那一行的三根小音波
struct NowPlayingBars: View {
    let isAnimating: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !isAnimating)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { bar in
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: 3, height: height(of: bar, at: time))
                }
            }
            .frame(height: 14, alignment: .bottom)
        }
    }

    private func height(of bar: Int, at time: TimeInterval) -> CGFloat {
        guard isAnimating else { return [6, 12, 8][bar] }
        let wave = (sin(time * 6 + Double(bar) * 1.7) + 1) / 2
        return 4 + 10 * CGFloat(wave)
    }
}

struct MiniPlayerBar: View {
    let song: Song
    let isPlaying: Bool
    let progress: PlaybackProgress
    let onOpen: () -> Void
    let onTogglePlay: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.separator)
                .frame(height: 0.5)
            MiniProgressLine(progress: progress)
            HStack(spacing: 12) {
                SongTile(title: song.title, folder: song.folder, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(song.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    if !song.folder.isEmpty {
                        Text(song.folder)
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onTogglePlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 40, height: 40)
                }
                Button(action: onNext) {
                    Image(systemName: "forward.fill")
                        .frame(width: 40, height: 40)
                }
            }
            .font(.title3)
            .foregroundColor(Theme.accent)
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
        .background(Theme.surface)
    }
}

/// 单独观察进度：每秒刷新 5 次，只重绘这一条线
private struct MiniProgressLine: View {
    @ObservedObject var progress: PlaybackProgress

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Theme.accent)
                .frame(width: geometry.size.width * fraction)
        }
        .frame(height: 2)
    }

    private var fraction: CGFloat {
        guard progress.duration > 0 else { return 0 }
        return CGFloat(min(max(progress.currentTime / progress.duration, 0), 1))
    }
}
