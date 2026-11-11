import AppKit

// Фон окна установочного образа: swift tools/dmg/make_background.swift <папка>
// Пишет background.png (660×400) и background@2x.png (1320×800). dmgbuild сам собирает из них
// образ для обычных и Retina-экранов.
//
// Цвет под подписями значков (полоса y 228–250) выбран средним — около #5B70B3. Finder рисует
// подписи чёрными в светлой теме и белыми в тёмной, и фон не может это изменить, поэтому там
// нужен цвет, на котором читаются оба: контраст с чёрным 4.4, с белым 4.7.

let W: CGFloat = 660, H: CGFloat = 400

struct Rng {
    var s: UInt64
    mutating func next() -> CGFloat {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((s >> 33) % 100000) / 100000
    }
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: a)
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let pw = Int(W * scale), ph = Int(H * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    let cs = CGColorSpaceCreateDeviceRGB()
    ctx.translateBy(x: 0, y: CGFloat(ph))
    ctx.scaleBy(x: scale, y: -scale)          // дальше Y вниз, единицы — пункты
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    var rng = Rng(s: 20261111)

    // небо: от ночного к сумеркам; на высоте подписей значков — средний цвет (см. шапку)
    let sky = CGGradient(colorsSpace: cs, colors: [rgb(0x0B1130), rgb(0x18235A), rgb(0x34478F), rgb(0x5B70B3), rgb(0x7F93CC)] as CFArray,
                         locations: [0, 0.20, 0.42, 0.60, 0.76])!
    ctx.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: H), options: [.drawsAfterEndLocation])

    // луна
    let moon = CGPoint(x: 566, y: 70)
    let glow = CGGradient(colorsSpace: cs, colors: [rgb(0xCFDBFF, 0.34), rgb(0xCFDBFF, 0.09), rgb(0xCFDBFF, 0)] as CFArray, locations: [0, 0.35, 1])!
    ctx.drawRadialGradient(glow, startCenter: moon, startRadius: 0, endCenter: moon, endRadius: 120, options: [])
    ctx.setFillColor(rgb(0xF4F2E6))
    ctx.fillEllipse(in: CGRect(x: moon.x - 17, y: moon.y - 17, width: 34, height: 34))
    ctx.setFillColor(rgb(0xDAD9D0, 0.7))
    for (dx, dy, r) in [(-6.0, -4.0, 4.2), (5.0, 3.0, 3.0), (-1.5, 7.5, 2.0), (6.5, -6.5, 1.6)] {
        ctx.fillEllipse(in: CGRect(x: moon.x + CGFloat(dx) - CGFloat(r), y: moon.y + CGFloat(dy) - CGFloat(r), width: CGFloat(r) * 2, height: CGFloat(r) * 2))
    }
    // звёзды: только в тёмной верхней части, тусклые
    for _ in 0..<60 {
        let x = rng.next() * W, y = rng.next() * 150, a = 0.16 + rng.next() * 0.36, r = 0.45 + rng.next() * 0.6
        ctx.setFillColor(rgb(0xDDE6FF, a))
        ctx.fillEllipse(in: CGRect(x: x, y: y, width: r * 2, height: r * 2))
    }

    // холмы: дальний с ельником, ближний — сугроб
    func ridge(base: CGFloat, amp: CGFloat, f: CGFloat, ph: CGFloat, color: CGColor, trees: Int, treeH: CGFloat) {
        func yAt(_ x: CGFloat) -> CGFloat {
            base - amp * (0.55 * sin(x * f + ph) + 0.3 * sin(x * f * 2.3 + ph * 1.7) + 0.15 * sin(x * f * 5.1 + ph * 0.6))
        }
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: H))
        var x: CGFloat = 0
        while x <= W + 4 { p.addLine(to: CGPoint(x: x, y: yAt(x))); x += 2 }
        p.addLine(to: CGPoint(x: W, y: H))
        p.closeSubpath()
        ctx.addPath(p)
        ctx.setFillColor(color)
        ctx.fillPath()
        for _ in 0..<trees {
            let tx = rng.next() * W, th = treeH * (0.6 + rng.next() * 0.7), ty = yAt(tx) + 2
            // ёлки не заходят в полосу подписей и не мешают стрелке
            if ty - th < 262 { continue }
            let t = CGMutablePath()
            t.move(to: CGPoint(x: tx, y: ty - th))
            t.addLine(to: CGPoint(x: tx - th * 0.32, y: ty))
            t.addLine(to: CGPoint(x: tx + th * 0.32, y: ty))
            t.closeSubpath()
            ctx.addPath(t)
            ctx.setFillColor(color)
            ctx.fillPath()
        }
    }
    ridge(base: 296, amp: 20, f: 0.0095, ph: 0.9, color: rgb(0x33468C), trees: 38, treeH: 30)
    ridge(base: 318, amp: 16, f: 0.0125, ph: 3.2, color: rgb(0x9FB1E0), trees: 0, treeH: 0)

    // ближний сугроб с градиентом, чтобы был объём
    let drift = CGMutablePath()
    drift.move(to: CGPoint(x: 0, y: H))
    var x: CGFloat = 0
    func dy(_ x: CGFloat) -> CGFloat { 334 - 14 * (0.6 * sin(x * 0.011 + 1.4) + 0.3 * sin(x * 0.027 + 0.3) + 0.1 * sin(x * 0.07)) }
    while x <= W + 2 { drift.addLine(to: CGPoint(x: x, y: dy(x))); x += 2 }
    drift.addLine(to: CGPoint(x: W, y: H))
    drift.closeSubpath()
    ctx.saveGState()
    ctx.addPath(drift)
    ctx.clip()
    let snow = CGGradient(colorsSpace: cs, colors: [rgb(0xF2F6FF), rgb(0xDCE5FA), rgb(0xBCCBF0)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(snow, start: CGPoint(x: 0, y: 312), end: CGPoint(x: 0, y: H), options: [.drawsAfterEndLocation])
    // голубые тени от неровностей
    for _ in 0..<16 {
        let cx = rng.next() * W, cy = 350 + rng.next() * 46, rw = 40 + rng.next() * 90
        ctx.setFillColor(rgb(0x8FA4DC, 0.16))
        ctx.fillEllipse(in: CGRect(x: cx - rw, y: cy - 5, width: rw * 2, height: 10 + rng.next() * 8))
    }
    ctx.restoreGState()

    // стрелка от приложения к «Программам»
    let a = CGPoint(x: 252, y: 172), c = CGPoint(x: 330, y: 150), b = CGPoint(x: 400, y: 172)
    let arrow = CGMutablePath()
    arrow.move(to: a)
    arrow.addQuadCurve(to: b, control: c)
    // касательная в конце — для наконечника
    let tx = b.x - c.x, ty = b.y - c.y, tl = hypot(tx, ty)
    let ux = tx / tl, uy = ty / tl
    let head = CGMutablePath()
    let tip = CGPoint(x: b.x + 7 * ux, y: b.y + 7 * uy)
    for s in [-1.0, 1.0] as [CGFloat] {
        let ang = s * 0.62                                    // раствор наконечника, рад
        let wx = -ux * cos(ang) + uy * sin(ang), wy = -ux * sin(ang) - uy * cos(ang)
        head.move(to: tip)
        head.addLine(to: CGPoint(x: tip.x + wx * 17, y: tip.y + wy * 17))
    }
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 10, color: rgb(0xBFD0FF, 0.9))
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.95))
    ctx.setLineWidth(5.5)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineDash(phase: 0, lengths: [0.1, 11])     // пунктир из круглых точек: как след по снегу
    ctx.addPath(arrow)
    ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.setLineWidth(5.5)
    ctx.addPath(head)
    ctx.strokePath()
    ctx.restoreGState()

    // снег в воздухе: мелкий дальний и несколько крупных ближних
    for i in 0..<170 {
        let x = rng.next() * W, y = rng.next() * 320
        let near = i % 7 == 0
        let r = near ? 1.8 + rng.next() * 1.6 : 0.6 + rng.next() * 0.9
        let al = near ? 0.55 + rng.next() * 0.3 : 0.22 + rng.next() * 0.4
        ctx.setFillColor(rgb(0xFFFFFF, al))
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    // надписи
    func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat, shadow: Bool = false) {
        let par = NSMutableParagraphStyle()
        par.alignment = .center
        var attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                    .foregroundColor: color, .paragraphStyle: par]
        if shadow {
            let sh = NSShadow()
            sh.shadowColor = NSColor(white: 0, alpha: 0.35)
            sh.shadowBlurRadius = 6
            sh.shadowOffset = NSSize(width: 0, height: -1)
            attrs[.shadow] = sh
        }
        NSAttributedString(string: s, attributes: attrs).draw(in: NSRect(x: 20, y: y, width: W - 40, height: size * 1.5))
    }
    text("Перетащите Сугроб в «Программы»", size: 23, weight: .semibold, color: .white, y: 36, shadow: true)
    text("Drag Sugrob to Applications", size: 13.5, weight: .regular, color: NSColor(white: 1, alpha: 0.72), y: 68, shadow: true)
    let ink = NSColor(srgbRed: 0.15, green: 0.20, blue: 0.43, alpha: 1)
    // подложка под подсказку: на неё не попадают тёмные ёлки, и текст читается везде.
    // Лежит не ниже y 344: в окне с включёнными строкой пути и строкой состояния Finder закрывает нижние ~55 пунктов.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 8, color: rgb(0x0B1130, 0.25))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 34, y: 303, width: W - 68, height: 41), cornerWidth: 10, cornerHeight: 10, transform: nil))
    ctx.setFillColor(rgb(0xEEF3FF, 0.92))
    ctx.fillPath()
    ctx.restoreGState()
    text("Не открывается? Системные настройки → Конфиденциальность и безопасность → «Всё равно открыть»",
         size: 11, weight: .medium, color: ink, y: 309)
    text("Won’t open? System Settings → Privacy & Security → Open Anyway",
         size: 10.5, weight: .regular, color: ink.withAlphaComponent(0.8), y: 326)

    NSGraphicsContext.current = nil
    return rep
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, scale) in [("background.png", 1.0), ("background@2x.png", 2.0)] as [(String, CGFloat)] {
    let rep = render(scale: scale)
    // dmgbuild/Finder выбирают Retina-вариант по DPI: 144 для @2x
    rep.size = NSSize(width: W, height: H)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    try png.write(to: URL(fileURLWithPath: out + "/" + name))
    print("wrote \(out)/\(name) \(rep.pixelsWide)x\(rep.pixelsHigh)")
}
