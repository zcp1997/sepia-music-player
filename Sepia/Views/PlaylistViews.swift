import SwiftUI

/// 「歌单」分页：歌单列表，可新建、重命名、删除
struct PlaylistsView: View {
    @EnvironmentObject private var library: Library
    @State private var isCreating = false
    @State private var newName = ""
    @State private var renamingID: UUID?
    @State private var renameText = ""

    var body: some View {
        List {
            Button {
                newName = ""
                isCreating = true
            } label: {
                Label("新建歌单", systemImage: "plus")
            }
            .disabled(!library.isDataReady)

            ForEach(library.data.playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlistID: playlist.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playlist.name)
                        Text("\(library.songs(in: playlist).count) 首")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .contextMenu {
                    Button {
                        renameText = playlist.name
                        renamingID = playlist.id
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        library.deletePlaylist(playlist.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
            .onDelete { offsets in
                offsets.map { library.data.playlists[$0].id }.forEach(library.deletePlaylist)
            }
        }
        .listStyle(.plain)
        .alert("新建歌单", isPresented: $isCreating) {
            TextField("歌单名", text: $newName)
            Button("取消", role: .cancel) {}
            Button("创建") { library.createPlaylist(named: newName) }
        }
        .alert("重命名歌单", isPresented: isRenaming) {
            TextField("歌单名", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") {
                if let id = renamingID { library.renamePlaylist(id, to: renameText) }
            }
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renamingID != nil }, set: { if !$0 { renamingID = nil } })
    }
}

/// 歌单内的歌：点击播放（队列 = 歌单），左滑移除，编辑模式拖动排序
struct PlaylistDetailView: View {
    @EnvironmentObject private var library: Library
    let playlistID: UUID

    var body: some View {
        let playlist = library.data.playlists.first { $0.id == playlistID }
        SongList(
            songs: playlist.map(library.songs(in:)) ?? [],
            emptyText: "在歌曲上长按，选择「加入歌单」",
            onDelete: { library.remove($0, from: playlistID) },
            onMove: { library.reorder(playlistID, to: $0) }
        )
        .navigationTitle(playlist?.name ?? "")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
    }
}

/// 把一首歌加入某个歌单（也可当场新建）
struct PlaylistPicker: View {
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    let song: Song
    @State private var isCreating = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    newName = ""
                    isCreating = true
                } label: {
                    Label("新建歌单", systemImage: "plus")
                }

                ForEach(library.data.playlists) { playlist in
                    let contains = playlist.songs.contains(song.id)
                    Button {
                        library.add(song, to: playlist.id)
                        dismiss()
                    } label: {
                        HStack {
                            Text(playlist.name)
                                .foregroundColor(.primary)
                            Spacer()
                            if contains {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(contains)
                }
            }
            .navigationTitle("加入歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("新建歌单", isPresented: $isCreating) {
                TextField("歌单名", text: $newName)
                Button("取消", role: .cancel) {}
                Button("创建并加入") {
                    if let id = library.createPlaylist(named: newName) {
                        library.add(song, to: id)
                    }
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
