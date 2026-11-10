import Foundation
import QuartzCore

/// Стресс-тест: случайные движения курсора, шары, броски, перетаскивание окон, смена режимов.
/// Ищет шаги симуляции, которые длятся слишком долго, и лавинный рост числа частиц.
enum Fuzz {
    static func run(seconds: Float, seed: UInt64, cell: Float) -> Int32 {
        // Если симуляция зациклится, шаг не вернётся никогда — тогда процесс убьёт будильник.
        alarm(180)
        var rng = Rng(seed: seed)
        let wPt: Float = 2056, hPt: Float = 1329
        let sim = Sim(widthPt: wPt, heightPt: hPt, cell: cell, seed: seed &+ 7)
        var wins: [(x: Float, y: Float, w: Float, h: Float)] = [(100, 200, 420, 300), (640, 320, 380, 260), (980, 150, 300, 500), (300, 560, 500, 200)]
        var dockUp = false
        func ledges() {
            var l: [Ledge] = []
            var b: [WinBox] = []
            for (i, w) in wins.enumerated() {
                l.append(Ledge(y: w.y, x0: w.x + 5, x1: w.x + w.w - 5, kind: 1, win: i, ox: w.x, wr: w.x + w.w, r: i % 2 == 0 ? 18 : 0))
                b.append(WinBox(x0: w.x, x1: w.x + w.w, y0: w.y, y1: w.y + w.h, win: i))
            }
            if dockUp { l.append(Ledge(y: hPt - 60, x0: 507, x1: 893, kind: 2, win: -1, ox: 500, wr: 900, r: 22)) }
            sim.setLedges(l, windows: b)
        }
        ledges()
        sim.topLimit = 40
        sim.cfg.intensity = 4
        sim.prefill()
        for _ in 0..<600 { sim.step(1.0 / 60) }
        sim.cfg.intensity = 1
        sim.cfg.agingRate = 12       // чтобы за прогон успел появиться и плотный снег, и наст

        var cur = SIMD2<Float>(700, 400), target = cur
        var speed: Float = 300
        var holding = false
        var rest: Float = 0          // сколько ещё курсор стоит на месте
        var storm: Float = 0, stormMax: Float = 0, depMax = 0
        var saved: SimState? = nil
        var hidden: (Int, PileStash, (x: Float, y: Float, w: Float, h: Float))? = nil
        var t: Float = 0
        var worst = 0.0, worstAt: Float = 0
        var maxParts = 0
        var slow = 0
        while t < seconds {
            let dt: Float = [1.0 / 60, 1.0 / 60, 1.0 / 30, 1.0 / 20][Int(rng.next() % 4)]
            t += dt
            // курсор идёт к случайной цели, чаще всего вдоль карнизов и низа экрана
            let d = target - cur
            let dist = (d.x * d.x + d.y * d.y).squareRoot()
            if rest > 0 {
                rest -= dt
            } else if dist < 4 || rng.f() < 0.004 {
                if rng.f() < 0.35 { rest = rng.range(0.5, 6) }       // постоять, в том числе в сугробе
                let k = Int(rng.next() % 7)
                if k < 4 {
                    let w = wins[k]
                    target = SIMD2(w.x + rng.range(-60, w.w + 60), w.y + rng.range(-30, 12))
                } else if k == 4 {
                    target = SIMD2(rng.range(0, wPt), hPt - rng.range(0, 40))
                } else {
                    target = SIMD2(rng.range(-20, wPt + 20), rng.range(0, hPt))
                }
                speed = [40, 120, 300, 900, 2500][Int(rng.next() % 5)]
            } else {
                cur += d / dist * min(dist, speed * dt)
            }
            sim.setCursor(x: cur.x, y: cur.y, dt: dt, on: cur.x >= 0 && cur.x <= wPt)
            // варежка
            if !holding && rng.f() < 0.01 { sim.handsMode = true; sim.grabBegin(); holding = sim.heldId != -1 }
            else if holding && rng.f() < 0.02 { sim.grabEnd(); sim.handsMode = false; holding = false }
            // окна
            if rng.f() < 0.02 {
                let k = Int(rng.next() % 4)
                let old = wins[k]
                wins[k].x = max(0, min(wPt - old.w, old.x + rng.range(-40, 40)))
                wins[k].y = max(60, min(hPt - 100, old.y + rng.range(-25, 25)))
                func c(_ v: Float) -> Int { Int((v / cell).rounded()) }
                for s in sim.segs where s.win == k {
                    sim.shiftPile(s, cols: c(wins[k].x) - c(old.x), rows: c(wins[k].y) - c(old.y),
                                  vx: (wins[k].x - old.x) / dt, vy: (wins[k].y - old.y) / dt)
                }
                ledges()
            }
            // окно уходит с экрана и возвращается; смена рабочего стола туда-обратно
            if hidden == nil && rng.f() < 0.002 {
                let k = Int(rng.next() % UInt64(wins.count))
                let st = sim.extractPile(win: k)
                hidden = (k, st, wins[k])
                wins[k] = (x: -5000, y: 300, w: 200, h: 200)
                ledges()
            } else if let h = hidden, rng.f() < 0.01 {
                wins[h.0] = h.2
                ledges()
                sim.insertPile(h.1, ox: h.2.x, y: h.2.y)
                hidden = nil
            }
            if rng.f() < 0.001 {
                let cur = sim.saveState()
                sim.loadState(saved)
                saved = cur
                if holding { holding = false; sim.handsMode = false }
                if rng.f() < 0.5 { sim.forceFill = true; sim.fillSurfaces(); sim.forceFill = false }
                ledges()
            }
            if rng.f() < 0.002 { sim.cfg.intensity = sim.cfg.intensity > 0 ? 0 : 1; sim.cfg.flakeRate = [14, 60, 110][Int(rng.next() % 3)] }
            if rng.f() < 0.001 { sim.cfg.wind = rng.range(-200, 200) }
            if rng.f() < 0.001 { sim.cfg.openOnly.toggle() }
            if rng.f() < 0.004 {            // Dock выезжает и прячется
                if dockUp { sim.dropDock() } else { sim.liftFloor(x0: 507, x1: 893, toY: hPt - 60) }
                dockUp.toggle()
                ledges()
            }
            if rng.f() < 0.0005 { sim.forceFill = true; sim.fillSurfaces(); sim.forceFill = false }

            let t0 = CACurrentMediaTime()
            sim.step(dt)
            let ms = (CACurrentMediaTime() - t0) * 1000
            if ms > worst { worst = ms; worstAt = t }
            maxParts = max(maxParts, sim.parts.count)
            depMax = max(depMax, sim.statDeposits)
            // «буря»: комья подолгу падают и срываются снова, хотя ничего не происходит
            if sim.statSpawns > 150 { storm += dt } else { storm = 0 }
            if storm > stormMax {
                stormMax = storm
                if storm > 3 && Int(storm * 10) % 20 == 0 {
                    let chunks = sim.parts.reduce(0) { $0 + ($1.kind == 1 ? 1 : 0) }
                    print(String(format: "STORM %.1f s at t=%.1f: chunks=%d deposits=%d spawns=%d cursor=(%.0f,%.0f) rest=%.1f held=%d intensity=%.0f",
                                 storm, t, chunks, sim.statDeposits, sim.statSpawns, cur.x, cur.y, rest, sim.heldId, sim.cfg.intensity))
                }
            }
            if ms > 30 {
                slow += 1
                if slow <= 8 {
                    let chunks = sim.parts.reduce(0) { $0 + ($1.kind == 1 ? 1 : 0) }
                    print(String(format: "SLOW step %.1f ms at t=%.2f dt=%.3f: parts=%d chunks=%d balls=%d deposits=%d spawns=%d cursor=(%.0f,%.0f) held=%d",
                                 ms, t, dt, sim.parts.count, chunks, sim.balls.count, sim.statDeposits, sim.statSpawns,
                                 cur.x, cur.y, sim.heldId))
                }
            }
        }
        print(String(format: "fuzz seed=%llu cell=%.0f: %.0f s simulated, worst step %.2f ms (t=%.1f), max particles %d, slow steps %d, max deposits/step %d, longest storm %.1f s",
                     seed, cell, seconds, worst, worstAt, maxParts, slow, depMax, stormMax))
        // Провал — это настоящее зависание: шаг в сотни миллисекунд или комья, которые секундами
        // падают и срываются снова. Отдельные шаги по 30–50 мс бывают просто от занятой машины
        // (например, на общем сервере сборки), поэтому они только печатаются.
        return worst > 400 || stormMax > 3 ? 1 : 0
    }
}
