import Foundation

func testWaveEnergyEasing() {
    var motion = WaveMotion(isPlaying: true, time: 100)
    check(motion.energy(at: 100) == WaveMotion.playingEnergy, "播放时能量为 1")

    motion.setPlaying(false, at: 110)
    check(abs(motion.energy(at: 110) - 1) < 1e-9, "刚暂停时能量从 1 开始，不跳变")
    let afterOneSecond = motion.energy(at: 111)
    check(afterOneSecond < 0.2 && afterOneSecond > WaveMotion.pausedEnergy, "约 1 秒后接近暂停值：\(afterOneSecond)")
    check(abs(motion.energy(at: 130) - WaveMotion.pausedEnergy) < 1e-6, "最终停在暂停值")

    // 缓动到一半时又点播放：从当时的能量继续，不跳变
    motion.setPlaying(true, at: 130.2)
    let resumed = motion.energy(at: 130.2)
    check(abs(resumed - WaveMotion.pausedEnergy) < 1e-6, "恢复播放时从当前能量出发：\(resumed)")
    check(motion.energy(at: 140) > 0.99, "恢复后回到 1")
}

func testWavePhaseContinuity() {
    var motion = WaveMotion(isPlaying: true, time: 0)
    let before = motion.phase(at: 5)
    motion.setPlaying(false, at: 5)
    check(abs(motion.phase(at: 5) - before) < 1e-9, "切换时相位连续，波形不会跳")

    var last = motion.phase(at: 5)
    for step in 1...50 {
        let phase = motion.phase(at: 5 + Double(step) * 0.1)
        check(phase > last, "相位一直往前走（暂停时只是变慢）")
        last = phase
    }

    let playingRate = WaveMotion(isPlaying: true, time: 0).phase(at: 10) / 10
    let pausedRate = WaveMotion(isPlaying: false, time: 0).phase(at: 10) / 10
    check(playingRate > pausedRate * 2, "暂停时流动明显变慢：\(playingRate) vs \(pausedRate)")
}

func testWaveOffsetShape() {
    for layer in 0..<WaveMotion.layerCount {
        check(abs(WaveMotion.offset(layer: layer, u: 0, phase: 3, energy: 1)) < 1e-9, "左端收细为 0")
        check(abs(WaveMotion.offset(layer: layer, u: 1, phase: 3, energy: 1)) < 1e-9, "右端收细为 0")
        var peak = 0.0
        for step in 0...200 {
            for phase in stride(from: 0.0, to: 20, by: 0.7) {
                peak = max(peak, abs(WaveMotion.offset(layer: layer, u: Double(step) / 200, phase: phase, energy: 1)))
            }
        }
        check(peak <= 1.0001 && peak > 0.3, "第 \(layer) 层振幅在合理范围：\(peak)")
    }
    let loud = abs(WaveMotion.offset(layer: 0, u: 0.5, phase: 0.4, energy: 1))
    let quiet = abs(WaveMotion.offset(layer: 0, u: 0.5, phase: 0.4, energy: WaveMotion.pausedEnergy))
    check(quiet < loud, "暂停时振幅变小")
}
