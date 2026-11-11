import AppKit
import Metal

/// Самотест забав и происшествий: `Sugrob --people-test <папка> fun [воксель] [пиксель]`.
/// (Чтобы прогон повторялся точь-в-точь, запускать с SWIFT_DETERMINISTIC_HASHING=1.)
/// Сценарии: fun (всё подряд), fun-tunnel (тоннель в слежавшейся горке), fun-loose (в рыхлой — свод падает),
/// fun-massif (высокий слежавшийся сугроб: нора с края), fun-pillars (после хода не остаётся стоек наста),
/// fun-den (нора с комнаткой, двое внутри, лаз наверх), fun-grow (нору удлиняют и дорывают комнатку во второй
/// и третий заход), fun-join (две норы навстречу соединяют), fun-storm (в буран прячутся в норе),
/// fun-long [секунд] (долгий прогон: сколько разных раскопок, какая доля времени у детей уходит на тоннели),
/// fun-natural (как дети роют сами),
/// fun-angel, fun-sled, fun-tree, fun-fuzz [секунд] (стресс: частые приходы, санки, ёлки, тоннели, быстрый курсор).
enum FunTest {
    static func run(_ st: PeopleStage, what: String, args: [String]) -> Int32 {
        if what == "fun-fuzz" { return fuzz(st, args: args) }
        if what == "fun-natural" { return natural(st, args: args) }
        if what == "fun-long" { return long(st, args: args) }
        let s = st.sim
        let all = what == "fun"
        if let seed = args.first.flatMap({ UInt64($0) }) { s.people.reseed(seed) }      // четвёртый параметр — зерно случайностей
        s.cfg.people = 2
        s.cfg.peopleLadders = false
        s.cfg.peopleStay = false
        st.wins[0] = CGRect(x: 330, y: 190, width: 430, height: 700)       // светлое окно до самого низа: фон для ёлки и санок
        st.setWindows()
        st.run(1)
        var bad = 0
        let t0 = CACurrentMediaTime()
        // сначала — на нетронутом снегу: санкам и ёлке нужен проход, ангелу — ровное место; потом роем
        if all || what == "fun-angel" { if !angel(st) { bad += 1 } }
        if all || what == "fun-sled" { if !sled(st) { bad += 1 } }
        if all || what == "fun-tree" { if !tree(st) { bad += 1 } }
        if all { s.cfg.people = 2; s.cfg.flakeRate = 14; st.run(45) }      // после ёлки небо полно снега — пусть выпадет
        if all || what == "fun-tunnel" { if !tunnel(st, tag: "a", hard: 232, side: -1) { bad += 1 } }
        if all || what == "fun-loose" { if !tunnel(st, tag: "b", hard: 0, side: 1) { bad += 1 } }
        if all || what == "fun-massif" { if !massif(st) { bad += 1 } }
        if all || what == "fun-pillars" { if !pillars(st) { bad += 1 } }
        if all || what == "fun-den" { if !den(st) { bad += 1 } }
        if all || what == "fun-grow" { if !grow(st) { bad += 1 } }
        if all || what == "fun-join" { if !join(st) { bad += 1 } }
        if all || what == "fun-storm" { if !storm(st) { bad += 1 } }
        print(String(format: "fun test (%@, cell %.0f, unit %.0f): %.0f s simulated in %.1f s, failed parts: %d",
                     what, st.cell, st.unit, s.time, CACurrentMediaTime() - t0, bad))
        return bad == 0 ? 0 : 1
    }

    // MARK: - Помощники

    static let debug = ProcessInfo.processInfo.environment["FUN_DEBUG"] != nil

    static func person(_ st: PeopleStage, _ id: Int32) -> Person? { st.sim.people.folks.first(where: { $0.id == id }) }

    static func near(_ p: Person, w: CGFloat = 150, h: CGFloat = 110) -> CGRect {
        CGRect(x: CGFloat(p.x) - w / 2, y: CGFloat(p.y) - h + 22, width: w, height: h)
    }

    /// Начать с чистого листа: никого, ровный свежий снег.
    static func fresh(_ st: PeopleStage) {
        let s = st.sim
        solo = false
        s.people.clearAll(s)
        s.clearAll()
        s.forceFill = true; s.fillSurfaces(); s.forceFill = false
        for i in s.snow.indices where s.snow[i] != 0 { s.hard[i] = 140 }      // полежавший, плотный — как обычно и бывает
        s.hardDirty = true
        st.run(0.5)
    }

    /// Гости не расходятся, пока идёт сценарий.
    static func hold(_ st: PeopleStage) {
        let s = st.sim, pp = s.people
        pp.visitEnd = max(pp.visitEnd, s.time + 600)
        // в сценариях про норы роют только по заказу: остальным гостям «не до тоннелей» (см. leaveTunnel)
        // и стоят на месте, пока не попросят (иначе затеют снежки и ступеньки как раз у норы)
        if solo {
            for j in pp.folks.indices where pp.folks[j].home == -1 {
                pp.folks[j].stayUntil = s.time + 600
                if pp.folks[j].job == .idle && People.funWish[pp.folks[j].id] == nil { pp.folks[j].wait = pp.folks[j].t + 5 }
            }
        }
    }
    static var solo = false
    /// Подождать, не отпуская гостей (и не давая им разбрестись, см. hold).
    static func rest(_ st: PeopleStage, _ secs: Float) {
        var t: Float = 0
        while t < secs - 0.001 { let d = min(0.1, secs - t); st.run(d); hold(st); t += d }
    }

    /// Поставить гостя прямо на место.
    static func place(_ st: PeopleStage, kid: Bool, x: Float) -> Int32 {
        let s = st.sim, pp = s.people
        var p = Person(id: pp.nextId, look: pp.makeLook(kid: kid, girl: pp.rng.f() < 0.5))
        pp.nextId += 1
        p.x = x
        p.y = pp.surface(s, x: x, stand: -2) ?? s.hPt
        pp.idle(&p, 0.5)
        pp.folks.append(p)
        return p.id
    }

    /// Срезать снег на участке до заданной высоты (в ячейках над полом).
    static func level(_ st: PeopleStage, from x0: Float, to x1: Float, cells: Int) {
        let s = st.sim
        let a = max(0, Int(x0 / st.cell)), b = min(s.W - 1, Int(x1 / st.cell))
        guard a <= b, cells < s.H else { return }
        for c in a...b { for r in 0..<(s.H - cells) where s.snow[r * s.W + c] != 0 { s.snow[r * s.W + c] = 0 } }
        s.gridDirty = true
    }

    /// Самый высокий взлёт комьев рядом с человечком, в его ростах над ногами (только те, что летят вверх).
    static func flight(_ st: PeopleStage, _ p: Person) -> Float {
        let s = st.sim, u = st.unit
        var m: Float = 0
        for q in s.parts where q.kind == 1 && q.vy < -30 && abs(q.x - p.x) < 60 * u { m = max(m, (p.y - q.y) / (p.tall * u)) }
        return m
    }

    /// Насыпать на пол горку заданной слежалости. Возвращает её высоту в pt.
    static func hill(_ st: PeopleStage, x: Float, hard: UInt8) -> Float {
        let s = st.sim, u = st.unit, cell = st.cell
        let rows = s.people.tunnelRows(s)
        let top = Float(rows) * cell + max(16, 5 * cell)
        let half = 15 * u, slope = 6 * u
        var rng = Rng(seed: 99)
        let a = max(0, Int((x - half - slope) / cell)), b = min(s.W - 1, Int((x + half + slope) / cell))
        guard a <= b else { return top }
        level(st, from: x - 80 * u, to: x + 80 * u, cells: rows + 1)       // вокруг — ровная невысокая площадка
        for c in a...b {
            let d = abs((Float(c) + 0.5) * cell - x)
            let k = min(1, max(0, (half + slope - d) / slope))
            let h = Int((top * k / cell).rounded())
            if h > 0 {
                for r in max(0, s.H - h)..<s.H {
                    let i = r * s.W + c
                    if s.snow[i] == 0 && s.ledge[i] == 0 { s.snow[i] = rng.shade() }
                }
            }
            for r in 0..<s.H where s.snow[r * s.W + c] != 0 { s.hard[r * s.W + c] = hard }      // вся толща — одной слежалости
        }
        s.gridDirty = true
        s.hardDirty = true
        return top
    }

    /// Дождаться, пока человечек возьмётся за забаву (желание повторяем: до выбора занятия он может быть занят).
    static func wish(_ st: PeopleStage, _ id: Int32, _ job: Person.Job, timeout: Float = 60) -> Bool {
        let s = st.sim
        let t0 = s.time
        while s.time - t0 < timeout {
            guard let p = person(st, id) else { return false }
            if p.job == job { People.funWish[id] = nil; return true }
            People.funWish[id] = job
            hold(st)
            st.run(0.1)
        }
        People.funWish[id] = nil
        return false
    }

    // MARK: - Тоннель

    /// Горка рядом с детьми, один роет, потом второй ползёт по готовому. hard 0 — рыхлая: свод должен упасть.
    static func tunnel(_ st: PeopleStage, tag: String, hard: UInt8, side: Float) -> Bool {
        let s = st.sim, pp = s.people, u = st.unit
        let firm = hard >= 200
        fresh(st)                       // без посторонних (никто не катает шары по своду и не падает в траншеи), на ровном снегу
        // Горка выше обычного предела сугроба, а такой снег быстро подтаивает снизу (Sim.relieve) — свод над ходом
        // истончался бы на глазах. На время сценария предел поднят, а сам снег почти не идёт.
        let saved = s.cfg
        s.cfg.capScale = 2.5
        s.cfg.intensity = 0
        s.cfg.flakeRate = 2
        if !firm { s.cfg.aging = false }        // рыхлая горка остаётся рыхлой
        defer { s.cfg = saved }
        // второго ребёнка ставим потом: пока первый роет, никто не должен катать шары по своду
        // (можно ставить — каждый раз свежий ребёнок на новом месте, подальше от прежних ям)
        hold(st)
        let first = place(st, kid: true, x: side < 0 ? 150 : 1050)
        guard let p0 = person(st, first) else { return false }
        /// Остальных занять ангелами, чтобы не мешали.
        func distract(_ id: Int32) {
            for q in pp.folks where q.id != id && q.home == -1 && q.job != .angel && People.funWish[q.id] == nil { People.funWish[q.id] = .angel }
        }
        // горка — рядом с тем, кто будет рыть
        let hx = max(80 * u, min(s.wPt - 80 * u, p0.x + (p0.x < s.wPt * 0.5 ? 1 : -1) * 50 * u))
        let top = hill(st, x: hx, hard: hard)
        let wide = CGRect(x: CGFloat(hx - 75 * u), y: CGFloat(s.hPt - top - 50), width: CGFloat(150 * u), height: CGFloat(top + 50))
        let c0 = st.cells()
        st.shot("f\(tag)0-hill", crops: [wide], zoom: 3, full: false)
        distract(first)
        People.funWishAt = hx           // рыть именно в горке
        defer { People.funWishAt = nil }
        guard wish(st, first, .tunnel) else {
            print("tunnel \(tag): FAIL — did not start (job \(String(describing: person(st, first)?.job)))")
            if debug, let q = person(st, first) {
                let c = Int(q.x * s.inv), h = Int(hx * s.inv)
                for i in 0..<5 {
                    let T = pp.tunnelSite(s, near: hx, strict: false, reach: 30)
                    print("  try \(i): site \(T.map { describe($0, st) + " cols \($0.c0)…\($0.c1)" } ?? "nil"), entry ok \(T.map { pp.tunnelEntry($0, q, toward: 0, s).ok } ?? false)")
                }
                print("  kid at col \(c), hill at col \(h); piles \((min(c, h) - 14...max(c, h) + 14).map { s.snowHeight($0, s.H) })")
            }
            return false
        }
        guard let T0 = pp.tunnels.last else { print("tunnel \(tag): FAIL — no record"); return false }
        print("tunnel \(tag): cols \(T0.c0)…\(T0.c1), roof between \(T0.r0) and \(T0.r1) (\(Float(T0.r1 - T0.r0) * st.cell) pt), rows \(T0.rows), holds by estimate: \(pp.roofHolds(s, T0.r0, T0.r1, rows: T0.rows))")
        var seen = Set<String>()
        var fly: Float = 0
        func snap(_ name: String) {
            if seen.insert(name).inserted { st.shot("f\(tag)\(name)", crops: [wide], zoom: 3, full: name.hasPrefix("3")) }
        }
        /// Проследить за ползущим. Возвращает: вылез сам, завалило, сколько секунд полз.
        func follow(_ id: Int32, _ k: String) -> (out: Bool, buried: Bool, crawl: Float) {
            let t0 = s.time
            var crawl: Float = 0, buried = false, out = false
            while s.time - t0 < 130 {
                st.run(0.1)
                hold(st)
                distract(id)
                guard let p = person(st, id) else { break }
                if debug && Int(s.time * 10) % 5 == 0 {
                    var roof = "", fillIn = 0
                    for c in T0.r0...T0.r1 {
                        var th = 0
                        var r = s.H - T0.rows - 1
                        while r >= 0 && s.snow[r * s.W + c] != 0 { th += 1; r -= 1 }
                        roof += th > 9 ? "+" : "\(th)"
                        if Int(s.time * 10) % 20 == 0 { roof += "/\(s.hard[(s.H - T0.rows - 1) * s.W + c]) " }
                        for r in (s.H - T0.rows)..<s.H where s.snow[r * s.W + c] != 0 && c != T0.r0 && c != T0.r1 { fillIn += 1 }
                    }
                    print(String(format: "  t=%.1f job %@ phase %d pt %.1f mode %@ x %.1f y %.1f col %d pile %d roof %@ in %d others %@", s.time, "\(p.job)", p.phase, p.t,
                                 "\(p.mode)", p.x, p.y, Int(p.x * s.inv), pp.pile(s, Int(p.x * s.inv), s.H), roof, fillIn,
                                 pp.folks.filter { $0.id != id }.map { "\($0.job)@\(Int($0.x))" }.joined(separator: ",")))
                }
                let inner = min(p.x, p.x + p.face * p.tall * u) > Float(T0.r0 + 1) * st.cell
                    && max(p.x, p.x + p.face * p.tall * u) < Float(T0.r1) * st.cell
                if p.job == .tunnel {
                    fly = max(fly, flight(st, p))
                    if p.phase == 1 && p.t > 1.2 { snap("\(k)1-trench") }
                    if p.phase == 4 && p.t > 1.0 { snap("\(k)3b-climbing-out") }
                    if p.phase == 3 || p.phase == 6 || p.phase == 7 {
                        crawl += 0.1
                        let head = Int((p.x + p.face * p.tall * u) * s.inv)
                        if head > T0.r0 + 2 && head < T0.r1 - 2 && !inner { snap("\(k)2-digging") }
                        if inner { snap("\(k)3-inside") }
                    }
                } else if p.job == .buried {
                    if !buried { st.run(0.6); snap("\(k)4-buried") }
                    buried = true
                } else if crawl > 0 || s.time - t0 > 40 {
                    out = crawl > 0 && !buried && p.job == .cheer && pp.tunnels.first(where: { $0.id == T0.id && !$0.dead })?.done == true
                    snap(out ? "\(k)4-out" : "\(k)4-end")
                    break
                }
            }
            return (out, buried, crawl)
        }
        let r1 = follow(first, "")
        st.run(3)
        let T1 = pp.tunnels.first(where: { $0.id == T0.id && !$0.dead })
        var filled = 0, roof = 0
        if T0.r1 - T0.r0 >= 2 {
            for c in (T0.r0 + 1)..<T0.r1 {
                for r in (s.H - T0.rows)..<s.H where s.snow[r * s.W + c] != 0 { filled += 1 }
                if pp.pile(s, c, s.H) > T0.rows { roof += 1 }
            }
        }
        print(String(format: "tunnel %@: first out=%@ buried=%@ crawl %.1f s; record %@; inside %d cells of snow, roof over %d of %d cols; grid cells %d -> %d (+%d chunks in the air)",
                     tag, "\(r1.out)", "\(r1.buried)", r1.crawl, T1 == nil ? "gone" : (T1!.done ? "done" : "not done"),
                     filled, roof, T0.r1 - T0.r0 - 1, c0, st.cells(), s.parts.filter { $0.kind == 1 }.count))
        var ok = true
        if firm {
            if !(r1.out && T1?.done == true && roof * 10 >= (T0.r1 - T0.r0 - 1) * 8) { print("tunnel \(tag): FAIL — firm roof must hold and the kid must get through"); ok = false }
            // второй — по готовому
            People.funWish.removeAll()
            solo = true                 // первый пусть постоит: полезет рубить ступеньки по горке — засыплет второму устье
            let second = place(st, kid: true, x: p0.x)
            People.funWishKind = "visit"
            defer { People.funWishKind = nil; solo = false }
            if ok, wish(st, second, .tunnel, timeout: 120) {
                let r2 = follow(second, "5")
                print(String(format: "tunnel %@: second out=%@ buried=%@ crawl %.1f s", tag, "\(r2.out)", "\(r2.buried)", r2.crawl))
                if !r2.out { print("tunnel \(tag): FAIL — second kid did not get through"); ok = false }
            } else if ok {
                let q = person(st, second)
                print("tunnel \(tag): FAIL — second kid did not start: now \(String(describing: q?.job)) phase \(q?.phase ?? -1) at x=\(q?.x ?? -1) y=\(q?.y ?? -1); tunnels \(pp.tunnels.map { "#\($0.id) done \($0.done) fails \($0.fails) age \(Int(s.time - $0.born))" })")
                ok = false
            }
        } else {
            // рыхлый свод обязан упасть; ребёнок либо завален (им займутся), либо вылез — но не застрял
            if r1.crawl == 0 { print("tunnel \(tag): NOTE — gave up before crawling: loose snow kept sliding into the trench") }
            else if roof * 2 > T0.r1 - T0.r0 - 1 && !r1.buried { print("tunnel \(tag): FAIL — loose roof still stands"); ok = false }
            st.run(25)
            st.shot("f\(tag)6-after", crops: [wide], zoom: 3, full: false)
            if let p = person(st, first), p.mode == .crawl { print("tunnel \(tag): FAIL — still crawling"); ok = false }
        }
        People.funWish.removeAll()
        st.run(4)
        st.shot("f\(tag)9-later", crops: [wide], zoom: 3, full: false)
        let stakes = lasting(st)
        if !stakes.isEmpty { print("tunnel \(tag): FAIL — frozen stakes left standing at columns \(stakes)"); ok = false }
        print(String(format: "tunnel %@: thrown snow rose at most %.2f of the digger's height above his feet", tag, fly))
        if fly > 1.8 { print("tunnel \(tag): FAIL — snow flies far above the digger's head"); ok = false }
        return ok
    }

    // MARK: - Высокий сугроб

    /// Слежавшийся массив в три с половиной роста: колодцем сверху в него не лезут — вход роют с края, где снег
    /// невысок; дальше — нора под сводом: снег утрамбовывают и понемногу выгребают из устья, выше головы ничего
    /// не летит; дорыв до конца, ребёнок пятится обратно.
    static func massif(_ st: PeopleStage) -> Bool {
        let s = st.sim, pp = s.people, u = st.unit
        fresh(st)
        let saved = s.cfg
        s.cfg.capScale = 6
        s.cfg.intensity = 0
        s.cfg.flakeRate = 2
        defer { s.cfg = saved; People.funWishAt = nil; People.funWish.removeAll() }
        let rows = pp.tunnelRows(s)
        let edge: Float = 520, high = 3.5 * 14 * u
        level(st, from: edge - 110 * u, to: edge, cells: rows + 1)
        var rng = Rng(seed: 7)
        let a = Int(edge / st.cell), b = min(s.W - 1, Int((edge + 110 * u) / st.cell))
        for c in a...b {
            for r in max(0, s.H - Int(high / st.cell))..<s.H where s.snow[r * s.W + c] == 0 && s.ledge[r * s.W + c] == 0 { s.snow[r * s.W + c] = rng.shade() }
            for r in 0..<s.H where s.snow[r * s.W + c] != 0 { s.hard[r * s.W + c] = 232 }
        }
        s.gridDirty = true
        s.hardDirty = true
        let crop = CGRect(x: CGFloat(edge - 100 * u), y: CGFloat(s.hPt - high - 40), width: CGFloat(170 * u), height: CGFloat(high + 40))
        st.shot("fm0-massif", crops: [crop], zoom: 2, full: false)
        hold(st)
        let kid = place(st, kid: true, x: edge - 45 * u)
        People.funWishAt = edge + 8 * u
        People.funWishKind = "burrow"
        defer { People.funWishKind = nil }
        guard wish(st, kid, .tunnel) else { print("massif: FAIL — did not start"); return false }
        guard let T0 = pp.tunnels.last else { return false }
        let burrow = T0.open0 != T0.open1
        print("massif: cols \(T0.c0)…\(T0.c1), under the roof \(T0.r0)…\(T0.r1) (\(Float(T0.r1 - T0.r0) * st.cell) pt), \(burrow ? "burrow" : "through"), entrance on the \(T0.open0 ? "left" : "right"), snow at the entrance \(Float(s.snowHeight(T0.open0 ? T0.r0 - 2 : T0.r1 + 2, s.H)) * st.cell) pt, over the tunnel \(Float(s.snowHeight((T0.r0 + T0.r1) / 2, s.H)) * st.cell) pt")
        var seen = Set<String>()
        func snap(_ name: String) { if seen.insert(name).inserted { st.shot(name, crops: [crop], zoom: 2, full: name.hasPrefix("fm3")) } }
        var fly: Float = 0, out = false, buried = false
        let t0 = s.time
        while s.time - t0 < 120 {
            st.run(0.1)
            hold(st)
            guard let p = person(st, kid) else { break }
            fly = max(fly, flight(st, p))
            if p.job == .tunnel {
                if p.phase == 1 && p.t > 1.5 { snap("fm1-entrance") }
                if p.phase == 1 && p.t > 3.0 { snap("fm1b-entrance") }
                if p.phase == 3 && p.t > 2.5 { snap("fm2-digging") }
                if p.phase == 3 && p.t > 5.0 { snap("fm3-inside") }
                if p.phase == 6 { snap("fm4-end") }
                if p.phase == 7 && p.t > 1.5 { snap("fm5-backing-out") }
            } else if p.job == .buried {
                buried = true
            } else if s.time - t0 > 5 {
                out = p.job == .cheer && pp.tunnels.first(where: { $0.id == T0.id && !$0.dead })?.done == true
                snap("fm6-out")
                break
            }
        }
        st.run(3)
        st.shot("fm7-later", crops: [crop], zoom: 2, full: false)
        var ok = true
        print(String(format: "massif: out=%@ buried=%@ in %.0f s; thrown snow rose at most %.2f of the digger's height above his feet", "\(out)", "\(buried)", s.time - t0, fly))
        if !burrow || !T0.open0 { print("massif: FAIL — must be a burrow dug from the low edge"); ok = false }
        if !out { print("massif: FAIL — the kid did not dig it and come back"); ok = false }
        if fly > 1.8 { print("massif: FAIL — snow flies far above the digger's head"); ok = false }
        // сверху, посреди массива, не роют
        let mid = edge + 60 * u
        if let T = pp.tunnelSite(s, near: mid, strict: false, reach: 25), T.r0 > Int(edge / st.cell) + 2 {
            print("massif: FAIL — a tunnel is offered in the middle of the tall drift (cols \(T.r0)…\(T.r1))"); ok = false
        }
        let stakes = lasting(st)
        if !stakes.isEmpty { print("massif: FAIL — frozen stakes left standing at columns \(stakes)"); ok = false }
        return ok
    }

    // MARK: - Норы: комнатка, продолжение, соединение, лаз, буран

    static func kindNames(_ bits: Int) -> String {
        let names = [1: "longer", 2: "second mouth", 3: "room", 4: "joined", 5: "shaft", 6: "through", 7: "through x2", 8: "den", 9: "burrow"]
        return names.keys.sorted().filter { bits & (1 << $0) != 0 }.map { names[$0]! }.joined(separator: ", ")
    }

    /// Слежавшийся массив высотой tall ростов от x0 шириной width (в «пикселях» человечка); вокруг — ровная
    /// невысокая площадка. Возвращает вырезку для кадров.
    static func block(_ st: PeopleStage, x0: Float, width: Float, tall: Float = 3.5, hard: UInt8 = 232, pad: Float = 110) -> CGRect {
        let s = st.sim, pp = s.people, u = st.unit
        let rows = pp.tunnelRows(s)
        let high = tall * 14 * u
        level(st, from: x0 - pad * u, to: x0 + (width + pad) * u, cells: rows + 1)
        var rng = Rng(seed: 7)
        let a = max(0, Int(x0 / st.cell)), b = min(s.W - 1, Int((x0 + width * u) / st.cell))
        for c in a...b {
            for r in max(0, s.H - Int(high / st.cell))..<s.H where s.snow[r * s.W + c] == 0 && s.ledge[r * s.W + c] == 0 { s.snow[r * s.W + c] = rng.shade() }
            for r in 0..<s.H where s.snow[r * s.W + c] != 0 { s.hard[r * s.W + c] = hard }
        }
        s.gridDirty = true
        s.hardDirty = true
        return CGRect(x: CGFloat(x0 - 70 * u), y: CGFloat(s.hPt - high - 50), width: CGFloat((width + 140) * u), height: CGFloat(high + 50))
    }

    /// Снег почти не идёт и не подтаивает сверх предела — чтобы сценарий был про раскопки, а не про погоду.
    static func calm(_ st: PeopleStage) -> SimConfig {
        let s = st.sim
        let saved = s.cfg
        solo = true
        s.cfg.capScale = 6
        s.cfg.intensity = 0
        s.cfg.flakeRate = 2
        s.cfg.people = 2
        return saved
    }

    /// Отправить ребёнка рыть (kind — что именно) и дождаться, пока он закончит. Возвращает, чем кончилось.
    @discardableResult
    static func send(_ st: PeopleStage, _ id: Int32, kind: String, at: Float, tag: String, crop: CGRect, shots: [(phase: Int, after: Float, name: String)] = [],
                     timeout: Float = 150) -> (ok: Bool, buried: Bool, fly: Float) {
        let s = st.sim, pp = s.people
        People.funWishAt = at
        People.funWishKind = kind
        defer { People.funWishAt = nil; People.funWishKind = nil; People.funWish.removeAll() }
        guard wish(st, id, .tunnel, timeout: 90) else {
            let q = person(st, id)
            print("\(tag): FAIL — '\(kind)' did not start (now \(String(describing: q?.job)) at x=\(q?.x ?? -1)); tunnels: \(pp.tunnels.map { describe($0, st) + " dead \($0.dead) done \($0.done) fails \($0.fails) busy \(pp.tunnelBusy($0.id))" })")
            if debug, let q {
                for T in pp.tunnels where !T.dead {
                    let wc = Int(14 * st.unit / st.cell)
                    for d in [-1, 1] where d > 0 ? !T.open1 : !T.open0 {
                        let E = d > 0 ? T.r1 : T.r0, w = E + d * (wc + 1)
                        let fit = pp.roomFit(s, min(E + d, w), max(E + d, w))
                        print("  #\(T.id) end \(d): entry ok \(pp.tunnelEntry(T, q, toward: d, s).ok), room fit \(String(describing: fit)), roof holds \(fit.map { pp.roofHolds(s, min(E, w), max(E, w), rows: $0, packed: true) } ?? false), piles \((min(E, w)...max(E, w)).map { s.snowHeight($0, s.H) }), solid \((min(E, w)...max(E, w)).map { c in (0..<s.H).first(where: { s.snow[(s.H - 1 - $0) * s.W + c] == 0 }) ?? s.H }), sup \(T.sup), floor row: \((min(E, w)...max(E, w)).map { c in "s\(s.snow[(s.H - 1) * s.W + c] != 0 ? 1 : 0)l\(s.ledge[(s.H - 1) * s.W + c])m\(s.mask[(s.H - 1) * s.W + c])" }), 2nd: \((min(E, w)...max(E, w)).map { c in "s\(s.snow[(s.H - 2) * s.W + c] != 0 ? 1 : 0)" }), path piles \((Int(q.x * s.inv)...T.c0 + 2).map { s.snowHeight($0, s.H) })")
                    }
                }
            }
            return (false, false, 0)
        }
        var seen = Set<String>()
        var fly: Float = 0, buried = false
        let t0 = s.time
        while s.time - t0 < timeout {
            st.run(0.1)
            hold(st)
            guard let p = person(st, id) else { return (false, buried, fly) }
            fly = max(fly, flight(st, p))
            if debug && Int(s.time * 10) % 5 == 0 {
                let c = Int(p.x * s.inv)
                print(String(format: "  t=%.1f %@ phase %d pt %.1f stage %d mode %@ x %.1f y %.1f col %d dir %.0f piles %@", s.time, "\(p.job)", p.phase, p.t, p.stage, "\(p.mode)", p.x, p.y, c, p.aux2,
                             "\((c - 4...c + 8).map { s.snowHeight($0, s.H) })"))
            }
            if p.job == .tunnel {
                for sh in shots where p.phase == sh.phase && p.t > sh.after && seen.insert(sh.name).inserted { st.shot(sh.name, crops: [crop], zoom: 2, full: false) }
            } else if p.job == .buried {
                buried = true
            } else if s.time - t0 > 3 {
                return (p.job == .cheer && !buried, buried, fly)
            }
        }
        print("\(tag): '\(kind)' timed out (job \(String(describing: person(st, id)?.job)) phase \(person(st, id)?.phase ?? -1))")
        return (false, buried, fly)
    }

    static func describe(_ T: Tunnel, _ st: PeopleStage) -> String {
        let s = st.sim
        var parts: [String] = []
        for i in 0..<T.seg.count {
            parts.append(String(format: "%@%.0f pt%@", i == T.room ? "room " : "", Float(T.sup[i + 1] - T.sup[i] - 1) * s.cell, T.seg[i] ? "" : " (not dug)"))
        }
        return "#\(T.id) [\(T.open0 ? "mouth" : "wall")] \(parts.joined(separator: " | ")) [\(T.open1 ? "mouth" : "wall")]\(T.shaft != 0 ? ", shaft \(T.shaftN) steps" : ""), links \(T.links), did: \(kindNames(T.kinds))"
    }

    /// Нора с комнаткой: ребёнок роет ход с края массива и комнатку в конце; потом в ней сидят двое;
    /// потом из неё прорубают лаз наверх и вылезают на макушку сугроба.
    static func den(_ st: PeopleStage) -> Bool {
        let s = st.sim, pp = s.people, u = st.unit
        fresh(st)
        let saved = calm(st)
        defer { s.cfg = saved }
        let edge: Float = 420
        let crop = block(st, x0: edge, width: 120)
        hold(st)
        var ok = true
        let kid = place(st, kid: true, x: edge - 45 * u)
        let r = send(st, kid, kind: "den", at: edge + 8 * u, tag: "den", crop: crop,
                     shots: [(1, 2.0, "fg1-entrance"), (3, 4.0, "fg2-passage"), (9, 1.0, "fg3-room-dug")])
        guard r.ok, let T0 = pp.tunnels.last(where: { !$0.dead }) else { print("den: FAIL — was not dug (buried \(r.buried))"); return false }
        print("den: " + describe(T0, st))
        if pp.denCap(T0, s) < 2 { print("den: FAIL — no room to sit in"); ok = false }
        // двое залезают посидеть
        let a = place(st, kid: true, x: edge - 40 * u), b = place(st, kid: true, x: edge - 60 * u)
        People.funWishAt = edge + 8 * u
        People.funWishKind = "visit"
        var inside = 0, most = 0
        let t0 = s.time
        while s.time - t0 < 80 {
            for id in [a, b] { if let p = person(st, id), p.job != .tunnel, p.job != .cheer, most < 2 { People.funWish[id] = .tunnel } }
            rest(st, 0.1)
            hold(st)
            inside = pp.folks.filter { $0.job == .tunnel && $0.obj == T0.id && $0.phase == 9 }.count
            if debug && Int(s.time * 10) % 5 == 0 {
                print(String(format: "  t=%.1f ", s.time) + pp.folks.map { String(format: "#%d %@/%d st%d x%.0f y%.0f %@", $0.id, "\($0.job)", $0.phase, $0.stage, $0.x, $0.y, "\($0.mode)") }.joined(separator: "  ")
                      + " | " + pp.tunnels.map { describe($0, st) }.joined(separator: "; "))
            }
            if inside > most {
                most = inside
                st.shot("fg4-inside-\(inside)", crops: [crop], zoom: 2, full: inside == 2)
                if inside == 2 { rest(st, 0.7); st.shot("fg4-inside-2b", crops: [crop], zoom: 3, full: false) }
            }
            if most >= 2 && !pp.tunnelBusy(T0.id) { break }
        }
        People.funWish.removeAll(); People.funWishAt = nil; People.funWishKind = nil
        print("den: sitting inside at once: \(most)")
        if most < 2 { print("den: FAIL — two kids must sit in the room together"); ok = false }
        rest(st, 3)
        // лаз наверх
        if let T = pp.tunnels.first(where: { $0.id == T0.id && !$0.dead }) {
            print("den: before the shaft: " + describe(T, st) + "; busy \(pp.tunnelBusy(T.id)), old \(T.old), way up in \(String(describing: pp.shaftPlan(s, T.r1, 1, except: T.id))) steps")
        }
        let c = place(st, kid: true, x: edge - 45 * u)
        let r2 = send(st, c, kind: "shaft", at: edge + 8 * u, tag: "den", crop: crop, shots: [(11, 2.5, "fg5-shaft"), (11, 5.0, "fg5b-shaft")])
        if let T = pp.tunnels.first(where: { $0.id == T0.id && !$0.dead }), let p = person(st, c) {
            st.shot("fg6-on-top", crops: [crop], zoom: 2, full: true)
            print("den: after the shaft: " + describe(T, st) + String(format: "; the kid stands %.0f pt above the floor", s.hPt - p.y))
            if !r2.ok || T.shaftN < 2 || s.hPt - p.y < 2.2 * 14 * u { print("den: FAIL — no way up was cut"); ok = false }
        } else { print("den: FAIL — the den is gone after the shaft"); ok = false }
        rest(st, 5)
        let stakes = lasting(st)
        if !stakes.isEmpty { print("den: FAIL — frozen stakes left standing at columns \(stakes)"); ok = false }
        return ok
    }

    /// Продолжение: нору во второй заход удлиняют, в третий — роют в конце комнатку.
    static func grow(_ st: PeopleStage) -> Bool {
        let s = st.sim, pp = s.people, u = st.unit
        fresh(st)
        let saved = calm(st)
        defer { s.cfg = saved }
        let edge: Float = 420
        let crop = block(st, x0: edge, width: 130)
        hold(st)
        var ok = true
        var lens: [Float] = []
        for (n, kind) in ["burrow", "longer", "room"].enumerated() {
            let kid = place(st, kid: true, x: edge - 45 * u)
            let r = send(st, kid, kind: kind, at: edge + 8 * u, tag: "grow", crop: crop, shots: [(3, 3.0, "fh\(n + 1)-\(kind)")])
            guard let T = pp.tunnels.last(where: { !$0.dead }) else { print("grow: FAIL — no tunnel after '\(kind)'"); return false }
            rest(st, 1)
            st.shot("fh\(n + 1)b-\(kind)-done", crops: [crop], zoom: 2, full: n == 2)
            lens.append(Float(T.r1 - T.r0) * st.cell)
            print("grow: after '\(kind)' (ok \(r.ok), buried \(r.buried)): " + describe(T, st))
            if !r.ok || T.seg.contains(false) { print("grow: FAIL — '\(kind)' was not finished"); ok = false }
            rest(st, 4)
        }
        if lens.count == 3 && !(lens[1] > lens[0] + 8 * u && lens[2] > lens[1] + 8 * u) { print("grow: FAIL — the burrow did not get longer: \(lens)"); ok = false }
        if let T = pp.tunnels.last(where: { !$0.dead }), pp.denCap(T, s) < 2 { print("grow: FAIL — no room at the end"); ok = false }
        let stakes = lasting(st)
        if !stakes.isEmpty { print("grow: FAIL — frozen stakes left standing at columns \(stakes)"); ok = false }
        return ok
    }

    /// Соединение: две норы с двух сторон бугра; третий заход — дорыться из одной в другую и вылезти с той стороны.
    static func join(_ st: PeopleStage) -> Bool {
        let s = st.sim, pp = s.people, u = st.unit
        fresh(st)
        let saved = calm(st)
        defer { s.cfg = saved }
        let edge: Float = 430, width: Float = 70
        let crop = block(st, x0: edge, width: width, tall: 2.6)
        hold(st)
        var ok = true
        let k1 = place(st, kid: true, x: edge - 45 * u)
        let r1 = send(st, k1, kind: "burrow", at: edge + 8 * u, tag: "join", crop: crop)
        let k2 = place(st, kid: true, x: edge + (width + 45) * u)
        let r2 = send(st, k2, kind: "burrow", at: edge + (width - 8) * u, tag: "join", crop: crop)
        let recs = pp.tunnels.filter { !$0.dead }
        st.shot("fj1-two-burrows", crops: [crop], zoom: 2, full: false)
        for T in recs { print("join: " + describe(T, st)) }
        guard r1.ok, r2.ok, recs.count == 2 else { print("join: FAIL — two burrows were not dug"); return false }
        let k3 = place(st, kid: true, x: edge - 45 * u)
        let r3 = send(st, k3, kind: "join", at: edge + 8 * u, tag: "join", crop: crop, shots: [(3, 4.0, "fj2-digging-across"), (4, 0.5, "fj3-out-the-other-side")])
        rest(st, 1)
        st.shot("fj4-joined", crops: [crop], zoom: 2, full: true)
        let after = pp.tunnels.filter { !$0.dead }
        for T in after { print("join: after: " + describe(T, st)) }
        let far = (person(st, k3)?.x ?? 0) > edge + width * u
        print("join: ok \(r3.ok), buried \(r3.buried), came out on the far side: \(far)")
        if !(r3.ok && after.count == 1 && after[0].open0 && after[0].open1 && after[0].links >= 1 && !after[0].seg.contains(false) && far) {
            print("join: FAIL — the burrows were not joined into one passage"); ok = false
        }
        // и по соединённому ходу пролезают насквозь
        let k4 = place(st, kid: true, x: edge + (width + 45) * u)
        let r4 = send(st, k4, kind: "visit", at: edge + width * 0.5 * u, tag: "join", crop: crop, shots: [(3, 2.5, "fj5-through")])
        if !r4.ok { print("join: FAIL — could not crawl through the joined passage"); ok = false }
        let stakes = lasting(st)
        if !stakes.isEmpty { print("join: FAIL — frozen stakes left standing at columns \(stakes)"); ok = false }
        return ok
    }

    /// Буран: те, кто рядом с норой, прячутся в ней (denShelter), сидят, пока не стихнет, и вылезают.
    static func storm(_ st: PeopleStage) -> Bool {
        let s = st.sim, pp = s.people, u = st.unit
        fresh(st)
        let saved = calm(st)
        defer { s.cfg = saved; s.wind.stopStorm() }
        let edge: Float = 420
        let crop = block(st, x0: edge, width: 120)
        hold(st)
        var ok = true
        let kid = place(st, kid: true, x: edge - 45 * u)
        guard send(st, kid, kind: "den", at: edge + 8 * u, tag: "storm", crop: crop).ok, let T0 = pp.tunnels.last(where: { !$0.dead }) else {
            print("storm: FAIL — no den to hide in"); return false
        }
        let cap = pp.denCap(T0, s)
        rest(st, 8)
        while pp.tunnelBusy(T0.id) && s.time < 200 { rest(st, 0.5); hold(st) }      // тот, кто рыл, досидит и вылезет
        let ids = [kid, place(st, kid: false, x: edge - 70 * u), place(st, kid: true, x: edge - 95 * u), place(st, kid: false, x: edge - 120 * u)]
        hold(st)
        rest(st, 1)
        s.wind.startStorm(strength: 1, dir: -1, seconds: 45)       // устье норы — слева, с подветренной стороны
        var t: Float = 0
        while s.wind.storm < 0.6 && t < 20 { rest(st, 0.2); t += 0.2 }
        var went = 0, free = 0
        var denIds: [Int32] = []
        let inside0 = pp.folks.filter { $0.job == .tunnel && $0.obj == T0.id }.count
        if debug { print("  before the storm hits: " + pp.folks.map { String(format: "#%d %@/%d x%.0f %@", $0.id, "\($0.job)", $0.phase, $0.x, "\($0.mode)") }.joined(separator: "  ")) }
        for id in ids {
            guard let j = pp.folks.firstIndex(where: { $0.id == id }), pp.folks[j].mode == .ground, pp.folks[j].job != .tunnel, pp.folks[j].job != .buried else { continue }
            free += 1
            var q = pp.folks[j]                             // ядро зовёт так же: со своей копией человечка
            let was = q.job
            let ok = pp.denShelter(&q, s)
            if ok { went += 1; denIds.append(id) }
            if debug { print(String(format: "  #%d %@ (was %@) at x %.0f: %@", q.id, q.look.kid ? "kid" : "adult", "\(was)", q.x, ok ? "to the den" : "no")) }
            pp.folks[j] = q
        }
        print(String(format: "storm: storm %.2f, wind %@; den for %d; went to the den: %d of %d free", s.wind.storm, s.wind.dir > 0 ? "to the right" : "to the left", cap, went, free))
        // (кому до устья не дойти — стенка, обрыв, — тот прячется как умеет; но больше, чем мест, нора не берёт)
        // Ядро само зовёт denShelter в начале бурана — кого-то оно могло отправить в нору раньше этой проверки.
        // (те, кого оно уже отправило, сосчитаны в inside0)
        if went + inside0 < 1 || went > max(0, cap - inside0) { print("storm: FAIL — the den must take someone, and no more than it holds"); ok = false }
        var most = 0
        let t0 = s.time
        while s.time - t0 < 40 && s.wind.storm > 0.5 {
            rest(st, 0.2)
            hold(st)
            let inside = pp.folks.filter { $0.job == .tunnel && $0.obj == T0.id && $0.phase == 9 }.count
            if inside > most { most = inside; st.shot("fs1-in-the-den-\(inside)", crops: [crop], zoom: 2, full: inside == went) }
            if debug && Int(s.time * 5) % 5 == 0 {
                print(String(format: "  t=%.1f storm %.2f: ", s.time, s.wind.storm) + pp.folks.map { String(format: "#%d %@/%d x%.0f y%.0f %@", $0.id, "\($0.job)", $0.phase, $0.x, $0.y, "\($0.mode)") }.joined(separator: "  "))
            }
        }
        st.shot("fs2-storm", crops: [crop], zoom: 2, full: true)
        print("storm: sat in the den at once: \(most)")
        if most < went {            // кто-то пошёл к норе и не дошёл (на пути вырос сугроб) — прячется как все
            let who: [String] = pp.folks.filter { denIds.contains($0.id) }.map { String(format: "#%d %@/%d x%.0f", $0.id, "\($0.job)", $0.phase, $0.x) }
            print("storm: NOTE — of \(went) who went to the den, \(most) got in: \(who)")
        }
        if most == 0 { print("storm: FAIL — nobody got into the den"); ok = false }
        // стихло — вылезают
        s.wind.stopStorm()
        var out = false
        let t1 = s.time
        var wasBuried = Set<Int32>(), outIds = Set<Int32>()
        while s.time - t1 < 90 {
            rest(st, 0.25)
            for q in pp.folks where q.job == .buried && denIds.contains(q.id) { wasBuried.insert(q.id) }
            if debug && Int(s.time * 4) % 4 == 0 {
                print(String(format: "  t=%.1f after: ", s.time) + pp.folks.map { String(format: "#%d %@/%d st%d x%.0f y%.0f %@", $0.id, "\($0.job)", $0.phase, $0.stage, $0.x, $0.y, "\($0.mode)") }.joined(separator: "  "))
            }
            for q in pp.folks where denIds.contains(q.id) && q.job != .tunnel && q.job != .buried { outIds.insert(q.id) }
            if denIds.allSatisfy({ id in outIds.contains(id) || !pp.folks.contains(where: { $0.id == id }) }) { out = true; break }
        }
        rest(st, 1)
        st.shot("fs3-after", crops: [crop], zoom: 2, full: false)
        print(String(format: "storm: all out %.0f s after the storm: %@; buried: %d", s.time - t1, "\(out)", pp.folks.filter { $0.job == .buried }.count))
        if !out { print("storm: FAIL — someone is still in the den"); ok = false }
        // (тех, кто пережидал снаружи, под стенкой, тоже может завалить — это забота ядра, здесь не считаем)
        let lost = denIds.filter { id in !pp.folks.contains(where: { $0.id == id }) }.count
        print("storm: of those in the den, were buried on the way out: \(wasBuried.count), did not survive: \(lost)")
        if lost > 0 { print("storm: FAIL — the den must not kill"); ok = false }
        return ok
    }

    // MARK: - Долгий прогон

    /// Двадцать минут обычной жизни: сколько разных раскопок появилось и каких, какую долю времени дети
    /// проводят в тоннелях, не роют ли снова там же, не лазит ли один и тот же ребёнок по одному ходу без конца.
    static func long(_ st: PeopleStage, args: [String]) -> Int32 {
        let s = st.sim, pp = s.people, u = st.unit
        let secs = args.first.flatMap { Float($0) } ?? 1200
        s.cfg.capScale = args.count > 1 ? Float(args[1]) ?? 1.4 : 1.4
        s.cfg.people = 3
        s.cfg.peopleEvents = true
        s.forceFill = true; s.fillSurfaces(); s.forceFill = false
        for i in s.snow.indices where s.snow[i] != 0 { s.hard[i] = 150 }
        s.hardDirty = true
        pp.summon()
        var kidT: Float = 0, tunT: Float = 0, worst = 0.0
        var born: [Int: (x: Float, t: Float)] = [:]         // где и когда начали
        var kinds: [Int: Int] = [:]
        var repeats = 0, most = 0, maxSeen = 0, denSat: Float = 0, buried = 0
        var last: [Int32: Person.Job] = [:]
        var lastPhase: [Int32: Int] = [:]
        var buriedIn: [String: Int] = [:]
        func cpu() -> Double { Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e6 }
        let t0 = s.time
        var nextShot = t0 + 240
        while s.time - t0 < secs {
            if pp.folks.filter({ $0.look.kid && $0.home == -1 }).count < 2 && Int(s.time * 60) % 600 == 0 {
                _ = place(st, kid: true, x: Float(150 + (Int(s.time) * 37) % 1100))        // чтобы дети были всегда
            }
            hold(st)
            let c1 = cpu()
            s.setCursor(x: -100, y: -100, dt: st.dt, on: false)
            s.step(st.dt)
            worst = max(worst, cpu() - c1)
            for p in pp.folks {
                if p.look.kid && p.home == -1 {
                    kidT += st.dt
                    if p.job == .tunnel { tunT += st.dt; if p.phase == 9 { denSat += st.dt } }
                }
                if p.job == .buried, let l = last[p.id], l != .buried {
                    buried += 1
                    buriedIn[l == .tunnel ? "tunnel phase \(lastPhase[p.id] ?? -1)" : "\(l)", default: 0] += 1
                    if debug { st.shot(String(format: "fl-buried-%04.0f", s.time), crops: [CGRect(x: CGFloat(p.x) - 150, y: 800 - 190, width: 300, height: 190)], zoom: 3, full: false) }
                }
                last[p.id] = p.job
                lastPhase[p.id] = p.phase
            }
            for T in pp.tunnels where !T.dead {
                if born[T.id] == nil {
                    let x = pp.tunnelMid(T, s)
                    for (_, b) in born where s.time - b.t < 400 && abs(b.x - x) < 60 * u { repeats += 1; break }
                    born[T.id] = (x, s.time)
                }
                kinds[T.id] = T.kinds
                maxSeen = max(maxSeen, T.seen.values.max() ?? 0)
            }
            most = max(most, pp.tunnels.filter { !$0.dead }.count)
            if s.time >= nextShot {
                nextShot += 240
                st.shot(String(format: "fl-%02d-min", Int((s.time - t0) / 60)), crops: [CGRect(x: 0, y: 800 - 190, width: 1400, height: 190)], zoom: 1, full: false)
                for T in pp.tunnels where !T.dead { print("   " + describe(T, st)) }
            }
        }
        var hist: [String: Int] = [:]
        for (_, b) in kinds { for k in 1...9 where b & (1 << k) != 0 { hist[kindNames(1 << k), default: 0] += 1 } }
        print(String(format: "long (cell %.0f, unit %.0f, cap x%.1f): %.0f s; excavations started %d (at most %d at once); kids spent %.1f%% of their time on tunnels (%.0f of %.0f kid-seconds, %.0f s of it sitting in a den)",
                     st.cell, st.unit, s.cfg.capScale, s.time - t0, born.count, most, kidT > 0 ? tunT / kidT * 100 : 0, tunT, kidT, denSat))
        print("  what was dug: \(hist.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", "))")
        print(String(format: "  new digs closer than 60u to a recent one: %d; most passes by one kid through one tunnel: %d; buried: %d %@; graves: %d; worst step %.2f ms cpu",
                     repeats, maxSeen, buried, "\(buriedIn)", pp.graves.count, worst))
        print("  how it went when a kid felt like tunnels: \(People.funLog.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
        st.shot("fl-end", crops: [CGRect(x: 0, y: 800 - 190, width: 1400, height: 190)], zoom: 1, full: true)
        return born.count >= 2 && repeats == 0 && worst < 15 ? 0 : 1
    }

    // MARK: - Стойки наста

    /// Узкие стойки: один-два столбца, которые выше снега с обеих сторон больше чем на четыре ячейки
    /// (ступени, постройки и стенка от ветра не в счёт).
    static func spikes(_ st: PeopleStage) -> [Int] {
        let s = st.sim, pp = s.people
        guard s.W >= 5 else { return [] }
        let lim = 4
        func h(_ c: Int) -> Int { s.snowHeight(c, s.H) }
        func own(_ c: Int) -> Bool {
            pp.isStair(s, c, s.H - 1) || pp.reserved(s, c) || (pp.wallTop >= 0 && c >= pp.wallCol - 1 && c <= pp.wallCol + 3)
        }
        var out: [Int] = []
        for c in 1..<(s.W - 2) where !own(c) {
            if h(c) - max(h(c - 1), h(c + 1)) > lim { out.append(c) }
            else if !own(c + 1) && h(c) - max(h(c - 1), h(c + 2)) > lim && h(c + 1) - max(h(c - 1), h(c + 2)) > lim { out.append(c) }
        }
        return out
    }

    /// Стойки, которые простояли дольше wait секунд.
    static func lasting(_ st: PeopleStage, wait: Float = 8) -> [Int] {
        var left = Set(spikes(st))
        var t: Float = 0
        while t < wait && !left.isEmpty {
            st.run(1)
            t += 1
            left.formIntersection(spikes(st))
        }
        if debug {
            let s = st.sim
            for c in left.sorted() {
                let cols = max(0, c - 4)...min(s.W - 1, c + 5)
                let piles: [Int] = cols.map { s.snowHeight($0, s.H) }
                var hards: [Int] = []
                for cc in cols {
                    var h = -1
                    for r in 0..<s.H where s.snow[r * s.W + cc] != 0 { h = Int(s.hard[r * s.W + cc]); break }
                    hards.append(h)
                }
                let who: [String] = s.people.folks.map { String(format: "#%d %@/%d x%.0f", $0.id, "\($0.job)", $0.phase, $0.x) }
                let balls: [String] = s.balls.map { String(format: "x%.0f r%.0f", $0.x, $0.r) }
                print("  stake at col \(c): piles \(piles), hard at top \(hards); people: \(who); balls: \(balls)")
                st.shot("stake-\(c)", crops: [CGRect(x: CGFloat(Float(c) * st.cell) - 100, y: CGFloat(s.hPt) - 160, width: 200, height: 160)], zoom: 4, full: false)
            }
        }
        return left.sorted()
    }

    /// Перемычки хода утоптаны до наста. Когда хода не стало — бросили, рухнул свод, «прогнали всех», —
    /// они не должны оставаться стоять столбиками.
    static func pillars(_ st: PeopleStage) -> Bool {
        let s = st.sim, pp = s.people
        let saved = s.cfg
        s.cfg.capScale = 2.5
        s.cfg.intensity = 0
        s.cfg.flakeRate = 2
        defer { s.cfg = saved; People.funWishAt = nil }
        var ok = true
        /// Горка, ребёнок, ход. stopAt — на какой фазе остановиться (nil — дорыть до конца).
        func dig(_ x: Float, stopAt: Int?) -> Tunnel? {
            fresh(st)
            hold(st)
            let top = hill(st, x: x, hard: 232)
            _ = top
            let kid = place(st, kid: true, x: x - 50 * st.unit)
            People.funWishAt = x
            guard wish(st, kid, .tunnel) else { return nil }
            let id = pp.tunnels.last?.id ?? -1
            let t0 = s.time
            while s.time - t0 < 90 {
                st.run(0.1)
                hold(st)
                guard let p = person(st, kid), let T = pp.tunnels.first(where: { $0.id == id }) else { return nil }
                if let stopAt, p.job == .tunnel, p.phase >= stopAt { return T }
                if stopAt == nil && T.done && p.job != .tunnel { return T }
                if p.job != .tunnel && !T.done {
                    print(String(format: "  dig at x=%.0f: kid dropped it after %.1f s: now %@, tunnel fails %d", x, s.time - t0, "\(p.job)", T.fails))
                    return nil
                }
                if debug && Int(s.time * 10) % 10 == 0 {
                    let c = Int(p.x * s.inv)
                    print(String(format: "  t=%.1f phase %d pt %.1f x %.1f y %.1f goal %.0f piles %@ T %d…%d flat %d…%d roof %d…%d", s.time, p.phase, p.t, p.x, p.y, p.goalX,
                                 "\((c - 3...c + 6).map { s.snowHeight($0, s.H) })", T.c0, T.c1, T.f0, T.f1, T.r0, T.r1))
                }
            }
            print(String(format: "  dig at x=%.0f: timed out", x))
            return nil
        }
        /// Снести свод (и всё над ходом) между перемычками.
        func knock(_ T: Tunnel) {
            for c in (T.r0 + 1)..<T.r1 { for r in 0..<(s.H - T.rows) where s.snow[r * s.W + c] != 0 { s.snow[r * s.W + c] = 0 } }
            s.gridDirty = true
            s.snowDisturbed(T.r0 - 1, 0, T.r1 + 1, s.H - 1)
        }
        func check(_ name: String, _ T: Tunnel?, _ after: (Tunnel) -> Void) {
            guard let T else { print("pillars \(name): FAIL — tunnel was not dug"); ok = false; return }
            after(T)
            let crop = CGRect(x: CGFloat(Float(T.c0) * st.cell) - 30, y: 800 - 140, width: CGFloat(Float(T.c1 - T.c0) * st.cell) + 60, height: 140)
            st.run(0.5)
            st.shot("fp-\(name)-0", crops: [crop], zoom: 3, full: false)
            let left = lasting(st)
            st.shot("fp-\(name)-1", crops: [crop], zoom: 3, full: false)
            let rec = pp.tunnels.contains(where: { $0.id == T.id && !$0.dead })
            print("pillars \(name): spikes left \(left), record \(rec ? "kept" : "gone")")
            if !left.isEmpty { print("pillars \(name): FAIL — frozen stakes are still standing at columns \(left)"); ok = false }
        }
        // свод рухнул
        check("roof", dig(170, stopAt: nil)) { knock($0) }
        // бросили на полдороге (перемычки уже утоптаны), а сугроб вокруг ушёл
        check("quit", dig(450, stopAt: 3)) { T in
            for j in pp.folks.indices where pp.folks[j].job == .tunnel {
                pp.folks[j].mode = .ground
                pp.idle(&pp.folks[j], 30)
            }
            knock(T)
        }
        // запись состарилась, потом рухнул свод
        check("old", dig(170 + 600, stopAt: nil)) { T in
            if let k = pp.tunnels.firstIndex(where: { $0.id == T.id }) { pp.tunnels[k].used = s.time - 400 }
            st.run(2)
            if pp.tunnels.first(where: { $0.id == T.id })?.old != true { print("pillars old: FAIL — intact old tunnel must be kept and marked old"); ok = false }
            knock(T)
        }
        // «прогнали всех»: записи нет, а перемычки остались
        check("cleared", dig(1100, stopAt: nil)) { T in
            pp.clearAll(s)
            knock(T)
        }
        pp.clearAll(s)
        return ok
    }

    // MARK: - Ангел

    static func angel(_ st: PeopleStage) -> Bool {
        let s = st.sim, pp = s.people
        hold(st)
        let fresh = [place(st, kid: false, x: 820), place(st, kid: true, x: 870)]       // свежие — на ровном месте, подальше от ям
        var ok = true
        for (n, kid) in [false, true].enumerated() {
            guard let p = pp.folks.first(where: { fresh.contains($0.id) && $0.look.kid == kid })
                    ?? pp.folks.first(where: { $0.look.kid == kid && !$0.gone && $0.mode == .ground && $0.stand == -2 && $0.job != .leave })
                    ?? pp.folks.first(where: { !$0.gone && $0.mode == .ground && $0.stand == -2 && $0.job != .leave }) else { continue }
            guard wish(st, p.id, .angel, timeout: 90) else {
                let q = person(st, p.id)
                print("angel: FAIL — did not start (now \(String(describing: q?.job)) at x=\(q?.x ?? -1), stand \(q?.stand ?? 0), mode \(String(describing: q?.mode)))")
                ok = false
                continue
            }
            let c0 = st.cells()
            st.run(1.6)
            if let q = person(st, p.id) { st.shot("fc\(n)1-angel", crops: [near(q)], zoom: 4, full: false) }
            st.run(0.15)
            if let q = person(st, p.id) { st.shot("fc\(n)2-angel", crops: [near(q)], zoom: 4, full: false) }
            var waited: Float = 0       // встал? (тут же лечь снова он может и сам — это не в счёт)
            while waited < 6, let q = person(st, p.id), q.job == .angel, q.phase == 1 || waited < 1 { st.run(0.1); waited += 0.1 }
            st.run(0.6)
            if let q = person(st, p.id) {
                st.shot("fc\(n)3-imprint", crops: [near(q)], zoom: 4, full: false)
                print(String(format: "angel: up after %.1f s — job %@, grid cells %d -> %d", waited + 1.75, "\(q.job)", c0, st.cells()))
                if waited >= 6 { print("angel: FAIL — still lying"); ok = false }
            }
        }
        return ok
    }

    // MARK: - Санки

    static func sled(_ st: PeopleStage) -> Bool {
        let s = st.sim, pp = s.people
        guard pp.startSled(s) else { print("sled: FAIL — startSled refused"); return false }
        if pp.startSled(s) { print("sled: FAIL — second sled started while the first is on screen"); return false }
        var ok = true
        var seen = Set<String>()
        let t0 = s.time
        let goal0 = pp.folks.first(where: { $0.job == .sled })?.goalX ?? 0
        var turned = false
        while s.time - t0 < 150 {
            st.run(0.25)
            guard let a = pp.folks.first(where: { $0.job == .sled }) else { break }
            if a.goalX != goal0 { turned = true }
            let k = pp.folks.first(where: { $0.job == .ride })
            let mid = CGRect(x: CGFloat((a.x + (k?.x ?? a.x)) / 2) - 90, y: CGFloat(a.y) - 85, width: 180, height: 110)
            let x = k?.x ?? a.x
            func snap(_ name: String) { if seen.insert(name).inserted { st.shot(name, crops: [mid], zoom: 4, full: name.hasSuffix("light")) } }
            if x > 60 && x < 300 || x > 1300 { snap("fd1-sled-edge") }
            if x > 450 && x < 640 { snap("fd2-sled-light") }
            if x > 790 && x < 900 { snap("fd3-sled-dark") }
            if x > 1000 && x < 1200 { snap("fd4-sled-window") }
            if k == nil { print("sled: FAIL — rider lost at x=\(a.x)"); ok = false; break }
        }
        print(String(format: "sled: crossed in %.1f s, shots %d, left on screen: %d", s.time - t0, seen.count,
                     pp.folks.filter { $0.job == .sled || $0.job == .ride }.count))
        if pp.folks.contains(where: { $0.job == .sled || $0.job == .ride }) { print("sled: FAIL — still on screen"); ok = false }
        else if turned { print("sled: NOTE — met a wall on the way, turned round and left where it came from") }
        else if seen.count < 3 { print("sled: FAIL — did not cross"); ok = false }
        // тянущего сбили: седок слезает и остаётся гостем
        hold(st)
        if pp.startSled(s) {
            st.run(14)
            if let a = pp.folks.first(where: { $0.job == .sled }), let k = pp.folks.first(where: { $0.job == .ride }) {
                if let j = pp.folks.firstIndex(where: { $0.id == a.id }) { pp.idle(&pp.folks[j], 3) }
                st.run(1.2)
                let kj = person(st, k.id)?.job
                st.shot("fd5-sled-stopped", crops: [near(k, w: 220)], zoom: 4, full: false)
                print("sled: puller stopped -> rider job \(String(describing: kj))")
                if kj == .ride { print("sled: FAIL — rider still riding"); ok = false }
            }
        }
        // седока не стало: тянущий идёт дальше с пустыми санками
        st.run(2)
        for j in pp.folks.indices where pp.folks[j].job == .ride || pp.folks[j].job == .sled { pp.folks[j].gone = true }
        st.run(0.2)
        if pp.startSled(s) {
            st.run(12)
            if let a = pp.folks.first(where: { $0.job == .sled }), let k = pp.folks.first(where: { $0.job == .ride }) {
                if let j = pp.folks.firstIndex(where: { $0.id == k.id }) { pp.folks[j].gone = true }
                st.run(2)
                st.shot("fd6-sled-empty", crops: [near(a, w: 220)], zoom: 4, full: false)
                let still = person(st, a.id)?.job == .sled
                print("sled: rider gone -> puller goes on: \(still)")
                if !still { ok = false }
                if let j = pp.folks.firstIndex(where: { $0.id == a.id }) { pp.folks[j].gone = true }
                st.run(0.2)
            }
        }
        return ok
    }

    // MARK: - Ёлка

    static func tree(_ st: PeopleStage) -> Bool {
        let s = st.sim, pp = s.people
        var ok = true
        // витрина: ёлки разной занесённости на светлом и на тёмном фоне (записи ставим напрямую)
        let saved = pp.trees
        pp.trees = [0, 0.3, 0.6, 0.9].enumerated().map { Tree(id: 900 + $0, x: 420 + Float($0) * 44 * st.unit, born: s.time, cover: $1) }
            + [0, 0.5].enumerated().map { Tree(id: 910 + $0, x: 800 + Float($0) * 44 * st.unit, born: s.time, cover: $1) }
        let rows = CGFloat(34 * st.unit) + 50
        st.shot("fe0-gallery", crops: [CGRect(x: 380, y: 800 - rows, width: CGFloat(190 * st.unit), height: rows),
                                       CGRect(x: 760, y: 800 - rows, width: CGFloat(100 * st.unit), height: rows)], zoom: 3, full: true)
        pp.trees = saved
        hold(st)
        guard pp.startTree(s) else { print("tree: FAIL — startTree refused"); return false }
        st.run(4)
        if let p = pp.folks.first(where: { $0.job == .tree }) { st.shot("fe1-carry", crops: [near(p, w: 180, h: 120)], zoom: 4, full: false) }
        st.run(3)
        if let p = pp.folks.first(where: { $0.job == .tree }) { st.shot("fe1b-carry", crops: [near(p, w: 180, h: 120)], zoom: 4, full: false) }
        let t0 = s.time
        var again = 0
        while pp.trees.isEmpty && s.time - t0 < 180 {
            st.run(0.25)
            hold(st)
            // не донёс (упёрся в чужого снеговика, место заняли) — ёлку приносят снова, как и в жизни
            if pp.trees.isEmpty && !pp.folks.contains(where: { $0.job == .tree || $0.obj == People.treeTag }) && again < 3 && pp.startTree(s) {
                again += 1
                print("tree: NOTE — the carrier gave up, another one comes (\(again))")
            }
        }
        guard let t = pp.trees.first else {
            st.shot("fe-not-planted", crops: [], zoom: 1, full: true)
            print("tree: FAIL — not planted; people: \(pp.folks.map { String(format: "#%d %@/%d x%.0f tries %d", $0.id, "\($0.job)", $0.phase, $0.x, $0.tries) }); tunnels: \(pp.tunnels.map { describe($0, st) + " at \(Float($0.c0) * st.cell)…\(Float($0.c1) * st.cell)" })")
            return false
        }
        let box = CGRect(x: CGFloat(t.x) - 90, y: 800 - rows - 20, width: 180, height: rows + 20)
        st.run(0.6)
        st.shot("fe2-planting", crops: [box], zoom: 4, full: false)
        st.run(2.2)
        st.shot("fe3-lights-a", crops: [box], zoom: 4, full: true)
        st.run(0.5)
        st.shot("fe4-lights-b", crops: [box], zoom: 4, full: false)
        if pp.startTree(s) { print("tree: FAIL — second tree while the first stands"); ok = false }
        st.run(6)
        print("tree: planted at x=\(t.x) in \(s.time - t0) s; carrier now \(String(describing: pp.folks.first(where: { $0.obj == t.id })?.job))")
        // все ушли — ёлку заносит (снегопад ускорен)
        st.run(20)
        if (pp.trees.first?.cover ?? 1) > 0.001 { print("tree: FAIL — snowed in while people are around"); ok = false }
        s.cfg.people = 0
        var k = 0
        while !pp.folks.isEmpty && k < 90 { st.run(1); k += 1 }
        if !pp.folks.isEmpty {              // кто-то застрял (завалило, выбирается из ямы) — для этой проверки его нет
            print("tree: NOTE — \(pp.folks.count) did not leave in 90 s: \(pp.folks.map { "\($0.job)" })")
            for j in pp.folks.indices { pp.folks[j].gone = true }
            st.run(0.1)
        }
        s.cfg.flakeRate = 450
        let t1 = s.time
        var seen = Set<String>()
        while !pp.trees.isEmpty && s.time - t1 < 200 {
            st.run(0.5)
            guard let c = pp.trees.first?.cover else { break }
            for (lim, name) in [(Float(0.25), "fe5-cover25"), (0.55, "fe6-cover55"), (0.85, "fe7-cover85"), (0.98, "fe8-cover98")] where c >= lim {
                if seen.insert(name).inserted { st.shot(name, crops: [box], zoom: 4, full: false) }
            }
        }
        st.run(0.15)
        st.shot("fe9a-crumbling", crops: [box], zoom: 4, full: false)
        st.run(4)
        st.shot("fe9b-gone", crops: [box], zoom: 4, full: false)
        print(String(format: "tree: people left in %d s, snowed in after %.0f s (rate x%.0f), trees left %d", k, s.time - t1,
                     max(s.cfg.intensity, s.cfg.flakeRate / 30), pp.trees.count))
        if !pp.trees.isEmpty { print("tree: FAIL — not snowed in"); ok = false }
        s.cfg.flakeRate = 14
        s.cfg.people = 2
        return ok
    }

    // MARK: - Как оно само

    /// «Высокие сугробы», снег слежался, никто не мешает: сами ли дети находят, где рыть, и чем это кончается.
    /// Параметры: секунд, множитель предела высоты (по умолчанию 1.8).
    static func natural(_ st: PeopleStage, args: [String]) -> Int32 {
        let s = st.sim, pp = s.people
        let secs = args.first.flatMap { Float($0) } ?? 300
        s.cfg.capScale = args.count > 1 ? Float(args[1]) ?? 1.8 : 1.8
        s.cfg.people = 3
        s.cfg.peopleLadders = false
        s.cfg.peopleStay = false
        s.forceFill = true; s.fillSurfaces(); s.forceFill = false
        s.cfg.agingRate = 8
        st.run(60)                      // снег слёживается
        s.cfg.agingRate = 1
        var spots = 0
        var x: Float = 60
        while x < s.wPt - 60 { if pp.tunnelSite(s, near: x, strict: true) != nil { spots += 1 }; x += 40 }
        print("natural: cap x\(s.cfg.capScale): tunnel sites found from \(spots) of \(Int((s.wPt - 120) / 40)) probe points")
        var started = Set<Int>(), done = Set<Int>()
        var frames: [String: Int] = [:]
        var shots = 0
        var last: [Int32: (job: Person.Job, phase: Int, mode: Person.Mode)] = [:]
        var buriedIn: [String: Int] = [:]
        let t0 = s.time
        while s.time - t0 < secs {
            if pp.folks.filter({ $0.look.kid }).count < 2 {
                _ = place(st, kid: true, x: Float(200 + (Int(s.time) * 37) % 1000))
            }
            hold(st)
            st.run(0.25)
            for T in pp.tunnels where !T.dead {
                started.insert(T.id)
                if T.done && done.insert(T.id).inserted && shots < 4 {
                    shots += 1
                    st.shot("fn\(shots)-tunnel", crops: [CGRect(x: CGFloat(Float(T.c0) * st.cell) - 40, y: 800 - 150, width: CGFloat(Float(T.c1 - T.c0) * st.cell) + 80, height: 150)], zoom: 3, full: false)
                }
            }
            for p in pp.folks {
                if p.job == .buried, let l = last[p.id], l.job != .buried {
                    let key = l.job == .tunnel ? "tunnel phase \(l.phase)" : "\(l.job)"
                    buriedIn[key, default: 0] += 1
                    if debug {
                        let c = Int(p.x * s.inv)
                        let T = pp.tunnels.first(where: { $0.id == p.obj })
                        print(String(format: "  BURIED t=%.1f #%d after %@: x %.1f y %.1f col %d, piles %@, tunnel %@", s.time, p.id, key, p.x, p.y, c,
                                     "\((c - 5...c + 5).map { s.snowHeight($0, s.H) })", T.map { "cols \($0.c0)…\($0.c1) flat \($0.f0)…\($0.f1) roof \($0.r0)…\($0.r1) open \($0.open0)/\($0.open1)" } ?? "-"))
                    }
                    if debug || shots < 8 {
                        shots += 1
                        st.shot(String(format: "fn-buried-%03.0f", s.time), crops: [CGRect(x: CGFloat(p.x) - 150, y: 800 - 170, width: 300, height: 170)], zoom: 3, full: false)
                    }
                }
                last[p.id] = (p.job, p.phase, p.mode)
                if debug && p.job == .tunnel && Int(s.time * 4) % 8 == 0, let T = pp.tunnels.first(where: { $0.id == p.obj }) {
                    print(String(format: "  t=%.1f #%d phase %d pt %.1f x %.0f y %.0f mode %@ | T %d cols %d…%d flat %d…%d roof %d…%d done %@ fails %d", s.time, p.id, p.phase, p.t, p.x, p.y,
                                 "\(p.mode)", T.id, T.c0, T.c1, T.f0, T.f1, T.r0, T.r1, "\(T.done)", T.fails))
                }
                switch p.job {
                case .tunnel, .angel, .buried: frames["\(p.job)", default: 0] += 1
                default: break
                }
                if p.job == .tunnel && p.phase == 5 && Int(s.time * 4) % 12 == 0 && shots < 4, let T = pp.tunnels.first(where: { $0.id == p.obj }) {
                    st.shot(String(format: "fn-crawl-%03.0f", s.time), crops: [CGRect(x: CGFloat(Float(T.c0) * st.cell) - 40, y: 800 - 150, width: CGFloat(Float(T.c1 - T.c0) * st.cell) + 80, height: 150)], zoom: 3, full: false)
                }
            }
        }
        print("natural: \(Int(s.time - t0)) s: tunnels started \(started.count), dug through \(done.count); seconds in jobs: "
              + frames.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value / 4)" }.joined(separator: " ") + "; graves \(pp.graves.count); buried while: \(buriedIn)")
        st.shot("fn-end")
        return 0
    }

    // MARK: - Стресс

    static func fuzz(_ st: PeopleStage, args: [String]) -> Int32 {
        let s = st.sim, pp = s.people
        let secs = args.first.flatMap { Float($0) } ?? 600
        var rng = Rng(seed: UInt64(st.cell * 1000) &+ UInt64(st.unit) &+ 4711)
        s.cfg.people = 3
        s.cfg.capScale = 1.8                    // «Высокие сугробы»: есть где рыть
        s.cfg.agingRate = 6
        s.cfg.peopleEvents = true
        s.forceFill = true; s.fillSurfaces(); s.forceFill = false
        pp.summon()
        st.curOn = true
        func cpu() -> Double { Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e6 }
        var target = SIMD2<Float>(700, 700), speed: Float = 300
        var worst = 0.0, worstWall = 0.0, slow = 0
        var nextEv = s.time + 8, nextWish = s.time + 5, evNo = 0
        var sleds = 0, treesN = 0, refused = 0, maxFolks = 0
        var doneIds = Set<Int>(), startedIds = Set<Int>()
        var crawlT: [Int32: Float] = [:]
        var frames: [String: Int] = [:]
        var stuck = false
        var spikeT: [Int: Int] = [:], spikeFails = 0
        var kindBits = 0
        let t0 = s.time
        while s.time - t0 < secs {
            let d = target - st.cur
            let dist = (d.x * d.x + d.y * d.y).squareRoot()
            if dist < 4 || rng.f() < 0.004 {
                let folks = pp.folks
                if !folks.isEmpty, rng.f() < 0.55 {
                    let p = folks[Int(rng.next() % UInt64(folks.count))]
                    target = SIMD2(p.x + rng.range(-60, 60), p.y - rng.range(0, 40))           // по человечкам
                } else if let t = pp.trees.first, rng.f() < 0.3 {
                    target = SIMD2(t.x + rng.range(-20, 20), s.hPt - rng.range(20, 80))         // по ёлке
                } else if let T = pp.tunnels.first(where: { !$0.dead }), rng.f() < 0.4 {
                    target = SIMD2(pp.tunnelMid(T, s) + rng.range(-60, 60), s.hPt - rng.range(0, 50))  // по тоннелю
                } else {
                    target = SIMD2(rng.range(0, s.wPt), rng.range(300, s.hPt))
                }
                speed = [60, 300, 900, 2500][Int(rng.next() % 4)]
            } else {
                st.cur += d / dist * min(dist, speed * st.dt)
            }
            s.setCursor(x: st.cur.x, y: st.cur.y, dt: st.dt, on: true)
            if s.time >= nextEv {               // происшествия — часто
                nextEv = s.time + rng.range(20, 40)
                evNo += 1
                let ok = evNo % 2 == 0 ? pp.startSled(s) : pp.startTree(s)
                if ok { if evNo % 2 == 0 { sleds += 1 } else { treesN += 1 } } else { refused += 1 }
            }
            if s.time >= nextWish {             // детей — в тоннель, взрослых иногда — в снег
                nextWish = s.time + rng.range(4, 9)
                People.funWish.removeAll()
                for p in pp.folks where p.home == -1 && p.mode == .ground && p.stand == -2 {
                    if p.look.kid { People.funWish[p.id] = rng.f() < 0.75 ? .tunnel : .angel }
                    else if rng.f() < 0.15 { People.funWish[p.id] = .angel }
                }
                if pp.trees.count == 1, rng.f() < 0.1 { pp.trees[0].cover = rng.range(0.6, 1.2) }     // ёлку занесло разом
            }
            if rng.f() < 0.00006 { pp.clearAll(s) }
            if rng.f() < 0.00008 { s.clearAll(); s.forceFill = true; s.fillSurfaces(); s.forceFill = false }
            if rng.f() < 0.0001 { s.cfg.people = s.cfg.people == 0 ? 3 : 0 }
            if rng.f() < 0.0004 { pp.summon() }
            let c1 = cpu(), w1 = CACurrentMediaTime()
            s.step(st.dt)
            let ms = cpu() - c1, wall = (CACurrentMediaTime() - w1) * 1000
            if ms > 15 {
                slow += 1
                print(String(format: "slow step %.1f ms cpu (%.1f wall) at t=%.1f: parts %d, %@", ms, wall, s.time, s.parts.count, pp.summary))
            }
            worst = max(worst, ms); worstWall = max(worstWall, wall)
            maxFolks = max(maxFolks, pp.folks.count)
            for T in pp.tunnels where !T.dead { startedIds.insert(T.id); if T.done { doneIds.insert(T.id) }; kindBits |= T.kinds }
            for p in pp.folks {
                if !p.x.isFinite || !p.y.isFinite || p.y < -200 || p.y > s.hPt + 200 {
                    print("BAD person at \(p.x),\(p.y) job \(p.job) mode \(p.mode) t=\(s.time)")
                    return 1
                }
                switch p.job {
                case .tunnel, .angel, .sled, .ride, .tree, .buried: frames["\(p.job)", default: 0] += 1
                default: break
                }
                if p.mode == .crawl || p.mode == .hop || p.job == .angel || p.job == .tree || p.job == .tunnel {
                    // ползёт не дольше 45 с, ангел — 5 с, ёлку несут и тоннель роют не дольше двух-трёх минут
                    let lim: Float = p.job == .angel ? 5 : (p.mode == .crawl || p.mode == .hop ? 45 : 200)
                    let key = p.id &* 8 &+ (p.job == .angel ? 1 : (p.job == .tree ? 2 : (p.mode == .ground ? 3 : 0)))
                    crawlT[key, default: 0] += st.dt
                    if crawlT[key]! > lim && !stuck { stuck = true; print("STUCK: id \(p.id) at x=\(p.x), job \(p.job), mode \(p.mode), phase \(p.phase), t=\(s.time)") }
                } else {
                    for k in 0..<4 where crawlT[p.id &* 8 &+ Int32(k)] != nil { crawlT[p.id &* 8 &+ Int32(k)] = nil }
                }
            }
            if Int(s.time) != Int(s.time - st.dt) {         // раз в секунду: не стоят ли стойки наста
                let now = Set(spikes(st))
                for c in now { spikeT[c, default: 0] += 1 }
                for c in spikeT.keys where !now.contains(c) { spikeT[c] = nil }
                if let (c, t) = spikeT.first(where: { $0.value > 12 }) {
                    spikeFails += 1
                    if spikeFails <= 3 {
                        print("SPIKE: column \(c) stands \(t) s at t=\(s.time): heights \((c - 2...c + 3).map { s.snowHeight($0, s.H) }), \(pp.summary)")
                        st.shot(String(format: "ff-spike-%03.0f", s.time), crops: [CGRect(x: CGFloat(Float(c) * st.cell) - 90, y: 800 - 170, width: 180, height: 170)], zoom: 3, full: false)
                    }
                    spikeT[c] = -1000
                }
            }
            if Int(s.time * 60) % (120 * 60) == 0 {
                st.shot(String(format: "ff-%03.0f", s.time), crops: [st.around()], zoom: 2, full: true)
            }
        }
        People.funWish.removeAll()
        let fr = frames.sorted { $0.key < $1.key }.map { "\($0.key):\(String(format: "%.0f", Float($0.value) / 60)) s" }.joined(separator: " ")
        print(String(format: "fun fuzz cell=%.0f unit=%.0f: %.0f s, worst step %.2f ms cpu (%.2f wall), slow steps %d, max people %d",
                     st.cell, st.unit, s.time - t0, worst, worstWall, slow, maxFolks))
        print("  sleds \(sleds), trees \(treesN), refused \(refused); tunnels started \(startedIds.count), dug through \(doneIds.count); time in jobs: \(fr)")
        print("  " + pp.summary)
        st.shot("ff-end")
        print("  stakes of frozen snow that stood longer than 12 s: \(spikeFails); kinds of digging seen: \(kindNames(kindBits))")
        return worst < 15 && !stuck && spikeFails == 0 ? 0 : 1
    }
}
