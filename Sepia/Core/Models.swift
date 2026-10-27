import Foundation

struct Song: Identifiable, Hashable {
    /// 相对音乐根文件夹的路径，如 "华语/晴天.mp3"；喜欢、歌单都靠它引用
    let id: String
    /// 真实文件位置；还没从 iCloud 下载时，这个文件可能暂时不存在
    let url: URL
    /// 同名字幕文件（SRT 优先于 LRC）
    let lyricsURL: URL?

    var title: String {
        ((id as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// 所在子文件夹，根目录下的歌为空字符串
    var folder: String {
        (id as NSString).deletingLastPathComponent
    }
}
