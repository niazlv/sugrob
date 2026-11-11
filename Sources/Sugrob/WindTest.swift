import AppKit
import Metal

/// Самотест ветра без экрана: `Sugrob --wind-test <папка> [сценарий] [ячейка] [секунд]`.
/// Сценарии: drift — позёмка сглаживает ландшафт, объём сохраняется; storm — буран, шапки окон, пласт;
/// trench — траншеи, стенка, гребень и выступы наста в буран и при сильном ветре; crust — наст и плотный снег; stairs (и stairs-calm — контроль без бурана) — ступени человечков;
/// rates — сколько несёт при разном ветре; stress (и stress-calm) — 10 минут с буранами каждые 40 с;
/// edge — отладочный профиль шапки у наветренного края; all — всё подряд.
/// Кадры — на общей сцене PeopleStage (два «окна»), стресс — на большом экране без отрисовки.
enum WindTest {
    static func run(outDir: String, args: [String]) -> Int32 {
        let what = args.first ?? "all"
        let cell = args.count > 1 ? Float(args[1]) ?? 3 : 3
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        if what == "stress" || what == "stress-calm" {      // calm — контроль: то же без ветра и буранов
            return stress(cells: args.count > 1 ? [cell] : [3, 2, 6], seconds: args.count > 2 ? Float(args[2]) ?? 600 : 600,
                          calm: what == "stress-calm")
        }
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = Renderer(device: device, pixelFormat: .bgra8Unorm),
              let queue = device.makeCommandQueue() else {
            print("no metal"); return 1
        }
        func stage() -> PeopleStage {
            let st = PeopleStage(outDir: outDir, device: device, renderer: renderer, queue: queue, cell: cell, unit: 2)
            st.sim.cfg.storms = false       // бураны сценарий зовёт сам
            return st
        }
        var fail: Int32 = 0
        if what == "drift" || what == "all" { fail += drift(stage()) }
        if what == "storm" || what == "all" { fail += storm(stage()) }
        if what == "crust" || what == "all" { fail += crust(stage()) }
        // траншеи, стенка, гребень, выступы наста: буран на рыхлом, плотном и насте; сильный ветер без бурана
        if what == "trench" || what == "all" {
            fail += trench(stage(), hard: 0, tag: "loose", storm: true)
            fail += trench(stage(), hard: 120, tag: "dense", storm: true)
            fail += trench(stage(), hard: 235, tag: "crust", storm: true)
            fail += trench(stage(), hard: 0, tag: "loose", storm: false)
            fail += trench(stage(), hard: 120, tag: "dense", storm: false)
        }
        if what == "stairs" || what == "all" { fail += stairs(stage()) }
        if what == "stairs-calm" { fail += stairs(stage(), calm: true) }
        if what == "rates" || what == "all" {       // сколько снега несёт при разном ветре
            let st = stage()
            let s = st.sim
            s.cfg.people = 0
            s.wind.reseed(11)
            for (w, gust) in [(Float(45), Float(6)), (90, 6), (-90, 6), (198, 6), (198, 60), (0, 60)] {
                s.cfg.wind = w
                s.cfg.gust = gust
                st.run(10)
                let l0 = s.wind.statLifted
                var chunks = 0, dust = 0, n = 0
                for _ in 0..<600 { st.run(0.1); chunks += s.wind.chunksAir; dust += s.wind.dustAir; n += 1 }
                print(String(format: "rates: wind %4.0f gust %2.0f: %.1f cells lifted per second, in the air on average %.1f chunks, %.0f dust",
                             w, gust, Float(s.wind.statLifted - l0) / 60, Float(chunks) / Float(n), Float(dust) / Float(n)))
                if abs(w) == 90 || gust == 60 { st.shot(String(format: "r-wind%.0f-gust%.0f", w, gust), crops: [CGRect(x: 0, y: 700, width: 700, height: 100), CGRect(x: 300, y: 120, width: 490, height: 110)], zoom: 2, full: w == 198) }
            }
        }
        if what == "edge" {     // отладка: профиль шапки у наветренного края по времени
            let st = stage()
            let s = st.sim
            s.cfg.people = 0
            if args.count > 2 { s.cfg.intensity = Float(args[2]) ?? 1 }
            s.wind.startStorm(strength: 1, dir: 1, seconds: 60)
            let g = s.segs[0]
            let c0 = Int((g.x0 * s.inv).rounded(.up))
            for k in 0...14 {
                var line = String(format: "t=%2d storm %.2f w %4.0f lifted %5d:", k * 5, s.wind.storm, s.windNow, s.wind.statLifted)
                for c in c0..<(c0 + 40) { line += " \(ledgeRow(s, g, c).map { s.snowHeight(c, $0) } ?? -1)" }
                print(line)
                st.run(5)
            }
        }
        if what == "all" { fail += stress(cells: [3, 2, 6], seconds: 600) }
        print(fail == 0 ? "wind test: OK" : "wind test: FAILED (\(fail))")
        return fail == 0 ? 0 : 1
    }

    // MARK: - Подсчёты

    /// Ячеек снега в сетке и комьев в воздухе.
    static func volume(_ s: Sim) -> (cells: Int, chunks: Int) {
        var n = 0
        for v in s.snow where v != 0 { n += 1 }
        var k = 0
        for p in s.parts where p.kind == 1 { k += 1 }
        return (n, k)
    }

    /// Шаг с учётом комьев, ушедших за боковые края экрана (метка — в неиспользуемом у комьев phase).
    static func tick(_ st: PeopleStage, _ seconds: Float, out: inout Int) {
        let s = st.sim
        let n = max(1, Int(seconds / st.dt))
        for _ in 0..<n {
            s.setCursor(x: -100, y: -100, dt: st.dt, on: false)
            s.step(st.dt)
            for i in s.parts.indices where s.parts[i].kind == 1 {
                let gone = s.parts[i].x < 0 || s.parts[i].x >= Float(s.W) * s.cell
                if gone && s.parts[i].phase == 0 { s.parts[i].phase = 1; out += 1 }
                else if !gone && s.parts[i].phase == 1 { s.parts[i].phase = 0; out -= 1 }
            }
        }
    }

    static func floorHeights(_ s: Sim) -> [Int] { (0..<s.W).map { s.snowHeight($0, s.H) } }

    /// Неровность: сумма перепадов между соседними столбцами, в ячейках.
    static func rough(_ h: [Int]) -> Int {
        var r = 0
        for i in 1..<h.count { r += abs(h[i] - h[i - 1]) }
        return r
    }

    /// Убрать весь снег с низа экрана (нижние 150 pt) и комья.
    static func clearFloor(_ s: Sim) {
        s.parts.removeAll { $0.kind == 1 }
        for r in max(0, s.H - Int(150 * s.inv))..<s.H {
            for c in 0..<s.W { s.snow[r * s.W + c] = 0; s.hard[r * s.W + c] = 0 }
        }
        s.gridDirty = true
        s.hardDirty = true
    }

    /// Насыпать на пол столбик высотой pt над тем, что уже лежит.
    static func heap(_ s: Sim, _ c: Int, _ pt: Float, hard: UInt8, rng: inout Rng) {
        guard c >= 0, c < s.W else { return }
        var n = Int((pt * s.inv).rounded())
        var r = s.H - 1
        while r >= 1 && s.snow[r * s.W + c] != 0 { r -= 1 }
        while n > 0 && r >= 1 {
            s.snow[r * s.W + c] = rng.shade()
            s.hard[r * s.W + c] = hard
            r -= 1
            n -= 1
        }
        s.gridDirty = true
        s.hardDirty = true
    }

    /// Строка карниза окна в столбце c.
    static func ledgeRow(_ s: Sim, _ g: Ledge, _ c: Int) -> Int? {
        let r0 = Int((g.y * s.inv).rounded())
        guard c >= 0, c < s.W, r0 >= 1 else { return nil }
        for r in r0...min(s.H - 1, r0 + Int(g.r * s.inv) + 2) where s.ledge[r * s.W + c] != 0 { return r }
        return nil
    }

    /// Средняя высота шапки окна, pt: у левого края (40 pt), посередине, у правого края.
    static func capProfile(_ s: Sim, _ g: Ledge) -> (l: Float, m: Float, r: Float) {
        var sum: [Float] = [0, 0, 0], cnt: [Float] = [0, 0, 0]
        let c0 = Int((g.x0 * s.inv).rounded(.up)), c1 = Int((g.x1 * s.inv).rounded(.down)) - 1
        guard c0 <= c1 else { return (0, 0, 0) }
        for c in c0...c1 {
            guard let row = ledgeRow(s, g, c) else { continue }
            let x = (Float(c) + 0.5) * s.cell
            let k = x < g.x0 + 40 ? 0 : (x > g.x1 - 40 ? 2 : 1)
            sum[k] += Float(s.snowHeight(c, row)) * s.cell
            cnt[k] += 1
        }
        return (sum[0] / max(1, cnt[0]), sum[1] / max(1, cnt[1]), sum[2] / max(1, cnt[2]))
    }

    // MARK: - (а) Позёмка сглаживает ландшафт

    static func drift(_ st: PeopleStage) -> Int32 {
        let s = st.sim
        s.cfg.people = 0; s.cfg.intensity = 0; s.cfg.flakeRate = 0; s.cfg.aging = false
        // чтобы сама симуляция не «подтаивала» насыпанное выше предела (Sim.relieve): предел выше, убыль медленнее
        s.cfg.capScale = 3; s.cfg.agingRate = 0.01
        s.wind.reseed(77)
        s.parts.removeAll()
        clearFloor(s)
        var rng = Rng(seed: 31337)
        // рыхлый неровный пол: горка, плато с ямой, гребёнка, пологий холм
        for c in 0..<s.W {
            let x = (Float(c) + 0.5) * s.cell
            var h: Float = 7
            h = max(h, 62 - abs(x - 250) * 0.9)                                 // острая горка
            if x > 420 && x < 660 { h = max(h, 32) }                            // плато…
            if x > 500 && x < 570 { h = 4 }                                     // …с ямой
            if x > 760 && x < 910 { h = max(h, 8 + (x - 760).truncatingRemainder(dividingBy: 30) * 0.8) }    // гребёнка
            h = max(h, 46 * expf(-(x - 1130) * (x - 1130) / (2 * 45 * 45)))     // холм
            heap(s, c, h + rng.range(-1.5, 1.5), hard: 0, rng: &rng)
        }
        s.snowDisturbed(0, 0, s.W - 1, s.H - 1)
        var out = 0
        tick(st, 5, out: &out)                                                  // слишком крутое осыпалось само
        let crops = [CGRect(x: 0, y: 700, width: 700, height: 100), CGRect(x: 700, y: 700, width: 700, height: 100)]
        let h0 = floorHeights(s), v0 = volume(s)
        out = 0
        let in0 = s.wind.statBlownIn, melt0 = s.statMelted
        st.shot("a0-before", crops: crops, zoom: 2)
        func pit(_ h: [Int]) -> Float {
            let a = Int(510 * s.inv), b = Int(560 * s.inv)
            return Float(h[a...b].reduce(0, +)) / Float(b - a + 1) * s.cell
        }
        func line(_ tag: String, _ h: [Int]) {
            let v = volume(s)
            print(String(format: "  %@: rough %d, max %.0f pt, pit %.1f pt, cells %d + chunks %d, lifted %d, in %d, out %d, parts %d",
                         tag, rough(h), Float(h.max() ?? 0) * s.cell, pit(h), v.cells, v.chunks, s.wind.statLifted,
                         s.wind.statBlownIn - in0, out, s.parts.count))
        }
        line("before", h0)
        s.cfg.wind = 180
        for k in 1...6 {
            tick(st, 30, out: &out)
            if k == 1 { st.shot("a1-30s", crops: crops, zoom: 2, full: false) }
            if k == 3 { st.shot("a2-90s", crops: crops, zoom: 2, full: false) }
            line(String(format: "t+%ds", k * 30), floorHeights(s))
        }
        st.shot("a3-wind-180s", crops: crops, zoom: 2)
        s.cfg.wind = 0
        s.cfg.gust = 0
        tick(st, 6, out: &out)                                                  // комья легли
        let h1 = floorHeights(s), v1 = volume(s)
        st.shot("a4-after", crops: crops, zoom: 2)
        line("after", h1)
        let blown = s.wind.statBlownIn - in0
        let melted = s.statMelted - melt0
        let unexplained = (v0.cells + v0.chunks) + blown - out - melted - (v1.cells + v1.chunks)
        print(String(format: "drift: rough %d -> %d, max %.0f -> %.0f pt, pit %.1f -> %.1f pt; volume %d -> %d (blown in %d, out over the edges %d, of them wind-carried %d, waiting to return %d, melted by Sim %d, unexplained %d)",
                     rough(h0), rough(h1), Float(h0.max() ?? 0) * s.cell, Float(h1.max() ?? 0) * s.cell, pit(h0), pit(h1),
                     v0.cells + v0.chunks, v1.cells + v1.chunks, blown, out, s.wind.statBlownOut, s.wind.pendingIn, melted, unexplained))
        var fail: Int32 = 0
        if abs(unexplained) > 3 { print("  FAIL: volume not conserved"); fail += 1 }
        if rough(h1) * 10 > rough(h0) * 8 { print("  FAIL: landscape not smoothed"); fail += 1 }
        if pit(h1) < pit(h0) + 6 { print("  FAIL: pit not filled"); fail += 1 }
        return fail
    }

    // MARK: - (б) Буран

    static func storm(_ st: PeopleStage) -> Int32 {
        let s = st.sim
        s.cfg.people = 0
        s.wind.reseed(5)
        var out = 0
        tick(st, 2, out: &out)
        let tops = [CGRect(x: 300, y: 120, width: 490, height: 110), CGRect(x: 900, y: 310, width: 390, height: 110)]
        let floor = [CGRect(x: 0, y: 700, width: 700, height: 100), CGRect(x: 700, y: 700, width: 700, height: 100)]
        func caps(_ tag: String) {
            var line = "  \(tag): storm \(String(format: "%.2f", s.wind.storm)) wind \(String(format: "%.0f", s.windNow))"
            for g in s.segs {
                let p = capProfile(s, g)
                line += String(format: " | win %d cap l %.1f m %.1f r %.1f", g.win, p.l, p.m, p.r)
            }
            let v = volume(s)
            print(line + String(format: " | cells %d chunks %d dust %d parts %d lifted %d slabs %d(%d)", v.cells, v.chunks, s.wind.dustAir,
                                s.parts.count, s.wind.statLifted, s.wind.statSlabs, s.wind.statSlabCells))
        }
        st.shot("b0-before", crops: tops + floor, zoom: 2)
        caps("before")
        let before = s.segs.map { capProfile(s, $0) }
        s.wind.startStorm(strength: 1, dir: 1, seconds: 60)
        var maxParts = 0, maxWind: Float = 0, slabShots = 0, slabSeen = 0
        var t: Float = 0
        var marks: [(Float, String)] = [(6, "b1-rise"), (25, "b2-peak"), (42, "b3-late"), (60, "b4-end"), (80, "b5-after"), (200, "b6-healed")]
        var peak = before
        while t < 200 {
            tick(st, 0.1, out: &out)
            t += 0.1
            maxParts = max(maxParts, s.parts.count)
            maxWind = max(maxWind, abs(s.windNow))
            if s.wind.statSlabs > slabSeen {            // пласт только что сорвался: два кадра вдогонку
                slabSeen = s.wind.statSlabs
                if slabShots < 3 {
                    slabShots += 1
                    tick(st, 0.1, out: &out); t += 0.1
                    st.shot("b-slab\(slabShots)-a", crops: tops, zoom: 2, full: false)
                    tick(st, 0.3, out: &out); t += 0.3
                    st.shot("b-slab\(slabShots)-b", crops: tops, zoom: 2, full: slabShots == 1)
                }
            }
            if let m = marks.first, t >= m.0 {
                marks.removeFirst()
                st.shot(m.1, crops: tops + floor, zoom: 2)
                caps(m.1)
                if m.1 == "b3-late" { peak = s.segs.map { capProfile(s, $0) } }
            }
        }
        print(String(format: "storm: max wind %.0f pt/s, max parts %d, lifted %d (crust chipped %d), brought by the storm %d, slabs %d (%d cells), out %d",
                     maxWind, maxParts, s.wind.statLifted, s.wind.statChipped, s.wind.statDrifted, s.wind.statSlabs, s.wind.statSlabCells, out))
        var fail: Int32 = 0
        // ветер вправо: наветренный край — левый; его должно сдуть
        for (k, b) in before.enumerated() where k < peak.count {
            print(String(format: "  win %d: windward edge %.1f -> %.1f pt, lee edge %.1f -> %.1f pt", s.segs[k].win, b.l, peak[k].l, b.r, peak[k].r))
            if peak[k].l > b.l * 0.75 { print("  FAIL: windward edge not scoured"); fail += 1 }
        }
        if s.wind.statSlabs == 0 { print("  FAIL: no slab fell"); fail += 1 }
        if s.wind.storm > 0.001 { print("  FAIL: storm did not end"); fail += 1 }
        return fail
    }

    // MARK: - Буран заметает траншеи и намётает у препятствий

    /// Ровный пол толщиной 30 pt заданной слежалости; в нём траншеи 15, 24 и 30 pt глубиной, на нём — гребень
    /// рыхлого снега, стенка из наста, столбик и пик из наста. storm: один буран на 60 с; иначе — ветер 180 четыре минуты.
    /// Сугробы сами не растут (intensity ≈ 0), так что всё, что изменилось, сделал ветер.
    static func trench(_ st: PeopleStage, hard: UInt8, tag: String, storm: Bool) -> Int32 {
        let s = st.sim
        s.cfg.people = 0; s.cfg.intensity = 0.0001; s.cfg.aging = false
        s.cfg.capScale = 3; s.cfg.agingRate = 0.01
        s.wind.reseed(21)
        s.parts.removeAll { $0.kind == 1 }
        clearFloor(s)
        var rng = Rng(seed: 808)
        let base: Float = 30
        let pits: [(x0: Float, x1: Float, depth: Float)] = [(90, 111, 24), (200, 212, 15), (330, 351, 24), (470, 500, 30)]
        for c in 0..<s.W {
            let x = (Float(c) + 0.5) * s.cell
            var h = base
            for p in pits where x >= p.x0 && x < p.x1 { h = base - p.depth }
            if h > 0 { heap(s, c, h, hard: hard, rng: &rng) }
            if x > 600 && x < 660 { heap(s, c, 20 - abs(x - 630) * 0.66, hard: 0, rng: &rng) }      // гребень рыхлого снега
            if x >= 780 && x < 789 { heap(s, c, 30, hard: 235, rng: &rng) }                          // стенка из наста
            if x >= 900 && x < 906 { heap(s, c, 24, hard: 235, rng: &rng) }                          // столбик наста в две ячейки
            if x >= 960 && x < 963 { heap(s, c, 15, hard: 235, rng: &rng) }                          // пик наста в одну
        }
        s.snowDisturbed(0, 0, s.W - 1, s.H - 1)
        var out = 0
        tick(st, 3, out: &out)
        func mean(_ x0: Float, _ x1: Float) -> Float {
            let a = max(0, Int(x0 * s.inv)), b = min(s.W - 1, Int((x1 - 0.01) * s.inv))
            guard a <= b else { return 0 }
            return Float((a...b).reduce(0) { $0 + s.snowHeight($1, s.H) }) / Float(b - a + 1) * s.cell
        }
        func peak(_ x0: Float, _ x1: Float) -> Float {
            let a = max(0, Int(x0 * s.inv)), b = min(s.W - 1, Int((x1 - 0.01) * s.inv))
            return Float((a...b).map { s.snowHeight($0, s.H) }.max() ?? 0) * s.cell
        }
        let name = "t-\(tag)-\(storm ? "storm" : "wind")"
        let crops = [CGRect(x: 150, y: 715, width: 550, height: 85), CGRect(x: 560, y: 715, width: 550, height: 85)]
        let pit0 = pits.map { mean($0.x0, $0.x1) }
        let wall0 = mean(762, 780), ridge0 = peak(600, 660), pillar0 = peak(900, 906), spike0 = peak(960, 963)
        let v0 = volume(s)
        let lifted0 = s.wind.statLifted, chip0 = s.wind.statChipped, drift0 = s.wind.statDrifted
        st.shot(name + "-0-before", crops: crops, zoom: 3, full: false)
        if storm {
            s.wind.startStorm(strength: 1, dir: 1, seconds: 60)
            tick(st, 30, out: &out)
            st.shot(name + "-1-30s", crops: crops, zoom: 3, full: tag == "crust")
            tick(st, 45, out: &out)
        } else {
            s.cfg.wind = 180
            tick(st, 120, out: &out)
            st.shot(name + "-1-120s", crops: crops, zoom: 3, full: false)
            tick(st, 120, out: &out)
            s.cfg.wind = 0; s.cfg.gust = 0
            tick(st, 5, out: &out)
        }
        st.shot(name + "-2-after", crops: crops, zoom: 3, full: false)
        let v1 = volume(s)
        var fills: [Float] = []
        var line = ""
        for (k, p) in pits.enumerated() {
            let was = pit0[k], now = mean(p.x0, p.x1)
            let f = (now - was) / max(1, base - was)
            fills.append(f)
            line += String(format: " %.0fx%.0f pt: %.0f%% (%.0f -> %.0f pt);", p.x1 - p.x0, p.depth, f * 100, was, now)
        }
        let wall1 = mean(762, 780), ridge1 = peak(600, 660), pillar1 = peak(900, 906), spike1 = peak(960, 963)
        print("\(name): trenches filled:\(line)")
        print(String(format: "  drift before the wall %.1f -> %.1f pt; loose ridge peak %.0f -> %.0f pt; crust pillar %.0f -> %.0f pt, crust spike %.0f -> %.0f pt",
                     wall0, wall1, ridge0, ridge1, pillar0, pillar1, spike0, spike1))
        print(String(format: "  cells lifted by wind %d (crust chipped %d), snow brought by the storm %d cells; cells on screen %d -> %d",
                     s.wind.statLifted - lifted0, s.wind.statChipped - chip0, s.wind.statDrifted - drift0, v0.cells + v0.chunks, v1.cells + v1.chunks))
        var fail: Int32 = 0
        if storm {
            if fills.contains(where: { $0 < 0.5 }) { print("  FAIL: a trench is less than half filled after one storm"); fail += 1 }
            if wall1 < wall0 + 3 { print("  FAIL: no drift before the wall"); fail += 1 }
            if ridge1 > ridge0 - 6 { print("  FAIL: loose ridge not cut"); fail += 1 }
            if spike1 > spike0 - 6 || pillar1 > pillar0 - 6 { print("  FAIL: crust spikes not ground"); fail += 1 }
        } else if hard < Sim.dense {
            if fills.reduce(0, +) / Float(fills.count) < 0.5 || fills.contains(where: { $0 < 0.3 }) {
                print("  FAIL: trenches are less than half filled after 4 minutes of strong wind"); fail += 1
            }
        }
        return fail
    }

    // MARK: - (в) Наст и плотный снег

    static func crust(_ st: PeopleStage) -> Int32 {
        let s = st.sim
        // intensity чуть больше нуля: снежинки бурана тают, а не строят сугробы; предел выше — Sim не «подтаивает» горки
        s.cfg.people = 0; s.cfg.intensity = 0.0001; s.cfg.flakeRate = 0; s.cfg.aging = false
        s.cfg.capScale = 3; s.cfg.agingRate = 0.01
        s.wind.reseed(9)
        s.parts.removeAll()
        clearFloor(s)
        var rng = Rng(seed: 4711)
        // три одинаковые горки: рыхлая, плотная, наст
        let hills: [(x: Float, hard: UInt8)] = [(260, 0), (640, 120), (1020, 230)]
        for c in 0..<s.W {
            let x = (Float(c) + 0.5) * s.cell
            for hl in hills {
                let h = 46 - abs(x - hl.x) * 0.75
                if h > 2 { heap(s, c, h, hard: hl.hard, rng: &rng) }
            }
        }
        /// На месте каждой горки (в её исходных границах): ячеек всего, плотных, наста и высота вершины, pt.
        func count() -> [(all: Int, dense: Int, frozen: Int, peak: Float)] {
            var n = [(all: Int, dense: Int, frozen: Int, peak: Float)](repeating: (0, 0, 0, 0), count: hills.count)
            for c in 0..<s.W {
                let x = (Float(c) + 0.5) * s.cell
                guard let k = hills.firstIndex(where: { abs(x - $0.x) < 62 }) else { continue }
                n[k].peak = max(n[k].peak, Float(s.snowHeight(c, s.H)) * s.cell)
                for r in max(0, s.H - Int(150 * s.inv))..<s.H where s.snow[r * s.W + c] != 0 {
                    let hd = s.hard[r * s.W + c]
                    n[k].all += 1
                    if hd >= Sim.frozen { n[k].frozen += 1 } else if hd >= Sim.dense { n[k].dense += 1 }
                }
            }
            return n
        }
        func frozen() -> Int {
            var n = 0
            for i in s.snow.indices where s.snow[i] != 0 && s.hard[i] >= Sim.frozen { n += 1 }
            return n
        }
        func show(_ tag: String, _ n: [(all: Int, dense: Int, frozen: Int, peak: Float)]) {
            print(String(format: "  %@: loose hill %d cells, peak %.0f pt | dense hill %d cells (%d dense), peak %.0f pt | crust hill %d cells (%d frozen), peak %.0f pt; lifted %d",
                         tag, n[0].all, n[0].peak, n[1].all, n[1].dense, n[1].peak, n[2].all, n[2].frozen, n[2].peak, s.wind.statLifted))
        }
        var out = 0
        tick(st, 3, out: &out)
        let crops = [CGRect(x: 150, y: 720, width: 1000, height: 80)]
        let n0 = count(), f0 = frozen()
        st.shot("c0-before", crops: crops, zoom: 2, full: false)
        show("before", n0)
        s.cfg.wind = 180
        tick(st, 120, out: &out)
        let n1 = count()
        st.shot("c1-wind-120s", crops: crops, zoom: 2, full: false)
        show("wind 180, 120 s", n1)
        s.cfg.wind = 0
        s.wind.startStorm(strength: 1, dir: 1, seconds: 60)
        tick(st, 72, out: &out)
        let n2 = count(), f2 = frozen()
        st.shot("c2-storm", crops: crops, zoom: 2, full: false)
        show("storm 60 s", n2)
        print("crust: frozen cells \(f0) -> \(f2); dense on site \(n0[1].dense) -> \(n1[1].dense) (wind) -> \(n2[1].dense) (storm); loose peak \(n0[0].peak) -> \(n1[0].peak) -> \(n2[0].peak) pt")
        var fail: Int32 = 0
        // наст ветер только шлифует (у горки — вершину): тело горки на месте
        if f2 * 100 < f0 * 93 || n2[2].peak < n0[2].peak - 9 { print("  FAIL: crust was blown away"); fail += 1 }
        if n1[1].dense * 10 < n0[1].dense * 6 { print("  FAIL: dense snow blown too easily by plain wind"); fail += 1 }
        if n2[1].dense >= n0[1].dense && n2[1].peak >= n0[1].peak { print("  FAIL: dense snow not eroded even by a storm"); fail += 1 }
        if n2[0].peak > n0[0].peak * 0.8 { print("  FAIL: loose hill hardly moved"); fail += 1 }
        return fail
    }

    // MARK: - (в) Ступени человечков

    /// calm — контроль: то же самое без бурана (ступени убывают и сами: их топчут, они оседают).
    static func stairs(_ st: PeopleStage, calm: Bool = false) -> Int32 {
        let s = st.sim
        st.wins.removeLast()            // только окно, не доходящее до низа: к нему строят лестницу со ступенями
        st.setWindows()
        s.cfg.people = 2
        s.cfg.peopleLadders = true
        s.wind.reseed(3)
        s.people.summon()
        func stairCells() -> [Int] {
            var a: [Int] = []
            for r in max(0, s.H - Int(400 * s.inv))..<s.H {
                for c in 0..<s.W where s.snow[r * s.W + c] != 0 && s.people.isStair(s, c, r) { a.append(r * s.W + c) }
            }
            return a
        }
        var t: Float = 0
        while t < 460 {
            st.run(10)
            t += 10
        }
        let before = stairCells()
        guard before.count > 20 else {
            print("stairs: people built no stairs (\(before.count) cells) — nothing to check")
            return 0
        }
        let xs = before.map { CGFloat(Float($0 % s.W) * s.cell) }
        let crop = CGRect(x: max(0, xs.min()! - 80), y: 500, width: min(700, xs.max()! - xs.min()! + 160), height: 300)
        let tag = calm ? "sc" : "s"
        st.shot("\(tag)0-stairs", crops: [crop], zoom: 2, full: false)
        let lifted0 = s.wind.statLifted
        if !calm { s.wind.startStorm(strength: 1, dir: 1, seconds: 60) }
        // после каждого шага: пропала ли ячейка ступеней и кто её снял — ветер (счётчик сорванных вырос в этом шаге) или нет
        var lostWind = 0, lostOther = 0
        var alive = before
        for k in 0..<Int(75 / st.dt) {
            let l0 = s.wind.statLifted + s.wind.statSlabCells
            s.setCursor(x: -100, y: -100, dt: st.dt, on: false)
            s.step(st.dt)
            let byWind = s.wind.statLifted + s.wind.statSlabCells > l0
            var keep: [Int] = []
            keep.reserveCapacity(alive.count)
            for i in alive {
                if s.snow[i] != 0 { keep.append(i) } else if byWind { lostWind += 1 } else { lostOther += 1 }
            }
            alive = keep
            if k == Int(30 / st.dt) { st.shot("\(tag)1-\(calm ? "calm" : "storm")", crops: [crop], zoom: 2) }
        }
        st.shot("\(tag)2-after", crops: [crop], zoom: 2, full: false)
        print("stairs\(calm ? " (calm control)" : ""): \(before.count) stair cells, gone in 75 s: \(lostOther) in steps where wind lifted nothing, \(lostWind) in steps where it lifted something; wind lifted \(s.wind.statLifted - lifted0) cells in all")
        return 0
    }

    // MARK: - (г) Стресс

    static func stress(cells: [Float], seconds: Float, calm: Bool = false) -> Int32 {
        var fail: Int32 = 0
        for cell in cells {
            let wPt: Float = 2056, hPt: Float = 1329
            let sim = Sim(widthPt: wPt, heightPt: hPt, cell: cell, seed: 777)
            let wins: [(x: Float, y: Float, w: Float, h: Float)] = [(100, 200, 420, 300), (640, 320, 380, 260), (980, 150, 300, 500),
                                                                    (300, 560, 500, 200), (1400, 420, 520, 600)]
            var l: [Ledge] = [], b: [WinBox] = []
            for (i, w) in wins.enumerated() {
                l.append(Ledge(y: w.y, x0: w.x + 5, x1: w.x + w.w - 5, kind: 1, win: i, ox: w.x, wr: w.x + w.w, r: i % 2 == 0 ? 18 : 0))
                b.append(WinBox(x0: w.x, x1: w.x + w.w, y0: w.y, y1: w.y + w.h, win: i))
            }
            l.append(Ledge(y: hPt - 60, x0: 807, x1: 1193, kind: 2, win: -1, ox: 800, wr: 1200, r: 22))
            sim.setLedges(l, windows: b)
            sim.topLimit = 40
            sim.cfg.storms = false
            sim.cfg.people = 3
            sim.cfg.agingRate = 6           // за прогон появятся и плотный снег, и наст
            sim.people.reseed(4242)
            sim.wind.reseed(UInt64(cell) * 101 + 7)
            sim.wind.profile = true
            sim.prefill()
            sim.forceFill = true; sim.fillSurfaces(); sim.forceFill = false
            var rng = Rng(seed: 99)
            let dt: Float = 1.0 / 60
            var t: Float = 0, nextStorm: Float = 5
            var worst = 0.0, worstAt: Float = 0, total = 0.0, slow = 0
            var maxParts = 0, maxChunks = 0, maxDust = 0, steps = 0
            let v0 = volume(sim)
            if calm { sim.cfg.gust = 0 }
            while t < seconds {
                t += dt
                if t >= nextStorm {
                    nextStorm += 40
                    let power = rng.range(0.7, 1), secs = rng.range(25, 36)
                    if !calm { sim.wind.startStorm(strength: power, dir: 0, seconds: secs) }
                    // погода и ветер тоже меняются: штиль, обычный, сильный, метель
                    var c = sim.cfg
                    c.wind = [0, 45, -45, 90, -90, 198, -198][Int(rng.next() % 7)]
                    if calm { c.wind = 0 }
                    let heavy = rng.f() < 0.4
                    c.flakeRate = heavy ? 110 : 14
                    c.gust = calm ? 0 : (heavy ? 60 : 6)
                    c.intensity = rng.f() < 0.25 ? 0 : (heavy ? 2.2 : 1)
                    sim.cfg = c
                }
                sim.setCursor(x: -100, y: -100, dt: dt, on: false)
                let w0 = sim.wind.totalStep
                // время процессора своего потока, а не часы: соседние сборки и тесты не мешают замеру
                let a = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
                sim.step(dt)
                let ms = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - a) * 1e-6
                if ms > 10 {
                    print(String(format: "  slow step %.2f ms at t=%.2f: wind.step %.3f ms, storm %.2f, wind %.0f, parts %d, chunks %d, spawns %d, deposits %d, people %d",
                                 ms, t, (sim.wind.totalStep - w0) * 1000, sim.wind.storm, sim.windNow, sim.parts.count, sim.wind.chunksAir,
                                 sim.statSpawns, sim.statDeposits, sim.people.folks.count))
                }
                total += ms
                steps += 1
                if ms > worst { worst = ms; worstAt = t }
                if ms > 10 { slow += 1 }
                maxParts = max(maxParts, sim.parts.count)
                maxChunks = max(maxChunks, sim.wind.chunksAir)
                maxDust = max(maxDust, sim.wind.dustAir)
            }
            let v1 = volume(sim)
            let w = sim.wind
            print(String(format: "stress cell=%.0f (%dx%d): %.0f s, %d storms; sim.step worst %.2f ms (t=%.0f), mean %.3f ms, steps over 10 ms: %d; wind.step worst %.3f ms, mean %.4f ms; max parts %d, max chunks %d, max dust %d; lifted %d (crust %d), drifted in %d, slabs %d (%d cells), blown in %d; cells %d -> %d",
                         cell, sim.W, sim.H, t, w.statStorms, worst, worstAt, total / Double(max(1, steps)), slow,
                         w.worstStep * 1000, w.totalStep * 1000 / Double(max(1, steps)), maxParts, maxChunks, maxDust,
                         w.statLifted, w.statChipped, w.statDrifted, w.statSlabs, w.statSlabCells, w.statBlownIn, v0.cells, v1.cells))
            if worst > 15 { print("  FAIL: step too slow"); fail += 1 }
            if maxParts > 30000 || maxChunks > 3000 { print("  FAIL: too many particles"); fail += 1 }
        }
        return fail
    }
}
