import Foundation

enum PlayMode: String, CaseIterable {
    /// 按列表顺序，最后一首之后回到第一首
    case sequential
    /// 播完重播这一首；手动上一首 / 下一首仍按列表走
    case repeatOne
    /// 整个列表随机排一遍，放完一轮前不重复
    case shuffle

    var next: PlayMode {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// 队列的播放顺序：order 里是队列下标，position 指向当前这首
struct PlayOrder: Equatable {
    private(set) var order: [Int]
    private(set) var position: Int

    /// 随机时当前这首排第一，其余打乱
    init(count: Int, current: Int, shuffled: Bool) {
        guard count > 0 else {
            order = []
            position = 0
            return
        }
        if shuffled {
            order = [current] + (0..<count).filter { $0 != current }.shuffled()
            position = 0
        } else {
            order = Array(0..<count)
            position = current
        }
    }

    var isEmpty: Bool { order.isEmpty }

    /// 前进或后退 delta 首（首尾相接），返回新的队列下标
    mutating func step(by delta: Int) -> Int? {
        guard !order.isEmpty else { return nil }
        position = ((position + delta) % order.count + order.count) % order.count
        return order[position]
    }

    /// 接下来的 count 首（不含当前），用于预取
    func upcoming(_ count: Int) -> [Int] {
        guard order.count > 1 else { return [] }
        return (1...min(count, order.count - 1)).map { order[(position + $0) % order.count] }
    }
}

extension Sequence where Element == Song {
    /// 歌曲所在的子文件夹，当作筛选标签；根目录下的歌不算
    var folders: [String] {
        Set(map(\.folder))
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
