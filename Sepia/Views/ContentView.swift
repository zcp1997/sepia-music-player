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

struct WelcomeView: View {
    let onPick: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 52, weight: .semibold))
                .foregroundColor(Theme.accent)
                .frame(width: 104, height: 104)
                .background(RoundedRectangle(cornerRadius: 26).fill(Theme.chipBackground))
            Text("选择音乐文件夹")
                .font(.title2.bold())
                .foregroundColor(Theme.textPrimary)
            Text("选一个 iCloud 云盘里的文件夹，里面的音乐和同名 srt / lrc 歌词会自动导入。")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button(action: onPick) {
                // 系统默认白字，在深色模式的浅琥珀底上看不清
                Text("选择文件夹")
                    .foregroundColor(Theme.onAccent)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text(AppInfo.summary)
                .font(.footnote.monospaced())
                .foregroundColor(Theme.textMuted)
                .padding(.top, 24)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}
