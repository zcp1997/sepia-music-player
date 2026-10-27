import Foundation

struct Playlist: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    /// 歌曲 ID（相对路径），按歌单内顺序
    var songs: [String]
}

/// 喜欢与歌单，存成音乐文件夹里的 sepia-library.json
struct LibraryData: Codable, Equatable {
    var version = 1
    var updatedAt: Date
    /// 最近喜欢的在前
    var favorites: [String]
    var playlists: [Playlist]

    static let empty = LibraryData(updatedAt: .distantPast, favorites: [], playlists: [])
}

/// App 沙盒里的副本：音乐文件夹暂时读不到（离线、未下载）时用它
struct LibraryMirror: Codable {
    var folderPath: String
    var data: LibraryData
}

enum LibraryFile {
    static let fileName = "sepia-library.json"

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    /// 两份数据取更新时间较新的；只有一份时用那一份
    static func newer(_ a: LibraryData?, _ b: LibraryData?) -> LibraryData? {
        guard let a else { return b }
        guard let b else { return a }
        return a.updatedAt >= b.updatedAt ? a : b
    }
}

extension LibraryData {
    func isFavorite(_ songID: String) -> Bool {
        favorites.contains(songID)
    }

    mutating func toggleFavorite(_ songID: String) {
        if let index = favorites.firstIndex(of: songID) {
            favorites.remove(at: index)
        } else {
            favorites.insert(songID, at: 0)
        }
    }

    mutating func removeFavorites(_ songIDs: [String]) {
        favorites.removeAll { songIDs.contains($0) }
    }

    @discardableResult
    mutating func createPlaylist(named name: String) -> UUID {
        let playlist = Playlist(id: UUID(), name: Self.cleanName(name), songs: [])
        playlists.append(playlist)
        return playlist.id
    }

    mutating func renamePlaylist(_ id: UUID, to name: String) {
        updatePlaylist(id) { $0.name = Self.cleanName(name) }
    }

    mutating func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
    }

    /// 已在歌单里的歌不重复添加
    mutating func add(_ songID: String, toPlaylist id: UUID) {
        updatePlaylist(id) { playlist in
            if !playlist.songs.contains(songID) { playlist.songs.append(songID) }
        }
    }

    mutating func removeSongs(_ songIDs: [String], fromPlaylist id: UUID) {
        updatePlaylist(id) { $0.songs.removeAll { songIDs.contains($0) } }
    }

    /// visibleOrder 是界面上能看到的歌的新顺序；文件已不存在（看不到）的歌保留在末尾
    mutating func reorderPlaylist(_ id: UUID, visibleOrder: [String]) {
        updatePlaylist(id) { playlist in
            let hidden = playlist.songs.filter { !visibleOrder.contains($0) }
            playlist.songs = visibleOrder + hidden
        }
    }

    private mutating func updatePlaylist(_ id: UUID, _ change: (inout Playlist) -> Void) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        change(&playlists[index])
    }

    private static func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "新歌单" : trimmed
    }
}
