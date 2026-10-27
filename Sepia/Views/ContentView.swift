import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: Player
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if library.rootURL == nil {
                WelcomeView {
                    FolderPicker.shared.present { library.setFolder($0) }
                }
            } else {
                LibraryView()
            }
        }
        .onChange(of: library.songs) { songs in
            player.restoreIfNeeded(from: songs)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                // 回到前台时文件夹里可能有新歌
                if !library.isScanning { library.rescan() }
            case .background:
                player.savePosition()
            default:
                break
            }
        }
    }
}

private struct WelcomeView: View {
    let onPick: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("选择音乐文件夹")
                .font(.title2.bold())
            Text("选一个 iCloud 云盘里的文件夹，里面的音乐和同名 srt / lrc 歌词会自动导入。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("选择文件夹", action: onPick)
                .buttonStyle(.borderedProminent)
            Text(AppInfo.summary)
                .font(.footnote.monospaced())
                .foregroundStyle(.tertiary)
                .padding(.top, 24)
        }
        .padding(32)
    }
}
