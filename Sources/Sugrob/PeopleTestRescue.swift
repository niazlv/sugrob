import AppKit

/// Самотесты завалов: `Sugrob --people-test <папка> rescue|rescue-fuzz [воксель] [пиксель] [секунд]`.
///  - rescue: завал и спасение; глубокий завал, палочка, её заметает; снег с карниза (avalanche);
///  - rescue-fuzz: быстрый случайный курсор сбрасывает снег с карнизов, сверху сыплются завалы,
///    окна двигают, человечков гонят и зовут — ищем падения, долгие шаги и застрявших под снегом.
enum RescueTest {
    static func run(_ st: PeopleStage, what: String, args: [String]) -> Int32 {
        what == "rescue-fuzz" ? fuzz(st, args) : scenes(st)
    }

    /// Высыпать над точкой (x, y) снег площадью как n комьев при вокселе 3 и «пикселе» 2.
    static func dump(_ st: PeopleStage, x: Float, y: Float, n: Int, spread: Float, _ rng: inout Rng) {
        let s = st.sim, k = st.unit / 2
        let cells = max(4, Int(Float(n) * 9 / (s.cell * s.cell) * k * k))
        for _ in 0..<cells where s.parts.count < s.maxParts {
            s.parts.append(Particle(x: x + rng.range(-spread, spread) * k, y: y - rng.range(44, 170) * k,
                                    vx: rng.range(-6, 6), vy: rng.range(120, 260), fall: 0, phase: 0, size: s.cell, alpha: 1,
                                    kind: 1, shade: rng.shade(), passer: false, ghost: 0, hard: 0))
        }
    }

    static func still(_ p: Person) -> Bool {
        p.job == .idle || p.job == .gaze || p.job == .cheer || p.job == .wave || (p.job == .fight && p.phase >= 1 && p.phase <= 3)
    }

    /// Человечек, который стоит на полу, а рядом (но не ближе apart «пикселей») есть хотя бы near свободных соседей.
    /// calm — ничем не занят (такой, увидев летящий сверху снег, замирает, а не уходит по делам) и стоит не под вторым окном.
    static func standing(_ st: PeopleStage, near: Int, apart: Float = 0, calm: Bool = false) -> Person? {
        let f = st.sim.people.folks
        for p in f where p.mode == .ground && p.stand == -2 && !p.away && still(p) && p.x > 120 && p.x < st.wPt - 120 {
            if calm && (p.job == .fight || (p.x > Float(st.wins[1].minX) - 40 && p.x < Float(st.wins[1].maxX) + 40)) { continue }
            let all = f.filter { $0.id != p.id && $0.mode == .ground && $0.stand == -2 && !$0.away
                && !($0.job == .hit && $0.phase >= 2) && abs($0.x - p.x) < 150 * st.unit }
            if all.count >= near && !all.contains(where: { abs($0.x - p.x) < apart * st.unit }) { return p }
        }
        return nil
    }

    /// Гонять симуляцию, пока условие не выполнится. false — не дождались.
    static func wait(_ st: PeopleStage, _ timeout: Float, step: Float = 0.1, _ ok: () -> Bool) -> Bool {
        var t: Float = 0
        while t < timeout {
            if ok() { return true }
            st.run(step)
            t += step
        }
        return ok()
    }

    static func crop(_ st: PeopleStage, _ x: Float, _ y: Float, w: Float = 150, up: Float = 120) -> CGRect {
        let k = CGFloat(st.unit / 2)
        return CGRect(x: CGFloat(x) - CGFloat(w) * k, y: CGFloat(y) - CGFloat(up) * k, width: CGFloat(w) * 2 * k, height: (CGFloat(up) + 22) * k)
    }

    /// Чтобы компания не разошлась посреди сценария.
    static func gather(_ st: PeopleStage, atLeast n: Int) {
        let pp = st.sim.people
        if pp.folks.filter({ $0.job != .leave }).count < n {
            pp.summon()
            st.run(9)
        }
        pp.visitEnd = st.sim.time + 900
    }

    static func scenes(_ st: PeopleStage) -> Int32 {
        let s = st.sim, pp = s.people
        var rng = Rng(seed: 99)
        var fails = 0
        func fail(_ m: String) { print("FAIL: " + m); fails += 1 }
        s.cfg.people = 2
        s.cfg.peopleLadders = false
        pp.summon()
        st.run(8)
        pp.visitEnd = s.time + 900

        // 1. Завал: на стоящего высыпается сугроб; соседи мечутся, бегут, откапывают
        if wait(st, 90, { standing(st, near: 2) != nil }), let v = standing(st, near: 2) {
            let c = crop(st, v.x, v.y)
            st.shot("r00-before", crops: [c], full: false)
            dump(st, x: v.x, y: v.y, n: 190, spread: 7, &rng)
            st.run(0.25); st.shot("r01-falling", crops: [c], full: false)
            _ = wait(st, 1.5, step: 0.05) { pp.folks.contains { $0.id == v.id && $0.job == .buried } }
            if !pp.folks.contains(where: { $0.id == v.id && $0.job == .buried }) { fail("nobody is buried by 190 chunks") }
            st.run(0.2); st.shot("r02-buried", crops: [c])
            st.run(0.45); st.shot("r03-panic", crops: [c], full: false)
            st.run(0.9); st.shot("r04-run", crops: [c], full: false)
            st.run(1.1); st.shot("r05-dig", crops: [c], full: false)
            st.run(0.2); st.shot("r05-dig-b", crops: [c], full: false)
            st.run(1.6); st.shot("r06-dig", crops: [c], full: false)
            let t0 = s.time
            let out = wait(st, 40, step: 0.05) { !pp.folks.contains { $0.id == v.id && $0.job == .buried } }
            if !out || pp.graves.contains(where: { $0.victim == v.id }) { fail("the buried one is not dug out") }
            print(String(format: "  dug out %.1f s later; %@", s.time - t0, RescueStats.line))
            st.run(0.15); st.shot("r07-out", crops: [c], full: false)
            st.run(0.6); st.shot("r08-saved", crops: [c])
            st.run(1.4); st.shot("r09-after", crops: [c], full: false)
        } else {
            fail("nobody stands still with neighbours")
        }

        // 2. Глубокий завал: не откопали — палочка, оплакивают, расходятся; палочку заметает
        st.run(6)
        gather(st, atLeast: 4)
        if wait(st, 180, { standing(st, near: 2, apart: 60) != nil }), let v = standing(st, near: 2, apart: 60) {
            let c = crop(st, v.x, v.y, up: 150)
            dump(st, x: v.x, y: v.y, n: 950, spread: 14, &rng)
            st.run(0.9); st.shot("r10-deep", crops: [c])
            if !pp.folks.contains(where: { $0.id == v.id && $0.job == .buried }) { fail("nobody is buried by the big dump") }
            st.run(3); st.shot("r11-dig", crops: [c], full: false)
            st.run(3); st.shot("r12-dig", crops: [c], full: false)
            let got = wait(st, 40, step: 0.05) { pp.graves.contains { $0.kind == 0 && $0.victim == v.id } }
            if !got { fail("no grave after the deep burial") }
            print("  \(RescueStats.line)")
            st.run(0.3); st.shot("r13-give-up", crops: [c], full: false)
            _ = wait(st, 8, step: 0.05) { pp.graves.contains { $0.kind == 0 && $0.planted } }
            st.shot("r14-planting", crops: [c], full: false)
            st.run(0.5); st.shot("r14-planting-b", crops: [c], full: false)
            st.run(1.5); st.shot("r15-mourn", crops: [c])
            st.run(2.5); st.shot("r16-mourn", crops: [c], full: false)
            st.run(2.3); st.shot("r16-mourn-b", crops: [c], full: false)
            st.run(6); st.shot("r17-leaving", crops: [c], full: false)
            st.run(8); st.shot("r18-left", crops: [c])
            // метель: палочку заметает
            s.cfg.intensity = 2.2
            s.cfg.flakeRate = 110
            s.cfg.wind = 60
            let t0 = s.time
            var k = 0
            while s.time - t0 < 500 && pp.graves.contains(where: { $0.kind == 0 }) {
                st.run(20)
                k += 1
                if k % 2 == 1 || !pp.graves.contains(where: { $0.kind == 0 }) {
                    st.shot(String(format: "r19-drift-%02d", k), crops: [c], full: false)
                }
            }
            if pp.graves.contains(where: { $0.kind == 0 }) { fail("the stick is still there after 500 s of blizzard") }
            print(String(format: "  the stick is covered %.0f s after the blizzard began; %@", s.time - t0, RescueStats.line))
            s.cfg.intensity = 1
            s.cfg.flakeRate = 14
            s.cfg.wind = 0
        } else {
            fail("nobody stands still with neighbours (2)")
        }

        // 3. Снег с карниза: окно подвигаем так, чтобы человечек оказался под его краем
        var hit = false
        for attempt in 0..<6 where !hit {
            st.run(4)
            gather(st, atLeast: 3)
            guard wait(st, 120, { standing(st, near: 1, calm: true) != nil }), let v = standing(st, near: 1, calm: true) else { fail("nobody stands still (3)"); break }
            let old = st.wins[0]
            let off = CGFloat(0.6 + 6 * st.unit)
            let right = CGFloat(v.x) - off - old.width > 20          // под правый край окна, если оно влезает слева
            let dx = right ? CGFloat(v.x) - off - old.maxX : CGFloat(v.x) + off - old.minX
            let cols = Int((Float(dx) / st.cell).rounded())
            st.wins[0] = old.offsetBy(dx: CGFloat(Float(cols) * st.cell), dy: 0)
            for sg in s.segs where sg.win == 100 { s.shiftPile(sg, cols: cols, rows: 0, vx: 0, vy: 0) }
            st.setWindows()
            s.forceFill = true; s.fillSurfaces(only: 100); s.forceFill = false
            let before = RescueStats.buried
            let c = crop(st, v.x, v.y, w: 170, up: 150)
            guard pp.avalanche(s) else { fail("avalanche() found no place though #\(v.id) stands under the edge"); continue }
            let edge = CGFloat(right ? st.wins[0].maxX : st.wins[0].minX)
            let top = CGRect(x: edge - 150, y: st.wins[0].minY - 70, width: 300, height: 190)
            let n = attempt * 10
            st.run(0.2); st.shot(String(format: "r%02d-avalanche", 20 + n), crops: [top, c], zoom: 2)
            st.run(0.3); st.shot(String(format: "r%02d-look-up", 21 + n), crops: [c], full: false)
            st.run(0.45); st.shot(String(format: "r%02d-landing", 22 + n), crops: [c], full: false)
            st.run(0.6); st.shot(String(format: "r%02d-landed", 23 + n), crops: [c], full: false)
            st.run(1.2); st.shot(String(format: "r%02d-then", 24 + n), crops: [c], full: false)
            st.run(2.5); st.shot(String(format: "r%02d-then", 25 + n), crops: [c], full: false)
            _ = wait(st, 40) { !pp.folks.contains { $0.job == .buried || $0.job == .rescue || $0.job == .panic } }
            st.run(1); st.shot(String(format: "r%02d-end", 26 + n), crops: [c])
            hit = RescueStats.buried > before
            print("  attempt \(attempt): \(hit ? "somebody is buried" : "everybody got away"); \(RescueStats.line)")
        }
        if !hit { fail("the avalanche buried nobody in 6 attempts") }

        // все расходятся; под снегом никого не остаётся
        s.cfg.people = 0
        st.run(40)
        st.shot("r90-gone")
        if !pp.folks.isEmpty { fail("somebody is still here: \(pp.summary)") }
        print("rescue test: \(RescueStats.line); fails \(fails)")
        return fails == 0 ? 0 : 1
    }

    static func fuzz(_ st: PeopleStage, _ args: [String]) -> Int32 {
        let s = st.sim, pp = s.people
        var rng = Rng(seed: UInt64(st.cell * 1000) &+ UInt64(st.unit) &+ 4711)
        let secs = Float(args.first ?? "") ?? 600
        s.cfg.people = 3
        s.cfg.peopleEvents = true
        s.cfg.agingRate = 4
        pp.summon()
        st.curOn = true
        st.cur = SIMD2(700, 400)
        var target = SIMD2<Float>(700, 700)
        var speed: Float = 600
        var worst = 0.0, slow = 0, bad = 0
        var since: [Int32: Float] = [:]
        var longest: Float = 0, maxFolks = 0, maxGraves = 0, dumps = 0
        while s.time < secs {
            let d = target - st.cur
            let dist = (d.x * d.x + d.y * d.y).squareRoot()
            if dist < 4 || rng.f() < 0.003 {
                let r = rng.f()
                let folks = pp.folks
                if r < 0.5, !s.segs.isEmpty {
                    // встать над карнизом и быстро проехать за его край: снег летит вниз, на тех, кто там стоит
                    let seg = s.segs[Int(rng.next() % UInt64(s.segs.count))]
                    let dir: Float = rng.f() < 0.5 ? -1 : 1
                    let edge = dir < 0 ? seg.x0 : seg.x1
                    st.cur = SIMD2(edge - dir * rng.range(50, 160), seg.y - rng.range(2, 14))
                    target = SIMD2(edge + dir * rng.range(10, 50), seg.y - rng.range(0, 12))
                    speed = [250, 600, 1200][Int(rng.next() % 3)]
                } else if r < 0.8, !folks.isEmpty {
                    let p = folks[Int(rng.next() % UInt64(folks.count))]
                    target = SIMD2(p.x + rng.range(-60, 60), p.y - rng.range(0, 50))
                    speed = [60, 300, 900, 2500][Int(rng.next() % 4)]
                } else {
                    target = SIMD2(rng.range(0, st.wPt), rng.range(100, st.hPt))
                    speed = [300, 900, 2500][Int(rng.next() % 3)]
                }
            } else {
                st.cur += d / dist * min(dist, speed * st.dt)
            }
            s.setCursor(x: st.cur.x, y: st.cur.y, dt: st.dt, on: true)
            if rng.f() < 0.002 {                // завал сверху: мелкий, обычный или глубокий
                let f = pp.folks.filter { $0.mode == .ground && !$0.away }
                if !f.isEmpty {
                    let p = f[Int(rng.next() % UInt64(f.count))]
                    dump(st, x: p.x, y: p.y, n: [50, 150, 300, 700][Int(rng.next() % 4)], spread: rng.range(3, 14), &rng)
                    dumps += 1
                }
            }
            if rng.f() < 0.0015 { _ = pp.avalanche(s) }
            if rng.f() < 0.002 { s.forceFill = true; s.fillSurfaces(); s.forceFill = false }      // на карнизах снова снег
            if rng.f() < 0.0006 {               // окно двигают
                let k = Int(rng.next() % UInt64(st.wins.count))
                let old = st.wins[k]
                st.wins[k] = old.offsetBy(dx: CGFloat(rng.range(-50, 50)), dy: CGFloat(rng.range(-30, 30)))
                func c(_ v: CGFloat) -> Int { Int((Float(v) / st.cell).rounded()) }
                for sg in s.segs where sg.win == k + 100 {
                    s.shiftPile(sg, cols: c(st.wins[k].minX) - c(old.minX), rows: c(st.wins[k].minY) - c(old.minY), vx: 400, vy: 0)
                }
                st.setWindows()
            }
            if rng.f() < 0.0003 { pp.summon() }
            if rng.f() < 0.0001 { s.cfg.people = s.cfg.people == 0 ? 3 : 0 }
            if rng.f() < 0.00004 { pp.clearAll(s) }
            if rng.f() < 0.0002 {               // метель то начинается, то стихает
                let on = s.cfg.flakeRate < 50
                s.cfg.flakeRate = on ? 110 : 14
                s.cfg.intensity = on ? 2.2 : 1
                s.cfg.wind = on ? rng.range(-100, 100) : 0
            }
            let t1 = CACurrentMediaTime()
            s.step(st.dt)
            let ms = (CACurrentMediaTime() - t1) * 1000
            if ms > 15 {
                slow += 1
                print(String(format: "slow step %.1f ms at t=%.1f: parts %d, %@", ms, s.time, s.parts.count, pp.summary))
            }
            worst = max(worst, ms)
            maxFolks = max(maxFolks, pp.folks.count)
            maxGraves = max(maxGraves, pp.graves.count)
            var seen = Set<Int32>()
            for p in pp.folks {
                if !p.x.isFinite || !p.y.isFinite || p.y < -200 || p.y > st.hPt + 200 {
                    print("BAD person at \(p.x),\(p.y) job \(p.job) mode \(p.mode) t=\(s.time)")
                    return 1
                }
                if p.job == .buried {
                    seen.insert(p.id)
                    let t0 = since[p.id] ?? s.time
                    since[p.id] = t0
                    longest = max(longest, s.time - t0)
                    if s.time - t0 > 130 && bad < 5 { bad += 1; print("BAD: #\(p.id) is under the snow for \(s.time - t0) s at \(p.x),\(p.y); \(pp.summary)") }
                }
            }
            since = since.filter { seen.contains($0.key) }
            for g in pp.graves where !g.x.isFinite || !g.topY.isFinite { print("BAD grave \(g)"); return 1 }
        }
        print(String(format: "rescue fuzz cell=%.0f unit=%.0f: %.0f s, worst step %.2f ms (%d over 15 ms), max people %d, max graves %d, dumps %d, longest under the snow %.0f s, parts %d",
                     st.cell, st.unit, s.time, worst, slow, maxFolks, maxGraves, dumps, longest, s.parts.count))
        print("  \(RescueStats.line)")
        print("  \(pp.summary)")
        st.shot("rf-end")
        return worst < 15 && bad == 0 ? 0 : 1
    }
}
