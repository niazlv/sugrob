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

        func shot(_ name: String) {
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
            guard let out = ctx.makeImage() else { return }
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

            // 5д. шар стоит долго: примерзает, его заметает, оседает, становится сугробом
            sim.cfg.aging = true; sim.cfg.agingRate = 30; sim.cfg.intensity = 1
            run(1.5, on: false)
            print(String(format: "after ~45 s at rest: rest %.0f s, cover %.2f, frozen in place: %@", ball(900).rest, ball(900).cover, ball(900).rest > Sim.stuckAfter ? "yes" : "no"))
            run(2.0, on: false)
            shot("5g-ball-covered")
            run(3.0, on: false)
            print(String(format: "after ~195 s: squash %.2f, cover %.2f", ball(900).squash, ball(900).cover))
            shot("5h-ball-slumped")
            let before = sim.snow.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
            run(2.5, on: false)
            print("after ~270 s: balls left \(sim.balls.count), cells \(before) -> \(sim.snow.reduce(0) { $0 + ($1 != 0 ? 1 : 0) })")
            shot("5i-ball-became-drift")
            sim.clearAll()
            sim.cfg.agingRate = 1; sim.cfg.flakeRate = 30
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
