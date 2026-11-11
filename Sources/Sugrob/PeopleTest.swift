import AppKit
import Metal
import ImageIO
import UniformTypeIdentifiers

/// Самотест человечков без экрана: `Sugrob --people-test <папка> [сценарий]`.
/// Сценарии: play (снежки и снеговик), ladder (лестница к окну, потом окно двигают),
/// stairs (окно не доходит до низа экрана — высокие ступени), all. Дальше — размер вокселя и «пикселя» человечка.
/// Кадры — в PNG: общий план и увеличенные вырезки.
enum PeopleTest {
    static func run(outDir: String, args: [String]) -> Int32 {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = Renderer(device: device, pixelFormat: .bgra8Unorm),
              let queue = device.makeCommandQueue() else {
            print("no metal"); return 1
        }
        let what = args.first ?? "all"
        // сценарии жизни (завалы, иглу, забавы) — в своих файлах, на общей сцене PeopleStage
        for prefix in ["rescue", "home", "fun"] where what.hasPrefix(prefix) {
            let stage = PeopleStage(outDir: outDir, device: device, renderer: renderer, queue: queue,
                                    cell: args.count > 1 ? Float(args[1]) ?? 3 : 3, unit: args.count > 2 ? Float(args[2]) ?? 2 : 2)
            let rest = Array(args.dropFirst(3))
            switch prefix {
            case "rescue": return RescueTest.run(stage, what: what, args: rest)
            case "home": return HomeTest.run(stage, what: what, args: rest)
            default: return FunTest.run(stage, what: what, args: rest)
            }
        }
        let cell = args.count > 1 ? Float(args[1]) ?? 3 : 3
        let unit = args.count > 2 ? Float(args[2]) ?? 2 : 2
        let wPt: Float = 1400, hPt: Float = 800, scale: Float = 2
        let sim = Sim(widthPt: wPt, heightPt: hPt, cell: cell, seed: 4242)
        var wins: [CGRect] = [CGRect(x: 330, y: 190, width: 430, height: 520),
                              CGRect(x: 930, y: 380, width: 330, height: 470)]
        if what == "stairs" { wins.removeLast() }       // только окно, не доходящее до низа: нужны высокие ступени
        // ярусы: нижнее окно и перед ним окно повыше — к нему с пола не подойти, только с карниза нижнего
        if what == "tier" { wins = [CGRect(x: 300, y: 520, width: 600, height: 400), CGRect(x: 560, y: 200, width: 300, height: 400)] }
        func setWindows() {
            if what == "tier" {
                let a = wins[0], b = wins[1]
                func box(_ r: CGRect, _ id: Int) -> WinBox { WinBox(x0: Float(r.minX), x1: Float(r.maxX), y0: Float(r.minY), y1: Float(r.maxY), win: id) }
                sim.setLedges([
                    Ledge(y: Float(a.minY), x0: Float(a.minX) + 5.4, x1: Float(b.minX) - 3, kind: 1, win: 100, ox: Float(a.minX), wr: Float(a.maxX), r: 18),
                    Ledge(y: Float(a.minY), x0: Float(b.maxX) + 3, x1: Float(a.maxX) - 5.4, kind: 1, win: 100, ox: Float(a.minX), wr: Float(a.maxX), r: 18),
                    Ledge(y: Float(b.minY), x0: Float(b.minX) + 5.4, x1: Float(b.maxX) - 5.4, kind: 1, win: 101, ox: Float(b.minX), wr: Float(b.maxX), r: 18),
                ], windows: [box(b, 101), box(a, 100)])
                return
            }
            let l = wins.enumerated().map {
                Ledge(y: Float($1.minY), x0: Float($1.minX) + 5.4, x1: Float($1.maxX) - 5.4, kind: 1, win: $0 + 100,
                      ox: Float($1.minX), wr: Float($1.maxX), r: 18)
            }
            let b = wins.enumerated().map {
                WinBox(x0: Float($1.minX), x1: Float($1.maxX), y0: Float($1.minY), y1: Float($1.maxY), win: $0 + 100)
            }
            sim.setLedges(l, windows: b)
        }
        sim.topLimit = 30
        setWindows()
        sim.cfg.flakeRate = 14
        sim.cfg.intensity = 1
        sim.cfg.storms = false          // бураны сценарий запускает сам
        sim.prefill()
        sim.forceFill = true; sim.fillSurfaces(); sim.forceFill = false

        let pw = Int(wPt * scale), ph = Int(hPt * scale)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: pw, height: ph, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        guard let target = device.makeTexture(descriptor: td) else { return 1 }
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        func save(_ img: CGImage, _ name: String) {
            let url = URL(fileURLWithPath: outDir).appendingPathComponent(name + ".png")
            if let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dst, img, nil)
                CGImageDestinationFinalize(dst)
            }
        }

        /// Кадр целиком и, если задано, вырезки (в пунктах экрана), увеличенные в zoom раз.
        func shot(_ name: String, crops: [CGRect] = [], zoom: Int = 3, full: Bool = true) {
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
            guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4,
                                      space: cs, bitmapInfo: info), let snowImg else { return }
            ctx.translateBy(x: 0, y: CGFloat(ph))
            ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
            // обои: тёмный верх, светлее к низу
            let grad = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.07, green: 0.10, blue: 0.27, alpha: 1),
                                                            CGColor(red: 0.22, green: 0.30, blue: 0.50, alpha: 1)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: CGFloat(hPt)), options: [])
            for (i, w) in wins.enumerated() {
                ctx.setFillColor(i == 0 ? CGColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1)
                                        : CGColor(red: 0.15, green: 0.16, blue: 0.20, alpha: 1))
                ctx.addPath(CGPath(roundedRect: w, cornerWidth: 18, cornerHeight: 18, transform: nil))
                ctx.fillPath()
                ctx.setFillColor(i == 0 ? CGColor(red: 0.86, green: 0.86, blue: 0.88, alpha: 1)
                                        : CGColor(red: 0.22, green: 0.23, blue: 0.28, alpha: 1))
                ctx.fill(CGRect(x: w.minX + 14, y: w.minY + 44, width: w.width - 28, height: 1))
                for k in 0..<3 {
                    ctx.setFillColor([CGColor(red: 1, green: 0.37, blue: 0.34, alpha: 1), CGColor(red: 1, green: 0.74, blue: 0.18, alpha: 1),
                                      CGColor(red: 0.16, green: 0.78, blue: 0.25, alpha: 1)][k])
                    ctx.fillEllipse(in: CGRect(x: w.minX + 18 + CGFloat(k) * 20, y: w.minY + 16, width: 12, height: 12))
                }
            }
            ctx.scaleBy(x: 1 / CGFloat(scale), y: -1 / CGFloat(scale))
            ctx.translateBy(x: 0, y: -CGFloat(ph))
            ctx.draw(snowImg, in: CGRect(x: 0, y: 0, width: pw, height: ph))
            guard let out = ctx.makeImage() else { return }
            if full { save(out, name) }
            for (k, r) in crops.enumerated() {
                let pr = CGRect(x: r.minX * CGFloat(scale), y: r.minY * CGFloat(scale), width: r.width * CGFloat(scale), height: r.height * CGFloat(scale))
                    .intersection(CGRect(x: 0, y: 0, width: pw, height: ph)).integral
                guard pr.width > 2, pr.height > 2, let part = out.cropping(to: pr) else { continue }
                let zw = Int(pr.width) * zoom, zh = Int(pr.height) * zoom
                guard let zc = CGContext(data: nil, width: zw, height: zh, bitsPerComponent: 8, bytesPerRow: zw * 4, space: cs, bitmapInfo: info) else { continue }
                zc.interpolationQuality = .none
                zc.draw(part, in: CGRect(x: 0, y: 0, width: zw, height: zh))
                if let z = zc.makeImage() { save(z, "\(name)-z\(k)") }
            }
            print(String(format: "%@  t=%.1f  %@", name, sim.time, sim.people.summary))
        }

        let dt: Float = 1.0 / 60
        var cur = SIMD2<Float>(-100, -100)
        var curOn = false
        func run(_ seconds: Float, to target: SIMD2<Float>? = nil) {
            let n = max(1, Int(seconds / dt))
            let from = cur
            for i in 1...n {
                if let target { cur = from + (target - from) * (Float(i) / Float(n)) }
                sim.setCursor(x: cur.x, y: cur.y, dt: dt, on: curOn)
                sim.step(dt)
            }
        }
        /// Рамка вокруг всех человечков — для увеличенной вырезки.
        func around(pad: CGFloat = 50) -> CGRect {
            let f = sim.people.folks
            guard !f.isEmpty else { return CGRect(x: 500, y: 600, width: 400, height: 200) }
            let xs = f.map { CGFloat($0.x) }, ys = f.map { CGFloat($0.y) }
            let x0 = max(0, xs.min()! - pad), x1 = min(CGFloat(wPt), xs.max()! + pad)
            let y0 = max(0, ys.min()! - pad - 20), y1 = min(CGFloat(hPt), ys.max()! + 14)
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
        func cells() -> Int { sim.snow.reduce(0) { $0 + ($1 != 0 ? 1 : 0) } }

        sim.cfg.peopleSize = unit
        sim.people.reseed(20261111)
        run(4)                              // окна «стоят на месте» уже несколько секунд
        let t0 = CACurrentMediaTime()

        if what == "play" || what == "all" {
            sim.cfg.people = 2
            sim.cfg.peopleLadders = false
            sim.people.summon()
            run(3); shot("p01-arrive", crops: [around()])
            for k in 0..<14 {
                run(k < 6 ? 2.5 : 6)
                shot(String(format: "p%02d-play", k + 2), crops: [around()], full: k % 3 == 2)
            }
            // курсор проносится сквозь компанию
            if let p = sim.people.folks.first(where: { $0.mode == .ground }) {
                curOn = true
                cur = SIMD2(p.x - 220, p.y - 16)
                run(0.05)
                run(0.25, to: SIMD2(p.x + 220, p.y - 16))
                run(0.25)
                shot("p20-poked", crops: [around()], full: false)
                run(0.8, to: SIMD2(p.x + 40, p.y - 120))
                run(2.5)
                shot("p21-payback", crops: [around()], full: false)
                curOn = false
                cur = SIMD2(-100, -100)
            }
            run(20)
            shot("p22-later", crops: [around()])
            for b in sim.balls { print(String(format: "  ball r=%.1f at %.0f,%.0f parent=%d child=%@", b.r, b.x, b.y, b.parent, b.hasChild ? "y" : "n")) }
        }

        if what == "ladder" || what == "all" || what == "stairs" {
            sim.cfg.people = 2
            sim.cfg.peopleLadders = true
            sim.people.summon()
            let c0 = cells()
            var doneAt: Float = -1
            var k = 0
            while sim.time < 520 {
                run(10)
                k += 1
                let L = sim.people.ladders.first
                if L == nil && k > 4 { print("no ladder project started"); break }
                let side = L.map { CGRect(x: CGFloat(Float(min($0.c0, $0.c1)) * cell) - 150, y: 150, width: 330, height: 650) } ?? around()
                if k % 3 == 0 || (L?.done ?? false) && doneAt < 0 {
                    shot(String(format: "l%02d-build", k), crops: [side], zoom: 2, full: k % 6 == 0)
                }
                if let L, L.done, doneAt < 0 { doneAt = sim.time }
                if doneAt >= 0 && sim.time - doneAt > 45 { break }
            }
            print(String(format: "ladder: done at t=%.0f; grid cells %d -> %d", doneAt, c0, cells()))
            if let L = sim.people.ladders.first {
                let side = CGRect(x: CGFloat(Float(min(L.c0, L.c1)) * cell) - 150, y: 150, width: 420, height: 650)
                shot("l80-on-top", crops: [side, CGRect(x: CGFloat(L.edgeX) - 120, y: CGFloat(L.ledgeY) - 90, width: 330, height: 130)], zoom: 2)
                // окно сдвинули: прилепленная лестница обваливается, кто на ней — падает
                let wi = L.win - 100
                if wi >= 0 && wi < wins.count {
                    let old = wins[wi]
                    wins[wi] = old.offsetBy(dx: 36, dy: 0)
                    for sg in sim.segs where sg.win == L.win {
                        sim.shiftPile(sg, cols: Int((36 / cell).rounded()), rows: 0, vx: 600, vy: 0)
                    }
                    setWindows()
                    run(0.25)
                    shot("l81-window-moved", crops: [side], zoom: 2, full: false)
                    run(1.2)
                    shot("l82-collapsed", crops: [side], zoom: 2, full: false)
                    run(30)
                    shot("l83-after", crops: [side], zoom: 2)
                }
            }
        }
        if what == "pit" {
            // Насыпь слежавшегося снега во всю середину пола, в ней яма глубже роста и пещера под сводом.
            // Гости приходят с краёв: на насыпь без ступенек не влезть, из ямы — тоже.
            let top = sim.H - Int(84 / cell)
            for c in Int(380 / cell)...Int(1020 / cell) {
                let x = Float(c) * cell
                let pit = x > 640 && x < 730
                let cave = x > 820 && x < 930
                for r in top..<sim.H {
                    let y = Float(r) * cell
                    if pit && r < sim.H - 2 { continue }
                    if cave && y > hPt - 46 && r < sim.H - 1 { continue }
                    sim.snow[r * sim.W + c] = 200
                    sim.hard[r * sim.W + c] = 230
                }
            }
            sim.gridDirty = true; sim.hardDirty = true
            sim.cfg.people = 2
            sim.cfg.peopleLadders = false
            sim.cfg.peopleStay = false
            sim.cfg.peopleEvents = false
            sim.cfg.aging = false
            sim.people.summon()
            _ = sim.people.debugSpawn(sim, x: 685, y: hPt - 20)          // один сразу в яме
            _ = sim.people.debugSpawn(sim, x: 700, y: hPt - 20, kid: true)
            _ = sim.people.debugSpawn(sim, x: 880, y: hPt - 20)          // один в пещере
            let view = CGRect(x: 330, y: 620, width: 740, height: 180)
            for k in 1...36 {
                run(5)
                if k % 2 == 0 || !sim.people.stepWorks.isEmpty && k < 14 {
                    shot(String(format: "pit%02d", k), crops: [view], zoom: 2, full: false)
                }
                if ProcessInfo.processInfo.environment["SUGROB_PEOPLE_DEBUG"] != nil {
                    for p in sim.people.folks { print(String(format: "   #%d %@ ph%d %@ x %.0f y %.0f carry %d block %.1f low %@ obj %d", p.id, "\(p.job)", p.phase, "\(p.mode)", p.x, p.y, p.carry, p.blockT, p.low ? "y" : "n", p.obj)) }
                }
                if sim.people.folks.isEmpty { sim.people.summon() }
            }
            print("step works: \(sim.people.stepWorks.count)")
            return 0
        }
        if what == "life" {
            // Долгая спокойная жизнь со всем включённым: гости, лестницы, дома, происшествия, бураны.
            let secs = args.count > 3 ? Float(args[3]) ?? 1500 : 1500
            sim.cfg.people = 3
            sim.cfg.peopleLadders = true
            sim.cfg.peopleStay = true
            sim.cfg.peopleEvents = true
            sim.cfg.storms = true
            sim.people.summon()
            var worst = 0.0
            var maxFolks = 0
            var nextStorm: Float = 200
            var k = 0
            while sim.time < secs {
                if sim.time > nextStorm { sim.wind.startStorm(); nextStorm += 260 }
                let t1 = CACurrentMediaTime()
                sim.setCursor(x: -100, y: -100, dt: dt, on: false)
                sim.step(dt)
                worst = max(worst, (CACurrentMediaTime() - t1) * 1000)
                maxFolks = max(maxFolks, sim.people.folks.count)
                for p in sim.people.folks where !p.x.isFinite || !p.y.isFinite || p.y < -200 || p.y > hPt + 200 {
                    print("BAD person at \(p.x),\(p.y) job \(p.job) mode \(p.mode) t=\(sim.time)")
                    return 1
                }
                if Int(sim.time / 150) > k {
                    k = Int(sim.time / 150)
                    shot(String(format: "life%02d", k), crops: [around()], zoom: 2, full: true)
                }
            }
            print(String(format: "life cell=%.0f unit=%.0f: %.0f s, worst step %.2f ms, max people %d, parts %d, balls %d", cell, unit, sim.time, worst, maxFolks, sim.parts.count, sim.balls.count))
            return 0
        }
        if what == "storm" {
            // Буран: компания на полу и готовая лестница. Смотрим, как прячутся, как треплет лестницу.
            sim.cfg.people = 2
            sim.cfg.peopleLadders = true
            sim.cfg.peopleStay = false
            sim.cfg.peopleEvents = false
            sim.people.summon()
            while sim.time < 400 && !(sim.people.ladders.first?.done ?? false) { run(5) }
            run(12)
            let lad = sim.people.ladders.first
            let view = lad.map { CGRect(x: CGFloat(Float($0.c0) * cell) - 420, y: 150, width: 640, height: 650) } ?? CGRect(x: 300, y: 150, width: 800, height: 650)
            func cellsOf() -> Int { sim.people.ladders.first.map { $0.rows.reduce(0) { $0 + $1.nonzeroBitCount } } ?? 0 }
            print("ladder cells before storm: \(cellsOf())")
            shot("s0-before", crops: [view], zoom: 2)
            sim.wind.startStorm(strength: 1, dir: 1, seconds: 70)
            for k in 1...9 {
                run(8)
                shot(String(format: "s%d-storm", k), crops: [view, around()], zoom: 2, full: k == 4)
                print(String(format: "   storm %.2f wind %.0f ladder cells %d", sim.wind.storm, sim.windNow, cellsOf()))
            }
            run(30)
            shot("s99-after", crops: [view], zoom: 2)
            print("ladder cells after: \(cellsOf())")
            return 0
        }
        if what == "tier" {
            sim.cfg.people = 2
            sim.cfg.peopleLadders = true
            sim.cfg.peopleStay = false
            sim.cfg.peopleEvents = false
            sim.people.summon()
            var allDone: Float = -1
            var k = 0
            while sim.time < 900 {
                run(15)
                k += 1
                if k % 2 == 0 { shot(String(format: "t%02d", k), crops: [CGRect(x: 180, y: 120, width: 760, height: 680)], zoom: 2, full: false) }
                if ProcessInfo.processInfo.environment["SUGROB_PEOPLE_DEBUG"] != nil {
                    for p in sim.people.folks { print(String(format: "   #%d %@ ph%d mode %@ stand %d x %.0f y %.0f carry %d ladder %d t %.1f tries %d", p.id, "\(p.job)", p.phase, "\(p.mode)", p.stand, p.x, p.y, p.carry, p.ladder, p.t, p.tries)) }
                }
                let ls = sim.people.ladders
                if ls.count >= 2 && ls.allSatisfy({ $0.done }) && allDone < 0 { allDone = sim.time }
                if allDone >= 0 && sim.time - allDone > 40 { break }
                if sim.people.folks.isEmpty && k > 6 { sim.people.summon() }
            }
            for L in sim.people.ladders { print("ladder #\(L.id): to win \(L.win) from \(L.base == -2 ? "floor" : "win \(L.base)"), rows \(L.front)/\(L.rows.count), done \(L.done)") }
            print(String(format: "tier: both ladders done at t=%.0f; on top of the upper window: %d", allDone, sim.people.folks.filter { $0.stand == 101 }.count))
            shot("t99-end", crops: [CGRect(x: 180, y: 120, width: 760, height: 680)], zoom: 2)
            return allDone >= 0 ? 0 : 1
        }
        if what == "fuzz" {
            // Стресс: человечки приходят часто и строят, а вокруг — быстрый случайный курсор, броски шаров,
            // окна то и дело двигают, снег иногда сгребают лопатой. Ищем падения и долгие шаги.
            var rng = Rng(seed: UInt64(cell * 1000) &+ UInt64(unit) &+ 77)
            let secs = args.count > 3 ? Float(args[3]) ?? 600 : 600
            sim.cfg.people = 3
            sim.cfg.agingRate = 6
            sim.people.summon()
            curOn = true
            var target = SIMD2<Float>(700, 700)
            var speed: Float = 300
            var holding = false
            var worst = 0.0
            var maxFolks = 0, laddersSeen = 0, doneSeen = 0, lastLadders = 0
            while sim.time < secs {
                let d = target - cur
                let dist = (d.x * d.x + d.y * d.y).squareRoot()
                if dist < 4 || rng.f() < 0.004 {
                    let folks = sim.people.folks
                    if !folks.isEmpty, rng.f() < 0.6 {
                        let p = folks[Int(rng.next() % UInt64(folks.count))]
                        target = SIMD2(p.x + rng.range(-60, 60), p.y - rng.range(0, 40))      // целиться в человечков
                    } else if let L = sim.people.ladders.first, rng.f() < 0.4 {
                        target = SIMD2(Float(L.c0) * cell + rng.range(-10, 30), rng.range(200, 780))  // и в лестницу
                    } else {
                        target = SIMD2(rng.range(0, wPt), rng.range(100, hPt))
                    }
                    speed = [60, 300, 900, 2500][Int(rng.next() % 4)]
                } else {
                    cur += d / dist * min(dist, speed * dt)
                }
                sim.setCursor(x: cur.x, y: cur.y, dt: dt, on: true)
                if !holding && rng.f() < 0.006 { sim.handsMode = true; sim.grabBegin(); holding = sim.heldId != -1 }
                else if holding && rng.f() < 0.03 { sim.grabEnd(); sim.handsMode = false; holding = false }
                if rng.f() < 0.0006 {           // окно двигают
                    let k = Int(rng.next() % UInt64(wins.count))
                    let dx = CGFloat(rng.range(-50, 50)), dy = CGFloat(rng.range(-30, 30))
                    let old = wins[k]
                    wins[k] = old.offsetBy(dx: dx, dy: dy)
                    func c(_ v: CGFloat) -> Int { Int((Float(v) / cell).rounded()) }
                    for sg in sim.segs where sg.win == k + 100 {
                        sim.shiftPile(sg, cols: c(wins[k].minX) - c(old.minX), rows: c(wins[k].minY) - c(old.minY), vx: 400, vy: 0)
                    }
                    setWindows()
                }
                if rng.f() < 0.00008 { sim.clearAll(); sim.forceFill = true; sim.fillSurfaces(); sim.forceFill = false }
                if rng.f() < 0.0001 { sim.cfg.people = sim.cfg.people == 0 ? 3 : 0 }
                if rng.f() < 0.0003 { sim.people.summon() }
                let t1 = CACurrentMediaTime()
                sim.step(dt)
                let ms = (CACurrentMediaTime() - t1) * 1000
                if ms > 12 { print(String(format: "slow step %.1f ms at t=%.1f: parts %d, spawns %d, %@", ms, sim.time, sim.parts.count, sim.statSpawns, sim.people.summary)) }
                worst = max(worst, ms)
                maxFolks = max(maxFolks, sim.people.folks.count)
                if sim.people.ladders.count > lastLadders { laddersSeen += 1 }
                lastLadders = sim.people.ladders.count
                if sim.people.ladders.contains(where: { $0.done }) { doneSeen += 1 }
                for p in sim.people.folks where !p.x.isFinite || !p.y.isFinite || p.y < -200 || p.y > hPt + 200 {
                    print("BAD person at \(p.x),\(p.y) job \(p.job) mode \(p.mode) t=\(sim.time)")
                    return 1
                }
            }
            print(String(format: "people fuzz cell=%.0f unit=%.0f: %.0f s, worst step %.2f ms, max people %d, ladders started %d, frames with a finished ladder %d, parts %d, balls %d",
                         cell, unit, sim.time, worst, maxFolks, laddersSeen, doneSeen, sim.parts.count, sim.balls.count))
            print(sim.people.summary)
            shot("f-end")
            return worst < 30 ? 0 : 1
        }
        // все расходятся
        sim.cfg.people = 0
        run(40)
        shot("z-gone")
        print(String(format: "people test: %.0f s simulated in %.1f s", sim.time, CACurrentMediaTime() - t0))
        return 0
    }
}
