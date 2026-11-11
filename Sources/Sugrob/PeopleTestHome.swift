import AppKit

/// Самотесты домов: `Sugrob --people-test <папка> <сценарий> [воксель] [пиксель] [секунд]`.
/// home — пара остаётся, ровняет площадку, вырезает и носит блоки, строит иглу, живёт (свет, лопата, костёр),
///        рядом селится вторая пара, поселение обустраивают; потом все уходят, иглу заносит, оно становится сугробом;
/// home-light — то же на фоне светлого окна;
/// home-look — иглу, костры, фонарики, флажки во всех видах без человечков (быстро посмотреть рисунок);
/// home-base — основание: выгребли снег из-под жилого дома — чинят; из-под брошенного — блоки падают, дом садится;
/// home-smash — удары курсором и шарами: чинят; обрушение — отстраивают заново;
/// home-dump — на дом сыплют снег: дом не поднимается, снег лежит на куполе; вход завалило — откапывают; некому — гибнут;
/// home-family — ребёнок у пары, оставшийся один знакомится с гостем, ребёнок вырастает и строит свой дом;
/// home-storm — в буран жители сидят дома;
/// home-village — три дома: тропинки, общий костёр, фонарики, флажки;
/// home-fuzz — стресс: быстрый курсор, шары и снег по иглу, бураны, частые приходы, всё ускорено.
enum HomeTest {
    static func run(_ st: PeopleStage, what: String, args: [String]) -> Int32 {
        defer { HomeTune.coverSpeed = 1; HomeTune.siteX = nil; HomeTune.evening = nil; HomeTune.trapLimit = 150; HomeTune.family = 1 }
        HomeTune.evening = false
        switch what {
        case "home-look": return look(st)
        case "home-fuzz": return fuzz(st, args)
        case "home-light": return story(st, light: true)
        case "home-base": return base(st)
        case "home-smash": return smash(st)
        case "home-dump": return dumpTest(st)
        case "home-family": return family(st)
        case "home-storm": return storm(st)
        case "home-village": return village(st)
        default: return story(st, light: false)
        }
    }

    // MARK: - Подручное

    /// Светлое окно до самого низа экрана: фон за иглу — почти белый.
    static func lightWindow(_ st: PeopleStage) {
        st.wins[0] = CGRect(x: 330, y: 190, width: 430, height: 660)
        st.setWindows()
    }

    /// Ждать, пока не выполнится условие. false — не дождались.
    static func wait(_ st: PeopleStage, _ maxSec: Float, step: Float = 0.2, _ cond: () -> Bool) -> Bool {
        let end = st.sim.time + maxSec
        while st.sim.time < end {
            if cond() { return true }
            st.run(step)
        }
        return cond()
    }

    /// Вырезка вокруг всех иглу.
    static func crop(_ st: PeopleStage, pad: Float = 70, up: Float = 46) -> CGRect {
        let pp = st.sim.people, u = st.unit
        guard !pp.igloos.isEmpty else { return st.around() }
        let x0 = max(0, CGFloat(pp.igloos.map { $0.x }.min()! - pad * u)), x1 = min(CGFloat(st.wPt), CGFloat(pp.igloos.map { $0.x }.max()! + pad * u))
        let y0 = CGFloat(pp.igloos.map { $0.baseY }.min()! - up * u)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: CGFloat(st.hPt) - y0)
    }

    static func shot(_ st: PeopleStage, _ name: String, full: Bool = false, pad: Float = 70, up: Float = 46) {
        st.shot(name, crops: [crop(st, pad: pad, up: up)], zoom: st.unit > 2 ? 2 : 3, full: full)
        print("    " + st.sim.people.homeSummary)
    }

    /// Высыпать над точкой x n комьев снега (с высоты от h0 до h1 над y).
    static func dump(_ st: PeopleStage, x: Float, y: Float, n: Int, spread: Float, _ rng: inout Rng) {
        let s = st.sim
        for _ in 0..<n where s.parts.count < s.maxParts {
            s.parts.append(Particle(x: x + rng.range(-spread, spread), y: y - rng.range(60, 260),
                                    vx: rng.range(-6, 6), vy: rng.range(120, 260), fall: 0, phase: 0, size: s.cell, alpha: 1,
                                    kind: 1, shade: rng.shade(), passer: false, ghost: 0, hard: 0))
        }
    }

    /// Добиться, чтобы иглу стало не меньше n: гости есть, желание остаться есть.
    static func settle(_ st: PeopleStage, _ n: Int) -> Bool {
        let sim = st.sim, pp = sim.people
        for _ in 0..<10 {
            if pp.igloos.count >= n { return true }
            pp.summon()
            st.run(0.2)
            pp.visitEnd = max(pp.visitEnd, sim.time + 150)
            pp.visitStart = sim.time - 30
            pp.settleWish = true
            if wait(st, 40, { pp.igloos.count >= n }) { return true }
        }
        return pp.igloos.count >= n
    }

    // MARK: - Рисунок

    static func look(_ st: PeopleStage) -> Int32 {
        let sim = st.sim, pp = sim.people
        let u = st.unit
        pp.u = u
        lightWindow(st)
        HomeTune.evening = true
        let xs: [Float] = [405, 545, 685, 850, 1010, 1170]
        @discardableResult
        func add(_ x: Float, door: Float, laid: Int? = nil, cover: Float = 0, inside: Int = 0, knock: Int = 0) -> Int {
            let k = pp.debugPlace(sim, x: x, door: door, laid: laid)
            var g = pp.igloos[k]
            let geo = IglooGeo.of(door)
            for j in 0..<knock { g.blocks[(j * 7 + 9) % geo.count] = false }
            if knock > 0 { pp.unsupported(&g, sim) }
            g.cover = cover
            g.inside = inside
            pp.igloos[k] = g
            return k
        }
        func fire(_ x: Float, age: Float, left: Float, big: Bool = false) {
            var f = Fire(id: pp.nextObjId, x: x, y: pp.surface(sim, x: x, stand: -2) ?? 780, born: sim.time - age, until: sim.time + left)
            f.big = big
            pp.fires.append(f)
            pp.nextObjId += 1
        }
        let crops = [CGRect(x: 330, y: 640, width: 430, height: 160), CGRect(x: 770, y: 640, width: 490, height: 160)]
        let geo = IglooGeo.left
        print("igloo: \(geo.count) blocks, \(geo.px.count) px, block cost \(pp.blockCost(sim)) cells; rows \(geo.row)")
        // а: целое с фонариком, со светом, наполовину (видна дальняя стенка), штабель и приступка
        for h in 0..<2 {
            let a = add(xs[h * 3], door: -1)
            pp.igloos[a].lantern = 0
            add(xs[h * 3 + 1], door: 1, inside: 1)
            let c = add(xs[h * 3 + 2], door: -1, laid: geo.count / 2)
            pp.igloos[c].stack = h == 0 ? 2 : 3
        }
        st.shot("look-a", crops: crops, zoom: 3)
        pp.igloos.removeAll()
        // б: начато, три ряда, верхний ряд с приступкой; побитое со светом
        for h in 0..<2 {
            add(xs[h * 3], door: -1, laid: 5)
            let b = add(xs[h * 3 + 1], door: 1, laid: 21)
            pp.igloos[b].stool = true
            add(xs[h * 3 + 2], door: -1, inside: 1, knock: 6)
        }
        st.shot("look-b", crops: crops, zoom: 3)
        pp.igloos.removeAll()
        // в: занос
        for h in 0..<2 {
            add(xs[h * 3], door: -1, cover: 0.14)
            add(xs[h * 3 + 1], door: 1, cover: 0.45, inside: 1)
            add(xs[h * 3 + 2], door: -1, cover: 0.8)
        }
        st.shot("look-c", crops: crops, zoom: 3)
        pp.igloos.removeAll()
        // г: поселение — флажки, фонарики, общий костёр
        for h in 0..<2 {
            let a = add(xs[h * 3], door: 1, inside: 1), b = add(xs[h * 3 + 2] - 20, door: -1)
            pp.igloos[a].lantern = 0; pp.igloos[b].lantern = 0
            pp.igloos[a].flagTo = pp.igloos[b].id
            pp.igloos[a].flagK = h == 0 ? 1 : 0.6
            fire((xs[h * 3] + xs[h * 3 + 2] - 20) / 2, age: 20, left: 60, big: true)
        }
        st.shot("look-d", crops: crops, zoom: 3)
        pp.igloos.removeAll(); pp.fires.removeAll()
        return 0
    }

    // MARK: - История

    static func story(_ st: PeopleStage, light: Bool) -> Int32 {
        let sim = st.sim, pp = sim.people
        let u = st.unit
        let t0 = CACurrentMediaTime()
        var ok = true
        func fail(_ m: String) { print("FAIL: " + m + " | " + pp.homeSummary); ok = false }
        if light {
            lightWindow(st)
            HomeTune.siteX = 545
            st.run(2)
        }
        sim.cfg.people = 2
        sim.cfg.peopleLadders = false
        guard settle(st, 1) else { print("FAIL: nobody settled"); st.shot("h-fail", crops: [st.around()]); return 1 }
        let id0 = pp.igloos[0].id, base0 = pp.igloos[0].baseY
        func g0() -> Igloo? { pp.igloos.first(where: { $0.id == id0 }) }
        func mine(_ f: (Person) -> Bool) -> Bool { pp.folks.contains(where: { $0.home == id0 && $0.job == .igloo && f($0) }) }

        // стройка
        let tb = sim.time
        if wait(st, 60, { mine { $0.phase == 21 } }) { shot(st, "h01-leveling", full: true) } else { fail("no levelling") }
        if wait(st, 120, { mine { $0.phase == 4 && $0.t > 1.3 } }) { shot(st, "h02-carving") } else { fail("no block carving") }
        if wait(st, 60, { mine { $0.phase == 6 && $0.t > 0.6 } }) { shot(st, "h03-carrying") } else { fail("nobody carries a block") }
        if wait(st, 60, { mine { $0.phase == 7 && $0.t > 0.25 && $0.t < 0.6 } }) { shot(st, "h04-laying") } else { fail("nobody lays a block") }
        if wait(st, 300, { (g0()?.laid ?? 0) * 2 >= (g0()?.blocks.count ?? 1) && mine { $0.phase == 6 } }) { shot(st, "h05-half") } else { fail("half not reached") }
        if wait(st, 400, { mine { $0.phase == 11 && $0.flag && $0.t > 0.3 } }) { shot(st, "h06-top-row") } else { fail("no top row from the stool") }
        guard wait(st, 500, { g0()?.built ?? false }) else { fail("igloo not built in \(Int(sim.time - tb)) s"); shot(st, "h-fail"); return 1 }
        print(String(format: "igloo built in %.0f s", sim.time - tb))
        st.run(0.7)
        shot(st, "h07-built", full: true)

        // жизнь: свет во входе, лопата, костёр
        if wait(st, 400, { (g0()?.inside ?? 0) > 0 }) { st.run(1); shot(st, "h08-light") } else { fail("nobody went inside") }
        if wait(st, 500, { pp.folks.contains(where: { $0.job == .shovel && $0.phase == 1 && $0.t > 0.6 }) }) { shot(st, "h09-shovel") } else { fail("nobody shovelled") }
        if wait(st, 600, { pp.folks.contains(where: { $0.job == .fire && $0.phase == 3 && $0.t > 1.5 }) && !pp.fires.isEmpty }) { shot(st, "h10-fire") } else { fail("no fire") }

        // вторая пара селится рядом; поселение обустраивают
        HomeTune.evening = true
        if settle(st, 2) {
            for k in pp.igloos.indices { pp.igloos[k].until = sim.time + 100000 }       // пока не обустроятся — не уходят
            if wait(st, 900, { pp.igloos.count >= 2 && pp.igloos.allSatisfy { $0.built } }) {
                shot(st, "h11-second-built")
                let t1 = sim.time
                // флажки и тропинка — только между соседними домами (не дальше 80u)
                let near = pp.igloos.indices.contains(where: { pp.rightOf($0) != nil })
                if !near { print("  (the second home is not next to the first: no flags and no path expected)") }
                let first = Set(pp.igloos.map { $0.id })        // новые дома, которые появятся позже, не в счёт
                var bigFire = false
                let done = wait(st, 900, {
                    if pp.fires.contains(where: { $0.big }) { bigFire = true }
                    return pp.igloos.allSatisfy { !first.contains($0.id) || $0.lantern >= 0 } && bigFire
                        && (!near || (pp.igloos.contains(where: { $0.flagK >= 1 }) && pp.igloos.contains(where: { $0.pathTo >= 0 })))
                })
                if !done { fail("village not finished (lanterns, flags, path, common fire)") }
                print(String(format: "village amenities in %.0f s", sim.time - t1))
                _ = wait(st, 200, { pp.fires.contains(where: { $0.big }) && pp.folks.filter { $0.job == .fire && $0.phase == 3 }.count >= 2 })
                shot(st, "h12-village", full: true)
            } else { fail("second igloo not built") }
        } else { fail("second pair did not settle") }
        if let g = g0(), abs(g.baseY - base0) > 0.01 { fail(String(format: "house moved: baseY %.1f -> %.1f", base0, g.baseY)) }
        else { print(String(format: "house stood still for %.0f s (baseY %.1f)", sim.time - tb, base0)) }

        // уходят (и новые гости в брошенные дома не вселяются)
        HomeTune.evening = false
        sim.cfg.peopleStay = false
        pp.debugHurry(sim)
        st.run(9)
        shot(st, "h13-leaving")
        if !wait(st, 200, { pp.igloos.allSatisfy { $0.abandoned >= 0 } }) { fail("residents did not leave") }
        st.run(12)
        shot(st, "h14-abandoned")

        // метель: брошенные иглу заносит
        sim.cfg.flakeRate = 110; sim.cfg.intensity = 2.2; sim.cfg.gust = 40
        HomeTune.coverSpeed = 2
        let tc = sim.time
        for mark in [0.35, 0.7] as [Float] {
            if wait(st, 400, { pp.igloos.isEmpty || pp.igloos.contains(where: { $0.cover >= mark }) }) {
                shot(st, String(format: "h15-cover%02d", Int(mark * 100)))
            }
        }
        let c0 = st.cells()
        if wait(st, 400, { pp.igloos.isEmpty }) {
            print(String(format: "covered in %.0f s of blizzard (x%.0f); grid cells %d -> %d", sim.time - tc, HomeTune.coverSpeed, c0, st.cells()))
            st.run(1)
            st.shot("h16-drift", crops: [CGRect(x: 0, y: CGFloat(base0 - 46 * u), width: CGFloat(st.wPt), height: CGFloat(st.hPt - base0 + 46 * u))], zoom: 2)
            if sim.mask.contains(where: { $0 >= 251 }) { fail("igloo mask left behind") }
        } else { fail("igloo did not turn into a drift") }
        print(String(format: "home test: %.0f s simulated in %.1f s, %@", sim.time, CACurrentMediaTime() - t0, ok ? "OK" : "FAILED"))
        return ok ? 0 : 1
    }

    // MARK: - Основание

    static func base(_ st: PeopleStage) -> Int32 {
        let sim = st.sim, pp = sim.people
        let u = st.unit
        var ok = true
        func fail(_ m: String) { print("FAIL: " + m + " | " + pp.homeSummary); ok = false }
        sim.cfg.people = 2
        sim.cfg.peopleLadders = false
        pp.u = u
        pp.visitEnd = sim.time + 100000
        let k = pp.debugHouse(sim, x: 700, door: -1)
        let id = pp.igloos[k].id
        func g() -> Igloo { pp.igloos.first(where: { $0.id == id }) ?? Igloo(id: -1, x: 0, baseY: 0, born: 0) }
        st.run(6)
        let base0 = g().baseY
        /// Выгрести снег из-под дома: столбцы от доли a до доли b ширины площадки, сверху depth ячеек (0 — весь).
        func dig(_ a: Float, _ b: Float, depth: Int, bottomOnly: Bool = false) {
            let gg = g()
            let n = gg.c1 - gg.c0 + 1
            for c in (gg.c0 + Int(Float(n) * a))...(gg.c0 + min(n - 1, Int(Float(n) * b))) {
                if bottomOnly { for r in max(gg.floorRow + 2, sim.H - 2)..<sim.H { sim.snow[r * sim.W + c] = 0 } }
                else { for r in gg.floorRow..<(depth == 0 ? sim.H : min(sim.H, gg.floorRow + depth)) { sim.snow[r * sim.W + c] = 0 } }
            }
            sim.gridDirty = true
            sim.snowDisturbed(gg.c0 - 1, gg.floorRow - 1, gg.c1 + 1, sim.H - 1)
        }
        // «на треть блока и глубже» — в ячейках; но под домом должно остаться хоть сколько-то снега
        let deep = max(1, min(Int(5 * u / sim.cell) + 1, sim.H - g().floorRow - 2))
        // 1. под жилым домом: пустота у самого низа
        dig(0.55, 0.95, depth: 0, bottomOnly: true)
        st.run(1.2)
        print("void under the house: need \(g().baseNeed)")
        if wait(st, 120, step: 0.05, { pp.folks.contains(where: { $0.job == .igloo && $0.phase == 21 }) }) { shot(st, "b01-void-filling") }
        else { print("  (the void closed by itself: nobody was seen filling it)") }
        if !wait(st, 240, { g().baseNeed < 3 && g().laid == g().blocks.count }) { fail("void not fixed") }
        // 2. выгребли весь снег из-под середины дома: блоки над ямой падают, жители засыпают и кладут заново
        dig(0.35, 0.65, depth: 0)
        st.run(0.7)
        let fell = g().blocks.count - g().laid
        if fell == 0 { fail("blocks over the pit did not fall") }
        shot(st, "b02-dug-out")
        if wait(st, 120, step: 0.05, { pp.folks.contains(where: { $0.job == .igloo && $0.phase == 21 && $0.t > 0.15 }) }) { shot(st, "b02-pit-filling") }
        else { print("  (the pit was filled by the debris: nobody was seen filling it)") }
        if wait(st, 60, { pp.folks.contains(where: { $0.job == .igloo && ($0.phase == 6 || $0.phase == 7) }) }) { shot(st, "b03-relaying") }
        if wait(st, 500, { g().baseNeed < 3 && g().laid == g().blocks.count }) { st.run(1.5); shot(st, "b04-repaired") } else { fail("house not repaired") }
        print("pit: \(fell) blocks fell, repaired; baseY \(base0) -> \(g().baseY)")
        if abs(g().baseY - base0) > 0.01 { fail("lived-in house moved") }
        // 3. брошенный: осела вся площадка — дом рывком садится на новый уровень
        pp.debugHurry(sim)
        if !wait(st, 200, { g().abandoned >= 0 }) { fail("residents did not leave") }
        st.run(10)
        if pp.igloos.contains(where: { $0.id == id }) {
            let y0 = g().baseY
            dig(0, 1, depth: deep)
            st.run(1.5)
            print(String(format: "abandoned house settles: baseY %.1f -> %.1f, %d blocks left", y0, g().baseY, g().laid))
            if !pp.igloos.contains(where: { $0.id == id }) { print("  (the abandoned house fell apart when the snow was dug from under it)") }
            else if g().baseY <= y0 {
                if sim.cell >= 5 { print("  (coarse grid: the snow slid back under the house, it did not have to settle)") }
                else { fail("abandoned house did not settle") }
            }
            shot(st, "b05-settled")
        } else { print("  (the abandoned house fell apart before the test could dig under it)") }
        // 4. выгребли из-под середины — никто не чинит: блоки над провалом падают
        if pp.igloos.contains(where: { $0.id == id }) {
            let before = g().laid
            dig(0.35, 0.65, depth: 0)
            st.run(1.5)
            shot(st, "b06-abandoned-sag")
            if pp.igloos.contains(where: { $0.id == id }) && g().laid >= before { fail("abandoned: blocks over the pit did not fall") }
            st.run(25)
            if pp.igloos.contains(where: { $0.id == id }) { print("  abandoned house: \(g().laid) of \(g().blocks.count) blocks left"); shot(st, "b07-later") }
            else { print("  abandoned house fell apart completely") }
        }
        print("home base: " + (ok ? "OK" : "FAILED"))
        return ok ? 0 : 1
    }

    // MARK: - Поломки

    static func smash(_ st: PeopleStage) -> Int32 {
        let sim = st.sim, pp = sim.people
        let u = st.unit
        var ok = true
        func fail(_ m: String) { print("FAIL: " + m + " | " + pp.homeSummary); ok = false }
        sim.cfg.people = 2
        sim.cfg.peopleLadders = false
        pp.u = u
        pp.visitEnd = sim.time + 100000
        let k = pp.debugHouse(sim, x: 700, door: 1)
        let id = pp.igloos[k].id
        func g() -> Igloo? { pp.igloos.first(where: { $0.id == id }) }
        st.run(4)
        let gx = pp.igloos[k].x, gy = pp.igloos[k].baseY
        let all = pp.igloos[k].blocks.count
        // резкий взмах курсора сквозь купол
        st.curOn = true
        st.cur = SIMD2(gx - 220, gy - 12 * u)
        st.run(0.05)
        st.run(0.2, to: SIMD2(gx + 220, gy - 12 * u))
        st.curOn = false
        st.cur = SIMD2(-100, -100)
        st.run(0.1)
        shot(st, "s01-poked")
        if (g()?.laid ?? all) >= all { fail("cursor did not knock anything out") }
        if wait(st, 300, { g().map { $0.laid == all } ?? false }) { st.run(1.3); shot(st, "s02-repaired") } else { fail("not repaired after the cursor") }
        // один шар — чинят
        func ball(_ side: Float) {
            sim.balls.removeAll { !$0.held && $0.parent == -1 && !$0.hasChild }
            st.curOn = true
            st.cur = SIMD2(gx + side * 260, gy - 45 * u)
            st.run(0.05)
            sim.handsMode = true
            sim.grabBegin()
            st.run(0.12, to: SIMD2(gx + side * 90, gy - 16 * u))
            sim.grabEnd()
            sim.handsMode = false
            st.curOn = false
            st.cur = SIMD2(-100, -100)
            st.run(0.25)
        }
        ball(-1)
        shot(st, "s03-ball")
        if (g()?.laid ?? all) >= all { fail("ball did not knock anything out") }
        if wait(st, 300, { g().map { $0.laid == all } ?? false }) { st.run(1.3); shot(st, "s04-ball-repaired") } else { fail("not repaired after the ball") }
        _ = wait(st, 300, { (g()?.inside ?? 0) > 0 })
        // шары, пока не рухнет
        var n = 0
        while (g()?.built ?? false) && n < 40 {
            ball(n % 2 == 0 ? -1 : 1)
            n += 1
        }
        if g()?.built ?? true { fail("igloo survived \(n) balls") } else { print("igloo collapsed after \(n) balls") }
        shot(st, "s05-collapse")
        if g() == nil { fail("lived-in igloo was removed after the collapse") }
        if wait(st, 120, step: 0.1, { pp.folks.contains(where: { $0.job == .igloo && $0.phase == 30 && $0.flag && $0.t > 0.8 }) }) { shot(st, "s06-grief") } else { fail("nobody grieved over the ruins") }
        let tr = sim.time
        if wait(st, 200, { (g()?.laid ?? 0) >= 6 }) { shot(st, "s07-rebuilding") } else { fail("no rebuilding") }
        if wait(st, 1300, { g()?.built ?? false }) {
            st.run(1.5)
            print(String(format: "rebuilt in %.0f s", sim.time - tr))
            shot(st, "s08-rebuilt")
        } else { fail("not rebuilt") }
        for p in pp.folks where p.mode == .inside && p.home == id && !(g()?.built ?? false) { fail("person \(p.id) is inside a ruin") }
        print("home smash: " + (ok ? "OK" : "FAILED"))
        return ok ? 0 : 1
    }

    // MARK: - Снег на дом, заваленный вход

    static func dumpTest(_ st: PeopleStage) -> Int32 {
        let sim = st.sim, pp = sim.people
        let u = st.unit
        var ok = true
        var rng = Rng(seed: 99)
        func fail(_ m: String) { print("FAIL: " + m + " | " + pp.homeSummary); ok = false }
        sim.cfg.people = 2
        sim.cfg.peopleLadders = false
        pp.u = u
        pp.visitEnd = sim.time + 100000
        let k = pp.debugHouse(sim, x: 700, door: -1)
        let id = pp.igloos[k].id
        func g() -> Igloo { pp.igloos.first(where: { $0.id == id }) ?? Igloo(id: -1, x: 0, baseY: 0, born: 0) }
        st.run(3)
        let base0 = g().baseY
        let scale = Int(9 / (sim.cell * sim.cell) * (u / 2) * (u / 2) * 100)      // столько же снега по площади при любом вокселе
        // 1. сыплем снег: дом стоит, снег — на куполе и вокруг
        dump(st, x: 700, y: base0 - 30 * u, n: 400 * scale / 100, spread: 20 * u, &rng)
        st.run(2.5)
        shot(st, "d01-snow-on-dome", full: true)
        print(String(format: "dumped %d chunks: roof %d cells, bury %.2f, baseY %.1f -> %.1f", 400 * scale / 100, g().roof, g().bury, base0, g().baseY))
        if abs(g().baseY - base0) > 0.01 { fail("house moved under the snow") }
        if g().roof < 20 { fail("snow does not lie on the dome") }
        if wait(st, 60, { pp.folks.contains(where: { $0.job == .shovel && $0.phase == 1 && $0.t > 1 }) }) { shot(st, "d02-shovelling") } else { fail("nobody shovels the dome") }
        if wait(st, 400, { g().roof < g().c1 - g().c0 + 1 }) { st.run(1); shot(st, "d03-clean") } else { fail("dome not cleaned: roof \(g().roof)") }
        if abs(g().baseY - base0) > 0.01 { fail("house moved while cleaning") }
        // 2. один дома, второй снаружи; вход завалило — откапывают
        guard wait(st, 600, { g().inside == 1 }) else { fail("nobody went inside"); return 1 }
        for j in pp.folks.indices where pp.folks[j].home == id && pp.folks[j].mode == .ground && abs(pp.folks[j].x - 700) < 60 * u {
            pp.folks[j].x = 700 + 70 * u            // того, кто снаружи, — в сторонку: под снег он попасть не должен
            pp.folks[j].y = pp.surface(sim, x: pp.folks[j].x, stand: -2) ?? pp.folks[j].y
        }
        dump(st, x: 700, y: base0 - 30 * u, n: 700 * scale / 100, spread: 16 * u, &rng)
        if wait(st, 20, { g().trappedAt >= 0 }) {
            st.run(2.5)
            shot(st, "d04-trapped")
            if wait(st, 100, { pp.folks.contains(where: { $0.job == .shovel && $0.phase == 31 && $0.t > 1 }) }) { shot(st, "d05-digging-out") } else { fail("nobody digs the door out") }
            if wait(st, 300, { g().trappedAt < 0 }) {
                st.run(1)
                shot(st, "d06-freed")
                if pp.folks.filter({ $0.home == id }).count != 2 { fail("someone was lost") }
            } else { fail("not dug out") }
        } else { fail(String(format: "door not blocked: bury %.2f roof %d", g().bury, g().roof)) }
        // 3. оба дома, снаружи никого — не дождались
        _ = wait(st, 600, { g().roof < g().c1 - g().c0 + 1 })
        for j in pp.folks.indices where pp.folks[j].home != id { pp.folks[j].gone = true }
        sim.cfg.people = 0
        pp.forced = true
        let doorX = g().x + IglooGeo.of(g().door).doorX * u
        for j in pp.folks.indices where pp.folks[j].home == id {            // все свои — дома
            pp.folks[j].job = .home
            pp.folks[j].phase = 2; pp.folks[j].t = 0; pp.folks[j].flag = false
            pp.folks[j].mode = .inside
            pp.folks[j].carry = 0
            pp.folks[j].wait = 1000
            pp.folks[j].x = doorX
            pp.folks[j].y = g().baseY
        }
        st.run(0.3)
        if g().inside < 2 { fail("could not get the residents inside: in \(g().inside)") }
        HomeTune.trapLimit = 25
        dump(st, x: 700, y: base0 - 30 * u, n: 900 * scale / 100, spread: 16 * u, &rng)
        if wait(st, 20, { g().trappedAt >= 0 }) {
            st.run(3)
            shot(st, "d07-trapped-alone")
            if wait(st, 60, { g().inside == 0 && g().abandoned >= 0 }) {
                st.run(2)
                shot(st, "d08-dark")
                print("nobody came: residents lost, graves \(pp.graves.count), people left \(pp.folks.count)")
                if pp.folks.contains(where: { $0.home == id }) { fail("ghost resident") }
            } else { fail("trapped residents neither freed nor lost") }
        } else { fail(String(format: "door not blocked (2): bury %.2f", g().bury)) }
        print("home dump: " + (ok ? "OK" : "FAILED"))
        return ok ? 0 : 1
    }

    // MARK: - Семья

    static func family(_ st: PeopleStage) -> Int32 {
        let sim = st.sim, pp = sim.people
        let u = st.unit
        var ok = true
        func fail(_ m: String) { print("FAIL: " + m + " | " + pp.homeSummary); ok = false }
        sim.cfg.people = 2
        sim.cfg.peopleLadders = false
        pp.u = u
        pp.visitEnd = sim.time + 100000
        HomeTune.family = 12
        let k = pp.debugHouse(sim, x: 700, door: -1)
        let id = pp.igloos[k].id
        func g() -> Igloo { pp.igloos.first(where: { $0.id == id }) ?? Igloo(id: -1, x: 0, baseY: 0, born: 0) }
        // 1. ребёнок
        if wait(st, 400, { !g().kids.isEmpty }) {
            st.run(1.5)
            shot(st, "f01-child")
            print(String(format: "child born at t=%.0f; people %d", sim.time, pp.folks.count))
        } else { fail("no child") }
        if wait(st, 400, { g().kids.count + g().grown.count >= 2 }) { st.run(2); shot(st, "f02-two-children") } else { fail("no second child") }
        st.run(60)
        if g().kidsBorn > 2 { fail("more than two children") }
        // 2. один из родителей пропал: второй горюет, потом знакомится с гостем
        if let j = pp.folks.firstIndex(where: { $0.home == id && !$0.look.kid && !g().grown.contains($0.id) }) {
            pp.folks[j].gone = true
        } else { fail("no adult resident to remove") }
        if wait(st, 120, { pp.folks.contains(where: { $0.home == id && $0.job == .home && $0.phase == 30 && $0.flag && $0.t > 1 }) }) { shot(st, "f03-grief") }
        else {
            fail("the one left alone did not grieve")
            print("   adults \(g().adults) grief until \(g().griefUntil) now \(sim.time) kids \(g().kids) grown \(g().grown) court \(g().court) \(g().courtT)")
            for p in pp.folks where p.home == id { print("   #\(p.id) job \(p.job) phase \(p.phase) mode \(p.mode) kid \(p.look.kid) x \(p.x)") }
        }
        var met = false
        for _ in 0..<12 where !met {
            pp.summon()
            st.run(0.2)
            pp.visitEnd = max(pp.visitEnd, sim.time + 200)
            pp.settleWish = false
            met = wait(st, 90, { pp.folks.contains(where: { $0.home == id && $0.job == .home && $0.phase == 40 && $0.flag && $0.t > 0.8 }) })
        }
        if met {
            shot(st, "f04-met")
            if wait(st, 60, { g().inside >= 1 }) { st.run(0.5); shot(st, "f05-home-together") }
            if g().adults != 2 && !wait(st, 5, { g().adults == 2 }) { fail("pair not formed: adults \(g().adults)") }
        } else { fail("the one left alone did not meet anyone") }
        // 3. дети вырастают и строят своё иглу рядом
        HomeTune.family = 60
        pp.settleWish = false
        var grewUp = false
        for _ in 0..<14 where pp.igloos.count < 2 {
            pp.summon()
            st.run(0.2)
            pp.visitEnd = max(pp.visitEnd, sim.time + 200)
            pp.settleWish = false
            _ = wait(st, 60, { pp.igloos.count >= 2 })
            if !g().grown.isEmpty { grewUp = true }
        }
        if pp.igloos.count >= 2 {
            st.run(8)
            shot(st, "f06-grown-up-builds")
            if wait(st, 900, { pp.igloos.allSatisfy { $0.built } }) { st.run(2); shot(st, "f07-two-homes", full: true) } else { fail("the new home was not built") }
        } else { fail("grown-up child did not start a home (grew up: \(grewUp))") }
        for p in pp.folks where p.home != -1 && !pp.igloos.contains(where: { $0.id == p.home && $0.residents.contains(p.id) }) && p.job != .leave {
            st.run(8)
            if let q = pp.folks.first(where: { $0.id == p.id }), q.home != -1, !pp.igloos.contains(where: { $0.id == q.home && $0.residents.contains(q.id) }) {
                fail("ghost resident \(p.id)")
            }
        }
        print("home family: " + (ok ? "OK" : "FAILED"))
        return ok ? 0 : 1
    }

    // MARK: - Буран

    static func storm(_ st: PeopleStage) -> Int32 {
        let sim = st.sim, pp = sim.people
        let u = st.unit
        var ok = true
        func fail(_ m: String) { print("FAIL: " + m + " | " + pp.homeSummary); ok = false }
        sim.cfg.people = 2
        sim.cfg.peopleLadders = false
        pp.u = u
        pp.visitEnd = sim.time + 100000
        let k = pp.debugHouse(sim, x: 700, door: -1)
        let id = pp.igloos[k].id
        func g() -> Igloo { pp.igloos.first(where: { $0.id == id }) ?? Igloo(id: -1, x: 0, baseY: 0, born: 0) }
        st.run(5)
        sim.wind.startStorm(strength: 1, dir: 1, seconds: 45)
        if wait(st, 30, { g().inside == 2 }) {
            st.run(2)
            shot(st, "st01-storm-at-home", full: true)
            var left = false
            while sim.wind.storm > 0.4 {
                st.run(0.25)
                if g().inside < 2 && g().laid * 10 >= g().blocks.count * 7 { left = true }
            }
            if left { fail("a resident came out into the storm") }
            if wait(st, 120, { g().inside < 2 }) { st.run(1); shot(st, "st02-after-storm") } else { fail("nobody came out after the storm") }
        } else { fail("residents did not hide at home: inside \(g().inside), storm \(sim.wind.storm)") }
        print("home storm: " + (ok ? "OK" : "FAILED"))
        return ok ? 0 : 1
    }

    // MARK: - Поселение

    static func village(_ st: PeopleStage) -> Int32 {
        let sim = st.sim, pp = sim.people
        let u = st.unit
        var ok = true
        func fail(_ m: String) { print("FAIL: " + m + " | " + pp.homeSummary); ok = false }
        sim.cfg.people = 2
        sim.cfg.peopleLadders = false
        pp.u = u
        pp.visitEnd = sim.time + 100000
        HomeTune.evening = true
        let x0: Float = 560
        for i in 0..<3 { pp.debugHouse(sim, x: x0 + Float(i) * 60 * u, door: i == 2 ? -1 : 1) }
        st.run(3)
        shot(st, "v01-three-homes", pad: 24, up: 36)
        // кадры — по мере того, как берутся за дела
        var seen: Set<String> = []
        let t1 = sim.time
        func finished() -> Bool {
            pp.igloos.allSatisfy { $0.lantern >= 0 } && pp.igloos.filter { $0.flagK >= 1 }.count >= 2 && pp.igloos.filter { $0.pathTo >= 0 }.count >= 2
        }
        while sim.time - t1 < 1500 && !(finished() && seen.count >= 3) {
            st.run(0.2)
            if !seen.contains("path"), pp.folks.contains(where: { $0.job == .shovel && $0.phase == 11 && $0.t > 0.5 }) { seen.insert("path"); shot(st, "v02-path-work", pad: 24, up: 36) }
            if !seen.contains("flags"), pp.folks.contains(where: { $0.job == .home && $0.phase == 22 && $0.t > 1.2 }) { seen.insert("flags"); shot(st, "v03-flags-work", pad: 24, up: 36) }
            if !seen.contains("lantern"), pp.folks.contains(where: { $0.job == .fire && $0.phase == 31 && $0.t > 1 }) { seen.insert("lantern"); shot(st, "v04-lantern-work", pad: 24, up: 36) }
        }
        if !finished() { fail("village not finished") }
        for w in ["path", "flags", "lantern"] where !seen.contains(w) { fail("nobody was seen at work: \(w)") }
        print(String(format: "village finished in %.0f s", sim.time - t1))
        if wait(st, 600, { pp.fires.contains(where: { $0.big }) && pp.folks.filter { $0.job == .fire && $0.phase == 3 }.count >= 3 }) {
            st.run(2)
            shot(st, "v05-evening-fire", full: true, pad: 24, up: 36)
        } else { fail("no gathering at the common fire") }
        // после снегопада тропинки расчищают снова
        sim.cfg.flakeRate = 60; sim.cfg.intensity = 4
        st.run(60)
        sim.cfg.flakeRate = 14; sim.cfg.intensity = 1
        shot(st, "v06-after-snowfall", pad: 24, up: 36)
        if wait(st, 600, { pp.folks.contains(where: { $0.job == .shovel && $0.phase == 11 }) }) { st.run(8); shot(st, "v07-paths-again", pad: 24, up: 36) }
        else { print("  (paths did not need clearing after the snowfall)") }
        HomeTune.evening = false
        st.run(30)
        shot(st, "v08-day", full: true, pad: 24, up: 36)
        print("home village: " + (ok ? "OK" : "FAILED"))
        return ok ? 0 : 1
    }

    // MARK: - Стресс

    static func fuzz(_ st: PeopleStage, _ args: [String]) -> Int32 {
        let sim = st.sim, pp = sim.people
        let cell = st.cell, unit = st.unit, dt = st.dt
        var rng = Rng(seed: UInt64(cell * 1000) &+ UInt64(unit) &+ 4141)
        let secs = args.first.flatMap { Float($0) } ?? 600
        sim.cfg.people = 3
        sim.cfg.agingRate = 6
        HomeTune.coverSpeed = 3
        HomeTune.family = 25
        HomeTune.trapLimit = 40
        pp.u = unit
        pp.debugHouse(sim, x: 520, door: 1)               // чтобы было что ломать с первой секунды
        pp.debugHouse(sim, x: 520 + 62 * unit, door: -1)
        for k in pp.igloos.indices { pp.igloos[k].until = sim.time + rng.range(200, 500) }
        pp.summon()
        var cur = SIMD2<Float>(700, 600), target = SIMD2<Float>(700, 700)
        var speed: Float = 300
        var holding = false
        var worst = 0.0, slow = 0
        var maxFolks = 0, founded = 0, builtN = 0, ruined = 0, drifted = 0, fireN = 0, insideFrames = 0, shovelFrames = 0, knocked = 0
        var trappedN = 0, kidsN = 0, maxIgloos = 0, dumps = 0, storms = 0, amen = 0
        var known: [Int: (built: Bool, abandoned: Bool, laid: Int, trapped: Bool, kids: Int)] = [:]
        var lastFire = 0
        while sim.time < secs {
            let d = target - cur
            let dist = (d.x * d.x + d.y * d.y).squareRoot()
            let calm = Int(sim.time / 45) % 3 != 2              // две трети времени курсор гуляет поверху: дать пожить
            if calm {
                if dist < 4 || rng.f() < 0.004 {
                    target = SIMD2(rng.range(0, st.wPt), rng.range(60, 420))
                    speed = [60, 300, 900][Int(rng.next() % 3)]
                } else {
                    cur += d / dist * min(dist, speed * dt)
                }
            } else if dist < 4 || rng.f() < 0.004 {
                if !pp.igloos.isEmpty, rng.f() < 0.5 {          // целиться в иглу
                    let g = pp.igloos[Int(rng.next() % UInt64(pp.igloos.count))]
                    target = SIMD2(g.x + rng.range(-60, 60), g.baseY - rng.range(-10, 50))
                } else if !pp.folks.isEmpty, rng.f() < 0.5 {
                    let p = pp.folks[Int(rng.next() % UInt64(pp.folks.count))]
                    target = SIMD2(p.x + rng.range(-60, 60), p.y - rng.range(0, 40))
                } else {
                    target = SIMD2(rng.range(0, st.wPt), rng.range(100, st.hPt))
                }
                speed = [60, 300, 900, 2500][Int(rng.next() % 4)]
            } else {
                cur += d / dist * min(dist, speed * dt)
            }
            sim.setCursor(x: cur.x, y: cur.y, dt: dt, on: true)
            if !holding && !calm && rng.f() < 0.006 {           // слепить шар и швырнуть
                sim.handsMode = true
                sim.grabBegin()
                holding = sim.heldId != -1
                if holding, let g = pp.igloos.first, rng.f() < 0.7 {
                    target = SIMD2(g.x + rng.range(-20, 20), g.baseY - rng.range(5, 35))
                    speed = rng.range(700, 2200)
                }
            } else if holding && rng.f() < 0.04 {
                sim.grabEnd(); sim.handsMode = false; holding = false
            }
            if rng.f() < 0.004 && !pp.settleWish { pp.settleWish = true; pp.visitStart = min(pp.visitStart, sim.time - 30) }
            if rng.f() < 0.00004 { pp.debugHurry(sim) }
            if rng.f() < 0.00003 { sim.cfg.people = sim.cfg.people == 0 ? 3 : 0 }
            if rng.f() < 0.00003 { sim.clearAll(); sim.forceFill = true; sim.fillSurfaces(); sim.forceFill = false }
            if rng.f() < 0.00002 { pp.clearAll(sim) }
            if rng.f() < 0.0008, sim.cfg.people > 0, !pp.igloos.contains(where: { $0.built && $0.abandoned < 0 }), pp.igloos.count < 3, pp.folks.count <= 8 {
                let x = rng.range(200, 1200)                    // построенных домов не осталось — поставить готовый
                if pp.siteRough(sim, x) != nil { pp.debugHouse(sim, x: x, door: rng.f() < 0.5 ? -1 : 1) }
            }
            if rng.f() < 0.0003 { pp.summon() }
            if rng.f() < 0.0004 {
                let heavy = rng.f() < 0.5
                sim.cfg.flakeRate = heavy ? 110 : 14
                sim.cfg.intensity = heavy ? 2.2 : 1
            }
            if rng.f() < 0.0004, !pp.igloos.isEmpty {           // снег на дом
                let g = pp.igloos[Int(rng.next() % UInt64(pp.igloos.count))]
                dump(st, x: g.x + rng.range(-30, 30), y: g.baseY - 40, n: Int(rng.range(100, 700)), spread: rng.range(20, 60), &rng)
                dumps += 1
            }
            if rng.f() < 0.00012 { sim.wind.startStorm(strength: rng.range(0.5, 1), dir: rng.f() < 0.5 ? -1 : 1, seconds: rng.range(10, 30)); storms += 1 }
            if rng.f() < 0.0003 { HomeTune.evening = rng.f() < 0.5 }
            if rng.f() < 0.0002, let g = pp.igloos.first, g.floorRow >= 1 {       // выгрести снег из-под дома
                for c in max(0, g.c0)...min(sim.W - 1, g.c0 + (g.c1 - g.c0) / 2) { for r in min(sim.H - 1, g.floorRow)..<sim.H { sim.snow[r * sim.W + c] = 0 } }
                sim.gridDirty = true
                sim.snowDisturbed(g.c0 - 1, g.floorRow - 1, g.c1 + 1, sim.H - 1)
            }
            let t1 = CACurrentMediaTime()
            sim.step(dt)
            let ms = (CACurrentMediaTime() - t1) * 1000
            if ms > 12 {
                slow += 1
                print(String(format: "slow step %.1f ms at t=%.1f: parts %d, %@ | %@", ms, sim.time, sim.parts.count, pp.summary, pp.homeSummary))
            }
            worst = max(worst, ms)
            maxFolks = max(maxFolks, pp.folks.count)
            maxIgloos = max(maxIgloos, pp.igloos.count)
            // учёт: что случилось с каждым иглу
            for g in pp.igloos {
                let laid = g.laid
                if let o = known[g.id] {
                    if g.built && !o.built { builtN += 1 }
                    if !g.built && o.built && g.abandoned < 0 { ruined += 1 }
                    if laid < o.laid { knocked += o.laid - laid }
                    if g.trappedAt >= 0 && !o.trapped { trappedN += 1 }
                    if g.kidsBorn > o.kids { kidsN += g.kidsBorn - o.kids }
                } else {
                    founded += 1
                }
                known[g.id] = (g.built, g.abandoned >= 0, laid, g.trappedAt >= 0, g.kidsBorn)
                if g.inside > 0 { insideFrames += 1 }
                if g.lantern >= 0 || g.flagK >= 1 || g.pathTo >= 0 { amen += 1 }
                let geo = IglooGeo.of(g.door)
                if g.blocks.count != geo.count || !g.cover.isFinite || g.cover < 0 || g.cover > 1 || !g.baseY.isFinite || !g.x.isFinite
                    || g.kids.count != g.grow.count || g.inside > g.residents.count {
                    print("BAD igloo \(g) t=\(sim.time)")
                    return 1
                }
            }
            if known.count != pp.igloos.count {
                for (id, o) in known where !pp.igloos.contains(where: { $0.id == id }) {
                    if o.abandoned { drifted += 1 }
                    known[id] = nil
                }
            }
            if pp.fires.count > lastFire { fireN += pp.fires.count - lastFire }
            lastFire = pp.fires.count
            for p in pp.folks {
                if p.job == .shovel && p.phase == 1 { shovelFrames += 1 }
                if !p.x.isFinite || !p.y.isFinite || p.y < -200 || p.y > st.hPt + 200 {
                    print("BAD person at \(p.x),\(p.y) job \(p.job) mode \(p.mode) t=\(sim.time)")
                    return 1
                }
                if p.mode == .inside && !pp.igloos.contains(where: { $0.id == p.home && $0.residents.contains(p.id) }) {
                    print("BAD person inside a missing igloo: id \(p.id) home \(p.home) job \(p.job) phase \(p.phase) t=\(sim.time)")
                    return 1
                }
            }
            if pp.folks.count > 12 { print("BAD: \(pp.folks.count) people t=\(sim.time)"); return 1 }
            for f in pp.fires where !f.x.isFinite || !f.y.isFinite { print("BAD fire \(f)"); return 1 }
        }
        // маска: только у стоящих домов
        var stray = 0
        for i in sim.mask.indices where sim.mask[i] >= 251 && !pp.igloos.contains(where: { $0.mk == sim.mask[i] }) { stray += 1 }
        print(String(format: "home fuzz cell=%.0f unit=%.0f: %.0f s, worst step %.2f ms, steps over 12 ms: %d, max people %d, max igloos %d", cell, unit, sim.time, worst, slow, maxFolks, maxIgloos))
        print("  igloos founded \(founded), built \(builtN), ruined and kept \(ruined), turned into drifts or removed \(drifted), blocks knocked out \(knocked), fires \(fireN), frames with light \(insideFrames), frames shovelling \(shovelFrames)")
        print("  snow dumps \(dumps), storms \(storms), trapped \(trappedN), children \(kidsN), graves \(pp.graves.count), frames with amenities \(amen), stray mask cells \(stray)")
        print("  " + pp.summary)
        print("  " + pp.homeSummary)
        st.shot("hf-end-\(Int(cell))-\(Int(unit))", crops: pp.igloos.isEmpty ? [] : [crop(st)], zoom: 2)
        return worst < 15 && stray == 0 ? 0 : 1
    }
}
