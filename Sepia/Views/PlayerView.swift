import SwiftUI

/// 播放页：沉浸式深棕，不随系统深浅色变化（配色见 PlayerPalette）
struct PlayerView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: Player
    @Environment(\.dismiss) private var dismiss
    @State private var songToAdd: Song?

    var body: some View {
        VStack(spacing: 18) {
            PlayerHeader(song: player.current) { dismiss() }

            LyricsView(lyrics: player.lyrics, progress: player.progress) { time in
                // 网易云式：点歌词旁的 ▶ 跳到那句并开始播放
                player.seek(to: time)
                if !player.isPlaying { player.resume() }
            }
            .frame(maxHeight: .infinity)

            if let status = player.status {
                Text(status)
                    .font(.footnote)
                    .foregroundColor(Color(uiColor: PlayerPalette.secondary))
            }

            if let song = player.current {
                PlayerActions(
                    isFavorite: library.isFavorite(song),
                    canEdit: library.isDataReady,
                    mode: player.mode,
                    onFavorite: { library.toggleFavorite(song) },
                    onMode: player.cycleMode,
                    onAdd: { songToAdd = song }
                )
            }

            PlaybackScrubber(progress: player.progress) { player.seek(to: $0) }

            PlayerControls(
                isPlaying: player.isPlaying,
                onPrevious: player.previous,
                onTogglePlay: player.togglePlayPause,
                onNext: player.next
            )
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(Color(uiColor: PlayerPalette.background).ignoresSafeArea())
        // 系统的拖动条在深棕底上看不清，PlayerHeader 里自己画一条
        .presentationDragIndicator(.hidden)
        .sheet(item: $songToAdd) { song in
            PlaylistPicker(song: song)
                .environmentObject(library)
        }
    }
}

struct PlayerHeader: View {
    let song: Song?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(Color(uiColor: PlayerPalette.track))
                .frame(width: 36, height: 5)
            HStack(alignment: .top) {
                Button(action: onClose) {
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(Color(uiColor: PlayerPalette.secondary))
                        .frame(width: 44, height: 44)
                }
                VStack(spacing: 3) {
                    Text(song?.title ?? "未在播放")
                        .font(.headline)
                        .foregroundColor(Color(uiColor: PlayerPalette.text))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if let folder = song?.folder, !folder.isEmpty {
                        Text(folder)
                            .font(.subheadline)
                            .foregroundColor(Color(uiColor: PlayerPalette.secondary))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                // 和左边按钮等宽，让标题居中
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 12)
    }
}

/// 喜欢 / 播放模式 / 加入歌单
struct PlayerActions: View {
    let isFavorite: Bool
    /// 歌单数据还没读完时不能改
    let canEdit: Bool
    let mode: PlayMode
    let onFavorite: () -> Void
    let onMode: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack {
            Button(action: onFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundColor(Color(uiColor: isFavorite ? PlayerPalette.heart : PlayerPalette.text))
                    .frame(width: 44, height: 44)
            }
            .disabled(!canEdit)
            Spacer()
            Button(action: onMode) {
                HStack(spacing: 5) {
                    Image(systemName: mode.symbol)
                        .font(.footnote.weight(.semibold))
                    Text(mode.title)
                        .font(.footnote)
                }
                .foregroundColor(Color(uiColor: PlayerPalette.amber))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(Capsule().stroke(Color(uiColor: PlayerPalette.track), lineWidth: 1))
            }
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "text.badge.plus")
                    .foregroundColor(Color(uiColor: PlayerPalette.text))
                    .frame(width: 44, height: 44)
            }
            .disabled(!canEdit)
        }
        .font(.title3)
        .padding(.horizontal, 18)
    }
}

/// 细轨道 + 小圆点的进度条。拖动期间只改本地的 scrubTime，不受播放进度回写影响；松手才真正 seek
struct PlaybackScrubber: View {
    @ObservedObject var progress: PlaybackProgress
    let onSeek: (TimeInterval) -> Void
    @State private var scrubTime: TimeInterval?

    var body: some View {
        let duration = progress.duration
        let time = scrubTime ?? progress.currentTime
        let fraction = duration > 0 ? CGFloat(min(max(time / duration, 0), 1)) : 0
        let knob: CGFloat = scrubTime == nil ? 12 : 18

        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(uiColor: PlayerPalette.track))
                        .frame(height: 3)
                    Capsule()
                        .fill(Color(uiColor: PlayerPalette.amber))
                        .frame(width: width * fraction, height: 3)
                    Circle()
                        .fill(Color(uiColor: PlayerPalette.highlight))
                        .frame(width: knob, height: knob)
                        .offset(x: width * fraction - knob / 2)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0, width > 0 else { return }
                            scrubTime = Double(min(max(value.location.x / width, 0), 1)) * duration
                        }
                        .onEnded { _ in
                            if let target = scrubTime { onSeek(target) }
                            scrubTime = nil
                        }
                )
            }
            .frame(height: 28)

            HStack {
                Text(format(time))
                Spacer()
                Text(format(duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundColor(Color(uiColor: PlayerPalette.secondary))
        }
        .padding(.horizontal, 24)
        .animation(.easeOut(duration: 0.12), value: scrubTime == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(format(time)) / \(format(duration))")
        .accessibilityAdjustableAction { direction in
            let step: TimeInterval = direction == .increment ? 10 : -10
            onSeek(min(max(progress.currentTime + step, 0), duration))
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// 上一首 / 米白圆形播放键 / 下一首
struct PlayerControls: View {
    let isPlaying: Bool
    let onPrevious: () -> Void
    let onTogglePlay: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 44) {
            Button(action: onPrevious) {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .frame(width: 52, height: 52)
            }
            Button(action: onTogglePlay) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .semibold))
                    // 三角形视觉重心偏左，往右挪一点看起来才居中
                    .offset(x: isPlaying ? 0 : 2)
                    .foregroundColor(Color(uiColor: PlayerPalette.background))
                    .frame(width: 68, height: 68)
                    .background(Circle().fill(Color(uiColor: PlayerPalette.highlight)))
            }
            Button(action: onNext) {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .frame(width: 52, height: 52)
            }
        }
        .foregroundColor(Color(uiColor: PlayerPalette.text))
    }
}

private extension PlayMode {
    var title: String {
        switch self {
        case .sequential: return "顺序播放"
        case .repeatOne: return "单曲循环"
        case .shuffle: return "随机播放"
        }
    }

    var symbol: String {
        switch self {
        case .sequential: return "repeat"
        case .repeatOne: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }
}
