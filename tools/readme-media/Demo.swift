import AppKit
import Metal
import ImageIO
import UniformTypeIdentifiers

// Анимации для README: `Sugrob --demo <папка> [сцена]`.
// В приложение этот файл не входит: tools/readme-media/make.sh подкладывает его в копию исходников,
// собирает её и запускает. Сцена — симуляция без экрана поверх нарисованного «рабочего стола»
// (обои, окна, Dock); кадры пишутся в PNG, в анимацию их собирает make.sh.
//
// Сцены не повторяются кадр в кадр от запуска к запуску, поэтому запись начинается по событию
// («лестница почти готова», «все собрались у костра»), а не по времени.

struct DemoWin {
    var rect: CGRect
    var dark: Bool
}

final class DemoStage {
    let sim: Sim
    let wPt: Float, hPt: Float, scale: Float
    var wins: [DemoWin]
    var dock: CGRect?
    var cur = SIMD2<Float>(-100, -100)
    var curOn = false
    var arrow = false               // рисовать стрелку курсора
    let dt: Float = 1.0 / 60

    // запись
    var recDir: String? = nil
    var recEvery = 3                // кадр на каждый третий шаг симуляции (1/20 с); показ — 20 кадров в секунду, см. make.sh
    var shrink: CGFloat = 1         // во сколько раз уменьшить записанный кадр
    var crop: CGRect? = nil         // вырезка, в пунктах
    private var recStep = 0
    var frames = 0

    private let renderer: Renderer
    private let queue: MTLCommandQueue
    private let target: MTLTexture
    private let cs = CGColorSpaceCreateDeviceRGB()
    private let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    private var back: CGImage?
    private let radius: CGFloat = 12

    init?(w: Float, h: Float, scale: Float, wins: [DemoWin], dock: CGRect?, cell: Float = 3, seed: UInt64 = 2026) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let r = Renderer(device: device, pixelFormat: .bgra8Unorm),
              let q = device.makeCommandQueue() else { return nil }
        renderer = r
        queue = q
        wPt = w; hPt = h; self.scale = scale
        self.wins = wins
        self.dock = dock
        sim = Sim(widthPt: w, heightPt: h, cell: cell, seed: seed)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(w * scale), height: Int(h * scale), mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        guard let t = device.makeTexture(descriptor: td) else { return nil }
        target = t
        sim.topLimit = 24
        sim.cfg.storms = false
        sim.cfg.peopleEvents = false
        sim.cfg.people = 0
        sim.cfg.capScale = 1.8
        sim.people.reseed(seed &+ 77)
        sim.wind.reseed(seed &+ 99)
        setWindows()
        sim.prefill()
        sim.forceFill = true; sim.fillSurfaces(); sim.forceFill = false
    }

    func setWindows() {
        var l = wins.enumerated().map {
            Ledge(y: Float($1.rect.minY), x0: Float($1.rect.minX) + 4, x1: Float($1.rect.maxX) - 4, kind: 1, win: $0 + 100,
                  ox: Float($1.rect.minX), wr: Float($1.rect.maxX), r: Float(radius))
        }
        if let d = dock {
            l.append(Ledge(y: Float(d.minY), x0: Float(d.minX) + 5, x1: Float(d.maxX) - 5, kind: 2, win: -1))
        }
        let b = wins.enumerated().map {
            WinBox(x0: Float($1.rect.minX), x1: Float($1.rect.maxX), y0: Float($1.rect.minY), y1: Float($1.rect.maxY), win: $0 + 100)
        }
        sim.setLedges(l, windows: b)
        back = nil
    }

    // MARK: - Ход времени

    /// Прогнать симуляцию; курсор за это время плавно едет к цели (ease — с разгоном и торможением).
    func run(_ seconds: Float, to goal: SIMD2<Float>? = nil, ease: Bool = false) {
        let n = max(1, Int((seconds / dt).rounded()))
        let from = cur
        for i in 1...n {
            if let goal {
                var k = Float(i) / Float(n)
                if ease { k = k * k * (3 - 2 * k) }
                cur = from + (goal - from) * k
            }
            sim.setCursor(x: cur.x, y: cur.y, dt: dt, on: curOn)
            sim.step(dt)
            if let dir = recDir {
                if recStep % recEvery == 0 {
                    frames += 1
                    save(String(format: "%@/f%04d.png", dir, frames))
                }
                recStep += 1
            }
        }
    }

    /// Гнать симуляцию, пока не выполнится условие (но не дольше seconds).
    func wait(_ seconds: Float, _ cond: () -> Bool) -> Bool {
        var t: Float = 0
        while t < seconds {
            if cond() { return true }
            run(0.2)
            t += 0.2
        }
        return cond()
    }

    func record(_ dir: String?) {
        if let dir {
            let fm = FileManager.default
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            for f in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where f.hasSuffix(".png") { try? fm.removeItem(atPath: dir + "/" + f) }
        }
        recDir = dir
        recStep = 0
        if dir != nil { frames = 0 }
    }

    /// Оставить из записанных целиком кадров отрезок с кадра `from` и вырезать из каждого рамку (в пунктах).
    /// Нужно, когда место действия известно только после записи.
    func trim(_ dir: String, from: Int, crop c: CGRect) {
        let fm = FileManager.default
        let s = CGFloat(scale)
        let r = CGRect(x: c.minX * s, y: c.minY * s, width: c.width * s, height: c.height * s).integral
        var n = 0
        for k in 1...max(1, frames) {
            let path = String(format: "%@/f%04d.png", dir, k)
            guard k >= from, let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil), let part = img.cropping(to: r) else {
                try? fm.removeItem(atPath: path); continue
            }
            try? fm.removeItem(atPath: path)
            n += 1
            if let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: String(format: "%@/f%04d.png", dir, n)) as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dst, part, nil)
                CGImageDestinationFinalize(dst)
            }
        }
        frames = n
    }

    // MARK: - Кадр

    func save(_ path: String) {
        guard var img = image() else { return }
        if shrink != 1 {
            let w = Int((CGFloat(img.width) * shrink).rounded()), h = Int((CGFloat(img.height) * shrink).rounded())
            if let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: info) {
                c.interpolationQuality = .high
                c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
                if let small = c.makeImage() { img = small }
            }
        }
        if let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dst, img, nil)
            CGImageDestinationFinalize(dst)
        }
    }

    func image() -> CGImage? {
        let pw = Int(wPt * scale), ph = Int(hPt * scale)
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = target
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        let cmd = queue.makeCommandBuffer()!
        renderer.encode(sim: sim, cmd: cmd, rpd: rpd, scale: scale)
        cmd.commit()
        cmd.waitUntilCompleted()
        var px = [UInt8](repeating: 0, count: pw * ph * 4)
        target.getBytes(&px, bytesPerRow: pw * 4, from: MTLRegionMake2D(0, 0, pw, ph), mipmapLevel: 0)
        let snowImg = px.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(data: raw.baseAddress, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4,
                      space: cs, bitmapInfo: info)?.makeImage()
        }
        if back == nil { back = background() }
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4,
                                  space: cs, bitmapInfo: info), let snowImg, let back else { return nil }
        let full = CGRect(x: 0, y: 0, width: pw, height: ph)
        ctx.draw(back, in: full)
        ctx.draw(snowImg, in: full)
        if arrow && curOn && !sim.handsMode {
            ctx.translateBy(x: 0, y: CGFloat(ph))
            ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
            drawArrow(ctx, at: CGPoint(x: CGFloat(cur.x), y: CGFloat(cur.y)))
        }
        guard let out = ctx.makeImage() else { return nil }
        guard let c = crop else { return out }
        let s = CGFloat(scale)
        return out.cropping(to: CGRect(x: c.minX * s, y: c.minY * s, width: c.width * s, height: c.height * s).integral)
    }

    private func drawArrow(_ ctx: CGContext, at p: CGPoint) {
        let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 17), (4, 13.2), (6.9, 19.8), (9.6, 18.6), (6.8, 12.2), (12, 12.2)]
        let path = CGMutablePath()
        for (i, q) in pts.enumerated() {
            let pt = CGPoint(x: p.x + q.0, y: p.y + q.1)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1.5 * CGFloat(scale)), blur: 3 * CGFloat(scale), color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
        ctx.addPath(path)
        ctx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.setLineWidth(1.3)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }

    // MARK: - Рабочий стол

    private func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
    }

    private func background() -> CGImage? {
        let pw = Int(wPt * scale), ph = Int(hPt * scale)
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4, space: cs, bitmapInfo: info) else { return nil }
        let W = CGFloat(wPt), H = CGFloat(hPt)
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))       // дальше ось Y вниз, единицы — пункты
        var rng = Rng(seed: 31337)
        func rnd() -> CGFloat { CGFloat(rng.next() % 100000) / 100000 }

        // небо
        let sky = CGGradient(colorsSpace: cs, colors: [rgb(0x080C24), rgb(0x131C48), rgb(0x2A3A78), rgb(0x566AA6)] as CFArray,
                             locations: [0, 0.38, 0.74, 1])!
        ctx.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: H), options: [])
        // луна и её свет
        let moon = CGPoint(x: W * 0.80, y: H * 0.19)
        let glow = CGGradient(colorsSpace: cs, colors: [rgb(0xBFD0FF, 0.30), rgb(0xBFD0FF, 0.08), rgb(0xBFD0FF, 0)] as CFArray, locations: [0, 0.4, 1])!
        ctx.drawRadialGradient(glow, startCenter: moon, startRadius: 0, endCenter: moon, endRadius: H * 0.42, options: [])
        ctx.setFillColor(rgb(0xF3F1E4))
        ctx.fillEllipse(in: CGRect(x: moon.x - 21, y: moon.y - 21, width: 42, height: 42))
        ctx.setFillColor(rgb(0xDAD9D0, 0.7))
        for (dx, dy, r) in [(-7.0, -5.0, 5.0), (6.0, 4.0, 3.5), (-2.0, 9.0, 2.5), (8.0, -8.0, 2.0)] {
            ctx.fillEllipse(in: CGRect(x: moon.x + CGFloat(dx) - CGFloat(r), y: moon.y + CGFloat(dy) - CGFloat(r), width: CGFloat(r) * 2, height: CGFloat(r) * 2))
        }
        // звёзды — редкие и тусклые, чтобы не спорили со снежинками
        for _ in 0..<70 {
            let x = rnd() * W, y = rnd() * H * 0.5, a = 0.18 + rnd() * 0.35, r = 0.5 + rnd() * 0.5
            ctx.setFillColor(rgb(0xDDE6FF, a))
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: r * 2, height: r * 2))
        }
        // холмы в три плана, на дальних — ельник
        func ridge(base: CGFloat, amp: CGFloat, f: CGFloat, ph: CGFloat, color: CGColor, trees: Int, treeH: CGFloat) {
            func yAt(_ x: CGFloat) -> CGFloat {
                base - amp * (0.55 * sin(x * f + ph) + 0.3 * sin(x * f * 2.3 + ph * 1.7) + 0.15 * sin(x * f * 5.1 + ph * 0.6))
            }
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: H))
            var x: CGFloat = 0
            while x <= W + 4 { p.addLine(to: CGPoint(x: x, y: yAt(x))); x += 4 }
            p.addLine(to: CGPoint(x: W, y: H))
            p.closeSubpath()
            ctx.addPath(p)
            ctx.setFillColor(color)
            ctx.fillPath()
            for _ in 0..<trees {
                let tx = rnd() * W, th = treeH * (0.6 + rnd() * 0.7), ty = yAt(tx) + 2
                let t = CGMutablePath()
                t.move(to: CGPoint(x: tx, y: ty - th))
                t.addLine(to: CGPoint(x: tx - th * 0.30, y: ty))
                t.addLine(to: CGPoint(x: tx + th * 0.30, y: ty))
                t.closeSubpath()
                ctx.addPath(t)
                ctx.fillPath()
            }
        }
        ridge(base: H * 0.80, amp: H * 0.085, f: 0.0052, ph: 0.4, color: rgb(0x33467F), trees: 0, treeH: 0)
        ridge(base: H * 0.88, amp: H * 0.060, f: 0.0085, ph: 2.1, color: rgb(0x283A6E), trees: 46, treeH: 20)
        ridge(base: H * 0.96, amp: H * 0.045, f: 0.0125, ph: 4.4, color: rgb(0x1E2C58), trees: 30, treeH: 30)

        // строка меню
        ctx.setFillColor(rgb(0x0A0E22, 0.42))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: 24))
        ctx.setFillColor(rgb(0xFFFFFF, 0.85))
        var mx: CGFloat = 14
        for w in [14.0, 46, 28, 30, 34, 44] as [CGFloat] {
            ctx.addPath(CGPath(roundedRect: CGRect(x: mx, y: 9, width: w, height: 6), cornerWidth: 3, cornerHeight: 3, transform: nil))
            mx += w + 16
        }
        ctx.fillPath()
        ctx.addPath(CGPath(roundedRect: CGRect(x: W - 58, y: 9, width: 44, height: 6), cornerWidth: 3, cornerHeight: 3, transform: nil))
        ctx.fillPath()
        snowflake(ctx, at: CGPoint(x: W - 82, y: 12), r: 6.5)

        // окна
        for w in wins { window(ctx, w) }

        // Dock
        if let d = dock {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -4 * CGFloat(scale)), blur: 14 * CGFloat(scale), color: rgb(0x000000, 0.35))
            ctx.addPath(CGPath(roundedRect: d, cornerWidth: 16, cornerHeight: 16, transform: nil))
            ctx.setFillColor(rgb(0xC9D3F2, 0.26))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.addPath(CGPath(roundedRect: d.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 16, cornerHeight: 16, transform: nil))
            ctx.setStrokeColor(rgb(0xFFFFFF, 0.28))
            ctx.setLineWidth(1)
            ctx.strokePath()
            let pal: [(UInt32, UInt32)] = [(0x5AC8FA, 0x2F7DF6), (0xFFD15C, 0xF59E0B), (0x6EE7A8, 0x16A34A), (0xFDA4AF, 0xE11D48),
                                           (0xC4B5FD, 0x7C3AED), (0xF4F4F5, 0xB9BCC8), (0x7DD3FC, 0x0EA5E9), (0xFDBA74, 0xEA580C)]
            let side = d.height - 14, gap: CGFloat = 8
            let n = max(1, Int((d.width - 14 + gap) / (side + gap)))
            let x0 = d.midX - (CGFloat(n) * side + CGFloat(n - 1) * gap) / 2
            for i in 0..<n {
                let r = CGRect(x: x0 + CGFloat(i) * (side + gap), y: d.minY + 7, width: side, height: side)
                ctx.saveGState()
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: side * 0.24, cornerHeight: side * 0.24, transform: nil))
                ctx.clip()
                let g = CGGradient(colorsSpace: cs, colors: [rgb(pal[i % pal.count].0), rgb(pal[i % pal.count].1)] as CFArray, locations: [0, 1])!
                ctx.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.minX, y: r.maxY), options: [])
                ctx.restoreGState()
            }
        }
        return ctx.makeImage()
    }

    private func snowflake(_ ctx: CGContext, at c: CGPoint, r: CGFloat) {
        ctx.setStrokeColor(rgb(0xFFFFFF, 0.95))
        ctx.setLineWidth(1.2)
        ctx.setLineCap(.round)
        for k in 0..<6 {
            let a = CGFloat(k) * .pi / 3
            let d = CGPoint(x: cos(a), y: sin(a))
            ctx.move(to: c)
            ctx.addLine(to: CGPoint(x: c.x + d.x * r, y: c.y + d.y * r))
            for s in [-1.0, 1.0] as [CGFloat] {
                let b = a + s * .pi / 4
                let m = CGPoint(x: c.x + d.x * r * 0.58, y: c.y + d.y * r * 0.58)
                ctx.move(to: m)
                ctx.addLine(to: CGPoint(x: m.x + cos(b) * r * 0.32, y: m.y + sin(b) * r * 0.32))
            }
        }
        ctx.strokePath()
    }

    private func window(_ ctx: CGContext, _ w: DemoWin) {
        let r = w.rect
        let shape = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * CGFloat(scale)), blur: 28 * CGFloat(scale), color: rgb(0x000000, 0.5))
        ctx.addPath(shape)
        ctx.setFillColor(w.dark ? rgb(0x1B1D27) : rgb(0xF6F6F9))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        // заголовок
        ctx.setFillColor(w.dark ? rgb(0x282B38) : rgb(0xE6E6EC))
        ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 34))
        ctx.setFillColor(w.dark ? rgb(0x0E0F15) : rgb(0xD0D0D8))
        ctx.fill(CGRect(x: r.minX, y: r.minY + 34, width: r.width, height: 1))
        for (k, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            ctx.setFillColor(rgb(UInt32(c)))
            ctx.fillEllipse(in: CGRect(x: r.minX + 13 + CGFloat(k) * 19, y: r.minY + 11.5, width: 11, height: 11))
        }
        ctx.setFillColor(w.dark ? rgb(0x6B7084) : rgb(0xA9A9B4))
        ctx.addPath(CGPath(roundedRect: CGRect(x: r.midX - 38, y: r.minY + 14, width: 76, height: 6), cornerWidth: 3, cornerHeight: 3, transform: nil))
        ctx.fillPath()
        // содержимое: строки-заглушки
        var rng = Rng(seed: UInt64(r.minX * 31 + r.minY))
        func rnd() -> CGFloat { CGFloat(rng.next() % 1000) / 1000 }
        var y = r.minY + 54
        if w.dark {
            let cols: [UInt32] = [0x7AA2F7, 0x9ECE6A, 0xE0AF68, 0x565F89, 0xBB9AF7, 0x565F89]
            while y < r.maxY - 16 {
                var x = r.minX + 18 + CGFloat(Int(rnd() * 3)) * 16
                let parts = 1 + Int(rnd() * 3.4)
                if rnd() < 0.16 { y += 15; continue }
                for _ in 0..<parts {
                    let len = 18 + rnd() * 70
                    if x + len > r.maxX - 18 { break }
                    ctx.setFillColor(rgb(cols[Int(rnd() * CGFloat(cols.count)) % cols.count], 0.9))
                    ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: len, height: 5), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
                    ctx.fillPath()
                    x += len + 8
                }
                y += 15
            }
        } else {
            ctx.setFillColor(rgb(0x30313A))
            ctx.addPath(CGPath(roundedRect: CGRect(x: r.minX + 22, y: y, width: r.width * 0.42, height: 9), cornerWidth: 4.5, cornerHeight: 4.5, transform: nil))
            ctx.fillPath()
            y += 28
            while y < r.maxY - 16 {
                let last = rnd() < 0.22
                let len = (r.width - 44) * (last ? 0.3 + rnd() * 0.35 : 0.86 + rnd() * 0.14)
                ctx.setFillColor(rgb(0xC3C4CE))
                ctx.addPath(CGPath(roundedRect: CGRect(x: r.minX + 22, y: y, width: len, height: 5), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
                ctx.fillPath()
                y += last ? 26 : 14
            }
        }
        ctx.restoreGState()
        ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setStrokeColor(w.dark ? rgb(0xFFFFFF, 0.14) : rgb(0x000000, 0.18))
        ctx.setLineWidth(1)
        ctx.strokePath()
    }
}

enum Demo {
    static func run(outDir: String, args: [String]) -> Int32 {
        let what = args.first ?? "all"
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let all: [(String, (String, [String]) -> Bool)] = [
            ("hero", hero), ("snowman", snowman), ("people", people), ("tree", tree), ("storm", storm), ("village", village),
        ]
        var ok = true
        for (name, f) in all where what == "all" || what == name {
            let t0 = CACurrentMediaTime()
            ok = f(outDir, Array(args.dropFirst())) && ok
            print(String(format: "%@: %.1f s", name, CACurrentMediaTime() - t0))
        }
        return ok ? 0 : 1
    }

    /// Сцены, которые в реальном времени смотрятся вяло, пишутся реже — кадр на каждый пятый шаг —
    /// и при тех же 20 кадрах в секунду идут в 1,7 раза быстрее. Буран и костёр — в реальном времени.
    static let fast = 5

    static let desk: [DemoWin] = [DemoWin(rect: CGRect(x: 64, y: 150, width: 340, height: 250), dark: false),
                                  DemoWin(rect: CGRect(x: 500, y: 236, width: 330, height: 226), dark: true)]
    static let deskDock = CGRect(x: 310, y: 504, width: 280, height: 48)

    /// Заглавная анимация: идёт снег, курсор сталкивает шапку с окна и взмахом разбрасывает кучу на Dock.
    static func hero(_ out: String, _ args: [String]) -> Bool {
        guard let st = DemoStage(w: 900, h: 560, scale: 2, wins: desk, dock: deskDock) else { return false }
        st.arrow = true
        st.recEvery = Demo.fast
        st.shrink = 0.75                // 1350 px: вдвое крупнее показа не нужно, а файл заметно легче
        st.run(8)
        st.record(out + "/hero")
        st.run(1.6)
        st.curOn = true
        st.cur = SIMD2(470, 330)
        st.run(1.0, to: SIMD2(66, 136), ease: true)
        st.run(2.6, to: SIMD2(420, 139))
        st.run(0.7, to: SIMD2(560, 330), ease: true)
        st.run(1.5)
        // резкий взмах сквозь кучу, упавшую на Dock
        st.run(0.7, to: SIMD2(360, 488), ease: true)
        st.run(0.16, to: SIMD2(560, 476))
        st.run(0.5, to: SIMD2(640, 400), ease: true)
        st.run(2.2)
        st.record(nil)
        print("hero frames: \(st.frames)")
        return true
    }

    /// Шар катят по снегу, ставят на окно, сверху ещё два — снеговик.
    static func snowman(_ out: String, _ args: [String]) -> Bool {
        let wins = [DemoWin(rect: CGRect(x: 560, y: 392, width: 280, height: 200), dark: false)]
        guard let st = DemoStage(w: 900, h: 560, scale: 2, wins: wins, dock: nil, seed: 21) else { return false }
        let sim = st.sim
        st.arrow = true
        st.crop = CGRect(x: 366, y: 272, width: 384, height: 288)
        st.run(8)
        var placed: [Int32] = []
        func top() -> SIMD2<Float>? {
            guard let id = placed.last, let b = sim.balls.first(where: { $0.id == id }) else { return nil }
            return SIMD2(b.x, b.y - b.r)
        }
        /// Скатать шар от a до b и опустить: на окно (x) или на макушку предыдущего шара.
        func roll(from a: SIMD2<Float>, to b: SIMD2<Float>, secs: Float, x: Float) {
            st.curOn = true
            st.run(0.55, to: a, ease: true)
            sim.handsMode = true
            st.run(0.15)
            let before = Set(sim.balls.map { $0.id })
            sim.grabBegin()
            st.run(secs, to: b)
            let mine = sim.balls.first { !before.contains($0.id) }
            let r = mine?.r ?? 12
            if let t = top() {
                st.run(0.9, to: SIMD2(t.x, t.y - r - 16), ease: true)
                st.run(0.5, to: SIMD2(t.x, t.y - r - 1.5))
            } else {
                st.run(0.9, to: SIMD2(x, 392 - 44 - r), ease: true)
                st.run(0.5, to: SIMD2(x, 392 - 22 - r))
            }
            st.run(0.2)
            sim.grabEnd()
            sim.handsMode = false
            if let m = mine { placed.append(m.id) }
            st.run(0.25)
            st.run(0.5, to: SIMD2(st.cur.x - 46, st.cur.y + 30), ease: true)
            st.run(0.3)
        }
        st.recEvery = Demo.fast
        st.record(out + "/snowman")
        st.cur = SIMD2(470, 420)
        st.curOn = true
        st.run(0.5)
        roll(from: SIMD2(300, 546), to: SIMD2(545, 546), secs: 1.7, x: 640)
        roll(from: SIMD2(545, 546), to: SIMD2(405, 546), secs: 1.1, x: 640)
        roll(from: SIMD2(400, 546), to: SIMD2(470, 546), secs: 0.7, x: 640)
        st.run(0.7, to: SIMD2(520, 330), ease: true)
        st.run(2.0)
        st.record(nil)
        for b in sim.balls { print(String(format: "  ball r=%.1f at %.0f,%.0f parent=%d decor=%d", b.r, b.x, b.y, b.parent, b.decor)) }
        print("snowman frames: \(st.frames)")
        return true
    }

    /// Человечки строят лестницу к окну и лезут на него. Запись начинается, когда лестница почти готова.
    static func people(_ out: String, _ args: [String]) -> Bool {
        let wins = [DemoWin(rect: CGRect(x: 520, y: 340, width: 300, height: 260), dark: true)]
        guard let st = DemoStage(w: 900, h: 560, scale: 2, wins: wins, dock: nil, seed: args.count > 1 ? UInt64(args[1]) ?? 7 : 7) else { return false }
        let pp = st.sim.people
        st.sim.cfg.people = 2
        st.sim.cfg.peopleLadders = true
        st.sim.cfg.peopleStay = false
        st.run(6)
        pp.summon()
        guard st.wait(200, { pp.ladders.contains { $0.active && $0.rows.count > 0 && $0.front >= $0.rows.count - 14 } }) else {
            print("people: no ladder"); return false
        }
        st.crop = CGRect(x: 322, y: 272, width: 384, height: 288)
        st.recEvery = Demo.fast
        st.record(out + "/people")
        _ = st.wait(30, { pp.ladders.contains { $0.done } })
        st.run(7.5)
        st.record(nil)
        print("people frames: \(st.frames)  \(pp.summary)")
        return true
    }

    /// Буран: ветер срывает снег с окон и несёт его по экрану.
    static func storm(_ out: String, _ args: [String]) -> Bool {
        guard let st = DemoStage(w: 900, h: 560, scale: 2, wins: desk, dock: deskDock, seed: 11) else { return false }
        st.sim.cfg.storms = true
        st.run(8)
        st.sim.wind.startStorm(strength: 1, dir: 1, seconds: 60)
        st.run(9)
        st.crop = CGRect(x: 452, y: 132, width: 384, height: 288)
        st.record(out + "/storm")
        st.run(7)
        st.record(nil)
        print("storm frames: \(st.frames)")
        return true
    }

    /// Поселение: три иглу, вечер, все собрались у общего костра.
    static func village(_ out: String, _ args: [String]) -> Bool {
        let wins = [DemoWin(rect: CGRect(x: 40, y: 190, width: 250, height: 420), dark: true)]
        guard let st = DemoStage(w: 900, h: 560, scale: 2, wins: wins, dock: nil, seed: 5) else { return false }
        let sim = st.sim, pp = sim.people
        sim.cfg.people = 2
        sim.cfg.peopleLadders = false
        pp.u = 2
        pp.visitEnd = sim.time + 100000
        HomeTune.evening = true
        st.run(6)
        for i in 0..<3 { _ = pp.debugHouse(sim, x: 440 + Float(i) * 138, door: i == 2 ? -1 : 1) }
        st.run(60)
        guard st.wait(900, { pp.fires.contains { $0.big } && pp.folks.filter { $0.job == .fire }.count >= 5 }) else {
            print("village: no gathering"); return false
        }
        st.run(4)
        st.crop = CGRect(x: 372, y: 392, width: 400, height: 168)        // узкая полоса: дома и костёр
        st.record(out + "/village")
        st.run(8)
        st.record(nil)
        print("village frames: \(st.frames)  \(pp.summary)")
        return true
    }

    /// Ёлка: её приносят из-за края экрана и ставят. Где поставят, заранее неизвестно,
    /// поэтому кадры пишутся целиком, а вырезка делается после.
    static func tree(_ out: String, _ args: [String]) -> Bool {
        let wins = [DemoWin(rect: CGRect(x: 560, y: 392, width: 280, height: 200), dark: false)]
        guard let st = DemoStage(w: 900, h: 560, scale: 2, wins: wins, dock: nil, seed: 9) else { return false }
        let sim = st.sim, pp = sim.people
        sim.cfg.people = 2
        sim.cfg.peopleLadders = false
        sim.cfg.peopleStay = false
        sim.cfg.peopleEvents = true
        st.run(6)
        pp.summon()
        st.run(14)
        guard pp.startTree(sim) else { print("tree: refused"); return false }
        st.recEvery = Demo.fast
        st.record(out + "/tree")
        guard st.wait(120, { !pp.trees.isEmpty }), let t = pp.trees.first else { print("tree: not planted"); return false }
        let planted = st.frames
        st.run(7)
        st.record(nil)
        let x = max(0, min(CGFloat(st.wPt) - 384, CGFloat(t.x) - 150))
        st.trim(out + "/tree", from: max(1, planted - 90), crop: CGRect(x: x, y: 272, width: 384, height: 288))
        print("tree frames: \(st.frames)")
        return true
    }
}
