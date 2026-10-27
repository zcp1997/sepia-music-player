// 生成 App 图标（1024×1024，不透明 PNG）：棕褐色渐变 + 唱片纹 + 米白色双连音符。
// 用法：swiftc scripts/make-icon.swift -o /tmp/make-icon && /tmp/make-icon Sepia/Assets.xcassets/AppIcon.appiconset/AppIcon.png
// 音符是手绘路径，不用 SF Symbols（Apple 不允许把 SF Symbols 用在 App 图标里）。
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
// 改成左上角为原点、y 向下，和设计稿坐标一致
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)

// 背景：左上浅棕 → 右下深棕
let background = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgb(214, 168, 120), rgb(150, 98, 60), rgb(92, 58, 34)] as CFArray,
    locations: [0, 0.55, 1]
)!
context.drawLinearGradient(background, start: .zero, end: CGPoint(x: size, y: size), options: [])

// 唱片纹：几道很淡的同心圆
let center = CGPoint(x: 512, y: 512)
context.setLineWidth(4)
for (radius, alpha) in [(430.0, 0.10), (370.0, 0.08), (310.0, 0.06)] {
    context.setStrokeColor(rgb(255, 245, 230, alpha))
    context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}

// 双连音符：两个倾斜的符头 + 两根符干 + 一条符杠
let note = CGMutablePath()
func addHead(cx: CGFloat, cy: CGFloat) {
    let transform = CGAffineTransform(translationX: cx, y: cy).rotated(by: -22 * .pi / 180)
    note.addEllipse(in: CGRect(x: -118, y: -86, width: 236, height: 172), transform: transform)
}
let offsetX: CGFloat = -14
addHead(cx: 382 + offsetX, cy: 700)
addHead(cx: 676 + offsetX, cy: 640)
note.addRect(CGRect(x: 450 + offsetX, y: 300, width: 44, height: 390))   // 左符干
note.addRect(CGRect(x: 744 + offsetX, y: 250, width: 44, height: 380))   // 右符干（顶端藏进倾斜的符杠里）
note.addLines(between: [                                                 // 符杠
    CGPoint(x: 450 + offsetX, y: 300),
    CGPoint(x: 788 + offsetX, y: 240),
    CGPoint(x: 788 + offsetX, y: 345),
    CGPoint(x: 450 + offsetX, y: 405),
])
note.closeSubpath()

context.saveGState()
// 阴影偏移不受坐标翻转影响：(0, -14) 是向下
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: rgb(40, 20, 8, 0.35))
context.setFillColor(rgb(250, 241, 226))
context.addPath(note)
context.fillPath(using: .winding)
context.restoreGState()

let image = context.makeImage()!
let url = URL(fileURLWithPath: output)
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("写入 \(output) 失败")
}
print("已生成 \(output)")
