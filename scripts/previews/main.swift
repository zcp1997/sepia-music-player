// 本机没有 Xcode / 模拟器：把主要界面组件拼成静态画面，用 ImageRenderer 渲染成 PNG 检查配色和布局。
// List、ScrollView、歌词的 UITableView 这些 UIKit 承载的控件画不出来，这里用等价的 SwiftUI 排版代替。
// 用法：scripts/render-previews.sh [输出目录]
import SwiftUI
import UIKit

let width: CGFloat = 390
let height: CGFloat = 844

func song(_ id: String, lyrics: Bool = false) -> Song {
    Song(
        id: id,
        url: URL(fileURLWithPath: "/music/" + id),
        lyricsURL: lyrics ? URL(fileURLWithPath: "/music/" + id + ".lrc") : nil
    )
}

let songs = [
    song("抒情/马灯.mp3", lyrics: true),
    song("抒情/赛里木.mp3"),
    song("抒情/时差 2.mp3", lyrics: true),
    song("说唱/绿幕.mp3"),
    song("说唱/皮影 4.mp3"),
    song("陶喆翻唱/二十二.mp3", lyrics: true),
    song("古风/白囍.mp3", lyrics: true),
    song("Armin/Armin_van_Buuren_Live.mp3"),
]

let progress: PlaybackProgress = {
    let progress = PlaybackProgress()
    progress.duration = 228
    progress.currentTime = 92
    return progress
}()

struct HomePreview: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Music").font(.headline).foregroundColor(Theme.textPrimary)
                HStack {
                    Spacer()
                    Image(systemName: "gearshape").font(.title3).foregroundColor(Theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            SegmentedTabs(selection: .constant(.all))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            FolderChips(folders: ["抒情", "说唱", "陶喆翻唱", "古风"], selection: .constant(nil))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .frame(width: width, alignment: .leading)
                .clipped()
            VStack(spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                    SongRow(
                        song: song,
                        isCurrent: index == 0,
                        isPlaying: false,
                        isFavorite: index == 1 || index == 6,
                        isInCloud: index == 3 || index == 4
                    )
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 70)
                }
            }
            Spacer(minLength: 0)
            MiniPlayerBar(song: songs[0], isPlaying: true, progress: progress, onOpen: {}, onTogglePlay: {}, onNext: {})
                .padding(.bottom, 20)
                .background(Theme.surface)
        }
        .padding(.top, 40)
        .frame(width: width, height: height)
        .background(Theme.background)
    }
}

struct PlayerPreview: View {
    enum Middle { case lyrics, wave, failed }
    var middle = Middle.lyrics

    let lines: [(String, String?, LyricStyle)] = [
        ("风吹过旧城的屋檐", nil, .normal),
        ("我提着灯走过从前", nil, .normal),
        ("一盏马灯 照亮你的脸", "A lantern lights your face", .current),
        ("照亮那年夏天", nil, .normal),
        ("和没说出口的再见", nil, .normal),
    ]

    enum LyricStyle { case normal, current }

    /// 歌词表格是 UITableView，渲染器画不出来，用同样的字号和配色排一遍
    private var lyricsBlock: some View {
        VStack(spacing: 20) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let isCurrent = line.2 == .current
                VStack(spacing: 4) {
                    Text(line.0)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(uiColor: isCurrent ? PlayerPalette.highlight : PlayerPalette.muted))
                    if let translation = line.1 {
                        Text(translation)
                            .font(.system(size: 14))
                            .foregroundColor(Color(uiColor: isCurrent ? PlayerPalette.amber : PlayerPalette.muted))
                    }
                }
                .scaleEffect(isCurrent ? 1.08 : 1)
            }
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            PlayerHeader(song: songs[0]) {}
            switch middle {
            case .lyrics:
                lyricsBlock.frame(maxHeight: .infinity)
            case .wave:
                WaveVisualizer(isPlaying: true).frame(maxHeight: .infinity)
            case .failed:
                LyricsFailedView(reason: "歌词下载超时，请检查网络", isPlaying: true, onRetry: {})
                    .frame(maxHeight: .infinity)
            }
            PlayerActions(isFavorite: true, canEdit: true, mode: .shuffle, onFavorite: {}, onMode: {}, onAdd: {})
            PlaybackScrubber(progress: progress) { _ in }
            PlayerControls(isPlaying: true, onPrevious: {}, onTogglePlay: {}, onNext: {})
                .padding(.bottom, 8)
        }
        .padding(.top, 52)
        .padding(.bottom, 30)
        .frame(width: width, height: height)
        .background(Color(uiColor: PlayerPalette.background))
    }
}

@MainActor
func render<V: View>(_ view: V, scheme: ColorScheme, to path: String) {
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme).tint(Theme.accent))
    renderer.scale = 2
    guard let data = renderer.uiImage?.pngData() else {
        print("渲染失败：\(path)")
        exit(1)
    }
    try! data.write(to: URL(fileURLWithPath: path))
    print("已生成 \(path)")
}

let output = CommandLine.arguments.dropFirst().first ?? "."
MainActor.assumeIsolated {
    render(HomePreview(), scheme: .light, to: "\(output)/home-light.png")
    render(HomePreview(), scheme: .dark, to: "\(output)/home-dark.png")
    render(PlayerPreview(), scheme: .light, to: "\(output)/player.png")
    render(PlayerPreview(middle: .wave), scheme: .light, to: "\(output)/player-wave.png")
    render(PlayerPreview(middle: .failed), scheme: .light, to: "\(output)/player-failed.png")
    render(WelcomeView {}, scheme: .light, to: "\(output)/welcome-light.png")
    render(WelcomeView {}.frame(width: width, height: height), scheme: .dark, to: "\(output)/welcome-dark.png")
}
