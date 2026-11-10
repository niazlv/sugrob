// Рисует значок приложения: ночное небо, воксельный сугроб и снеговик. Запуск: swift tools/make_icon.swift <папка.iconset>
import AppKit

func draw(_ px: Int) -> Data? {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let s = CGFloat(px) / 32.0           // значок рисуется на сетке 32x32 «вокселя»
    func cell(_ x: Int, _ y: Int, _ c: (CGFloat, CGFloat, CGFloat)) {   // y сверху вниз
        ctx.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1))
        ctx.fill(CGRect(x: CGFloat(x) * s, y: CGFloat(31 - y) * s, width: s + 0.5, height: s + 0.5))
    }
    let m = CGFloat(px) * 0.09
    let r = CGRect(x: m, y: m, width: CGFloat(px) - 2 * m, height: CGFloat(px) - 2 * m)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: r.width * 0.225, cornerHeight: r.width * 0.225, transform: nil))
    ctx.clip()
    let g = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.09, green: 0.13, blue: 0.40, alpha: 1),
                                                 CGColor(red: 0.20, green: 0.33, blue: 0.78, alpha: 1)] as CFArray,
                       locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(px)), end: CGPoint(x: 0, y: 0), options: [])
    var seed: UInt64 = 42
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 40) / 16777216 }
    for _ in 0..<26 { cell(3 + Int(rnd() * 26), 3 + Int(rnd() * 18), (0.85, 0.9, 1.0)) }
    // сугроб
    for x in 0..<32 {
        let h = 6 + Int(2.2 * sin(Double(x) * 0.33) + 1.5 * sin(Double(x) * 0.9 + 1))
        for k in 0..<h {
            let y = 31 - k
            let top = k == h - 1
            let v = 0.82 + 0.1 * rnd()
            cell(x, y, top ? (1, 1, 1) : (v * 0.95, v * 1.0, min(1, v * 1.14)))
        }
    }
    // снеговик из двух шаров
    func ball(_ cx: Double, _ cy: Double, _ rad: Double) {
        for y in 0..<32 { for x in 0..<32 {
            let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
            let d = (dx * dx + dy * dy).squareRoot()
            if d <= rad {
                let l = CGFloat(max(0, min(1, 0.78 - (dx * 0.45 + dy * 0.6) / rad * 0.32)))
                cell(x, y, (0.62 + 0.38 * l, 0.72 + 0.28 * l, 0.92 + 0.08 * l))
            }
        } }
    }
    ball(16, 20.5, 6.6)
    ball(16, 11.5, 4.4)
    cell(14, 10, (0.08, 0.1, 0.16)); cell(17, 10, (0.08, 0.1, 0.16))
    cell(16, 12, (0.98, 0.52, 0.12)); cell(17, 12, (0.95, 0.47, 0.1)); cell(18, 12, (0.88, 0.4, 0.08))
    cell(16, 18, (0.1, 0.12, 0.18)); cell(16, 21, (0.1, 0.12, 0.18))
    guard let img = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])
}

let dir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                   ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
                   ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try draw(px)?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
}
