import AppKit
import CoreGraphics

// 生成 1024x1024 Q 版「薄肌男」App 图标（渐变背景 + 卡通人物）
// 用法: swiftc scripts/make_icon.swift -o /tmp/make_icon && /tmp/make_icon <out.png>

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "/tmp/AppIcon.png"

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no ctx") }

// MARK: - 背景（圆角 + 对角渐变 橙→粉）
let bgRect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
let path = CGPath(roundedRect: bgRect, cornerWidth: 180, cornerHeight: 180, transform: nil)
ctx.addPath(path)
ctx.clip(using: .evenOdd)

let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.25, alpha: 1).cgColor,
                                   NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.55, alpha: 1).cgColor] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])

// 高光弧（左上柔光）
ctx.setFillColor(NSColor.white.withAlphaComponent(0.12).cgColor)
ctx.fillEllipse(in: CGRect(x: -200, y: 700, width: 700, height: 500))

// MARK: - 配色
let skin   = NSColor(calibratedRed: 0.98, green: 0.80, blue: 0.63, alpha: 1)
let skinD  = NSColor(calibratedRed: 0.90, green: 0.68, blue: 0.50, alpha: 1)
let hair   = NSColor(calibratedRed: 0.23, green: 0.17, blue: 0.15, alpha: 1)
let ink    = NSColor(calibratedRed: 0.20, green: 0.14, blue: 0.12, alpha: 1)
let blush  = NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.45, alpha: 0.55)
let shorts = NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.33, alpha: 1)
let shoe   = NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.97, alpha: 1)

func stroke(_ pts: [(CGFloat, CGFloat)], width: CGFloat, color: NSColor,
            close: Bool = false) {
    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
    for p in pts.dropFirst() { ctx.addLine(to: CGPoint(x: p.0, y: p.1)) }
    if close { ctx.closePath() }
    ctx.strokePath()
}

func fillOval(_ rect: CGRect, _ color: NSColor) {
    ctx.setFillColor(color.cgColor)
    ctx.fillEllipse(in: rect)
}

// MARK: - 人物（Q 版比例：大头 + 小 V 型薄肌身材，双肱二头肌姿势）
let cx: CGFloat = 512

// 腿（两条，微分）
stroke([(cx - 55, 330), (cx - 75, 150)], width: 62, color: skin)
stroke([(cx + 55, 330), (cx + 75, 150)], width: 62, color: skin)
// 鞋
fillOval(CGRect(x: cx - 140, y: 95, width: 150, height: 85), shoe)
fillOval(CGRect(x: cx - 10,  y: 95, width: 150, height: 85), shoe)
ctx.setStrokeColor(skinD.cgColor); ctx.setLineWidth(6)
ctx.strokeEllipse(in: CGRect(x: cx - 140, y: 95, width: 150, height: 85))
ctx.strokeEllipse(in: CGRect(x: cx - 10, y: 95, width: 150, height: 85))

// 短裤（盖住髋部）
let shortsPath = CGMutablePath()
shortsPath.move(to: CGPoint(x: cx - 120, y: 470))
shortsPath.addLine(to: CGPoint(x: cx + 120, y: 470))
shortsPath.addLine(to: CGPoint(x: cx + 105, y: 350))
shortsPath.addLine(to: CGPoint(x: cx + 8, y: 340))
shortsPath.addLine(to: CGPoint(x: cx, y: 400))
shortsPath.addLine(to: CGPoint(x: cx - 8, y: 340))
shortsPath.addLine(to: CGPoint(x: cx - 105, y: 350))
shortsPath.closeSubpath()
ctx.setFillColor(shorts.cgColor)
ctx.addPath(shortsPath)
ctx.fillPath()

// 躯干（V 型薄肌：肩宽 → 腰窄）
let torso = CGMutablePath()
torso.move(to: CGPoint(x: cx - 165, y: 690))          // 左肩
torso.addQuadCurve(to: CGPoint(x: cx + 165, y: 690), control: CGPoint(x: cx, y: 655)) // 肩线微弧
torso.addLine(to: CGPoint(x: cx + 92, y: 480))        // 右腰（收腰）
torso.addLine(to: CGPoint(x: cx - 92, y: 480))        // 左腰
torso.closeSubpath()
ctx.setFillColor(skin.cgColor)
ctx.addPath(torso)
ctx.fillPath()
// 躯干描边
ctx.setStrokeColor(skinD.cgColor); ctx.setLineWidth(8)
ctx.addPath(torso); ctx.strokePath()

// 胸肌（两条对称弧线）
stroke([(cx - 78, 640), (cx - 40, 655)], width: 9, color: skinD)
stroke([(cx + 78, 640), (cx + 40, 655)], width: 9, color: skinD)
stroke([(cx, 600), (cx, 640)], width: 8, color: skinD)   // 中缝
// 腹肌（2x2）
stroke([(cx - 34, 585), (cx + 34, 585)], width: 7, color: skinD)
stroke([(cx - 30, 545), (cx + 30, 545)], width: 7, color: skinD)
stroke([(cx, 565), (cx, 600)], width: 7, color: skinD)

// 手臂（双肱二头肌：上臂外张、前臂上弯）
// 左臂
stroke([(cx - 150, 675), (cx - 285, 610), (cx - 250, 760)], width: 62, color: skin)
fillOval(CGRect(x: cx - 345, y: 700, width: 120, height: 110), skin)   // 肱二头肌鼓起
// 右臂
stroke([(cx + 150, 675), (cx + 285, 610), (cx + 250, 760)], width: 62, color: skin)
fillOval(CGRect(x: cx + 225, y: 700, width: 120, height: 110), skin)
// 拳头
fillOval(CGRect(x: cx - 305, y: 800, width: 92, height: 88), skin)
fillOval(CGRect(x: cx + 213, y: 800, width: 92, height: 88), skin)

// 脖子
ctx.setFillColor(skin.cgColor)
ctx.fill(CGRect(x: cx - 42, y: 675, width: 84, height: 60))

// 头（大圆）
fillOval(CGRect(x: cx - 185, y: 690, width: 370, height: 360), skin)
ctx.setStrokeColor(skinD.cgColor); ctx.setLineWidth(7)
ctx.strokeEllipse(in: CGRect(x: cx - 185, y: 690, width: 370, height: 360))
// 耳朵
fillOval(CGRect(x: cx - 205, y: 830, width: 55, height: 70), skin)
fillOval(CGRect(x: cx + 150, y: 830, width: 55, height: 70), skin)

// 头发（顶部厚发盖 + 碎发）
let hairPath = CGMutablePath()
hairPath.move(to: CGPoint(x: cx - 190, y: 900))
hairPath.addQuadCurve(to: CGPoint(x: cx + 190, y: 900), control: CGPoint(x: cx, y: 1140))
hairPath.addQuadCurve(to: CGPoint(x: cx + 175, y: 800), control: CGPoint(x: cx + 200, y: 870))
hairPath.addQuadCurve(to: CGPoint(x: cx, y: 770), control: CGPoint(x: cx + 90, y: 760))
hairPath.addQuadCurve(to: CGPoint(x: cx - 175, y: 800), control: CGPoint(x: cx - 90, y: 760))
hairPath.addQuadCurve(to: CGPoint(x: cx - 190, y: 900), control: CGPoint(x: cx - 200, y: 870))
hairPath.closeSubpath()
ctx.setFillColor(hair.cgColor)
ctx.addPath(hairPath); ctx.fillPath()
// 三撮呆毛
stroke([(cx - 30, 792), (cx - 55, 745)], width: 16, color: hair)
stroke([(cx + 10, 785), (cx + 5, 730)], width: 16, color: hair)
stroke([(cx + 50, 792), (cx + 75, 748)], width: 16, color: hair)

// 眼睛（^ ^ 眯眯笑眼）
stroke([(cx - 105, 880), (cx - 75, 905), (cx - 45, 880)], width: 13, color: ink)
stroke([(cx + 45, 880), (cx + 75, 905), (cx + 105, 880)], width: 13, color: ink)
// 眉毛（细短）
stroke([(cx - 110, 855), (cx - 60, 848)], width: 8, color: hair)
stroke([(cx + 60, 848), (cx + 110, 855)], width: 8, color: hair)
// 腮红
fillOval(CGRect(x: cx - 150, y: 820, width: 60, height: 38), blush)
fillOval(CGRect(x: cx + 90, y: 820, width: 60, height: 38), blush)
// 嘴（开口笑 + 舌头）
ctx.setFillColor(ink.cgColor)
ctx.beginPath()
ctx.addArc(center: CGPoint(x: cx, y: 855), radius: 34, startAngle: .pi, endAngle: 0, clockwise: true)
ctx.closePath()
ctx.fillPath()
ctx.setFillColor(blush.cgColor)
ctx.fillEllipse(in: CGRect(x: cx - 22, y: 848, width: 44, height: 26))

// 额头高光
ctx.setFillColor(NSColor.white.withAlphaComponent(0.35).cgColor)
ctx.fillEllipse(in: CGRect(x: cx - 120, y: 1000, width: 90, height: 40))

// 胸前小徽章「薄」
let badge = CGRect(x: cx + 30, y: 600, width: 64, height: 64)
fillOval(badge, NSColor.white.withAlphaComponent(0.92))
ctx.setStrokeColor(skinD.cgColor); ctx.setLineWidth(4)
ctx.strokeEllipse(in: badge)
let badgeText = "薄" as NSString
let badgeAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 40, weight: .heavy),
    .foregroundColor: NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.35, alpha: 1)
]
let badgeSize = badgeText.size(withAttributes: badgeAttrs)
badgeText.draw(at: CGPoint(x: badge.midX - badgeSize.width / 2, y: badge.midY - badgeSize.height / 2 - 2),
               withAttributes: badgeAttrs)

image.unlockFocus()

// 保存
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("encode failed")
}
try png.write(to: URL(fileURLWithPath: outPath))
print("saved \(outPath)")


