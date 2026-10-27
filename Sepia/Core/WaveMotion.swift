import Foundation

/// 没有歌词时的流动波浪：不读真实音频，几条正弦曲线叠加。
/// “能量”在播放时为 1、暂停时为 0.12，切换时按指数缓动；相位随能量变快变慢。
/// 全部用闭式公式按时间直接算，不需要逐帧累积状态。
struct WaveMotion: Equatable {
    static let playingEnergy = 1.0
    static let pausedEnergy = 0.12
    /// 缓动速度：约 1 秒内基本到位
    static let easing = 3.0
    static let layerCount = 4

    private var changeTime: TimeInterval
    private var energyAtChange: Double
    private var phaseAtChange: Double
    private var target: Double

    init(isPlaying: Bool, time: TimeInterval) {
        changeTime = time
        target = isPlaying ? Self.playingEnergy : Self.pausedEnergy
        energyAtChange = target
        phaseAtChange = 0
    }

    func energy(at time: TimeInterval) -> Double {
        let elapsed = max(time - changeTime, 0)
        return target + (energyAtChange - target) * exp(-Self.easing * elapsed)
    }

    /// 相位速度 = 0.35 + 0.65 × 能量；对缓动中的能量积分
    func phase(at time: TimeInterval) -> Double {
        let elapsed = max(time - changeTime, 0)
        let integral = target * elapsed + (energyAtChange - target) * (1 - exp(-Self.easing * elapsed)) / Self.easing
        return phaseAtChange + 0.35 * elapsed + 0.65 * integral
    }

    mutating func setPlaying(_ isPlaying: Bool, at time: TimeInterval) {
        let newTarget = isPlaying ? Self.playingEnergy : Self.pausedEnergy
        guard newTarget != target else { return }
        energyAtChange = energy(at: time)
        phaseAtChange = phase(at: time)
        changeTime = time
        target = newTarget
    }

    /// 第 layer 条曲线在横向位置 u（0…1）处的纵向偏移，范围约 -1…1（乘以最大振幅即可）。
    /// 两端收细为 0，越靠后的层振幅越小、频率越高。
    static func offset(layer: Int, u: Double, phase: Double, energy: Double) -> Double {
        let k = Double(layer)
        let envelope = pow(sin(Double.pi * u), 2)
        let amplitude = (34 - 6 * k) / 34 * envelope * (0.25 + 0.75 * energy)
        let wave = sin(u * (6 + 1.3 * k) + phase * (2.2 + 0.6 * k) + 1.1 * k)
        let breathing = 0.75 + 0.25 * sin(phase * 1.3 + k)
        return amplitude * wave * breathing
    }
}
