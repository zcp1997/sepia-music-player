import SwiftUI
import UIKit

/// 配色取自 App 图标（琥珀棕、米白、深棕）。主页等跟随系统深浅色；播放页固定深棕，见 PlayerPalette。
enum Theme {
    /// 主题色。系统控件（文件选择器、弹窗按钮等）用的是 Assets 里同值的 AccentColor
    static let accent = Color(uiColor: .dynamic(light: 0x9A5B2E, dark: 0xD6A878))
    /// 放在主题色上的文字
    static let onAccent = Color(uiColor: .dynamic(light: 0xFFF7EE, dark: 0x1C1612))
    static let background = Color(uiColor: .dynamic(light: 0xFAF6F0, dark: 0x1C1612))
    /// 迷你播放条、设置里的卡片
    static let surface = Color(uiColor: .dynamic(light: 0xF3EADF, dark: 0x2A211A))
    static let separator = Color(uiColor: .dynamic(light: 0xEADFD2, dark: 0x3A2E25))
    static let textPrimary = Color(uiColor: .dynamic(light: 0x2B211A, dark: 0xF3E9DC))
    static let textSecondary = Color(uiColor: .dynamic(light: 0x8C7B6B, dark: 0xA8957F))
    /// ☁ 这类次要图标
    static let textMuted = Color(uiColor: .dynamic(light: 0xB3A190, dark: 0x6F604F))
    static let chipBackground = Color(uiColor: .dynamic(light: 0xF0E6D9, dark: 0x33281F))
    static let chipText = Color(uiColor: .dynamic(light: 0x5C4330, dark: 0xE3D3C0))
    /// 分段控件里选中的那一格
    static let segmentSelected = Color(uiColor: .dynamic(light: 0xFFFFFF, dark: 0x4A3A2E))
    static let heart = Color(uiColor: .dynamic(light: 0xC2553D, dark: 0xE07A62))

    /// 首字色块的配色：按文件夹名取一组，同一文件夹永远同色
    static func tile(for folder: String) -> (background: Color, foreground: Color) {
        let palette = tilePalette[Int(stableHash(folder) % UInt64(tilePalette.count))]
        return (
            Color(uiColor: .dynamic(light: palette.light, dark: palette.dark)),
            Color(uiColor: .dynamic(light: palette.dark, dark: palette.light))
        )
    }

    /// 每组：浅色模式的底色（深色模式里用作文字色）、深色模式的底色（浅色模式里用作文字色）
    private static let tilePalette: [(light: UInt32, dark: UInt32)] = [
        (0xF3D9B5, 0x6E4219), // 琥珀
        (0xF2C9BA, 0x6E3020), // 珊瑚
        (0xDCD3C0, 0x4F412A), // 沙
        (0xCFDCCB, 0x34503A), // 鼠尾草
        (0xEBCFD2, 0x62303C), // 玫瑰
        (0xD9CBBE, 0x4E3E30), // 灰褐
        (0xEDDDA6, 0x5E4A12), // 赭黄
        (0xE6C3A8, 0x63361C), // 陶土
    ]

    /// FNV-1a：Swift 的 hashValue 每次启动都不同，颜色会变
    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

extension View {
    /// List / Form 换成主题背景（iOS 16 起可以隐藏系统默认背景）
    func themedListBackground() -> some View {
        scrollContentBackground(.hidden).background(Theme.background)
    }

    /// 列表行：主题背景 + 暖灰分隔线
    func themedRow() -> some View {
        listRowBackground(Theme.background).listRowSeparatorTint(Theme.separator)
    }

    /// 导航栏用主题背景，不透出系统灰
    func themedNavigationBar() -> some View {
        toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

/// 播放页：不论系统深浅色都用深棕底、米白字（和图标一致）
enum PlayerPalette {
    static let background = UIColor(hex: 0x3B2A1E)
    /// 当前句歌词、播放键底色
    static let highlight = UIColor(hex: 0xFFF4E4)
    static let text = UIColor(hex: 0xF6EBDD)
    /// 歌名下的文件夹、时间
    static let secondary = UIColor(hex: 0xCDB8A2)
    /// 非当前句歌词
    static let muted = UIColor(hex: 0xA8927E)
    /// 当前句的翻译、进度条已播部分、播放模式文字
    static let amber = UIColor(hex: 0xE8C9A4)
    /// 进度条底、胶囊边框
    static let track = UIColor(hex: 0x6B5443)
    /// 波形的第三层
    static let clay = UIColor(hex: 0xC98B5E)
    static let heart = UIColor(hex: 0xE8A08C)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        let lightColor = UIColor(hex: light)
        let darkColor = UIColor(hex: dark)
        return UIColor { $0.userInterfaceStyle == .dark ? darkColor : lightColor }
    }
}
