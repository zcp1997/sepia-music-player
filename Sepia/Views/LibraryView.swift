import SwiftUI

struct LibraryView: View {
    private enum Tab: Hashable {
        case all, favorites, playlists
    }

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: Player
    @State private var tab = Tab.all
    /// 「全部」页选中的文件夹标签；nil 表示不筛选
    @State private var folder: String?
    @State private var isShowingPlayer = false
    @State private var isShowingSettings = false

    var body: some View {
        // 播放条放在 NavigationStack 下方而不是叠在上面：iOS 16 不会把 NavigationStack 外层的
        // safeAreaInset 传给里面的列表，列表最后一首会被播放条挡住
        VStack(spacing: 0) {
            navigation
            if player.current != nil {
                MiniPlayerBar { isShowingPlayer = true }
            }
        }
        // 新建歌单的输入框弹出键盘时，播放条不跟着顶上来
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
                Picker("分类", selection: $tab) {
                    Text("全部").tag(Tab.all)
                    Text("喜欢").tag(Tab.favorites)
                    Text("歌单").tag(Tab.playlists)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

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
            .onChange(of: library.folders) { folders in
                // 重新扫描后选中的文件夹没了，回到不筛选
                if let selected = folder, !folders.contains(selected) { folder = nil }
            }
            .navigationTitle(library.rootURL?.lastPathComponent ?? "Sepia")
            .navigationBarTitleDisplayMode(.inline)
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

/// 文件夹标签：横向滑动，单选；再点一次选中的标签取消筛选
private struct FolderFilterBar: View {
    let folders: [String]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("全部", isSelected: selection == nil) { selection = nil }
                ForEach(folders, id: \.self) { folder in
                    chip(folder, isSelected: selection == folder) {
                        selection = selection == folder ? nil : folder
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundColor(isSelected ? .white : .primary)
                .background(Capsule().fill(isSelected ? Color.accentColor : Color(.secondarySystemFill)))
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
                    SongRow(
                        song: song,
                        isCurrent: song.id == player.current?.id,
                        isFavorite: library.isFavorite(song),
                        // 只对屏幕上可见的行计算（List 是懒加载的）
                        isInCloud: !CloudFile.isLocal(song.url)
                    )
                }
                .contextMenu {
                    Group {
                        Button {
                            library.toggleFavorite(song)
                        } label: {
                            if library.isFavorite(song) {
                                Label("取消喜欢", systemImage: "heart.slash")
                            } else {
                                Label("喜欢", systemImage: "heart")
                            }
                        }
                        Button {
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
        .overlay {
            if songs.isEmpty {
                if let emptyText {
                    Text(emptyText)
                        .foregroundColor(.secondary)
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
        return { offsets in onDelete(offsets.map { songs[$0] }) }
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

private struct SongRow: View {
    let song: Song
    let isCurrent: Bool
    let isFavorite: Bool
    /// 还不在本机：点了要先等 iCloud 下载
    let isInCloud: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .foregroundColor(isCurrent ? .accentColor : .primary)
                    .lineLimit(1)
                if !song.folder.isEmpty {
                    Text(song.folder)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundColor(.pink)
            }
            if song.lyricsURL != nil {
                Image(systemName: "text.quote")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if isInCloud {
                Image(systemName: "icloud")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct MiniPlayerBar: View {
    @EnvironmentObject private var player: Player
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MiniProgressLine(progress: player.progress)
            HStack(spacing: 20) {
                Text(player.current?.title ?? "")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: player.togglePlayPause) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                }
                Button(action: player.next) {
                    Image(systemName: "forward.fill")
                }
            }
            .font(.title3)
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
        .background(.bar)
    }
}

private struct MiniProgressLine: View {
    @ObservedObject var progress: PlaybackProgress

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: geometry.size.width * fraction)
        }
        .frame(height: 2)
    }

    private var fraction: CGFloat {
        guard progress.duration > 0 else { return 0 }
        return CGFloat(min(max(progress.currentTime / progress.duration, 0), 1))
    }
}
