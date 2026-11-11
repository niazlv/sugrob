import Foundation

// Забавы и происшествия: дети роют тоннели и делают снежных ангелов, мимо везут санки, приносят и ставят ёлку.
//
// Тоннель — настоящая пустота в сетке снега у самого низа экрана. Экран — это разрез сугроба, и сквозной
// ход отрезал бы свод от земли: держаться ему было бы не на чем (см. Sim.holds — плита опирается на соседей
// по горизонтали). Поэтому у обоих устьев остаётся перемычка в один столбец, утоптанная до наста: свод лежит
// на двух перемычках мостом, а ребёнок пролезает сквозь них. До перемычек с обеих сторон — открытые
// траншеи-подходы: ровное дно на длину тела и откос наружу (отвесная стенка в рыхлом снегу тут же
// осыпалась бы внутрь, а по откосу из траншеи можно выйти пешком). В рыхлом снегу свод не держится
// и падает на того, кто ползёт (дальше — PeopleRescue).
//
// Вход роют только там, где снег невысок и его можно выбросить из траншеи руками (комья летят из рук
// невысокой дугой за край). В высокий сугроб заходят с края. Если за бугром снова низко — ход сквозной;
// если дальше сплошной высокий снег — это нора в один конец: свод с той стороны опирается на сам сугроб.
//
// Порядок: ребёнок роет траншею у входа, ложится, ползёт под сводом, выбирая снег перед собой (под сводом
// выбросить некуда — снег утрамбовывают в свод и стенки, немного выгребают из устья). В сквозном ходе за
// дальней перемычкой выкапывает место, чтобы встать, и откосом выбирается наружу; из норы пятится обратно.

struct Tunnel {
    var id: Int
    var c0: Int, c1: Int        // столбцы от и до, вместе с траншеями-подходами
    var rows: Int               // высота хода, ячеек
    var born: Float
    var r0 = 0, r1 = 0          // столбцы-перемычки у устьев: между ними ход идёт под сводом
    var f0 = 0, f1 = 0          // докуда у траншей ровное дно; дальше к c0 и c1 — откос, ячейка на столбец
    var open0 = true, open1 = true  // с какого конца есть вход: у сквозного — с обоих, у норы — с одного
    var done = false            // прокопан насквозь
    var acc: Float = 0          // до следующей проверки, цел ли ход
    var fails = 0               // сколько раз подряд сюда лезли и бросали
    var old = false             // давний: детям уже не интересен, но за перемычками ещё следим
}

struct Tree {
    var id: Int
    var x: Float
    var born: Float
    var cover: Float = 0        // 0…1: насколько занесло снегом
}

extension People {
    // MARK: - Общее

    /// Пометка в `obj` у того, кто несёт ёлку (пока не поставил).
    static let treeTag = -77

    /// Для самотеста: при следующем выборе занятия человечек с этим id возьмётся за тоннель или ангела.
    static var funWish: [Int32: Person.Job] = [:]
    /// Для самотеста: рыть только здесь (x горки), а не где удобнее.
    static var funWishAt: Float? = nil

    /// Пройдёт ли человечек по полу от x0 до x1: нет ли на пути стенок выше груди и обрывов, с которых падают.
    func pathClear(_ s: Sim, from x0: Float, to x1: Float, tall: Float) -> Bool {
        let a = max(0, min(s.W - 1, Int(min(x0, x1) * s.inv))), b = max(0, min(s.W - 1, Int(max(x0, x1) * s.inv)))
        guard a < b else { return true }
        let up = max(1, Int(0.7 * tall * u * s.inv) - 1), down = max(1, Int(14 * u * s.inv) - 1)
        var h = pile(s, a, s.H)
        for c in (a + 1)...b {
            let n = pile(s, c, s.H)
            let rise = x1 > x0 ? n - h : h - n          // по ходу: вверх или вниз
            if rise > up || -rise > down { return false }
            h = n
        }
        return true
    }

    func overDock(_ s: Sim, _ x: Float, pad: Float) -> Bool {
        s.segs.contains { $0.kind == 2 && x > $0.x0 - pad && x < $0.x1 + pad }
    }

    /// Выбрать забаву (тоннель, снежный ангел). true — выбрал.
    func chooseFun(_ p: inout Person, _ s: Sim) -> Bool {
        guard p.stand == -2, p.mode == .ground else { return false }
        if p.obj == People.treeTag {                    // сбили с ног, пока нёс ёлку: поднимает и несёт дальше
            if trees.isEmpty { p.job = .tree; next(&p, 0); return true }
            p.obj = -1
        }
        if !People.funWish.isEmpty, let w = People.funWish.removeValue(forKey: p.id) {
            if w == .tunnel ? startTunnel(&p, s, strict: false, at: People.funWishAt) : startAngel(&p, s) { return true }
        }
        let r = rng.f()
        if p.look.kid {
            if r < 0.3 { return p.home == -1 && startTunnel(&p, s, strict: true) }     // жителям не до тоннелей
            if r < 0.45 { return startAngel(&p, s) }
        } else if r < 0.04 {
            return startAngel(&p, s)
        }
        return false
    }

    // MARK: - Тоннель

    func tunnelRows(_ s: Sim) -> Int { max(2, Int((8 * u / s.cell).rounded(.up))) }
    func tunnelMid(_ T: Tunnel, _ s: Sim) -> Float { Float(T.c0 + T.c1 + 1) * 0.5 * s.cell }
    func tunnelBusy(_ id: Int) -> Bool { folks.contains { $0.job == .tunnel && $0.obj == id && !$0.gone } }

    /// Выше этого (ячеек над полом) снег из ямы руками не выбросить: вход роют только там, где он ниже, —
    /// в высокий сугроб заходят с края, а не колодцем сверху.
    func throwMax(_ s: Sim) -> Int { max(tunnelRows(s) + 2, Int(1.2 * 14 * u * s.inv)) }

    /// Здесь можно копать: не ступени, не постройка, не Dock (и не полоса, где он выезжает), в строках хода нет карнизов.
    func canDig(_ s: Sim, _ c: Int, rows: Int) -> Bool {
        guard c >= 1, c < s.W - 1, s.H > rows + 2 else { return false }
        if isStair(s, c, s.H - 1) || reserved(s, c) || inDock(s, c) || overDock(s, (Float(c) + 0.5) * s.cell, pad: 6) { return false }
        for r in (s.H - rows - 1)..<s.H where s.ledge[r * s.W + c] != 0 { return false }
        return true
    }

    /// Удержится ли свод между опорами a и b (то же правило, что в Sim.holds, с небольшим запасом).
    func roofHolds(_ s: Sim, _ a: Int, _ b: Int, rows: Int) -> Bool {
        let y = s.H - rows - 1
        guard y >= 1, a >= 0, b < s.W, b - a >= 2 else { return false }
        let x0 = Float(a) * s.cell, x1 = Float(b + 1) * s.cell
        for ball in s.balls where ball.r >= Sim.heavyR && ball.x > x0 - ball.r && ball.x < x1 + ball.r { return false }
        for x in (a + 1)..<b {
            let i = y * s.W + x
            guard s.snow[i] != 0, s.hard[i] >= Sim.dense else { return false }
            let t = Float(Int(s.hard[i]) - Int(Sim.dense)) / Float(255 - Int(Sim.dense))
            var th = 1
            while th < 6 && y - th >= 0 && s.snow[(y - th) * s.W + x] != 0 { th += 1 }
            let span = (8 + 34 * t) * min(1.6, max(0.45, Float(th) * s.cell / 7)) * s.inv * 0.9
            let dl = x - a, dr = b - x
            if Float(min(dl, dr)) <= span * 0.32 || Float(dl + dr) <= span { continue }
            return false
        }
        return true
    }

    /// Где рыть. Вход — там, где снег невысок (см. throwMax), рядом с местом, где над ходом будет хотя бы две
    /// ячейки свода. Если за бугром снова низко — ход сквозной; если дальше сплошной высокий снег — нора
    /// в один конец. strict — только там, где свод удержится.
    func tunnelSite(_ s: Sim, near x: Float, strict: Bool, reach: Float = 150) -> Tunnel? {
        let rows = tunnelRows(s)
        let W = s.W, H = s.H
        guard H > rows + 4, W > 16 else { return nil }
        let cu = u * s.inv                                  // «пиксель» человечка в ячейках
        let body = Int((16 * cu).rounded(.up)) + 1          // дно траншеи: чтобы лечь целиком
        let minL = max(4, Int((16 * cu).rounded(.up)))
        let maxL = max(minL, Int(28 * cu))
        let step = max(1, Int(2 * cu))
        let low = throwMax(s)
        let lo = max(body + 3, Int((x - reach * u) * s.inv)), hi = min(W - body - 4, Int((x + reach * u) * s.inv))
        guard lo < hi else { return nil }
        let y = H - rows - 1                                // нижняя строка свода
        // высоты и «можно копать» — один раз на весь участок (с запасом по краям)
        let g0 = max(0, lo - maxL - body - 2), g1 = min(W - 1, hi + maxL + body + 2)
        var hgt = [Int](repeating: 0, count: g1 - g0 + 1), okDig = [Bool](repeating: false, count: g1 - g0 + 1)
        for c in g0...g1 { hgt[c - g0] = pile(s, c, H); okDig[c - g0] = canDig(s, c, rows: rows) }
        func deep(_ c: Int) -> Bool {                       // над ходом хотя бы две ячейки снега
            c >= g0 && c <= g1 && okDig[c - g0] && s.snow[y * W + c] != 0 && s.snow[(y - 1) * W + c] != 0
        }
        func entry(_ a: Int, _ d: Int) -> Bool {            // у опоры a можно вырыть вход; ход уходит от него в сторону d
            for j in 1...body {
                let c = a - d * j
                if c < max(g0, 2) || c > min(g1, W - 3) || !okDig[c - g0] || hgt[c - g0] > low { return false }
            }
            return true
        }
        func taken(_ a: Int, _ b: Int) -> Bool {            // вплотную к другому ходу и к снеговику не роют
            for T in tunnels where T.c1 + body >= a && T.c0 - body <= b { return true }
            if let st = site, st.finished < 0, st.x > Float(a - body) * s.cell, st.x < Float(b + body + 1) * s.cell { return true }
            return false
        }
        func make(_ a: Int, _ e: Int, _ d: Int, through: Bool) -> Tunnel {
            var T = Tunnel(id: 0, c0: 0, c1: 0, rows: rows, born: s.time, r0: min(a, e), r1: max(a, e))
            T.open0 = d > 0 || through
            T.open1 = d < 0 || through
            T.f0 = T.open0 ? T.r0 - body : T.r0
            T.f1 = T.open1 ? T.r1 + body : T.r1
            T.c0 = T.f0; T.c1 = T.f1                        // откосы: пока не выйдут на поверхность
            if T.open0 { while T.f0 - T.c0 < low && T.c0 - 1 >= 2 && pile(s, T.c0 - 1, H) > T.f0 - T.c0 + 1 && canDig(s, T.c0 - 1, rows: rows) { T.c0 -= 1 } }
            if T.open1 { while T.c1 - T.f1 < low && T.c1 + 1 <= W - 3 && pile(s, T.c1 + 1, H) > T.c1 - T.f1 + 1 && canDig(s, T.c1 + 1, rows: rows) { T.c1 += 1 } }
            return T
        }
        let kc = max(lo, min(hi, Int(x * s.inv)))
        let rough = Int(24 * cu)                            // длина хода, если на то, удержится ли свод, не смотрят
        var soft: Tunnel? = nil                             // запасной вариант: свод не удержится
        var k = 0
        while kc - k >= lo || kc + k <= hi {
            for a in (k == 0 ? [kc] : [kc - k, kc + k]) where a >= lo && a <= hi && deep(a) {
                for d in [1, -1] where entry(a, d) {
                    var run = 1                             // сколько столбцов вглубь можно рыть под сводом
                    while run <= maxL && deep(a + d * run) { run += 1 }
                    guard run >= minL else { continue }
                    var L = min(run, maxL)
                    while L >= minL {                       // сквозной: за бугром снова можно выйти
                        let b = a + d * (L - 1)
                        if entry(b, -d) && roofHolds(s, min(a, b), max(a, b), rows: rows) && !taken(min(a, b), max(a, b)) {
                            return make(a, b, d, through: true)
                        }
                        L -= step
                    }
                    L = min(run - 1, maxL)
                    while L >= minL {                       // нора: дальше сплошной снег, свод опирается на него
                        let e = a + d * L
                        if roofHolds(s, min(a, e), max(a, e), rows: rows) && !taken(min(a, e), max(a, e)) { return make(a, e, d, through: false) }
                        L -= step
                    }
                    if soft == nil {
                        let b = a + d * (min(run, max(minL, rough)) - 1), e = a + d * min(run - 1, max(minL, rough))
                        if entry(b, -d) && !taken(min(a, b), max(a, b)) { soft = make(a, b, d, through: true) }
                        else if run > minL && !taken(min(a, e), max(a, e)) { soft = make(a, e, d, through: false) }
                    }
                }
            }
            k += step
        }
        // свод не удержится: для самотеста роем всё равно, а дети изредка лезут и в такой — если снег хотя бы плотный
        guard let T = soft else { return nil }
        if strict {
            var dense = 0
            for q in T.r0...T.r1 where s.hard[y * W + q] >= Sim.dense { dense += 1 }
            if dense * 4 < (T.r1 - T.r0 + 1) * 3 || rng.f() >= 0.08 { return nil }
        }
        return T
    }

    /// Утоптать столбец до наста сверху донизу: перемычка у устья, на которую ляжет свод.
    func packColumn(_ s: Sim, _ c: Int) {
        guard c >= 0, c < s.W else { return }
        let h = min(s.H, pile(s, c, s.H))
        guard h > 0 else { return }
        for r in (s.H - h)..<s.H {
            let i = r * s.W + c
            if s.snow[i] != 0 && s.hard[i] < 235 { s.hard[i] = 235 }
        }
        s.hardDirty = true
    }

    /// Ход бросили или он обвалился: перемычки у устьев снова рыхлые — что стоит без опоры, осыплется
    /// (утоптанные до наста, они иначе стояли бы столбиками вечно).
    func crumblePillars(_ s: Sim, _ T: Tunnel) {
        if T.open0 { soften(s, T.r0, above: 0) }
        if T.open1 { soften(s, T.r1, above: 0) }
    }

    /// Снег столбца c выше `above` ячеек над полом снова рыхлый: всё, что стоит без боковой опоры, осыплется.
    func soften(_ s: Sim, _ c: Int, above: Int) {
        guard c >= 0, c < s.W else { return }
        let h = min(s.H, pile(s, c, s.H))
        guard h > above else { return }
        var any = false
        for r in (s.H - h)..<(s.H - max(0, above)) {
            let i = r * s.W + c
            if s.snow[i] != 0 && s.hard[i] > 40 { s.hard[i] = 40; any = true }
        }
        if any {
            s.hardDirty = true
            s.snowDisturbed(c - 1, s.H - h - 1, c + 1, s.H - 1)
        }
    }

    /// Стойки наста — в один-два столбца, заметно выше снега с обеих сторон — сами собой не бывают и не падают
    /// (наст по склону не осыпается). Откуда бы такая ни взялась (перемычка хода, от которого ничего не осталось;
    /// осколок расколотого сугроба), она рыхлеет и осыпается.
    func sweepSpikes(_ s: Sim) {
        guard s.W >= 5 else { return }
        let lim = 4
        func free(_ c: Int) -> Bool {       // не чужая постройка
            if isStair(s, c, s.H - 1) || reserved(s, c) { return false }
            if wallTop >= 0 && c >= wallCol - 1 && c <= wallCol + 3 { return false }     // стенка от ветра
            for T in tunnels where (c == T.r0 || c == T.r1) && tunnelBusy(T.id) { return false }
            return true
        }
        var a = pile(s, 0, s.H), b = pile(s, 1, s.H), d = pile(s, 2, s.H)
        for c in 1..<(s.W - 2) {
            let e = pile(s, c + 2, s.H)
            if b - max(a, d) > lim {
                if free(c) { soften(s, c, above: max(a, d)) }
            } else if b - max(a, e) > lim && d - max(a, e) > lim {
                if free(c) && free(c + 1) { soften(s, c, above: max(a, e)); soften(s, c + 1, above: max(a, e)) }
            }
            a = b; b = d; d = e
        }
    }

    /// Какие строки столбца c надо освободить: под сводом — только ход, в траншее — весь столбец
    /// (на откосе — всё, что выше откоса), опоры свода — ничего.
    func tunnelSpan(_ s: Sim, _ T: Tunnel, _ c: Int) -> (r0: Int, r1: Int)? {
        guard c >= max(0, T.c0), c <= min(s.W - 1, T.c1), c != T.r0, c != T.r1, T.rows < s.H else { return nil }
        if c > T.r0 && c < T.r1 { return (s.H - T.rows, s.H - 1) }
        let k = c < T.f0 ? T.f0 - c : (c > T.f1 ? c - T.f1 : 0)        // столько ячеек остаётся лежать на откосе
        let h = min(s.H, pile(s, c, s.H))
        return h > k ? (s.H - h, s.H - 1 - k) : nil
    }

    /// Мешает ли снег в столбце c ползти. Крошки на дне не в счёт: под сводом — одна ячейка,
    /// в открытой траншее, куда всё время что-нибудь скатывается, — до трети высоты хода.
    func tunnelBlocked(_ s: Sim, _ T: Tunnel, _ c: Int) -> Bool {
        guard let sp = tunnelSpan(s, T, c) else { return false }
        let keep = c > T.r0 && c < T.r1 ? 1 : max(1, T.rows / 3)
        guard sp.r1 - keep >= sp.r0 else { return false }
        for r in sp.r0...(sp.r1 - keep) where s.snow[r * s.W + c] != 0 { return true }
        return false
    }

    /// Выбрать снег из столбца c. Возвращает, сколько ячеек снято и какой они слежалости (в среднем).
    /// limit — не больше стольких ячеек за раз, сверху: стоя в траншее, роют слоями. Иначе рядом с выбранным
    /// до дна столбцом встаёт отвесная стенка, и рыхлый снег съезжает с неё лавиной прямо на того, кто роет.
    func tunnelDig(_ s: Sim, _ T: Tunnel, _ c: Int, limit: Int = .max) -> (n: Int, hard: UInt8, top: Int) {
        guard let sp = tunnelSpan(s, T, c) else { return (0, 0, s.H) }
        var n = 0, hd = 0, top = s.H
        for r in sp.r0...sp.r1 {
            let i = r * s.W + c
            if s.snow[i] != 0 && s.ledge[i] == 0 {
                s.snow[i] = 0; n += 1; hd += Int(s.hard[i]); top = min(top, r)
                if n >= limit { break }
            }
        }
        if n > 0 {
            s.gridDirty = true
            s.snowDisturbed(c - 1, sp.r0 - 2, c + 1, sp.r1)
            // и по всей ширине хода — чтобы пустота под сводом перерисовалась целиком. Только нижняя строка:
            // будить всю толщу нельзя, рыхлый снег от этого «закипает» и сыплется на того, кто роет
            s.snowDisturbed(T.c0 - 1, s.H - 1, T.c1 + 1, s.H - 1)
        }
        return (n, UInt8(n > 0 ? hd / n : 0), top)
    }

    func startTunnel(_ p: inout Person, _ s: Sim, strict: Bool, at: Float? = nil) -> Bool {
        var T: Tunnel
        if let ready = tunnels.first(where: { $0.done && !$0.old && abs(tunnelMid($0, s) - p.x) < 220 * u && !tunnelBusy($0.id) }) {
            T = ready                                       // по готовому ходу
        } else if strict && (tunnels.filter({ !$0.old }).count >= 2 || folks.contains(where: { $0.job == .tunnel && !$0.gone })) {
            return false                                    // роют по одному
        } else if let found = tunnelSite(s, near: at ?? p.x, strict: strict, reach: at != nil ? 30 : 150) {
            T = found
            T.id = nextObjId
            nextObjId += 1
            tunnels.append(T)
        } else {
            return false
        }
        p.job = .tunnel
        p.obj = T.id
        p.aux = 0
        // в какую сторону ползти: в нору — от её входа, в сквозной ход — с ближнего конца
        p.aux2 = !T.open1 ? 1 : (!T.open0 ? -1 : (p.x <= tunnelMid(T, s) ? 1 : -1))
        next(&p, 0)
        return true
    }

    /// Вылезти наверх прямо отсюда (ход пропал или застрял).
    func popOut(_ p: inout Person, _ s: Sim) {
        if p.mode == .crawl || p.mode == .hop {
            p.mode = .ground
            p.stand = -2
            p.y = min(p.y, surface(s, x: p.x, stand: -2) ?? p.y)
            puff(s, p.x, p.y, n: 4, stand: -2)
        }
        idle(&p, 0.6)
        p.anim = .getup
    }

    /// Шагать к gx по дну траншеи: ноги просто идут по тому, что под ними, — без карабканья и без того,
    /// чтобы упереться в стенку (её сейчас и роют). true — дошёл.
    func tread(_ p: inout Person, _ s: Sim, to gx: Float, speed: Float, _ dt: Float) -> Bool {
        let dx = gx - p.x
        let gy = ground(s, x: p.x, feet: p.y, up: 2 * stepMax(s)) ?? p.y
        p.y += max(-40 * u * dt, min(80 * u * dt, gy - p.y))
        p.blockT = 0
        if abs(dx) < 1.5 { return true }
        p.face = dx > 0 ? 1 : -1
        let st = min(abs(dx), speed * dt)
        p.x += p.face * st
        p.walkPhase += st / (4.5 * u)
        p.anim = .walk
        return false
    }

    /// Первый столбец, где мешает снег, от столбца from в сторону stop (не включая его). nil — чисто.
    func firstBlocked(_ s: Sim, _ T: Tunnel, from: Int, to stop: Int) -> Int? {
        guard from != stop else { return nil }
        let di = stop > from ? 1 : -1
        var c = from
        while c != stop {
            if tunnelBlocked(s, T, c) { return c }
            c += di
        }
        return nil
    }

    /// Свалить n ячеек снега комьями сразу за внешним краем траншеи side: объём выкопанного не теряется.
    func dumpOutside(_ s: Sim, _ T: Tunnel, side: Float, _ n: Int, hard: UInt8) {
        guard n > 0 else { return }
        let outerX = (side < 0 ? Float(T.c0) : Float(T.c1 + 1)) * s.cell
        for _ in 0..<min(n, 120) {
            let x = clampX(outerX + side * rng.range(4, 30) * u, s)
            let y = (surface(s, x: x, stand: -2) ?? Float(s.H) * s.cell) - rng.range(1, 4) * u
            chunk(s, x, y, side * rng.range(10, 60), -rng.range(10, 50), hard: hard)
        }
    }

    /// Выбросить снег из траншеи side (-1 — левая, +1 — правая): комья летят из рук невысокой дугой за её край
    /// и ложатся там широко, а не кучей у самого края (с кучи всё съезжало бы обратно). Летит всё выбранное;
    /// если край выше, чем можно добросить, снег выносят и сваливают за краем.
    func throwOut(_ p: Person, _ s: Sim, _ T: Tunnel, side: Float, _ dug: (n: Int, hard: UInt8, top: Int)) {
        guard dug.n > 0 else { return }
        let outerX = (side < 0 ? Float(T.c0) : Float(T.c1 + 1)) * s.cell
        let rim = surface(s, x: clampX(outerX + side * 3 * u, s), stand: -2) ?? p.y
        let x0 = p.x + side * 2 * u, y0 = p.y - (p.tall - 6) * u
        let need = max(0, y0 - rim)                         // на сколько край выше рук
        let top = 0.85 * p.tall * u                         // выше не подбросить
        guard need + 3 * u <= top else {                    // не добросить — вынести и свалить за краем
            dumpOutside(s, T, side: side, dug.n, hard: dug.hard)
            return
        }
        let g: Float = 1400
        for _ in 0..<min(dug.n, 120) {
            let h = min(top, need + rng.range(3, 6) * u)
            let vy = sqrtf(2 * g * h)
            let t = (vy + sqrtf(max(0, vy * vy - 2 * g * need))) / g
            let dist = max(0, (outerX - x0) * side) + rng.range(6, 40) * u
            chunk(s, x0 + rng.range(-1, 1) * u, y0 + rng.range(-1, 1) * u, side * dist / t * 1.2, -vy * 1.1, hard: dug.hard)
        }
    }

    /// Снег, выбранный под сводом: свод и стенки при этом утаптываются (крепче держат),
    /// а сам снег выгребают наружу — комья выкатываются из устья по дну траншеи.
    func stowSnow(_ s: Sim, _ T: Tunnel, _ c: Int, _ dug: (n: Int, hard: UInt8, top: Int), mouth: Float, out: Float, rake: Bool) {
        guard dug.n > 0 else { return }
        let y = s.H - T.rows - 1
        if y >= 3 {
            for cc in max(T.r0, c - 1)...min(T.r1, c + 1) {
                for r in (y - 3)...y {
                    let i = r * s.W + cc
                    if s.snow[i] != 0 && s.hard[i] < 255 { s.hard[i] = UInt8(min(255, Int(s.hard[i]) + 40)) }
                }
            }
            s.hardDirty = true
        }
        // Объём не пропадает: всё выбранное вытаскивают по траншее наружу и сваливают за её краем
        // (не у самого устья и не на того, кто там лежит).
        _ = rake
        _ = mouth
        dumpOutside(s, T, side: out, dug.n, hard: dug.hard)
    }

    /// Рыть траншею side одним проходом от столбца goalX к stop (за спиной её уже понемногу заносит — назад
    /// не возвращается). Роет слоями, в такт взмахам рук, понемногу подаваясь вперёд; выбранное бросает за край.
    /// В goalX — докуда дошёл. true — дошёл до конца.
    func digTrench(_ p: inout Person, _ s: Sim, _ T: Tunnel, side: Float, to stop: Int, _ dt: Float) -> Bool {
        let from = max(T.c0, min(T.c1, Int(p.goalX)))
        guard let c = firstBlocked(s, T, from: from, to: stop) else { return true }
        p.goalX = Float(c)
        let d: Float = stop > from ? 1 : -1
        let standX = (d > 0 ? Float(c) : Float(c + 1)) * s.cell - d * max(3 * u, 2 * s.cell)
        if abs(standX - p.x) > 5 * u {                      // далеко — подойти
            _ = tread(&p, s, to: standX, speed: 20 * u, dt)
            return false
        }
        _ = tread(&p, s, to: p.x, speed: 0, dt)            // ноги — по дну
        p.x += max(-7 * u * dt, min(7 * u * dt, standX - p.x))
        digBeat(&p, s, T, c, side: side, face: d, dt)
        return false
    }

    /// Стоя копает столбец c: взмах — слой снега.
    func digBeat(_ p: inout Person, _ s: Sim, _ T: Tunnel, _ c: Int, side: Float, face: Float, _ dt: Float) {
        p.face = face
        p.anim = .dig
        let now = s.time * 7 + Float(p.id)                  // тот же счёт, что у взмахов в позе
        if Int(now) != Int(now - dt * 7) {
            throwOut(p, s, T, side: side, tunnelDig(s, T, c, limit: max(2, T.rows / 2)))
        }
    }

    /// Не вышло (снег сыплется быстрее, чем копает): бросить. Ход, который не дался дважды, забывают.
    func giveUp(_ p: inout Person, _ k: Int) {
        tunnels[k].fails += 1
        idle(&p, 0.5)
    }

    func runTunnel(_ p: inout Person, _ s: Sim, _ dt: Float) {
        guard let k = tunnels.firstIndex(where: { $0.id == p.obj }) else { popOut(&p, s); return }
        let T = tunnels[k]
        let dir: Float = p.aux2 >= 0 ? 1 : -1               // куда ползти: от входа вглубь
        let di = dir > 0 ? 1 : -1
        let through = dir > 0 ? T.open1 : T.open0           // сквозной ход или нора
        let floorY = Float(s.H) * s.cell
        let off = max(3 * u, 2.5 * s.cell)
        let inX = dir > 0 ? Float(T.c0) * s.cell : Float(T.c1 + 1) * s.cell         // внешний край траншеи у входа
        let outX = dir > 0 ? Float(T.c1 + 1) * s.cell : Float(T.c0) * s.cell        // и у выхода (в сквозном)
        let inPillar = dir > 0 ? T.r0 : T.r1, farEnd = dir > 0 ? T.r1 : T.r0
        let mouth = dir > 0 ? Float(T.r0) * s.cell : Float(T.r1 + 1) * s.cell      // устье: внешний бок перемычки у входа
        var lieX = mouth - dir * (p.tall * u + 2)           // лёжа у входа: голова у самой перемычки
        lieX = dir > 0 ? max(lieX, inX + 1) : min(lieX, inX - 1)
        let digT = 0.22 * min(1, s.cell / 3)                // столбец под сводом
        switch p.phase {
        case 0:     // к входу
            if walk(&p, s, to: clampX(inX - dir * off, s), speed: 26 * u, dt) {
                if p.mode == .ground { p.aux = 0; p.goalX = Float(dir > 0 ? T.c0 : T.c1); next(&p, 1) }
            } else if p.t > 25 {
                giveUp(&p, k)
            }
        case 1:     // траншея у входа: откос и дно, до самой перемычки (в готовом ходе — только расчистить)
            if !p.flag {
                p.flag = true
                // утоптать перемычки у устьев, пока свод ещё на снегу (если он вообще удержится)
                if roofHolds(s, T.r0, T.r1, rows: T.rows) {
                    if T.open0 { packColumn(s, T.r0) }
                    if T.open1 { packColumn(s, T.r1) }
                }
            }
            if digTrench(&p, s, T, side: -dir, to: inPillar, dt) { next(&p, 2) } else if p.t > 40 { giveUp(&p, k) }
        case 2:     // отойти на свой рост от перемычки, дочистить место под собой и лечь
            guard tread(&p, s, to: lieX, speed: 20 * u, dt) || p.t > 6 else { return }
            if let c = firstBlocked(s, T, from: Int(lieX * s.inv) - di, to: inPillar) {
                digBeat(&p, s, T, c, side: -dir, face: dir, dt)
                if p.t > 16 { giveUp(&p, k) }
                return
            }
            p.mode = .crawl
            p.y = floorY
            p.face = dir
            p.fallDir = dir
            p.aux = digT
            next(&p, 3)
        case 3, 6, 7:   // ползком: 3 — вглубь, выбирая снег перед собой; 6 — в конце норы; 7 — задом обратно
            guard p.mode == .crawl || p.mode == .hop else { popOut(&p, s); return }
            // Пока ноги протискиваются сквозь перемычку, это не «ползёт под снегом»: утоптанный столбец
            // у самых ног иначе сошёл бы за завал (PeopleRescue меряет снег вокруг ног).
            let zone = 1.5 * u + s.cell * 0.5 + 1
            p.mode = abs(p.x - (Float(T.r0) + 0.5) * s.cell) < zone || abs(p.x - (Float(T.r1) + 0.5) * s.cell) < zone ? .hop : .crawl
            p.anim = .crawl
            p.y = floorY
            p.face = dir
            p.fallDir = dir
            if p.t > 45 { tunnels[k].fails += 1; popOut(&p, s); return }       // застрял — наверх
            p.aux = min(p.aux + dt, digT)
            if p.phase == 6 {           // добрался до конца норы: полежал — и назад
                p.walkPhase += dt * 2
                if p.t > 1.2 { next(&p, 7) }
                return
            }
            if p.phase == 7 {           // пятится к входу; что насыпалось за спиной — выгребает ногами наружу
                if dir > 0 ? p.x <= lieX : p.x >= lieX {
                    p.mode = .ground
                    p.stand = -2
                    next(&p, 5)
                    p.anim = .getup
                    return
                }
                let cb = Int((p.x - dir * (1.5 * u + s.cell)) * s.inv)
                if tunnelBlocked(s, T, cb) {
                    if p.aux >= digT {      // приминает ногами
                        p.aux = 0
                        let d = tunnelDig(s, T, cb)
                        if d.n > 0 {
                            dust(s, (Float(cb) + 0.5) * s.cell, floorY - 2 * s.cell)
                            dumpOutside(s, T, side: -dir, d.n, hard: d.hard)       // выгребает наружу, объём не теряется
                        }
                    }
                } else {
                    let st = min(s.cell * 0.9, 12 * u * dt)
                    p.x -= dir * st
                    p.walkPhase += st / (3 * u)
                }
                return
            }
            // сквозной ход: ноги уже за дальней перемычкой — можно вставать
            if through && (dir > 0 ? p.x > Float(T.r1 + 1) * s.cell + 1.5 * u : p.x < Float(T.r0) * s.cell - 1.5 * u) {
                tunnels[k].done = true
                tunnels[k].fails = 0
                p.mode = .ground
                p.stand = -2
                p.goalX = Float(Int(p.x * s.inv))
                next(&p, 4)
                p.anim = .getup
                return
            }
            let ch = Int((p.x + dir * (p.tall * u + 1)) * s.inv)        // столбец перед головой
            if !through && (dir > 0 ? ch >= farEnd : ch <= farEnd) {    // нора дорыта
                tunnels[k].done = true
                tunnels[k].fails = 0
                next(&p, 6)
                return
            }
            // что мешает: сначала снег перед головой, потом осыпавшийся на тело
            var target = -1
            var ahead = tunnelBlocked(s, T, ch)
            if ahead { target = ch } else {
                for j in 1...(Int(p.tall * u * s.inv) + 1) where tunnelBlocked(s, T, ch - di * j) { target = ch - di * j; break }
            }
            if target >= 0 && p.aux >= digT {
                p.aux = 0
                let dug = tunnelDig(s, T, target)
                if target > T.r0 && target < T.r1 {         // под сводом: в свод и стенки, немного — наружу
                    let inside = (p.x - (mouth + dir * s.cell)) * dir > 3 * u        // ноги уже под сводом
                    stowSnow(s, T, target, dug, mouth: mouth, out: -dir, rake: inside)
                } else if dir > 0 ? target > T.r1 : target < T.r0 {
                    // за дальней перемычкой: что лежало выше хода, вываливается вперёд, остальное приминает
                    let over = max(pile(s, target + di, s.H), pile(s, target + 2 * di, s.H), s.H - dug.top)
                    for _ in 0..<min(dug.n, 90) {
                        chunk(s, (Float(target) + 0.5) * s.cell, Float(s.H - over) * s.cell - rng.range(0.5, 1.5) * s.cell,
                              dir * rng.range(50, 130), -rng.range(30, 80), hard: dug.hard)
                    }
                } else {                                    // у входа, за спиной: выгребает наружу
                    dust(s, (Float(target) + 0.5) * s.cell, floorY - 2 * s.cell)
                    dumpOutside(s, T, side: -dir, dug.n, hard: dug.hard)
                }
                if target == ch { ahead = tunnelBlocked(s, T, ch) }
            }
            if !ahead {             // роет — ползёт ровно с той скоростью, с какой выбирает снег; свободно — быстрее
                let digging = p.aux < digT
                let st = min(s.cell * 0.9, (digging ? s.cell / digT : 16 * u) * dt)
                p.x += dir * st
                p.walkPhase += (digging ? dt * 4 : st / (3 * u))
            } else {
                p.walkPhase += dt * 4
            }
        case 4:     // встал за дальней перемычкой; откосом — наружу
            if p.t < 0.35 { p.anim = .getup; _ = tread(&p, s, to: p.x, speed: 0, dt); return }
            if digTrench(&p, s, T, side: dir, to: dir > 0 ? T.c1 + 1 : T.c0 - 1, dt) || p.t > 40 { next(&p, 5) }
        default:    // выйти по откосу — и радоваться
            if p.t < 0.3 { p.anim = .getup; _ = tread(&p, s, to: p.x, speed: 0, dt); return }
            let gx = through ? outX + dir * off : inX - dir * off
            if tread(&p, s, to: clampX(gx, s), speed: 22 * u, dt) || p.t > 8 {
                p.job = .cheer
                p.wait = 1.8
                next(&p, 0)
            }
        }
    }

    // MARK: - Снежный ангел

    func startAngel(_ p: inout Person, _ s: Sim) -> Bool {
        var dir = p.face
        let len = (p.tall + 3) * u
        if p.x + dir * len < 10 || p.x + dir * len > s.wPt - 10 { dir = -dir }
        let a = Int(min(p.x, p.x + dir * len) * s.inv), b = Int(max(p.x, p.x + dir * len) * s.inv)
        guard a >= 1, b < s.W - 1, !overDock(s, p.x + dir * len * 0.5, pad: len) else { return false }
        var lo = Int.max, hi = 0
        for c in a...b {
            let h = pile(s, c, s.H)
            if h < 1 || isStair(s, c, s.H - 1) || reserved(s, c) { return false }
            lo = min(lo, h); hi = max(hi, h)
        }
        if hi < 2 || Float(hi - lo) * s.cell > max(6 * u, 2 * s.cell) { return false }      // лечь нужно на снег, и на ровное
        for T in tunnels where T.c0 <= b && T.c1 >= a { return false }
        p.face = dir
        p.fallDir = dir
        p.job = .angel
        next(&p, 0)
        return true
    }

    func runAngel(_ p: inout Person, _ s: Sim, _ dt: Float) {
        settle(&p, s, dt)
        if p.mode != .ground { return }
        if p.phase == 0 {               // присел — и на спину
            p.anim = .getup
            if p.t > 0.25 { next(&p, 1) }
            return
        }
        p.anim = .angel
        if p.t > 1.0 && !p.flag {       // отпечаток: верхний слой из-под рук и ног разлетается в стороны
            p.flag = true
            let x1 = p.x + p.fallDir * p.tall * u
            let a = max(1, Int(min(p.x, x1) * s.inv)), b = min(s.W - 2, Int(max(p.x, x1) * s.inv))
            if a <= b {
                var rMin = s.H, rMax = 0
                for c in a...b {
                    let h = pile(s, c, s.H)
                    let r = s.H - h
                    guard h >= 2, r >= 0, !isStair(s, c, r), !reserved(s, c) else { continue }
                    let i = r * s.W + c
                    guard s.snow[i] != 0 else { continue }
                    s.snow[i] = 0
                    rMin = min(rMin, r); rMax = max(rMax, r)
                    let side: Float = c * 2 < a + b ? -1 : 1
                    chunk(s, (Float(c) + 0.5) * s.cell, Float(r) * s.cell - 2, side * rng.range(50, 120), -rng.range(80, 150))
                }
                if rMin <= rMax {
                    s.gridDirty = true
                    s.snowDisturbed(a - 1, rMin - 1, b + 1, rMax + 1)
                }
            }
        }
        if p.t > 3 {
            p.job = .hit
            next(&p, 3)                 // встаёт
        }
    }

    // MARK: - Санки

    /// Происшествие: мимо везут санки. false — сейчас нельзя.
    func startSled(_ s: Sim) -> Bool {
        guard s.cfg.people > 0 || forced, folks.count < 10,
              !folks.contains(where: { ($0.job == .sled || $0.job == .ride) && !$0.gone }) else { return false }
        // с той стороны, откуда с санками можно пройти весь экран (ямы и стенки — не для них)
        var left = rng.f() < 0.5
        if !pathClear(s, from: left ? 0 : s.wPt, to: left ? s.wPt : 0, tall: 17) {
            left.toggle()
            if !pathClear(s, from: left ? 0 : s.wPt, to: left ? s.wPt : 0, tall: 17) { return false }
        }
        let dir: Float = left ? 1 : -1
        let y = surface(s, x: left ? 2 : s.wPt - 2, stand: -2) ?? s.hPt
        var a = Person(id: nextId, look: makeLook(kid: false, girl: rng.f() < 0.45))
        var k = Person(id: nextId + 1, look: makeLook(kid: true, girl: rng.f() < 0.5))
        nextId += 2
        a.x = left ? -14 : s.wPt + 14
        a.y = y
        a.face = dir
        a.job = .sled
        a.goalX = left ? s.wPt + 60 * u : -60 * u
        k.x = a.x - dir * People.sledGap * u
        k.y = y - 4 * u
        k.face = dir
        k.job = .ride
        k.target = a.id
        folks.append(a)
        folks.append(k)
        return true
    }

    /// Тянет санки через весь экран.
    func runSled(_ p: inout Person, _ s: Sim, _ dt: Float) {
        let dir: Float = p.goalX > s.wPt * 0.5 ? 1 : -1
        _ = walk(&p, s, to: p.goalX, speed: 24 * u, dt)
        if p.mode != .ground { return }
        if p.blockT > 0.3 && !p.flag {          // стенка, на которую с санками не влезть: разворачивается и увозит обратно
            p.flag = true
            p.blockT = 0
            p.goalX = dir > 0 ? -60 * u : s.wPt + 60 * u
            return
        }
        p.face = dir
        if p.anim == .walk || p.anim == .run || p.anim == .stand { p.anim = .pull }
        if (dir > 0 ? p.x > s.wPt + 40 * u : p.x < -40 * u) || p.t > 240 { p.gone = true }
    }

    /// Едет на санках за тем, кто тянет.
    func runRide(_ p: inout Person, _ s: Sim, _ dt: Float) {
        guard let q = folks.first(where: { $0.id == p.target }), !q.gone, q.job == .sled else {
            if p.x < 4 || p.x > s.wPt - 4 { p.gone = true; return }      // уехали за край вместе
            p.target = -1                                                 // везти некому — слезает
            idle(&p, rng.range(0.5, 1.5))
            p.anim = .getup
            return
        }
        p.face = q.face
        let want = q.x - q.face * People.sledGap * u
        p.x += max(-70 * u * dt, min(70 * u * dt, want - p.x))
        let sy = surface(s, x: max(0, min(s.wPt, p.x)), stand: -2) ?? q.y
        p.y += max(-60 * u * dt, min(60 * u * dt, sy - 4 * u - p.y))      // сиденье в четырёх «пикселях» над снегом
        p.anim = .ride
    }

    // MARK: - Ёлка

    /// Происшествие: приносят и ставят ёлку. false — сейчас нельзя.
    func startTree(_ s: Sim) -> Bool {
        guard s.cfg.people > 0 || forced, trees.isEmpty, folks.count < 12,
              !folks.contains(where: { $0.job == .tree && !$0.gone }), let x = treeSpot(s) else { return false }
        var left = x < s.wPt * 0.5 ? rng.f() < 0.7 : rng.f() < 0.3
        if !pathClear(s, from: left ? 0 : s.wPt, to: x, tall: 17) {       // с ёлкой через ямы не лазают
            left.toggle()
            if !pathClear(s, from: left ? 0 : s.wPt, to: x, tall: 17) { return false }
        }
        var p = Person(id: nextId, look: makeLook(kid: false, girl: rng.f() < 0.4))
        nextId += 1
        p.x = left ? -16 : s.wPt + 16
        p.y = surface(s, x: left ? 2 : s.wPt - 2, stand: -2) ?? s.hPt
        p.face = left ? 1 : -1
        p.job = .tree
        p.obj = People.treeTag
        p.goalX = x - p.face * 5 * u            // встанет рядом, ёлка — перед ним
        folks.append(p)
        visitEnd = max(visitEnd, s.time + 60)   // поставит — и ещё побудет
        return true
    }

    /// Здесь можно поставить ёлку.
    func treeOK(_ s: Sim, _ x: Float) -> Bool {
        guard x > 30 * u, x < s.wPt - 30 * u, !overDock(s, x, pad: 12 * u) else { return false }
        let a = max(0, Int((x - 9 * u) * s.inv)), b = min(s.W - 1, Int((x + 9 * u) * s.inv))
        guard a <= b else { return false }
        for c in a...b where isStair(s, c, s.H - 1) || reserved(s, c) || inDock(s, c) { return false }
        for T in tunnels where T.c0 <= b && T.c1 >= a { return false }
        if let st = site, abs(st.x - x) < 20 * u { return false }
        return true
    }

    func treeSpot(_ s: Sim) -> Float? {
        for ig in igloos {                      // рядом с домом
            let first: Float = rng.f() < 0.5 ? -1 : 1
            var d = 20 * u
            while d < 70 * u {
                for side in [first, -first] where treeOK(s, ig.x + side * d) { return ig.x + side * d }
                d += 4 * u
            }
        }
        for _ in 0..<14 {
            let x = rng.range(s.wPt * 0.3, s.wPt * 0.7)
            if treeOK(s, x) { return x }
        }
        return nil
    }

    func runTree(_ p: inout Person, _ s: Sim, _ dt: Float) {
        switch p.phase {
        case 0:     // несёт
            let there = walk(&p, s, to: p.goalX, speed: 20 * u, dt)
            if p.mode != .ground { return }
            if p.anim != .climb { p.anim = .carryTree }
            let tx = ((p.x + p.face * 5 * u) / u).rounded() * u
            if trees.isEmpty && (there || p.t > 90) && treeOK(s, tx) {
                trees.append(Tree(id: nextObjId, x: tx, born: s.time))
                p.obj = nextObjId
                nextObjId += 1
                next(&p, 1)
            } else if there || p.t > 90 || p.blockT > 0.3 {
                // не дойти (стенка выше груди) или место заняли: поискать другое, с третьего раза — бросить
                p.blockT = 0
                p.tries += 1
                if p.tries > 3 || !trees.isEmpty {
                    p.obj = -1
                    idle(&p, 0.5)
                } else {
                    let back = clampX(p.x - p.face * rng.range(16, 40) * u, s)
                    p.goalX = treeOK(s, back - p.face * 5 * u) ? back : (treeSpot(s) ?? back)
                    p.t = 0
                }
            }
        case 1:     // притаптывает снег у ствола
            p.anim = .pat
            settle(&p, s, dt)
            if p.t > 1.3 { p.goalX = clampX(p.x - p.face * 7 * u, s); next(&p, 2) }
        default:    // отходит полюбоваться
            let back = p.face
            if walk(&p, s, to: p.goalX, speed: 16 * u, dt) || p.t > 4 || p.blockT > 0.2 {
                p.blockT = 0
                p.face = p.t > 0.3 ? -back : back
                p.job = .cheer
                p.wait = 2.2
                next(&p, 0)
            }
        }
    }

    // MARK: - Раз в кадр

    func stepFun(_ s: Sim, _ dt: Float) {
        var k = 0
        while k < tunnels.count {
            tunnels[k].acc += dt
            if tunnels[k].acc >= 0.5 {
                tunnels[k].acc = 0
                // Ход бросили, засыпало или рухнул свод: перемычки рыхлеют (иначе стояли бы столбиками наста вечно),
                // запись убираем. Целый ход через пять минут детям надоедает, но запись живёт, пока он цел.
                if !tunnelBusy(tunnels[k].id) {
                    if !tunnelAlive(s, tunnels[k]) {
                        crumblePillars(s, tunnels[k])
                        tunnels.remove(at: k)
                        continue
                    }
                    if s.time - tunnels[k].born > 300 { tunnels[k].old = true }
                }
            }
            k += 1
        }
        if Int(s.time * 0.5) != Int((s.time - dt) * 0.5) { sweepSpikes(s) }       // раз в две секунды
        var i = 0
        while i < trees.count {
            var t = trees[i]
            // пока рядом люди, ёлку отряхивают; ушли — её понемногу заносит
            if folks.isEmpty { t.cover += dt * max(s.cfg.intensity, s.cfg.flakeRate / 30) / 1200 }
            let sy = surface(s, x: t.x, stand: -2) ?? s.hPt
            if t.cover > 0.03 && s.cursorOn && s.cvx * s.cvx + s.cvy * s.cvy > 400 * 400
                && abs(s.cx - t.x) < 8 * u && s.cy < sy && s.cy > sy - 26 * u {
                t.cover = max(0, t.cover - 3 * dt)          // курсор стряхивает снег
                dust(s, t.x + rng.range(-6, 6) * u, s.cy)
            }
            if t.cover >= 1 {                               // занесло совсем: осыпается в сугроб
                let n = min(150, Int(26 * u * 10 * u * 0.5 / (s.cell * s.cell)))
                for _ in 0..<n {
                    let h = rng.f()
                    chunk(s, t.x + rng.range(-1, 1) * (1 - h) * 8 * u, sy - 2 - h * 24 * u, rng.range(-25, 25), rng.range(0, 30))
                }
                for _ in 0..<10 { dust(s, t.x + rng.range(-8, 8) * u, sy - rng.range(2, 24) * u) }
                trees.remove(at: i)
                continue
            }
            trees[i] = t
            i += 1
        }
    }

    /// Ход ещё цел: прокопан, засыпан меньше чем наполовину, свод на месте.
    func tunnelAlive(_ s: Sim, _ T: Tunnel) -> Bool {
        guard T.done, T.fails < 2, T.r0 >= 0, T.r1 < s.W, T.r1 - T.r0 >= 3, T.rows < s.H else { return false }
        var filled = 0, roof = 0
        for c in (T.r0 + 1)..<T.r1 {
            for r in (s.H - T.rows)..<s.H where s.snow[r * s.W + c] != 0 { filled += 1 }
            if pile(s, c, s.H) > T.rows { roof += 1 }
        }
        let n = T.r1 - T.r0 - 1
        return filled * 2 <= n * T.rows && roof * 2 >= n
    }

    // MARK: - Отрисовка

    static let sledGap: Float = 19      // от тянущего до середины санок, «пикселей»
    static let wood = SIMD4<Float>(0.45, 0.28, 0.15, 1), woodLight = SIMD4<Float>(0.86, 0.62, 0.33, 1)
    static let rope = SIMD4<Float>(0.74, 0.62, 0.42, 1), sledRed = SIMD4<Float>(0.84, 0.22, 0.20, 1)
    static let fir: [SIMD4<Float>] = [SIMD4(0.08, 0.40, 0.21, 1), SIMD4(0.15, 0.55, 0.27, 1), SIMD4(0.27, 0.70, 0.35, 1)]
    static let trunk = SIMD4<Float>(0.40, 0.25, 0.14, 1)
    static let snowW = SIMD4<Float>(0.97, 0.985, 1, 1), snowS = SIMD4<Float>(0.80, 0.86, 0.96, 1)
    /// Полуширина ёлки по строкам снизу вверх: четыре яруса по пять строк.
    static let treeHW: [Int] = [8, 7, 6, 5, 4, 6, 5, 4, 4, 3, 5, 4, 3, 2, 2, 3, 2, 2, 1, 0]
    /// Огоньки: строка яруса снизу, смещение от ствола, цвет.
    static let treeLights: [(k: Int, dx: Int, c: Int)] = [
        (1, -5, 0), (2, 0, 1), (1, 4, 2), (6, 3, 3), (7, -2, 4), (6, -4, 5),
        (11, -2, 1), (12, 1, 0), (11, 3, 2), (16, -1, 3), (17, 1, 4)]
    static let lightColors: [SIMD3<Float>] = [
        SIMD3(1.0, 0.27, 0.24), SIMD3(1.0, 0.86, 0.25), SIMD3(0.36, 0.62, 1.0),
        SIMD3(1.0, 0.42, 0.82), SIMD3(1.0, 0.60, 0.18), SIMD3(0.42, 0.96, 0.92)]

    /// Прямоугольник в «пикселях» человечка от точки (ox, oy); f < 0 — зеркально.
    @inline(__always)
    func px(_ out: inout [PxInst], _ ox: Float, _ oy: Float, _ f: Float, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: SIMD4<Float>) {
        let wx = f > 0 ? ox + Float(x) * u : ox - Float(x + w) * u
        out.append(PxInst(rect: SIMD4(wx, oy + Float(y) * u, Float(w) * u, Float(h) * u), color: c))
    }

    func emitFun(_ s: Sim, into out: inout [PxInst]) {
        for t in trees { emitTree(s, t, into: &out) }
        for p in folks where !p.gone {
            if p.job == .sled { emitSled(s, p, into: &out) }
            else if p.job == .tree && p.phase == 0 { emitCarried(s, p, down: false, into: &out) }
            else if p.obj == People.treeTag && p.job != .tree && p.job != .leave && p.job != .buried && p.mode == .ground {
                emitCarried(s, p, down: true, into: &out)       // уронил
            }
        }
    }

    /// Ёлка: ствол, четыре яруса лап, звезда, огоньки. Снег ложится на лапы сверху: чем больше занесло,
    /// тем больше строк каждого яруса под снегом; под конец — белый конус.
    func emitTree(_ s: Sim, _ t: Tree, into out: inout [PxInst]) {
        guard t.x > -12 * u, t.x < s.wPt + 12 * u, let sy = surface(s, x: t.x, stand: -2) else { return }
        let ox = (t.x / u).rounded() * u, oy = (sy / u).rounded() * u + u
        let cover = min(1, max(0, t.cover))
        let m = Int(cover * 5.2)                            // столько верхних строк яруса занесено
        let tip = cover > 0.5 ? 2 : (cover > 0.08 ? 1 : 0)  // и столько «пикселей» на концах остальных лап
        px(&out, ox, oy, 1, -1, -3, 3, 3, People.trunk)
        px(&out, ox, oy, 1, 1, -3, 1, 3, People.wood)
        for k in 0..<People.treeHW.count {
            let hw = People.treeHW[k], row = -4 - k, tier = k % 5
            let w = 2 * hw + 1
            if tier >= 5 - m {
                px(&out, ox, oy, 1, -hw, row, w, 1, People.snowW)
                if hw >= 2 { px(&out, ox, oy, 1, hw - hw / 2, row, hw / 2 + 1, 1, People.snowS) }
                continue
            }
            px(&out, ox, oy, 1, -hw, row, w, 1, People.fir[tier == 0 ? 0 : (tier >= 3 ? 2 : 1)])
            if hw >= 2 { px(&out, ox, oy, 1, hw - hw / 2, row, hw / 2 + 1, 1, People.fir[tier >= 3 ? 1 : 0]) }      // тень справа
            if tip > 0 && hw > tip {
                px(&out, ox, oy, 1, -hw, row, tip, 1, People.snowW)
                px(&out, ox, oy, 1, hw - tip + 1, row, tip, 1, People.snowS)
            }
        }
        for (j, l) in People.treeLights.enumerated() {
            if l.k % 5 >= 5 - m || abs(l.dx) > People.treeHW[l.k] - tip { continue }       // под снегом
            let c = People.lightColors[l.c]
            if sinf(s.time * 2.3 + Float(j) * 1.9 + Float(t.id)) > -0.25 {
                let glow = SIMD4<Float>(c.x * 0.3, c.y * 0.3, c.z * 0.3, 0.3)
                px(&out, ox, oy, 1, l.dx - 1, -4 - l.k, 3, 1, glow)
                px(&out, ox, oy, 1, l.dx, -5 - l.k, 1, 3, glow)
                px(&out, ox, oy, 1, l.dx, -4 - l.k, 1, 1, SIMD4(c.x, c.y, c.z, 1))
            } else {
                px(&out, ox, oy, 1, l.dx, -4 - l.k, 1, 1, SIMD4(c.x * 0.45, c.y * 0.45, c.z * 0.45, 1))
            }
        }
        let top = -4 - People.treeHW.count                  // первая строка над макушкой
        if cover < 0.9 {            // звезда
            let c = sinf(s.time * 3.1 + Float(t.id)) > 0.3 ? SIMD4<Float>(1, 0.90, 0.38, 1) : SIMD4<Float>(1, 0.74, 0.12, 1)
            px(&out, ox, oy, 1, -1, top, 1, 1, c)
            px(&out, ox, oy, 1, 1, top, 1, 1, c)
            px(&out, ox, oy, 1, -1, top - 1, 3, 1, c)
            px(&out, ox, oy, 1, -2, top - 2, 5, 1, c)
            px(&out, ox, oy, 1, 0, top - 3, 1, 1, c)
            if cover > 0.45 {
                px(&out, ox, oy, 1, 0, top - 3, 1, 1, People.snowW)
                px(&out, ox, oy, 1, -2, top - 2, 5, 1, People.snowW)
            }
        } else {
            px(&out, ox, oy, 1, -1, top - 1, 3, 2, People.snowW)
        }
    }

    /// Санки за тем, кто тянет: полозья с загнутым передком, сиденье, спинка — и верёвка к руке.
    func emitSled(_ s: Sim, _ q: Person, into out: inout [PxInst]) {
        let f = q.face
        var sx = q.x - f * People.sledGap * u
        var sy: Float
        if let r = folks.first(where: { $0.job == .ride && $0.target == q.id && !$0.gone }) {
            sx = r.x
            sy = r.y + 4 * u
        } else {
            sy = surface(s, x: max(0, min(s.wPt, sx)), stand: -2) ?? q.y
        }
        guard sx > -30 * u, sx < s.wPt + 30 * u else { return }
        let ox = (sx / u).rounded() * u, oy = (sy / u).rounded() * u + u
        px(&out, ox, oy, f, -7, -1, 14, 1, People.wood)             // полоз
        px(&out, ox, oy, f, 7, -3, 1, 2, People.wood)               // загнутый передок
        px(&out, ox, oy, f, 6, -4, 1, 1, People.wood)
        px(&out, ox, oy, f, -5, -3, 1, 2, People.wood)              // стойки
        px(&out, ox, oy, f, 3, -3, 1, 2, People.wood)
        px(&out, ox, oy, f, -6, -4, 12, 1, People.woodLight)        // сиденье
        px(&out, ox, oy, f, -6, -8, 1, 4, People.sledRed)           // спинка
        px(&out, ox, oy, f, -6, -8, 2, 1, People.sledRed)
        // верёвка от передка к руке
        let hx = q.x - f * 5.5 * u, hy = q.y - 5.5 * u
        let fx = sx + f * 7.5 * u, fy = sy - 2.5 * u
        for k in 1...5 {
            let t = Float(k) / 6
            let x = fx + (hx - fx) * t, y = fy + (hy - fy) * t + sinf(t * .pi) * 1.5 * u
            out.append(PxInst(rect: SIMD4(((x - u * 0.5) / u).rounded() * u, ((y - u * 0.5) / u).rounded() * u, u, u), color: People.rope))
        }
    }

    /// Ёлка на плече: лежит наклонно, комлем вперёд, макушкой назад и вверх. down — уронил: лежит на снегу перед ним.
    func emitCarried(_ s: Sim, _ p: Person, down: Bool, into out: inout [PxInst]) {
        guard p.x > -30 * u, p.x < s.wPt + 30 * u else { return }
        let f = p.face
        let ox = (p.x / u).rounded() * u, oy = ((p.y + u) / u).rounded() * u
        let top = p.look.kid ? -7 : -9                              // строка плеч
        for i in 0..<22 {
            let x = down ? 4 + i : 6 - i, y = down ? -6 : top - 2 - (i * 3 + 5) / 10
            if i < 3 {
                px(&out, ox, oy, f, x, y, 1, 1, People.trunk)
                continue
            }
            let k = i - 3
            let hw = max(1, (People.treeHW[k] * 6 + 5) / 10), tier = k % 5
            px(&out, ox, oy, f, x, y - hw, 1, 2 * hw + 1, People.fir[tier == 0 ? 0 : (tier >= 3 ? 2 : 1)])
            px(&out, ox, oy, f, x, y + hw, 1, 1, People.fir[0])
        }
    }
}
