import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: Player
    @Environment(\.dismiss) private var dismiss
    @State private var songToAdd: Song?

    var body: some View {
        VStack(spacing: 20) {
            header

            LyricsView(lyrics: player.lyrics, progress: player.progress) { time in
                // 网易云式：点歌词旁的 ▶ 跳到那句并开始播放
                player.seek(to: time)
                if !player.isPlaying { player.resume() }
            }
            .frame(maxHeight: .infinity)

            if let status = player.status {
                Text(status)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            songActions

            ProgressSlider(progress: player.progress) { player.seek(to: $0) }
                .padding(.horizontal, 24)

            HStack(spacing: 48) {
                Button(action: player.previous) {
                    Image(systemName: "backward.fill")
                }
                Button(action: player.togglePlayPause) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }
                Button(action: player.next) {
                    Image(systemName: "forward.fill")
                }
            }
            .font(.title)
            .foregroundColor(.primary)
            .padding(.bottom, 8)
        }
        .padding(.vertical, 16)
        .presentationDragIndicator(.visible)
        .sheet(item: $songToAdd) { song in
            PlaylistPicker(song: song)
                .environmentObject(library)
        }
    }

    /// 喜欢 / 加入歌单
    private var songActions: some View {
        HStack {
            if let song = player.current {
                let isFavorite = library.isFavorite(song)
                Button {
                    library.toggleFavorite(song)
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(isFavorite ? .pink : .primary)
                }
                Spacer()
                Button {
                    songToAdd = song
                } label: {
                    Image(systemName: "text.badge.plus")
                        .foregroundColor(.primary)
                }
            }
        }
        .font(.title2)
        .disabled(!library.isDataReady)
        .padding(.horizontal, 32)
        .frame(height: 32)
    }

    private var header: some View {
        HStack(alignment: .top) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
            }
            VStack(spacing: 4) {
                Text(player.current?.title ?? "未在播放")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let folder = player.current?.folder, !folder.isEmpty {
                    Text(folder)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            // 和左边按钮等宽，让标题居中
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
    }
}

/// 拖动期间只改本地的 scrubTime，不受播放进度回写影响；松手才真正 seek
private struct ProgressSlider: View {
    @ObservedObject var progress: PlaybackProgress
    let onSeek: (TimeInterval) -> Void
    @State private var scrubTime: TimeInterval?

    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { scrubTime ?? progress.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(progress.duration, 1),
                onEditingChanged: { isEditing in
                    guard !isEditing, let time = scrubTime else { return }
                    onSeek(time)
                    scrubTime = nil
                }
            )
            .disabled(progress.duration == 0)

            HStack {
                Text(format(scrubTime ?? progress.currentTime))
                Spacer()
                Text(format(progress.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundColor(.secondary)
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
