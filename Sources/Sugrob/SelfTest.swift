import AppKit
import Metal
import ImageIO
import UniformTypeIdentifiers

/// Самотест без экрана: прогоняет сценарий (снегопад, смахивание, шары, бросок)
/// и сохраняет кадры в PNG поверх нарисованного «рабочего стола».
enum SelfTest {
    static func run(outDir: String) -> Int32 {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = Renderer(device: device, pixelFormat: .bgra8Unorm),
              let queue = device.makeCommandQueue() else {
            print("no metal"); return 1
        }
        let wPt: Float = 1200, hPt: Float = 750, scale: Float = 2
        let sim = Sim(widthPt: wPt, heightPt: hPt, cell: 3, seed: 12345)
        sim.cfg.flakeRate = 30
        sim.cfg.intensity = 3
        sim.cfg.openOnly = true
        var wins: [CGRect] = [CGRect(x: 100, y: 200, width: 400, height: 300),
                              CGRect(x: 620, y: 300, width: 380, height: 260)]
        var ledges = wins.enumerated().map {
            Ledge(y: Float($1.minY), x0: Float($1.minX + 5), x1: Float($1.maxX - 5), kind: 1, win: $0, ox: Float($1.minX))
        }
        ledges.append(Ledge(y: 690, x0: 450, x1: 750, kind: 2, win: -1))
        let behind = CGRect(x: 800, y: 270, width: 260, height: 200)
        func boxes() -> [WinBox] {
            (wins + [behind]).enumerated().map {
                WinBox(x0: Float($1.minX), x1: Float($1.maxX), y0: Float($1.minY), y1: Float($1.maxY), win: $0)
            }
        }
        sim.setLedges(ledges, windows: boxes())
        sim.prefill()

        let pw = Int(wPt * scale), ph = Int(hPt * scale)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: pw, height: ph, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        guard let target = device.makeTexture(descriptor: td) else { return 1 }

        func shot(_ name: String, crop: CGRect? = nil, hide: [CGRect] = []) {
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = target
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].storeAction = .store
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            let cmd = queue.makeCommandBuffer()!
            renderer.encode(sim: sim, cmd: cmd, rpd: rpd, scale: scale, hide: hide)
            cmd.commit()
            cmd.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: pw * ph * 4)
            target.getBytes(&px, bytesPerRow: pw * 4, from: MTLRegionMake2D(0, 0, pw, ph), mipmapLevel: 0)
            let cs = CGColorSpaceCreateDeviceRGB()
            let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            let snowImg = px.withUnsafeMutableBytes { raw -> CGImage? in
                CGContext(data: raw.baseAddress, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4,
                          space: cs, bitmapInfo: info)?.makeImage()
            }
            guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4,
                                      space: cs, bitmapInfo: info), let snowImg else { return }
            // фон: ось Y у CG вверх, поэтому переворачиваем
            ctx.translateBy(x: 0, y: CGFloat(ph))
            ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
            ctx.setFillColor(CGColor(red: 0.07, green: 0.10, blue: 0.30, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(wPt), height: CGFloat(hPt)))
            ctx.setFillColor(CGColor(red: 0.45, green: 0.2, blue: 0.3, alpha: 1))
            ctx.addPath(CGPath(roundedRect: behind, cornerWidth: 10, cornerHeight: 10, transform: nil))
            ctx.fillPath()
            for (i, w) in wins.enumerated() {
                ctx.setFillColor(i == 0 ? CGColor(red: 0.16, green: 0.20, blue: 0.46, alpha: 1)
                                        : CGColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1))
                ctx.addPath(CGPath(roundedRect: w, cornerWidth: 10, cornerHeight: 10, transform: nil))
                ctx.fillPath()
            }
            ctx.setFillColor(CGColor(red: 0.3, green: 0.33, blue: 0.5, alpha: 0.8))
            ctx.addPath(CGPath(roundedRect: CGRect(x: 450, y: 690, width: 300, height: 54), cornerWidth: 14, cornerHeight: 14, transform: nil))
            ctx.fillPath()
            ctx.scaleBy(x: 1 / CGFloat(scale), y: -1 / CGFloat(scale))
            ctx.translateBy(x: 0, y: -CGFloat(ph))
            ctx.draw(snowImg, in: CGRect(x: 0, y: 0, width: pw, height: ph))
            guard let full = ctx.makeImage() else { return }
            let s = CGFloat(scale)
            guard let out = crop.map({ full.cropping(to: CGRect(x: $0.minX * s, y: $0.minY * s, width: $0.width * s, height: $0.height * s)) }) ?? full else { return }
            let url = URL(fileURLWithPath: outDir).appendingPathComponent(name + ".png")
            if let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dst, out, nil)
                CGImageDestinationFinalize(dst)
            }
            let cells = sim.snow.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
            print("\(name): cells=\(cells) parts=\(sim.parts.count) balls=\(sim.balls.count)")
        }

        let dt: Float = 1.0 / 60
        var cur = SIMD2<Float>(-100, -100)
        func run(_ seconds: Float, to target: SIMD2<Float>? = nil, on: Bool = true) {
            let n = max(1, Int(seconds / dt))
            let from = cur
            for i in 1...n {
                if let target { cur = from + (target - from) * (Float(i) / Float(n)) }
                sim.setCursor(x: cur.x, y: cur.y, dt: dt, on: on)
                sim.step(dt)
            }
        }

        // 1. снегопад
        let t0 = CACurrentMediaTime()
        run(45, on: false)
        let per = (CACurrentMediaTime() - t0) / (45 * 60) * 1000
        print(String(format: "step: %.3f ms (%d particles)", per, sim.parts.count))
        shot("1-snowfall")

        // 1v. видео: в правом окне идёт видео — снег поверх него не рисуется, шапка на нём остаётся;
        //     потом видео в заднем (тёмно-красном) окне — закрыта только та его часть, что видна из-за передних
        do {
            func info(_ i: Int, _ r: CGRect, video: Bool) -> WinInfo { WinInfo(id: i, video: video, rect: r) }
            let frame = CGRect(x: 0, y: 0, width: CGFloat(wPt), height: CGFloat(hPt))
            let dockRect = CGRect(x: 450, y: 690, width: 300, height: 60)
            let front = videoZones([info(0, wins[0], video: false), info(1, wins[1], video: true), info(2, behind, video: false)],
                                   capped: [0, 1], dock: dockRect, frame: frame, dip: 8)
            shot("1v-video-front", hide: front)
            let back = videoZones([info(0, wins[0], video: false), info(1, wins[1], video: false), info(2, behind, video: true)],
                                  capped: [0, 1], dock: dockRect, frame: frame, dip: 8)
            shot("1w-video-behind", hide: back)
            let pip = videoZones([info(0, wins[0], video: false)], floating: [CGRect(x: 880, y: 560, width: 300, height: 170)],
                                 capped: [0], frame: frame, dip: 8)
            shot("1x-video-floating", hide: pip)
            func area(_ rs: [CGRect]) -> Int { Int(rs.reduce(0) { $0 + $1.width * $1.height }) }
            // зона окна с видео не трогает шапку над ним; зона заднего окна не заходит на передние и на их шапки
            let capZone = CGRect(x: wins[1].minX - 4, y: wins[1].minY - 64, width: wins[1].width + 8, height: wins[1].height + 64)
            let okFront = front.allSatisfy { $0.minY >= wins[1].minY + 8 && wins[1].contains($0) }
            let okBack = back.allSatisfy { !$0.intersects(capZone) && behind.contains($0) } && area(back) > 0
            let okNone = videoZones([info(0, wins[0], video: false)], capped: [0], frame: frame, dip: 8).isEmpty
            print("video zones: front \(front.count) rects \(area(front)) pt², behind \(back.count) rects \(area(back)) pt², floating \(pip.count); checks: \(okFront && okBack && okNone ? "ok" : "FAILED")")
            if !(okFront && okBack && okNone) { return 1 }
        }

        // 1i. значки рабочего стола: маленькие опоры (kind 3) со своей, небольшой высотой шапки
        do {
            let s2 = Sim(widthPt: 420, heightPt: 220, cell: 3, seed: 77)
            s2.cfg.flakeRate = 30
            s2.cfg.intensity = 3
            s2.cfg.floor = false
            let roofs: [(x0: Float, x1: Float, y: Float)] = [(40, 98, 80), (160, 208, 76), (280, 312, 90)]   // папка, документ, мелкий значок
            s2.setLedges(roofs.enumerated().map {
                Ledge(y: $1.y, x0: $1.x0 + 1, x1: $1.x1 - 1, kind: 3, win: 0x4000_0000 + $0, ox: $1.x0, wr: $1.x1, cap: 10)
            })
            for _ in 0..<(60 * 60) { s2.step(1.0 / 60) }
            var report: [String] = []
            var ok = true
            for r in roofs {
                let row = Int((r.y / 3).rounded())
                let cols = Int((r.x0 / 3).rounded(.up))...Int((r.x1 / 3).rounded(.down)) - 1
                let hs = cols.map { s2.snowHeight($0, row) }
                let peak = hs.max() ?? 0
                report.append("\(peak * 3) pt")
                // шапка есть, но не выше полутора пределов (10 pt) с запасом на одну ячейку
                if peak < 1 || Float(peak) * 3 > 10 * 1.5 + 3 { ok = false }
            }
            print("icon ledges: peak caps \(report.joined(separator: ", ")) (limit 10 pt); checks: \(ok ? "ok" : "FAILED")")
            if !ok { return 1 }
        }

        // 1j. значки и перелистывание столов: стол уехал вбок вместе со слоем снега и окнами (их координаты
        //     сдвигает система), а Finder называет значки по-прежнему — опора значка в слое сдвинуться не должна
        do {
            _ = NSApplication.shared
            if let screen = NSScreen.screens.first,
               let o = Overlay(screen: screen, device: device, cell: 3, cfg: SimConfig(), spaceId: 1) {
                o.rules.icons = true
                let f = screen.frame
                let icon = WinInfo(id: 0x4000_0001, icon: true, iconSize: 64, rect: CGRect(x: 300, y: 400, width: 58, height: 53))
                let win = WinInfo(id: 77, rect: CGRect(x: 600, y: 300, width: 400, height: 300))
                func at(_ id: Int) -> Float? { o.sim.segs.first { $0.win == id }?.x0 }
                o.updateWindows([win, icon])
                let before = (at(icon.id), at(win.id))
                var moved = win
                moved.rect = win.rect.offsetBy(dx: -500, dy: 0)
                o.updateWindows([moved, icon], own: [o.panel.windowNumber: CGRect(x: -500, y: 0, width: f.width, height: f.height)])
                let after = (at(icon.id), at(win.id))
                let ok = before.0 != nil && before.1 != nil && before.0 == after.0 && before.1 == after.1
                print("icons while swiping spaces: icon ledge \(before.0 ?? -1) -> \(after.0 ?? -1), window ledge \(before.1 ?? -1) -> \(after.1 ?? -1); checks: \(ok ? "ok" : "FAILED")")
                o.close()
                if !ok { return 1 }
            } else {
                print("icons while swiping spaces: no screen, skipped")
            }
        }

        // 0. скруглённые углы и слежавшийся снег: левое окно получает радиус, снег старится ускоренно
        do {
            var l = wins.enumerated().map {
                Ledge(y: Float($1.minY), x0: Float($1.minX) + ($0 == 0 ? 8 : 5), x1: Float($1.maxX) - ($0 == 0 ? 8 : 5), kind: 1, win: $0,
                      ox: Float($1.minX), wr: Float($1.maxX), r: $0 == 0 ? 26 : 0)
            }
            l.append(Ledge(y: 690, x0: 450, x1: 750, kind: 2, win: -1))
            sim.cfg.openOnly = false
            sim.setLedges(l, windows: boxes())
            run(25, on: false)
            shot("0a-rounded-corner")
            sim.cfg.agingRate = 40
            run(4, on: false)           // ≈ 2,5 минуты: снег под слоем уже плотный
            shot("0b-dense")
            run(9, on: false)           // ≈ 8,5 минуты: наст
            shot("0c-frozen")
            var fresh = 0, dense = 0, frozen = 0
            for i in sim.snow.indices where sim.snow[i] != 0 {
                if sim.hard[i] >= Sim.frozen { frozen += 1 } else if sim.hard[i] >= Sim.dense { dense += 1 } else { fresh += 1 }
            }
            print("aged: fresh \(fresh), dense \(dense), frozen \(frozen)")
            // наст: медленный курсор его не берёт, резкий удар раскалывает
            let before = sim.snow.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
            sim.cfg.agingRate = 0; sim.cfg.intensity = 0
            cur = SIMD2(620, 292); run(0.05); run(1.2, to: SIMD2(900, 292))
            let afterSlow = sim.snow.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
            cur = SIMD2(620, 292); run(0.05); run(0.12, to: SIMD2(900, 292)); run(0.3)
            let afterFast = sim.snow.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
            print("frozen crust: cells \(before); after slow pass \(afterSlow); after hard strike \(afterFast)")
            shot("0d-crust-struck")
            cur = SIMD2(-100, -100)
            sim.clearAll(); sim.resetHardness()
            sim.cfg.agingRate = 1; sim.cfg.intensity = 3; sim.cfg.openOnly = true
            sim.setLedges(ledges, windows: boxes())
            run(45, on: false)
        }

        // 1а. медленно столкнуть всю шапку с правого края первого окна; снег не доливается
        do {
            func mass() -> (cells: Int, chunks: Int) {
                (sim.snow.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }, sim.parts.reduce(0) { $0 + ($1.kind == 1 ? 1 : 0) })
            }
            sim.cfg.intensity = 0
            let m0 = mass()
            cur = SIMD2(80, 194)
            run(0.05)
            run(2.2, to: SIMD2(470, 194))
            shot("1a-push-near-edge")
            run(0.25, to: SIMD2(515, 194))
            shot("1b-push-over-edge")
            run(0.2, to: SIMD2(550, 194))
            shot("1c-falling")
            cur = SIMD2(-100, -100)
            run(0.25, on: false)
            shot("1d-falling-later")
            run(2, on: false)
            let m1 = mass()
            print("push off edge: cells+chunks \(m0.cells + m0.chunks) -> \(m1.cells + m1.chunks)")
            sim.cfg.intensity = 3
            run(20, on: false)
        }

        sim.cfg.intensity = 1
        cur = SIMD2(90, 190)
        run(0.05)
        run(0.22, to: SIMD2(330, 192))
        shot("2-sweep-mid")
        run(0.2, to: SIMD2(520, 180))
        run(0.25)
        shot("3-sweep-after")
        run(2.0, on: false)
        shot("4-settled")

        // 2а. медленно вести курсор сквозь сугроб на втором окне: перед ним должен идти вал
        cur = SIMD2(600, 288)
        run(0.05)
        run(0.9, to: SIMD2(760, 288))
        shot("4a-plough-mid")
        run(0.9, to: SIMD2(920, 288))
        shot("4b-plough-far")
        cur = SIMD2(-100, -100)
        run(1.0, on: false)

        // 2б. перетащить второе окно: сугроб едет вместе с ним
        func dragWindow(_ k: Int, by d: SIMD2<Float>, seconds: Float) {
            let polls = max(1, Int(seconds * 30))
            for _ in 0..<polls {
                let old = wins[k]
                wins[k] = old.offsetBy(dx: CGFloat(d.x) / CGFloat(polls), dy: CGFloat(d.y) / CGFloat(polls))
                func cellOf(_ v: CGFloat) -> Int { Int((Float(v) / sim.cell).rounded()) }
                let cols = cellOf(wins[k].minX) - cellOf(old.minX), rows = cellOf(wins[k].minY) - cellOf(old.minY)
                for sg in sim.segs where sg.win == k {
                    sim.shiftPile(sg, cols: cols, rows: rows, vx: d.x / seconds, vy: d.y / seconds)
                }
                var l = wins.enumerated().map {
                    Ledge(y: Float($1.minY), x0: Float($1.minX + 5), x1: Float($1.maxX - 5), kind: 1, win: $0, ox: Float($1.minX))
                }
                l.append(Ledge(y: 690, x0: 450, x1: 750, kind: 2, win: -1))
                sim.setLedges(l, windows: boxes())
                run(1.0 / 30, on: false)
            }
        }
        dragWindow(1, by: SIMD2(70, 40), seconds: 0.5)
        shot("4c-window-dragged")
        dragWindow(1, by: SIMD2(-70, -40), seconds: 0.5)
        run(0.5, on: false)
        shot("4d-window-back")

        // 2в. окно уходит на другой рабочий стол и возвращается: сугроб должен уйти и вернуться с ним
        let before = sim.snow.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
        let stash = sim.extractPile(win: 1)
        sim.setLedges(sim.segs.filter { $0.win != 1 })
        run(1.0, on: false)
        shot("4e-window-away")
        var back = wins.enumerated().map {
            Ledge(y: Float($1.minY), x0: Float($1.minX + 5), x1: Float($1.maxX - 5), kind: 1, win: $0, ox: Float($1.minX))
        }
        back.append(Ledge(y: 690, x0: 450, x1: 750, kind: 2, win: -1))
        sim.setLedges(back, windows: boxes())
        sim.insertPile(stash, ox: Float(wins[1].minX), y: Float(wins[1].minY))
        run(0.5, on: false)
        let after = sim.snow.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
        print("stash: \(stash.cells.count) cells; grid before \(before), after return \(after)")
        shot("4f-window-returned")

        // 3. скатать шар по земле, поставить на окно, сверху второй — снеговик
        var rolls = 0
        func roll(from a: SIMD2<Float>, to b: SIMD2<Float>, place: SIMD2<Float>) {
            cur = a
            sim.handsMode = true
            run(0.1)
            sim.grabBegin()
            run(1.6, to: b)
            rolls += 1
            if rolls == 1 { shot("5a-rolling") }
            run(0.8, to: place)
            run(0.25)
            sim.grabEnd()
            sim.handsMode = false
            cur = SIMD2(-100, -100)
            run(1.2, on: false)
        }
        roll(from: SIMD2(60, 742), to: SIMD2(420, 742), place: SIMD2(800, 215))
        shot("5-ball-on-window")
        roll(from: SIMD2(1150, 742), to: SIMD2(1000, 742), place: SIMD2(802, 190))
        roll(from: SIMD2(1150, 742), to: SIMD2(1090, 742), place: SIMD2(801, 140))
        shot("6-snowman")
        for b in sim.balls { print(String(format: "  ball r=%.1f at %.0f,%.0f parent=%d", b.r, b.x, b.y, b.parent)) }

        // 4. бросок снежка в сугроб на первом окне
        cur = SIMD2(760, 640)
        sim.handsMode = true
        run(0.1)
        sim.grabBegin()
        run(0.12, to: SIMD2(560, 440))
        sim.grabEnd()
        sim.handsMode = false
        run(0.08, on: false)
        shot("7-throw-flight")
        run(0.25, on: false)
        shot("8-throw-impact")
        run(2.5, on: false)
        shot("9-final")

        // 5. другой рабочий стол: снег убирается целиком и возвращается таким же
        func count() -> Int { sim.snow.reduce(0) { $0 + ($1 != 0 ? 1 : 0) } }
        let saved = sim.saveState()
        let c0 = count(), b0 = sim.balls.count
        sim.loadState(nil)
        run(0.5, on: false)
        let c1 = count(), b1 = sim.balls.count
        sim.loadState(saved)
        let c2 = count(), b2 = sim.balls.count
        print("spaces: cells \(c0) -> \(c1) -> \(c2); balls \(b0) -> \(b1) -> \(b2); ok=\(c0 == c2 && b0 == b2 && b1 == 0)")
        // 5а. шар на склоне: насыпаем на низ экрана горку и ставим на её склон шар
        do {
            sim.clearAll()
            sim.cfg.intensity = 0; sim.cfg.flakeRate = 0; sim.cfg.aging = false
            let c0 = Int(60 / sim.cell), c1 = Int(360 / sim.cell)
            for c in c0...c1 {                       // высота растёт слева направо до 120 pt
                let hgt = (c - c0) * 40 / (c1 - c0)
                for k in 0..<hgt { sim.snow[(sim.H - 1 - k) * sim.W + c] = 200 }
            }
            sim.gridDirty = true
            cur = SIMD2(300, 520)
            sim.handsMode = true
            run(0.1)
            sim.grabBegin()
            run(0.3)
            sim.grabEnd()
            sim.handsMode = false
            cur = SIMD2(-100, -100)
            run(0.6, on: false)
            let x0 = sim.balls.first?.x ?? -1, r0 = sim.balls.first?.r ?? -1
            shot("5b-ball-on-slope")
            run(2.5, on: false)
            let x1 = sim.balls.first?.x ?? -1, r1 = sim.balls.first?.r ?? -1
            shot("5c-ball-rolled")
            print(String(format: "ball on slope: x %.0f -> %.0f, r %.1f -> %.1f (rolled downhill: %@)", x0, x1, r0, r1, x1 < x0 - 30 ? "yes" : "NO"))
            sim.cfg.flakeRate = 30; sim.cfg.aging = true
        }

        // 5г. тяжёлый шар: продавливает рыхлый снег и гонит перед собой вал
        do {
            sim.clearAll()
            sim.cfg.intensity = 0; sim.cfg.flakeRate = 0; sim.cfg.aging = false
            let c0 = Int(300 / sim.cell), c1 = Int(1000 / sim.cell), depth = 12
            for c in c0...c1 { for k in 0..<depth { sim.snow[(sim.H - 1 - k) * sim.W + c] = 180; sim.hard[(sim.H - 1 - k) * sim.W + c] = 0 } }
            sim.gridDirty = true; sim.hardDirty = true
            let surface = Float(sim.H - depth) * sim.cell
            sim.balls.append(Ball(id: 900, x: 420, y: 560, r: 28, seed: 3))
            sim.balls.append(Ball(id: 901, x: 900, y: 600, r: 7, seed: 5))
            run(1.5, on: false)
            func ball(_ id: Int32) -> Ball { sim.balls.first { $0.id == id }! }
            let col = Int(420 / sim.cell)
            var top = sim.H - 1; while top >= 0 && sim.snow[top * sim.W + col] != 0 { top -= 1 }
            print(String(format: "heavy ball (r 28): sunk %.1f pt into snow, snow under it hardness %d; light ball (r 7): sunk %.1f pt",
                         ball(900).y + ball(900).r - surface, sim.hard[(top + 1) * sim.W + col], ball(901).y + ball(901).r - surface))
            shot("5d-heavy-sunk")
            let cellsBefore = sim.snow.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
            for i in sim.balls.indices where sim.balls[i].id == 900 { sim.balls[i].vx = 420 }
            run(0.5, on: false)
            shot("5e-heavy-ploughing")
            run(2.0, on: false)
            var maxH = 0
            for c in Int(ball(900).x / sim.cell)...min(sim.W - 1, Int((ball(900).x + 90) / sim.cell)) {
                var y = sim.H - 1, h = 0
                while y >= 0 && sim.snow[y * sim.W + c] != 0 { h += 1; y -= 1 }
                maxH = max(maxH, h)
            }
            print(String(format: "pushed with 420 pt/s: stopped at x %.0f (from 420), r %.1f; snow ahead up to %d cells (was %d); cells %d -> %d",
                         ball(900).x, ball(900).r, maxH, depth, cellsBefore, sim.snow.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }))
            shot("5f-heavy-stopped")

            // 5д. шар стоит долго: примерзает, его припорашивает, потом заносит по бокам
            sim.cfg.aging = true; sim.cfg.agingRate = 30; sim.cfg.intensity = 1; sim.cfg.flakeRate = 30
            run(1.6, on: false)
            print(String(format: "after ~45 s at rest: cover %.2f, frozen in place: %@", ball(900).cover, ball(900).rest > Sim.stuckAfter ? "yes" : "no"))
            shot("5g-ball-dusted")

            // примёрзший шар толкают: низ остаётся на месте настом, шар выходит сколотым
            let stumpBefore = sim.hard.reduce(0) { $0 + ($1 >= Sim.frozen ? 1 : 0) }
            sim.cfg.agingRate = 0
            cur = SIMD2(ball(900).x - 70, ball(900).y)
            run(0.05)
            run(0.14, to: SIMD2(ball(900).x + 20, ball(900).y))
            cur = SIMD2(-100, -100)
            run(0.5, on: false)
            let stumpAfter = sim.hard.reduce(0) { $0 + ($1 >= Sim.frozen ? 1 : 0) }
            print(String(format: "shoved while frozen: chip depth %.2f of radius, %d frozen voxels left behind", ball(900).cutD, stumpAfter - stumpBefore))
            shot("5h-ball-chipped")

            // дальше стоит ещё долго: заносит целиком, шар уходит в сугроб
            sim.cfg.agingRate = 30
            run(4.0, on: false)
            print(String(format: "after ~2 more minutes: cover %.2f, buried %.2f, squash %.2f", ball(900).cover, ball(900).bury, ball(900).squash))
            shot("5i-ball-drifted-over")
            let before = sim.snow.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
            run(7.0, on: false)
            print("after ~5 more minutes: balls left \(sim.balls.count), cells \(before) -> \(sim.snow.reduce(0) { $0 + ($1 != 0 ? 1 : 0) })")
            shot("5j-ball-became-drift")
            sim.clearAll()
            sim.cfg.agingRate = 1; sim.cfg.flakeRate = 30
        }

        // 5е. снеговик под снегом: снег настоящий — ложится на шары и ветки, липнет, заносит.
        //     Обозначения видны, пока их не закрыло; смахнул снег — они снова на месте.
        do {
            sim.clearAll()
            sim.cfg.intensity = 1; sim.cfg.flakeRate = 30; sim.cfg.aging = true; sim.cfg.agingRate = 1
            let base = Float(sim.H) * sim.cell
            func build(_ x: Float, _ id: Int32) {
                var a = Ball(id: id, x: x, y: base - 30, r: 30, seed: 1); a.grounded = true
                var b = Ball(id: id + 1, x: x, y: base - 30 - 51, r: 22, seed: 2); b.parent = id; b.offY = -51
                var c = Ball(id: id + 2, x: x, y: base - 30 - 51 - 36, r: 15, seed: 3); c.parent = id + 1; c.offY = -36
                sim.balls += [a, b, c]
            }
            func onBalls() -> Int {
                var n = 0
                for i in sim.mask.indices where sim.mask[i] != 0 && sim.snow[i] != 0 { n += 1 }
                return n
            }
            build(250, 910)
            run(1.0, on: false)
            print("snowman marks right after building: \(sim.balls.map { $0.decor }) (0 none, 1 face, 2 buttons and sticks)")
            shot("5k-snowman-fresh")
            sim.cfg.intensity = 12                  // ускоренный снегопад: ~12 секунд за секунду
            run(5, on: false)
            print("after ~1 min of snowfall: \(onBalls()) voxels of snow stuck on the balls, balls \(sim.balls.count)")
            shot("5l-snowman-1min")
            run(10, on: false)
            print("after ~3 min: \(onBalls()) voxels stuck, balls \(sim.balls.count), marks \(sim.balls.map { $0.decor })")
            shot("5m-snowman-3min")
            // смахнуть снег с головы курсором: лицо снова видно
            sim.cfg.intensity = 0
            let stuck = onBalls()
            cur = SIMD2(205, base - 117); run(0.05); run(0.5, to: SIMD2(295, base - 117)); run(0.4, to: SIMD2(205, base - 125))
            cur = SIMD2(-100, -100); run(0.6, on: false)
            print("brushed the head with the cursor: stuck voxels \(stuck) -> \(onBalls()), balls \(sim.balls.count)")
            shot("5n-snowman-brushed")
            sim.cfg.intensity = 12
            run(30, on: false)
            print("after ~9 min: balls left \(sim.balls.count) (buried balls become part of the drift)")
            shot("5o-snowman-buried")

            // свежий снеговик толкают: шары слетают, но остаются собой
            sim.clearAll()
            sim.cfg.intensity = 0; sim.cfg.flakeRate = 0
            build(700, 920)
            run(0.6, on: false)
            cur = SIMD2(620, base - 85); run(0.05); run(0.1, to: SIMD2(700, base - 85))
            shot("5p-snowman-hit")
            cur = SIMD2(-100, -100)
            run(1.5, on: false)
            let left = sim.balls.sorted { $0.id < $1.id }
            print("fresh snowman shoved in the middle: \(left.map { "id \($0.id): marks \($0.decor), on another ball: \($0.parent != -1)" })")
            shot("5q-snowman-parts")

            // сколотый шар катят по снегу: скол зарастает
            sim.clearAll()
            let c0 = Int(100 / sim.cell), c1 = Int(1100 / sim.cell)
            for c in c0...c1 { for k in 0..<8 { sim.snow[(sim.H - 1 - k) * sim.W + c] = 180; sim.hard[(sim.H - 1 - k) * sim.W + c] = 0 } }
            sim.gridDirty = true
            var chipped = Ball(id: 930, x: 200, y: base - 24 - 20, r: 20, seed: 4)
            chipped.cutD = 0.4; chipped.cutA = 0.6; chipped.vx = 330
            sim.balls = [chipped]
            run(0.4, on: false)
            let mid = sim.balls.first?.cutD ?? -1
            shot("5r-chipped-rolling")
            run(2.5, on: false)
            print(String(format: "chipped ball rolled over snow: chip 0.40 -> %.2f -> %.2f of radius, r %.1f", mid, sim.balls.first?.cutD ?? -1, sim.balls.first?.r ?? -1))
            shot("5s-chip-healed")
            sim.clearAll()
            sim.cfg.agingRate = 1; sim.cfg.intensity = 1; sim.cfg.flakeRate = 30
        }

        // 7. долго лежащий снег (время ускорено в 30 раз): оседает под своим весом, у основания
        //    испаряется, наст остаётся плитой над пустотами, а пустоты растут, пока плита не провалится
        do {
            sim.clearAll()
            sim.resetHardness()
            sim.cfg.flakeRate = 0; sim.cfg.aging = true; sim.cfg.agingRate = 1
            sim.cfg.openOnly = false
            sim.cfg.intensity = 3
            sim.setLedges(ledges, windows: boxes())
            sim.forceFill = true; sim.fillSurfaces(); sim.forceFill = false
            run(0.3, on: false)
            sim.cfg.intensity = 0                 // не доливать: видно, как сугробы оседают
            func floorH() -> Float {
                var n = 0, cols = 0
                for x in Int(1080 / sim.cell)..<Int(1190 / sim.cell) {
                    cols += 1
                    for y in stride(from: sim.H - 1, through: sim.H - 40, by: -1) where sim.snow[y * sim.W + x] != 0 { n += 1 }
                }
                return Float(n) / Float(cols) * sim.cell
            }
            func stats(_ tag: String) {
                var cells = 0, dense = 0, frozen = 0, caves = 0
                for i in sim.snow.indices {
                    if sim.snow[i] != 0 {
                        cells += 1
                        if sim.hard[i] >= Sim.frozen { frozen += 1 } else if sim.hard[i] >= Sim.dense { dense += 1 }
                    }
                    if sim.cave[i] != 0 { caves += 1 }
                }
                // шероховатость поверхности на полу: сколько столбцов торчат над обоими соседями (зубцы)
                var hs: [Int] = []
                for x in 0..<sim.W {
                    var t = sim.H - 1
                    while t >= sim.H - 40 && (sim.snow[t * sim.W + x] != 0 || sim.cave[t * sim.W + x] != 0) { t -= 1 }
                    hs.append(sim.H - 1 - t)
                }
                var spikes = 0
                for x in 1..<(sim.W - 1) where hs[x] > hs[x - 1] && hs[x] > hs[x + 1] { spikes += 1 }
                print(String(format: "%@: cells %d (dense %d, frozen %d), hollow cells %d; settled %d, hollowed %d, collapsed %d; floor snow %.1f pt; spikes %d",
                             tag, cells, dense, frozen, caves, sim.statSettled, sim.statHollowed, sim.statCollapsed, floorH(), spikes))
            }
            let floorCrop = CGRect(x: 0, y: 640, width: 450, height: 110)
            let winCrop = CGRect(x: 80, y: 160, width: 450, height: 60)
            stats("old snow, fresh")
            shot("11a-fresh", crop: floorCrop)
            sim.cfg.agingRate = 30
            run(6, on: false)
            stats("~3 min")
            shot("11b-3min", crop: floorCrop)
            run(8, on: false)
            stats("~7 min")
            shot("11c-7min", crop: floorCrop)
            shot("11c-7min-window", crop: winCrop)
            run(16, on: false)
            stats("~15 min")
            shot("11d-15min", crop: floorCrop)
            shot("11d-15min-window", crop: winCrop)
            run(30, on: false)
            stats("~30 min")
            shot("11e-30min", crop: floorCrop)
            shot("11e-30min-window", crop: winCrop)
            shot("11f-30min-full")

            // то же, но сугробы доливаются (как по умолчанию) — тоже в 30 раз быстрее
            sim.clearAll(); sim.resetHardness()
            sim.cfg.agingRate = 1; sim.cfg.intensity = 3
            sim.forceFill = true; sim.fillSurfaces(); sim.forceFill = false
            sim.cfg.agingRate = 30; sim.cfg.intensity = 30
            let s0 = (sim.statSettled, sim.statHollowed, sim.statCollapsed)
            for (k, m) in [10, 20, 30].enumerated() {
                run(20, on: false)
                stats("refilled ~\(m) min")
                shot("11g\(k)-refilled-\(m)min", crop: floorCrop)
                shot("11g\(k)-refilled-\(m)min-window", crop: winCrop)
            }
            print("refilled 30 min: settled \(sim.statSettled - s0.0), hollowed \(sim.statHollowed - s0.1), collapsed \(sim.statCollapsed - s0.2)")

            // 7б. Предел не обрывает снегопад: выше него снег ложится понемногу, а лишнее уходит
            //     на уплотнение и подтаивание снизу. Три погоды по 20 минут (в 30 раз быстрее).
            for (name, w) in [("light", Float(0.5)), ("normal", 1), ("blizzard", 2.2)] {
                sim.clearAll(); sim.resetHardness()
                sim.cfg.agingRate = 1; sim.cfg.intensity = 3
                sim.forceFill = true; sim.fillSurfaces(); sim.forceFill = false
                sim.cfg.agingRate = 30; sim.cfg.intensity = w * 30
                let m0 = sim.statMelted
                var line = "limit, \(name): level floor/windows"
                for k in 1...4 {
                    run(10, on: false)
                    let l = sim.fillLevel()
                    line += String(format: " %d min %.2f/%.2f;", k * 5, l.floor, l.windows)
                }
                var fresh = 0, cells = 0
                for i in sim.snow.indices where sim.snow[i] != 0 { cells += 1; if sim.hard[i] < Sim.dense { fresh += 1 } }
                print(line + " melted \(sim.statMelted - m0), fresh cells \(fresh * 100 / max(1, cells))%")
                if name == "normal" {
                    shot("13a-limit-normal-20min", crop: floorCrop)
                    shot("13a-limit-normal-20min-window", crop: winCrop)
                }
            }
            // сугробы «Высокие», потом переключили на «Низкие»: лишнее не исчезает разом, а оседает и подтаивает
            sim.clearAll(); sim.resetHardness()
            sim.cfg.agingRate = 1; sim.cfg.intensity = 3; sim.cfg.capScale = 1.8
            sim.forceFill = true; sim.fillSurfaces(); sim.forceFill = false
            sim.cfg.capScale = 0.6; sim.cfg.agingRate = 30; sim.cfg.intensity = 30
            var line = "depth high -> low: level floor/windows"
            for k in 0...4 {
                let l = sim.fillLevel()
                line += String(format: " %d min %.2f/%.2f;", k * 3, l.floor, l.windows)
                if k < 4 { run(6, on: false) }
            }
            print(line)
            shot("13b-high-to-low-12min", crop: floorCrop)
            sim.cfg.capScale = 1; sim.cfg.intensity = 3; sim.cfg.agingRate = 1
        }

        // 7а. шары на насте над пустотой: лёгкий стоит, тяжёлый проваливается; слишком широкая пустота рушится сама
        do {
            sim.clearAll()
            sim.cfg.intensity = 0; sim.cfg.flakeRate = 0; sim.cfg.aging = false; sim.cfg.agingRate = 1
            sim.setLedges([], windows: [])
            let depth = 16, W = sim.W, H = sim.H
            for c in Int(60 / sim.cell)...Int(1140 / sim.cell) {
                for k in 0..<depth { sim.snow[(H - 1 - k) * W + c] = 150; sim.hard[(H - 1 - k) * W + c] = 230 }
            }
            func hollow(_ x0: Float, _ cols: Int, rows: Int) {
                let c0 = Int(x0 / sim.cell)
                for c in c0..<(c0 + cols) { for k in 0..<rows { sim.snow[(H - 1 - k) * W + c] = 0 } }
            }
            hollow(150, 15, rows: 12)         // под тяжёлым шаром: наст 12 pt
            hollow(600, 15, rows: 12)         // под лёгким
            hollow(900, 45, rows: 12)         // широкая — без шаров
            sim.gridDirty = true; sim.hardDirty = true
            sim.recheckHanging()
            run(0.4, on: false)
            let before = sim.statCollapsed
            print("crust over hollows: wide hollow (135 pt) collapsed cells: \(before)")
            let surface = Float(H - depth) * sim.cell
            sim.balls.append(Ball(id: 950, x: 172, y: surface - 28.5, r: 28, seed: 3))
            sim.balls.append(Ball(id: 951, x: 622, y: surface - 7.5, r: 7, seed: 5))
            run(0.1, on: false)
            shot("12a-balls-on-crust", crop: CGRect(x: 60, y: 580, width: 1100, height: 170))
            run(2.5, on: false)
            func ball(_ id: Int32) -> Ball? { sim.balls.first { $0.id == id } }
            print(String(format: "heavy ball r 28: bottom %.0f -> %.0f pt (fell through: %@); light ball r 7: bottom %.0f -> %.0f; collapsed cells %d",
                         surface, (ball(950).map { $0.y + $0.r } ?? -1), ((ball(950).map { $0.y + $0.r } ?? 0) > surface + 4) ? "yes" : "NO",
                         surface, (ball(951).map { $0.y + $0.r } ?? -1), sim.statCollapsed - before))
            shot("12b-heavy-fell-through", crop: CGRect(x: 60, y: 580, width: 1100, height: 170))
            sim.clearAll()
            sim.cfg.aging = true; sim.cfg.flakeRate = 30; sim.cfg.openOnly = true
            sim.setLedges(ledges, windows: boxes())
        }

        // 6. самонарастание выключено: шапки строят только упавшие снежинки
        sim.clearAll()
        sim.cfg.intensity = 0
        sim.cfg.flakeRate = 60
        sim.prefill()
        run(90, on: false)
        var onLedges = 0, blockedCells = 0
        for sg in sim.segs where sg.kind == 1 {
            let row = Int((sg.y / sim.cell).rounded())
            for c in Int(sg.x0 / sim.cell)...Int(sg.x1 / sim.cell) {
                var y = row - 1
                while y >= 0 && sim.snow[y * sim.W + c] != 0 {
                    onLedges += 1
                    if sg.win == 1 && Float(c) * sim.cell > 805 { blockedCells += 1 }
                    y -= 1
                }
            }
        }
        print("autofill off, 90 s of snowfall: cells \(count()), on window ledges \(onLedges), over the window behind \(blockedCells)")
        shot("10-flakes-only")
        return 0
    }
}
