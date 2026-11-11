import Foundation

// Ветер над лежачим снегом и бураны. Подключено в Sim.step: boost — сразу после расчёта windNow,
// step — после частиц и шаров, перед человечками.
//
// Позёмка: верхняя рыхлая ячейка сугроба, открытая ветру (с наветренной стороны и сверху свободно),
// срывается комом и низко летит по ветру, пока не упрётся в снег, — там снова становится ячейкой.
// Гребни и уступы навстречу ветру стачиваются, ямы и подветренные стороны заметаются; объём не меняется.
// Плотный снег поддаётся только сильному ветру и бурану, наст ветер лишь шлифует — срывает острые выступы.
// С карниза окна снег уносит вдоль шапки и за подветренный край, в буран порыв срывает целый пласт.
// Буран — добавка к ветру с плавным подъёмом и спадом, порывами, своим снегом в воздухе; этот снег
// он ещё и намётает: в затишье за гребнями, в ямы и траншеи, перед препятствиями.

final class Wind {
    /// Сила бурана сейчас, 0…1 (0 — бурана нет).
    private(set) var storm: Float = 0
    /// Куда дует буран: -1 — влево, +1 — вправо.
    private(set) var dir: Float = 1

    // счётчики — для самотеста
    private(set) var statLifted = 0      // ячеек сорвано позёмкой
    private(set) var statChipped = 0     // из них — сколото наста с острых выступов
    private(set) var statDrifted = 0     // ячеек намело: снег, который принёс буран
    private(set) var statSlabs = 0       // пластов сорвано с окон
    private(set) var statSlabCells = 0   // ячеек в этих пластах
    private(set) var statBlownIn = 0     // комьев принесло из-за наветренного края экрана
    private(set) var statBlownOut = 0    // комьев позёмки унесло за край экрана
    private(set) var pendingIn = 0       // унесено, но ещё не принесено обратно
    private(set) var statStorms = 0      // буранов началось
    private(set) var chunksAir = 0       // комьев в воздухе (всех, не только своих)
    private(set) var dustAir = 0         // снежной пыли в воздухе
    /// Замерять время своего шага (для стресс-теста).
    var profile = false
    private(set) var worstStep: Double = 0      // секунды
    private(set) var totalStep: Double = 0

    /// Один буран на все экраны (у каждого экрана своя Sim). Включает приложение; в тестах выключено.
    static var linked = false
    private static var shared: (id: Int, wall: Double, len: Float, power: Float, dir: Float) = (0, 0, 0, 0, 1)
    private var seenShared = Wind.shared.id

    static let calm: Float = 40          // слабее этого ветер лежачий снег не трогает, pt/с
    static let stormWind: Float = 200    // добавка бурана в полную силу, pt/с (с порывами до ~265)
    static let gapMin: Float = 480, gapMax: Float = 1200     // между буранами, с
    static let maxChunks = 700           // больше комьев в воздухе — позёмка ждёт
    static let heapRate: Float = 0.08    // сколько раз в секунду на столбец буран пробует намести снег
    static let maxDust = 900
    static let maxAir = 26000            // больше частиц — буран своих снежинок не добавляет
    /// Метка снежной пыли в Particle.hard (у снежинок поле не используется): её время жизни — ghost.
    static let dustMark: UInt8 = 255
    /// Метка кома позёмки с низа экрана в Particle.drift (у комьев поле не используется); +1 — уже учтён как ушедший.
    static let floorMark: Float = 2
    /// Метка кома из сорванного пласта: такой летит вместе со всеми, пока весь пласт не уйдёт за край окна.
    static let slabMark: Float = 5
    /// Какую долю тяжести ветер снимает с кома позёмки, пока несёт его (тяжесть комьев в Sim — 1400 pt/с²).
    static let carryLift: Float = 0.9
    static let chunkGravity: Float = 1400

    private var rng = Rng(seed: UInt64(Date().timeIntervalSince1970 * 1000) ^ 0x51ED_270B_9F3C_11A7)
    private var clock: Double = 0
    private var on = false               // буран идёт
    private var auto = false             // пришёл сам (а не из меню или теста)
    private var t0: Double = 0
    private var len: Float = 0, power: Float = 0, rise: Float = 8, fade: Float = 12
    private var aim: Float = 1           // куда дует идущий буран
    private var level: Float = 0         // сглаженная сила со знаком направления
    private var nextAt: Double = -1      // когда придёт следующий; -1 — ещё не назначен
    private var ph: (Float, Float, Float) = (0, 2.1, 4.4)
    private var slabAt: Double = 0
    private var cfgWind: Float = 0
    private var liftAcc: Float = 0, topAcc: Float = 0, sideAcc: Float = 0, baseAcc: Float = 0

    /// Опора, над которой лежит снег: низ экрана или карниз.
    private struct Span {
        var row: Int        // строка верхнего края опоры
        var c0: Int, c1: Int
        var depth: Int      // на сколько строк ниже опора у скруглённых углов
        var floor: Bool
    }
    private var spans: [Span] = []
    private var spanCols = 0             // столбцов во всех опорах
    private var heapAcc: Float = 0
    private var slabBuf: [Int32] = []

    func reseed(_ v: UInt64) { rng = Rng(seed: v) }

    /// Идёт ли буран (в том числе на подъёме и спаде).
    var active: Bool { on }
    /// Через сколько секунд сам придёт следующий буран; -1 — не назначен.
    var nextIn: Float { nextAt < 0 || on ? -1 : Float(max(0, nextAt - clock)) }

    // MARK: - Буран

    /// Начать буран сейчас (меню, тесты). dir: -1 — влево, +1 — вправо, 0 — по настроенному ветру или случайно.
    func startStorm(strength: Float = 1, dir: Float = 0, seconds: Float = 60) {
        begin(strength: strength, dir: dir, seconds: seconds, auto: false, elapsed: 0)
    }

    /// Буран стихает за несколько секунд.
    func stopStorm() {
        guard on else { return }
        let e = Float(clock - t0)
        if len - e > 5 { len = e + 5; fade = 5 }
    }

    private func begin(strength: Float, dir d: Float, seconds: Float, auto a: Bool, elapsed: Float) {
        let secs = max(6, min(600, seconds))
        guard elapsed < secs else { return }
        on = true
        auto = a
        power = max(0.05, min(1, strength))
        len = secs
        rise = max(3, min(14, secs * 0.2))
        fade = max(4, min(20, secs * 0.3))
        t0 = clock - Double(elapsed)
        if d != 0 { aim = d > 0 ? 1 : -1 }
        else if abs(cfgWind) >= 20 { aim = cfgWind > 0 ? 1 : -1 }
        else { aim = rng.next() & 1 == 0 ? -1 : 1 }
        if abs(level) < 0.02 { dir = aim }
        ph = (rng.range(0, 6.283), rng.range(0, 6.283), rng.range(0, 6.283))
        slabAt = clock + Double(rise + rng.range(1, 6))
        statStorms += 1
    }

    /// Добавка к ветру, pt/с со знаком. Вызывается каждый шаг сразу после расчёта `sim.windNow`.
    func boost(_ s: Sim, _ dt: Float) -> Float {
        guard dt > 0 else { return 0 }
        clock += Double(dt)
        cfgWind = s.cfg.wind
        if s.cfg.storms {
            if nextAt < 0 { nextAt = clock + Double(rng.range(Wind.gapMin, Wind.gapMax)) }
            if !on && clock >= nextAt {
                begin(strength: rng.range(0.7, 1), dir: 0, seconds: rng.range(40, 90), auto: true, elapsed: 0)
                if Wind.linked {        // остальные экраны подхватят тот же буран
                    Wind.shared = (Wind.shared.id + 1, Date().timeIntervalSince1970, len, power, aim)
                    seenShared = Wind.shared.id
                }
            }
        } else {
            nextAt = -1
            if on && auto { stopStorm() }       // настройку выключили — буран стихает
        }
        if Wind.linked && Wind.shared.id != seenShared {
            seenShared = Wind.shared.id
            let sh = Wind.shared
            let late = Float(max(0, Date().timeIntervalSince1970 - sh.wall))
            if s.cfg.storms && !on { begin(strength: sh.power, dir: sh.dir, seconds: sh.len, auto: true, elapsed: late) }
        }
        var goal: Float = 0
        if on {
            let e = Float(clock - t0)
            if e >= len {
                on = false
                nextAt = s.cfg.storms ? clock + Double(rng.range(Wind.gapMin, Wind.gapMax)) : -1
            } else {
                func smooth(_ v: Float) -> Float { let u = max(0, min(1, v)); return u * u * (3 - 2 * u) }
                goal = power * min(smooth(e / rise), smooth((len - e) / fade)) * aim
            }
        }
        // сила меняется плавно, в том числе при смене направления и новом буране поверх старого
        level += (goal - level) * min(1, dt * 2.5)
        if !on && abs(level) < 0.004 { level = 0 }
        storm = min(1, abs(level))
        if storm > 0.01 { dir = level > 0 ? 1 : -1 }
        guard storm > 0 else { return 0 }
        let t = Float(clock - t0)
        let gust = 1 + 0.18 * sinf(t * 0.9 + ph.0) + 0.1 * sinf(t * 2.3 + ph.1) + 0.05 * sinf(t * 5.3 + ph.2)
        return level * Wind.stormWind * gust
    }

    // MARK: - Шаг

    /// Перенос лежачего снега ветром. Вызывается каждый шаг.
    func step(_ s: Sim, _ dt: Float) {
        let began = profile ? clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) : 0
        defer {
            if profile {
                let sec = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - began) * 1e-9
                worstStep = max(worstStep, sec)
                totalStep += sec
            }
        }
        let n = s.W * s.H
        guard dt > 0, s.snow.count == n, s.hard.count == n, s.ledge.count == n, s.mask.count == n else { return }
        let w = s.windNow, a = abs(w)
        flakes(s, dt, w)
        if a < Wind.calm && dustAir == 0 && chunksAir == 0 { return }
        sweepParts(s, dt, w)
        guard a >= Wind.calm else { return }
        listSpans(s)
        drift(s, dt, w)
        blowIn(s, dt, w)
        if storm > 0.15 { snowIn(s, dt, w) }
        if storm > 0.5 && clock >= slabAt {
            slabAt = clock + Double(rng.range(7, 15))
            slab(s, w)
        }
    }

    /// Свободна ли ячейка для ветра. За краем экрана — открыто.
    @inline(__always) private func open(_ s: Sim, _ c: Int, _ r: Int) -> Bool {
        if c < 0 || c >= s.W || r < 0 { return true }
        if r >= s.H { return false }
        let i = r * s.W + c
        return s.snow[i] == 0 && s.ledge[i] == 0 && s.mask[i] == 0
    }

    /// Строка опоры в столбце c (у скруглённого угла окна она ниже верхнего края). nil — опоры тут нет.
    private func baseRow(_ s: Sim, _ sp: Span, _ c: Int) -> Int? {
        if c < 0 || c >= s.W { return nil }
        if sp.floor { return s.H }
        var r = sp.row
        let last = min(s.H - 1, sp.row + sp.depth)
        while r >= 1 && r <= last {
            if s.ledge[r * s.W + c] != 0 { return r }
            r += 1
        }
        return nil
    }

    /// Позёмка идёт струями: бегущие по ветру полосы, где метёт сильнее. 0.15…1.
    private func streak(_ x: Float, _ d: Int) -> Float {
        let t = Float(clock.truncatingRemainder(dividingBy: 4096))
        return 0.575 + 0.425 * sinf(x * 0.013 - Float(d) * t * 2.3 + 1.4 * sinf(t * 0.37 + x * 0.0021))
    }

    /// Ком. carry — сколько секунд ветер несёт его над самой поверхностью (у комьев поле fall не занято:
    /// пока оно больше нуля, sweepParts почти снимает с кома тяжесть и подгоняет его по ветру).
    private func chunk(_ s: Sim, _ x: Float, _ y: Float, _ vx: Float, _ vy: Float, _ shade: UInt8, _ hard: UInt8,
                       ghost: Float = 0, carry: Float = 0, floor: Bool = false, slab: Bool = false) {
        guard s.parts.count < s.maxParts else { return }
        s.parts.append(Particle(x: x, y: y, vx: vx, vy: vy, fall: carry, phase: 0, size: s.cell, alpha: 1, kind: 1,
                                shade: shade == 0 ? 1 : shade, passer: false, ghost: ghost,
                                drift: slab ? Wind.slabMark : (floor ? Wind.floorMark : 0), hard: hard))
        chunksAir += 1
    }

    /// Снежная пыль над поверхностью: живёт около секунды, летит по ветру, в сугробы не ложится
    /// (пока ghost > 0, снег её не останавливает, а потом её убирает sweepParts).
    private func puff(_ s: Sim, _ x: Float, _ y: Float, _ w: Float) {
        guard s.parts.count < s.maxParts, dustAir < Wind.maxDust else { return }
        let e = rng.f()
        s.parts.append(Particle(x: x + rng.range(-2, 2), y: y - rng.range(0.5, 4), vx: w * rng.range(0.45, 0.85), vy: -rng.range(2, 24),
                                fall: rng.range(-10, 2), phase: rng.range(0, 6.283), size: 1.6 + 2.0 * e, alpha: 0.3 + 0.45 * e,
                                kind: 0, shade: 1, passer: true, ghost: rng.range(0.45, 1.1), drift: rng.range(-6, 6),
                                hard: Wind.dustMark))
        dustAir += 1
    }

    /// Один проход по частицам: нести позёмку, убрать отжившую пыль, посчитать комья в воздухе.
    private func sweepParts(_ s: Sim, _ dt: Float, _ w: Float) {
        var keep = s.parts.count
        var dust = 0, chunks = 0
        let lift = Wind.carryLift * Wind.chunkGravity * dt, pull = min(1, 2 * dt), blowing = abs(w) >= Wind.calm
        let W = s.W, H = s.H, inv = s.inv, wPt = Float(s.W) * s.cell
        var gone = 0
        let deep = Int(10 * inv) + 1            // выше стольких ячеек над снегом ветер ком уже не держит
        s.parts.withUnsafeMutableBufferPointer { p in
            var i = 0
            while i < keep {
                if p[i].kind == 1 {
                    chunks += 1
                    if p[i].drift == Wind.floorMark && (p[i].x < 0 || p[i].x >= wPt) {      // унесло за край экрана
                        p[i].drift = Wind.floorMark + 1
                        gone += 1
                    }
                    if p[i].fall > 0 {
                        p[i].fall -= dt
                        if blowing && !p[i].fresh && abs(p[i].x) < 1e6 && abs(p[i].y) < 1e6 {
                            p[i].vy -= lift
                            p[i].vx += (w * 0.75 - p[i].vx) * pull
                            // За гребнем, над ямой, за краем карниза под комом пусто — там затишье,
                            // и ком падает: подветренные склоны и ямы заметает.
                            let c = Int((p[i].x * inv).rounded(.down)), r = Int((p[i].y * inv).rounded(.down))
                            if c >= 0 && c < W && r >= 0 && p[i].drift != Wind.slabMark {
                                var k = 1
                                while k <= deep && r + k < H && s.snow[(r + k) * W + c] == 0 && s.ledge[(r + k) * W + c] == 0 { k += 1 }
                                if k > deep { p[i].fall = 0; p[i].vx *= 0.35 }
                            }
                        }
                    }
                    i += 1
                    continue
                }
                if p[i].hard != Wind.dustMark { i += 1; continue }
                let g = p[i].ghost
                if g <= 0.05 {
                    keep -= 1
                    p[i] = p[keep]
                    continue
                }
                if g < 0.3 { p[i].alpha = min(p[i].alpha, g * 2.2) }
                dust += 1
                i += 1
            }
        }
        if keep < s.parts.count { s.parts.removeLast(s.parts.count - keep) }
        dustAir = dust
        chunksAir = chunks
        pendingIn += gone
        statBlownOut += gone
    }

    // MARK: - Позёмка

    /// Опоры, над которыми лежит снег, на этот шаг: низ экрана и карнизы.
    private func listSpans(_ s: Sim) {
        let W = s.W, H = s.H
        spans.removeAll(keepingCapacity: true)
        spans.append(Span(row: H, c0: 0, c1: W - 1, depth: 0, floor: true))
        spanCols = W
        for g in s.segs {
            let row = Int((g.y * s.inv).rounded())
            let c0 = max(0, Int((g.x0 * s.inv).rounded(.up))), c1 = min(W - 1, Int((g.x1 * s.inv).rounded(.down)) - 1)
            if row < 1 || row >= H || c0 > c1 { continue }
            spans.append(Span(row: row, c0: c0, c1: c1, depth: g.r > 0 ? Int(g.r * s.inv) + 2 : 0, floor: false))
            spanCols += c1 - c0 + 1
        }
    }

    /// Случайный столбец случайной опоры (каждый столбец равновероятен).
    private func pickColumn() -> (sp: Span, c: Int) {
        var k = Int(rng.next() % UInt64(max(1, spanCols)))
        var sp = spans[0]
        for q in spans {
            let n = q.c1 - q.c0 + 1
            if k < n { sp = q; break }
            k -= n
        }
        return (sp, min(sp.c1, sp.c0 + k))
    }

    private func drift(_ s: Sim, _ dt: Float, _ w: Float) {
        let W = s.W, H = s.H, cell = s.cell
        let a = abs(w), d = w > 0 ? 1 : -1
        // Сколько раз в секунду ветер пробует сорвать открытую ячейку: растёт круче квадрата скорости,
        // в буран — ещё в несколько раз чаще. 45 pt/с — почти ничего, 150 — заметно, буран — по нескольку раз в секунду.
        let lam = min(9, 4 * powf((a - 35) / 265, 1.8) * (1 + 1.5 * storm))
        liftAcc += lam * dt * Float(spanCols)
        var tries = Int(liftAcc)
        liftAcc -= Float(tries)
        tries = min(tries, 128)
        guard tries > 0, spanCols > 0 else { return }
        let gale = storm > 0.3
        // плотный снег ветер точит в буран, а без бурана — только сильный, и понемногу
        let denseK = gale ? 0.45 * storm : max(0, min(0.25, (a - 90) / 400))
        for _ in 0..<tries {
            let (sp, c0) = pickColumn()
            var c = c0
            if !sp.floor && rng.next() % 3 == 0 {
                // у наветренного края карниза ветер сильнее всего: край выметает первым
                let zone = min(sp.c1 - sp.c0 + 1, max(3, Int(36 * s.inv)))
                let j = Int(rng.next() % UInt64(zone))
                c = d > 0 ? sp.c0 + j : sp.c1 - j
            }
            guard c >= 0, c < W, let row = baseRow(s, sp, c) else { continue }
            let h = s.snowHeight(c, row)
            if h <= 0 { continue }
            let t = row - h
            if t < 1 || t >= H { continue }
            let i = t * W + c
            let sh = s.snow[i]
            if sh == 0 || s.mask[i] != 0 || !open(s, c, t - 1) { continue }
            let px = (Float(c) + 0.5) * cell, top = Float(t) * cell
            let gust = streak(px, d)
            let hd = s.hard[i]
            // (за краем экрана считаем, что лежит такой же снег: крайний столбец — не обрыв)
            let inside = c - d >= 0 && c - d < W
            var p: Float
            if hd >= Sim.frozen {
                // Наст ветер только шлифует: срывает острые выступы — одиночный пик или столбик в одну-две
                // ячейки, торчащий хотя бы на две ячейки, и козырёк, под которым пусто.
                guard gale || a >= 150, inside, open(s, c - d, t) else { continue }
                let tall = open(s, c - d, t + 1)
                let spike = tall && open(s, c + d, t) && open(s, c + d, t + 1)
                let pillar = tall && !open(s, c + d, t) && open(s, c + 2 * d, t) && open(s, c + 2 * d, t + 1)
                guard spike || pillar || open(s, c, t + 1) else { continue }
                p = gale ? min(1, 1.5 * storm * gust) : 0.1 * gust
            } else {
                // насколько ячейка открыта ветру: сколько свободных ячеек подряд с наветренной стороны
                var e = 0
                while e < 3 && c - d * (e + 1) >= 0 && c - d * (e + 1) < W && open(s, c - d * (e + 1), t) { e += 1 }
                if e == 0 {
                    if a >= 70 && rng.f() < (0.3 + 0.9 * storm) * gust {
                        puff(s, px, top, w)
                        if storm > 0.4 { puff(s, px, top - rng.range(0, 7), w) }       // в буран пыль стелется гуще и выше
                    }
                    // Затишье за гребнем (сосед с наветренной стороны выше) — снег лежит. С ровного места
                    // сильный ветер тоже срывает, но редко: так позёмка идёт и по ровному полю.
                    guard inside, open(s, c - d, t - 1) else { continue }
                    p = gust * (gale ? 0.12 * storm : (a >= 120 ? 0.03 : 0))
                } else {
                    p = Float(e) / 3 * gust
                    if open(s, c + d, t) { p *= 2 }             // одинокий бугорок: ветер обтекает его с обеих сторон
                }
                if hd >= Sim.dense {
                    p *= denseK * (1 - 0.6 * Float(hd - Sim.dense) / Float(Sim.frozen - Sim.dense))
                } else {
                    p *= 1 - 0.5 * Float(hd) / Float(Sim.dense)
                }
            }
            if p <= 0 || rng.f() >= p || chunksAir >= Wind.maxChunks { continue }
            // Уступ в одну ячейку ком перемахивает — так снег ползёт вверх по наветренному склону;
            // перед стенкой выше он остаётся лежать — так у препятствий растёт намёт.
            let uphill = !open(s, c + d, t - 1)
            if uphill && (!open(s, c + d, t - 2) || !open(s, c, t - 2) || rng.f() < 0.3) { continue }
            if s.people.isStair(s, c, t) || s.people.reserved(s, c) { continue }     // постройки человечков
            // Ком несёт низко над поверхностью: ветер почти снимает с него тяжесть на доли секунды.
            let vx = Float(d) * min(330, a * rng.range(0.4, 0.7) + 10)
            let vy = -rng.range(14, 36) * (0.6 + min(a, 400) / 300)
            let carry = rng.range(0.35, 0.9)
            s.snow[i] = 0
            s.gridDirty = true
            if hd >= Sim.dense { s.snowDisturbed(c - 24, t - 1, c + 24, t + 1) }     // плотный мог держать плиту
            else { s.snowDisturbed(c - 1, t - 1, c + 1, t + 1) }
            // сколотый наст летит плотным комом
            chunk(s, px, top - min(0.5, cell * 0.25) - (uphill ? cell : 0), vx, vy, sh, min(hd, 170), carry: carry, floor: sp.floor)
            statLifted += 1
            if hd >= Sim.frozen { statChipped += 1 }
            if a >= 60 && rng.f() < 0.7 { puff(s, px, top, w) }
        }
    }

    /// Буран не только переносит лежачий снег, но и приносит свой: намётает его в затишье —
    /// за гребнями и стенками, в ямах и траншеях — и перед препятствиями. Чем глубже затишье,
    /// тем больше ложится; когда яму занесло, а намёт дорос до препятствия, расти перестаёт.
    private func snowIn(_ s: Sim, _ dt: Float, _ w: Float) {
        let W = s.W, cell = s.cell
        let d = w > 0 ? 1 : -1
        heapAcc += Wind.heapRate * storm * dt * Float(spanCols)
        var tries = Int(heapAcc)
        heapAcc -= Float(tries)
        tries = min(tries, 32)
        guard tries > 0, spanCols > 0 else { return }
        for _ in 0..<tries {
            let (sp, c) = pickColumn()
            if sp.floor && !s.cfg.floor { continue }
            guard c >= 0, c < W, let row = baseRow(s, sp, c) else { continue }
            let t = row - s.snowHeight(c, row)          // строка верхней ячейки (или сама опора)
            let r = t - 1                               // сюда ляжет новая
            guard r >= 3, open(s, c, r), open(s, c, r - 1), Float(r) * cell >= s.topLimit else { continue }
            if t < row && s.mask[t * W + c] != 0 { continue }
            // затишье: с наветренной стороны в пределах восьми столбцов снег заметно выше (тень 1:3)
            var depth = 0
            for k in 1...8 {
                let cc = c - d * k
                guard cc >= sp.c0, cc <= sp.c1, let rk = baseRow(s, sp, cc) else { break }
                let tk = rk - s.snowHeight(cc, rk)
                depth = max(depth, t - tk - k / 3)
            }
            if depth < 1 {
                // перед препятствием: сосед с подветренной стороны выше на две ячейки и больше
                let cc = c + d
                guard cc >= sp.c0, cc <= sp.c1, let rk = baseRow(s, sp, cc), t - (rk - s.snowHeight(cc, rk)) >= 2,
                      rng.f() < 0.6 else { continue }
                depth = 1
            }
            if s.people.reserved(s, c) || s.people.isStair(s, c, r) { continue }
            let n = min(3, 1 + depth / 3)
            for j in 0..<n where chunksAir < Wind.maxChunks + 200 && open(s, c, r - 1 - j) {
                chunk(s, (Float(c) + 0.5) * cell + rng.range(-0.3, 0.3) * cell, (Float(r - j) - 0.3) * cell,
                      Float(d) * rng.range(5, 30), rng.range(10, 50), rng.shade(), 0)
                statDrifted += 1
            }
            if rng.f() < 0.5 { puff(s, (Float(c) + 0.5) * cell, Float(r) * cell, w) }
        }
    }

    /// Позёмку с низа экрана, унесённую за его край, столько же несёт и из-за наветренного края
    /// (за экраном лежит такой же снег): объём на экране сохраняется, наветренный край не оголяется.
    private func blowIn(_ s: Sim, _ dt: Float, _ w: Float) {
        guard pendingIn > 0 else { return }
        guard s.cfg.floor else { pendingIn = 0; return }
        pendingIn = min(pendingIn, 300)
        guard rng.f() < Float(pendingIn) * 3 * dt, chunksAir < Wind.maxChunks else { return }
        let d = w > 0 ? 1 : -1, a = abs(w)
        let ce = d > 0 ? 0 : s.W - 1
        let r = s.H - s.snowHeight(ce, s.H) - 1 - Int(rng.next() % 3)
        guard r >= 1, open(s, ce, r) else { return }
        chunk(s, (Float(ce) + 0.5) * s.cell, (Float(r) + 0.5) * s.cell, Float(d) * min(330, a * rng.range(0.4, 0.7) + 10),
              -rng.range(4, 18), rng.shade(), 0, carry: rng.range(0.2, 0.7), floor: true)
        pendingIn -= 1
        statBlownIn += 1
    }

    // MARK: - Пласт с окна

    /// Порыв срывает кусок шапки у подветренного края окна: весь рыхлый и плотный снег полосой
    /// в несколько десятков пунктов разом съезжает за край и падает одним куском.
    private func slab(_ s: Sim, _ w: Float) {
        guard chunksAir < Wind.maxChunks / 2 else { return }
        let W = s.W, H = s.H, cell = s.cell
        let d = w > 0 ? 1 : -1
        let segs = s.segs
        guard !segs.isEmpty else { return }
        for _ in 0..<4 {
            let g = segs[Int(rng.next() % UInt64(segs.count))]
            if g.kind != 1 { continue }
            let row = Int((g.y * s.inv).rounded())
            let c0 = max(0, Int((g.x0 * s.inv).rounded(.up))), c1 = min(W - 1, Int((g.x1 * s.inv).rounded(.down)) - 1)
            if row < 1 || row >= H || c0 > c1 { continue }
            let sp = Span(row: row, c0: c0, c1: c1, depth: g.r > 0 ? Int(g.r * s.inv) + 2 : 0, floor: false)
            let cols = min(c1 - c0 + 1, max(5, Int(rng.range(36, 80) * s.inv)))
            let edge = d > 0 ? c1 : c0
            slabBuf.removeAll(keepingCapacity: true)
            var reach = 0
            for k in 0..<cols {
                let c = edge - d * k
                guard c >= c0, c <= c1, let br = baseRow(s, sp, c), !s.people.reserved(s, c) else { break }
                let h = s.snowHeight(c, br)
                var y = br - h
                while y < br && slabBuf.count < 240 {
                    if y >= 1 {
                        let i = y * W + c
                        if s.snow[i] != 0 {
                            // наст и то, что под ним, остаётся; постройки человечков — тоже
                            if s.hard[i] >= Sim.frozen || s.mask[i] != 0 || s.people.isStair(s, c, y) { break }
                            slabBuf.append(Int32(i))
                            reach = k
                        }
                    }
                    y += 1
                }
                if slabBuf.count >= 240 { break }
            }
            if slabBuf.count < max(5, Int(36 * s.inv)) { continue }     // у края почти пусто — срывать нечего
            // Весь кусок съезжает с одной скоростью, почти не взлетая: ветер несёт его, пока дальний
            // край не уйдёт за край окна, и тогда он падает целиком (см. sweepParts).
            let up = rng.range(24, 32)
            let v = max(150, min(260, abs(w) * 0.75))
            let carry = min(0.42, (Float(reach + 1) * cell + 10) / v + 0.08)
            var x0 = W, x1 = 0, y0 = H, y1 = 0
            for q in slabBuf {
                let i = Int(q)
                let c = i % W, y = i / W
                let sh = s.snow[i]
                s.snow[i] = 0
                chunk(s, (Float(c) + 0.5) * cell, (Float(y) + 0.5) * cell, Float(d) * v * rng.range(0.96, 1.04),
                      -up * rng.range(0.92, 1.08), sh, s.hard[i], ghost: 0.08, carry: carry, slab: true)
                x0 = min(x0, c); x1 = max(x1, c); y0 = min(y0, y); y1 = max(y1, y)
                if rng.f() < 0.12 { puff(s, (Float(c) + 0.5) * cell, Float(y) * cell, w) }
            }
            s.gridDirty = true
            s.snowDisturbed(x0 - 24, y0 - 2, x1 + 24, y1 + 1)
            statSlabs += 1
            statSlabCells += slabBuf.count
            return
        }
    }

    // MARK: - Снег в воздухе

    /// При боковом ветре снежинки влетают не только сверху, но и из-за наветренного края экрана:
    /// Sim сеет их над экраном с запасом не дальше 500 pt в сторону, и при ветре посильнее нижний
    /// наветренный угол оставался бы пустым. В буран снега в воздухе к тому же больше, и несёт его почти вдоль земли.
    private func flakes(_ s: Sim, _ dt: Float, _ w: Float) {
        let a = abs(w)
        guard a > 1, s.parts.count < Wind.maxAir else { return }
        let fallAvg = max(20, (s.cfg.fallMin + s.cfg.fallMax) * 0.5)
        // обычный снегопад: ниже этой высоты у наветренного края снежинкам сверху не долететь
        let y0 = 500 * fallAvg / (a * 0.8)
        if y0 < s.hPt && s.cfg.flakeRate > 0 {
            baseAcc += s.cfg.flakeRate / 1000 / fallAvg * a * 0.8 * (s.hPt - y0) * dt
        }
        // буран: плотность — как у «Метели» при полной силе; на больших экранах реже, чтобы не плодить частицы
        let rho = 0.0026 * storm * min(1, 1.8e6 / max(1, s.wPt * s.hPt))
        topAcc += rho * fallAvg * (s.wPt + 300) * dt
        sideAcc += rho * a * 0.8 * s.hPt * dt
        func flake(_ x: Float, _ y: Float) {
            let e = rng.f()
            let fall = s.cfg.fallMin + (s.cfg.fallMax - s.cfg.fallMin) * e
            let al = 0.28 + e * 0.6
            s.parts.append(Particle(x: x, y: y, vx: w * (0.6 + 0.4 * al), vy: fall, fall: fall, phase: rng.range(0, 6.283),
                                    size: 2.2 + 3.2 * e * e, alpha: al, kind: 0, shade: 1, passer: rng.f() < 0.4,
                                    ghost: 0, drift: rng.range(-9, 9)))
        }
        var n = min(60, Int(topAcc))
        topAcc -= Float(Int(topAcc))
        while n > 0 {
            n -= 1
            flake(w > 0 ? rng.range(-300, s.wPt) : rng.range(0, s.wPt + 300), -rng.range(2, 14))
        }
        n = min(60, Int(sideAcc))
        sideAcc -= Float(Int(sideAcc))
        while n > 0 {
            n -= 1
            flake(w > 0 ? -rng.range(2, 40) : s.wPt + rng.range(2, 40), rng.range(-30, s.hPt - 4))
        }
        n = min(40, Int(baseAcc))
        baseAcc -= Float(Int(baseAcc))
        while n > 0 {
            n -= 1
            flake(w > 0 ? -rng.range(2, 40) : s.wPt + rng.range(2, 40), rng.range(y0, s.hPt - 4))
        }
    }
}
