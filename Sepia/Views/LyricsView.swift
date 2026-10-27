import SwiftUI
import UIKit

struct LyricsView: View {
    @ObservedObject var lyrics: LyricsLoader
    @ObservedObject var progress: PlaybackProgress
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        switch lyrics.state {
        case .none:
            message("暂无歌词")
        case .loading:
            message("正在加载歌词…")
        case .failed:
            message("歌词加载失败")
        case .loaded(let lines):
            LyricsTable(lines: lines, time: progress.currentTime, onSeek: onSeek)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundColor(Color(uiColor: PlayerPalette.muted))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// iOS 16 的 SwiftUI ScrollView 拿不到“开始拖动 / 松手”事件，歌词列表用 UITableView 实现
private struct LyricsTable: UIViewRepresentable {
    let lines: [LyricLine]
    let time: TimeInterval
    let onSeek: (TimeInterval) -> Void

    func makeUIView(context: Context) -> LyricsUIView {
        LyricsUIView()
    }

    func updateUIView(_ view: LyricsUIView, context: Context) {
        view.onSeek = onSeek
        view.update(lines: lines, time: time)
    }
}

/// 网易云式歌词：播放时当前句居中高亮；手指拖动时出现中线、时间和 ▶，点 ▶ 跳到中线那句；松手 3 秒后回到当前句
final class LyricsUIView: UIView, UITableViewDataSource, UITableViewDelegate {
    var onSeek: ((TimeInterval) -> Void)?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let indicator = SeekIndicatorView()
    private var lines: [LyricLine] = []
    private var currentIndex: Int?
    /// 拖动浏览时中线对准的行
    private var centerIndex: Int?
    private var isBrowsing = false
    private var resumeTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.allowsSelection = false
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.estimatedRowHeight = 48
        tableView.rowHeight = UITableView.automaticDimension
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(LyricCell.self, forCellReuseIdentifier: LyricCell.reuseID)
        addSubview(tableView)

        indicator.isHidden = true
        indicator.playButton.addTarget(self, action: #selector(seekToCenter), for: .touchUpInside)
        addSubview(indicator)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        tableView.frame = bounds
        indicator.frame = CGRect(x: 0, y: bounds.midY - 22, width: bounds.width, height: 44)
        // 上下各留半屏空白，第一句和最后一句也能滚到正中
        let inset = bounds.height / 2
        if tableView.contentInset.top != inset {
            tableView.contentInset = UIEdgeInsets(top: inset, left: 0, bottom: inset, right: 0)
            scrollToCurrent(animated: false)
        }
    }

    func update(lines newLines: [LyricLine], time: TimeInterval) {
        if newLines != lines {
            lines = newLines
            currentIndex = nil
            endBrowsing()
            tableView.reloadData()
            scrollToCurrent(animated: false)
        }
        // 稍微提前一点，避免 seek 到某句开头后因浮点误差仍高亮上一句
        let index = LyricsParser.index(at: time + 0.05, in: lines)
        guard index != currentIndex else { return }
        currentIndex = index
        refreshVisibleCells()
        if !isBrowsing { scrollToCurrent(animated: true) }
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        lines.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: LyricCell.reuseID, for: indexPath) as! LyricCell
        cell.configure(lines[indexPath.row], style: style(for: indexPath.row))
        return cell
    }

    // MARK: - 拖动浏览

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        resumeTimer?.invalidate()
        isBrowsing = true
        indicator.isHidden = false
        updateCenter()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if isBrowsing { updateCenter() }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { scheduleResume() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scheduleResume()
    }

    private func updateCenter() {
        guard !lines.isEmpty else { return }
        let point = CGPoint(x: tableView.bounds.midX, y: tableView.bounds.midY)
        let row = tableView.indexPathForRow(at: point)?.row ?? (point.y < 0 ? 0 : lines.count - 1)
        guard row != centerIndex else { return }
        centerIndex = row
        indicator.timeLabel.text = Self.format(lines[row].time)
        refreshVisibleCells()
    }

    private func scheduleResume() {
        resumeTimer?.invalidate()
        resumeTimer = Timer.scheduledTimer(
            timeInterval: 3, target: self, selector: #selector(resumeFollowing), userInfo: nil, repeats: false
        )
    }

    @objc private func resumeFollowing() {
        endBrowsing()
        scrollToCurrent(animated: true)
    }

    @objc private func seekToCenter() {
        guard let row = centerIndex, lines.indices.contains(row) else { return }
        onSeek?(lines[row].time)
        endBrowsing()
        currentIndex = row
        refreshVisibleCells()
        scrollToCurrent(animated: true)
    }

    private func endBrowsing() {
        resumeTimer?.invalidate()
        resumeTimer = nil
        isBrowsing = false
        centerIndex = nil
        indicator.isHidden = true
        refreshVisibleCells()
    }

    // MARK: - 显示

    private func scrollToCurrent(animated: Bool) {
        let row = currentIndex ?? 0
        guard row < tableView.numberOfRows(inSection: 0) else { return }
        tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .middle, animated: animated)
    }

    private func refreshVisibleCells() {
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            (tableView.cellForRow(at: indexPath) as? LyricCell)?.apply(style: style(for: indexPath.row), animated: true)
        }
    }

    private func style(for row: Int) -> LyricCell.Style {
        if row == currentIndex { return .current }
        if isBrowsing, row == centerIndex { return .focused }
        return .normal
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private final class LyricCell: UITableViewCell {
    static let reuseID = "LyricCell"

    enum Style {
        case normal
        /// 拖动时中线对准的行
        case focused
        case current
    }

    private let label = UILabel()
    private var line: LyricLine?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ line: LyricLine, style: Style) {
        self.line = line
        apply(style: style, animated: false)
    }

    func apply(style: Style, animated: Bool) {
        guard let line else { return }
        let color: UIColor
        let translationColor: UIColor
        switch style {
        case .current:
            color = PlayerPalette.highlight
            translationColor = PlayerPalette.amber
        case .focused:
            color = PlayerPalette.amber
            translationColor = PlayerPalette.amber
        case .normal:
            color = PlayerPalette.muted
            translationColor = PlayerPalette.muted
        }
        let text = NSMutableAttributedString(
            string: line.text,
            attributes: [.font: UIFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: color]
        )
        if let translation = line.translation {
            text.append(NSAttributedString(
                string: "\n" + translation,
                attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .regular), .foregroundColor: translationColor]
            ))
        }
        label.attributedText = text

        // 当前句放大用 transform 而不是换字号：不改行高，列表不会跳
        let transform = style == .current ? CGAffineTransform(scaleX: 1.08, y: 1.08) : .identity
        if animated {
            UIView.animate(withDuration: 0.25) { self.label.transform = transform }
        } else {
            label.transform = transform
        }
    }
}

/// 拖动歌词时屏幕中间的一条线：左边时间，右边 ▶
private final class SeekIndicatorView: UIView {
    let timeLabel = UILabel()
    let playButton = UIButton(type: .system)
    private let line = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeLabel.textColor = PlayerPalette.secondary
        line.backgroundColor = PlayerPalette.track
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.tintColor = PlayerPalette.highlight
        addSubview(timeLabel)
        addSubview(line)
        addSubview(playButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        timeLabel.frame = CGRect(x: 16, y: 0, width: 48, height: bounds.height)
        playButton.frame = CGRect(x: bounds.width - 56, y: 0, width: 44, height: bounds.height)
        line.frame = CGRect(x: 68, y: bounds.midY, width: max(bounds.width - 68 - 60, 0), height: 1)
    }

    /// 只有 ▶ 接收点击，其余区域把触摸让给下面的歌词列表
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === playButton ? hit : nil
    }
}
