import SwiftUI

/// 没有歌词时播放页中间的流动波浪（不读真实音频，形状见 WaveMotion）。
/// 播放时活跃；暂停后约 1 秒平静下来，只保留缓慢的起伏。
struct WaveVisualizer: View {
    let isPlaying: Bool
    @State private var motion: WaveMotion

    /// 从前往后：米白、浅琥珀、陶土、灰棕，越靠后越淡
    private static let layers: [(color: UIColor, opacity: Double, width: CGFloat)] = [
        (PlayerPalette.highlight, 1, 2.6),
        (PlayerPalette.amber, 0.85, 1.8),
        (PlayerPalette.clay, 0.7, 1.8),
        (PlayerPalette.muted, 0.55, 1.8),
    ]

    init(isPlaying: Bool) {
        self.isPlaying = isPlaying
        _motion = State(initialValue: WaveMotion(isPlaying: isPlaying, time: Date().timeIntervalSinceReferenceDate))
    }

    var body: some View {
        // 暂停时降到 30 帧，省电
        TimelineView(.animation(minimumInterval: isPlaying ? nil : 1.0 / 30)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            let energy = motion.energy(at: now)
            let phase = motion.phase(at: now)
            Canvas { canvas, size in
                // 先画后面的淡色层，最亮的一层压在最上面
                for layer in (0..<WaveMotion.layerCount).reversed() {
                    let style = Self.layers[layer]
                    canvas.stroke(
                        path(layer: layer, in: size, phase: phase, energy: energy),
                        with: .color(Color(uiColor: style.color).opacity(style.opacity)),
                        style: StrokeStyle(lineWidth: style.width, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .onChange(of: isPlaying) { playing in
            motion.setPlaying(playing, at: Date().timeIntervalSinceReferenceDate)
        }
        .accessibilityHidden(true)
    }

    private func path(layer: Int, in size: CGSize, phase: Double, energy: Double) -> Path {
        let steps = 96
        let left = size.width * 0.06
        let span = size.width * 0.88
        let amplitude = min(size.height * 0.36, 120)
        var path = Path()
        for step in 0...steps {
            let u = Double(step) / Double(steps)
            let point = CGPoint(
                x: left + span * CGFloat(u),
                y: size.height / 2 + amplitude * CGFloat(WaveMotion.offset(layer: layer, u: u, phase: phase, energy: energy))
            )
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}
