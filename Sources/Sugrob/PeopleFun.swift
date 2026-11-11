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
// Порядок: ребёнок роет траншею у входа, ложится, ползёт под сводом, выбирая снег перед собой (свод при этом
// утаптывается, снег вытаскивают наружу). В сквозном ходе за дальней перемычкой выкапывает место, чтобы
// встать, и откосом выбирается наружу; из норы пятится обратно.
//
// Раскопки растут: в следующий заход нору удлиняют (бывший торец становится перемычкой), выводят второе
// устье, роют в конце комнатку (в ней сидят, пригнувшись, двое-трое — и пережидают буран, см. denShelter),
// дорываются до соседнего хода или до пустоты под настом, прорубают ступеньками лаз наверх. Где рыли и
// лазили, помнится: новое начинают в стороне от недавнего (см. dugNear), один и тот же ход ребёнку
// надоедает после пары раз, а после любой вылазки к тоннелям какое-то время не тянет.

struct Tunnel {
    var id: Int
    var c0: Int, c1: Int        // столбцы от и до, вместе с траншеями-подходами
    var rows: Int               // высота хода, ячеек
    var born: Float
    var sup: [Int] = []         // опоры свода слева направо: перемычки (сквозь них пролезают) и глухие торцы
    var seg: [Bool] = []        // вырыт ли отрезок хода между sup[i] и sup[i + 1]
    var packed: [Int] = []      // какие опоры утоптаны до наста (бросят ход — их надо разрыхлить)
    var f0 = 0, f1 = 0          // докуда у траншей ровное дно; дальше к c0 и c1 — откос, ячейка на столбец
    var open0 = true, open1 = true  // с какого конца есть вход: у сквозного — с обоих, у норы — с одного
    var room = -1               // комнатка — отрезок с этим номером (-1 — нет): в ней сидят
    var roomRows = 0            // её высота, ячеек
    var shaft = 0               // лаз наверх ступеньками за глухим торцом: -1 — за левым, +1 — за правым, 0 — нет
    var shaftN = 0              // сколько ступеней в нём вырыто (0 — только задуман)
    var done = false            // хоть раз дорыт: по нему можно лазить
    var acc: Float = 0          // до следующей проверки, цел ли ход
    var fails = 0               // сколько раз подряд сюда лезли и бросали
    var old = false             // давно никто не лазил: детям уже не интересен, но за опорами ещё следим
    var dead = false            // хода больше нет — осталась память места: здесь недавно рыли
    var used: Float = 0         // когда тут последний раз рыли или лазили
    var seen: [Int32: Int] = [:]    // кто сколько раз по нему лазил
    var links = 0               // сколько раз его соединяли с другим ходом или пустотой под настом
    var kinds = 0               // что с ним делали (биты): 1 — удлиняли, 2 — второе устье, 3 — комнатка, 4 — соединяли,
                                // 5 — лаз наверх; начат как: 6 — сквозной, 7 — сквозной в два пролёта, 8 — нора с комнаткой, 9 — нора
    var r0: Int { sup.first ?? c0 }     // крайние опоры: между ними ход идёт под сводом
    var r1: Int { sup.last ?? c1 }
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
    /// Для самотеста: что именно делать с тоннелями (см. startTunnel); nil — что получится.
    static var funWishKind: String? = nil
    /// Для самотеста: сколько раз за тоннели брались и чем это кончалось.
    static var funLog: [String: Int] = [:]
    /// Кто в буран шёл к норе и не дошёл: до какого времени больше не пробует (иначе ходил бы к ней по кругу).
    static var denShy: [Int32: Float] = [:]

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
            // (не вышло то, что просили, — само в этот раз ничего не выбирает: сценарий ждёт именно этого)
            return w == .tunnel ? startTunnel(&p, s, strict: false, at: People.funWishAt, kind: People.funWishKind) : startAngel(&p, s)
        }
        let r = rng.f()
        if p.look.kid {
            // жителям не до тоннелей; а после вылазки к ним какое-то время не тянет (см. leaveTunnel)
            if r < 0.5 {
                guard p.home == -1 else { return false }
                if s.time < p.stayUntil { People.funLog["resting", default: 0] += 1; return false }
                let ok = startTunnel(&p, s, strict: true)
                People.funLog[ok ? "started" : "nothing to do", default: 0] += 1
                return ok
            }
            if r < 0.62 { return startAngel(&p, s) }
        } else if r < 0.04 {
            return startAngel(&p, s)
        }
        return false
    }

    // MARK: - Тоннели и норы

    func tunnelRows(_ s: Sim) -> Int { max(2, Int((8 * u / s.cell).rounded(.up))) }
    /// Высота комнатки: чтобы сидеть в ней, пригнувшись.
    /// Не выше, чем Sim ещё считает пустотой внутри сугроба (gapMax): иначе свод перестал бы быть его частью.
    func denRows(_ s: Sim) -> Int { min(max(tunnelRows(s) + 2, Int((15 * u / s.cell).rounded(.up))), s.gapMax - 1) }
    func tunnelMid(_ T: Tunnel, _ s: Sim) -> Float { Float(T.c0 + T.c1 + 1) * 0.5 * s.cell }
    func tunnelBusy(_ id: Int) -> Bool { folks.contains { $0.job == .tunnel && $0.obj == id && !$0.gone } }
    /// Сколько человечков помещается в комнатке (0 — комнатки нет или она не вырыта).
    func denCap(_ T: Tunnel, _ s: Sim) -> Int {
        guard T.room >= 0, T.room < T.seg.count, T.seg[T.room] else { return 0 }
        return Float(T.sup[T.room + 1] - T.sup[T.room] - 1) * s.cell >= 14.5 * u ? 3 : 2
    }

    /// Выше этого (ячеек над полом) снег из ямы руками не выбросить: вход роют только там, где он ниже, —
    /// в высокий сугроб заходят с края, а не колодцем сверху.
    func throwMax(_ s: Sim) -> Int { max(tunnelRows(s) + 2, Int(1.2 * 14 * u * s.inv)) }

    /// Здесь можно копать: не ступени, не постройка, не Dock (и не полоса, где он выезжает), не под ёлкой,
    /// в строках хода нет карнизов.
    func canDig(_ s: Sim, _ c: Int, rows: Int) -> Bool {
        guard c >= 1, c < s.W - 1, s.H > rows + 2 else { return false }
        let x = (Float(c) + 0.5) * s.cell
        if isStair(s, c, s.H - 1) || reserved(s, c) || inDock(s, c) || overDock(s, x, pad: 6) { return false }
        for t in trees where abs(t.x - x) < 10 * u { return false }
        for r in (s.H - rows - 1)..<s.H where s.ledge[r * s.W + c] != 0 { return false }
        return true
    }

    /// Удержится ли свод между опорами a и b над ходом высотой rows (то же правило, что в Sim.holds, с небольшим
    /// запасом). packed — свод утрамбуют до наста (комнатка): считать его слежалость не ниже утоптанной.
    func roofHolds(_ s: Sim, _ a: Int, _ b: Int, rows: Int, packed: Bool = false) -> Bool {
        let y = s.H - rows - 1
        guard y >= 1, a >= 0, b < s.W, b - a >= 2 else { return false }
        let x0 = Float(a) * s.cell, x1 = Float(b + 1) * s.cell
        for ball in s.balls where ball.r >= Sim.heavyR && ball.x > x0 - ball.r && ball.x < x1 + ball.r { return false }
        for x in (a + 1)..<b {
            let i = y * s.W + x
            let hd = packed ? max(s.hard[i], 235) : s.hard[i]
            guard s.snow[i] != 0, hd >= Sim.dense else { return false }
            let t = Float(Int(hd) - Int(Sim.dense)) / Float(255 - Int(Sim.dense))
            var th = 1
            while th < 6 && y - th >= 0 && s.snow[(y - th) * s.W + x] != 0 { th += 1 }
            let span = (8 + 34 * t) * min(1.6, max(0.45, Float(th) * s.cell / 7)) * s.inv * 0.9
            let dl = x - a, dr = b - x
            if Float(min(dl, dr)) <= span * 0.32 || Float(dl + dr) <= span { continue }
            return false
        }
        return true
    }

    /// Какой высоты комнатку можно вырыть в столбцах a…b, чтобы над ней осталось хотя бы две ячейки свода:
    /// от 12u (сидеть пригнувшись) до 15u. nil — снег здесь для комнатки мелковат.
    func roomFit(_ s: Sim, _ a: Int, _ b: Int) -> Int? {
        guard a >= 1, b < s.W - 1, a <= b else { return nil }
        var low = Int.max
        for c in a...b {
            var h = 0                                       // сплошного снега от пола
            // (пустота у самого пола — подтаяло снизу — не в счёт: её и так выбирать)
            while h < tunnelRows(s) && h < s.H && s.snow[(s.H - 1 - h) * s.W + c] == 0 { h += 1 }
            while h < s.H && s.snow[(s.H - 1 - h) * s.W + c] != 0 { h += 1 }
            low = min(low, h)
        }
        let rr = min(denRows(s), low - 2)
        return rr >= max(tunnelRows(s) + 1, Int((12 * u / s.cell).rounded(.up))) ? rr : nil
    }

    /// Здесь или рядом (ближе 60u) рыли недавно: новое место ищут в стороне, на нетронутом снегу.
    func dugNear(_ s: Sim, _ a: Int, _ b: Int) -> Bool {
        let gap = Int(60 * u * s.inv)
        for T in tunnels where T.c1 + gap >= a && T.c0 - gap <= b { return true }
        return false
    }

    /// Ступени лаза наверх: высота ступени (как у ступенек в ядре — на такую шагают), её длина и высота
    /// прохода над ней, ячеек.
    func shaftGeo(_ s: Sim) -> (rise: Int, run: Int, hb: Int) {
        (max(1, Int(stepMax(s) * s.inv)), max(1, Int((4 * u * s.inv).rounded())), max(2, Int((13 * u * s.inv).rounded(.up))))
    }

    /// Столбцы ступени k лаза за торцом E в сторону d (1 — первая).
    func shaftCols(_ s: Sim, _ E: Int, _ d: Int, _ k: Int) -> (a: Int, b: Int) {
        let g = shaftGeo(s)
        let x0 = E + d * ((k - 1) * g.run + 1), x1 = E + d * (k * g.run)
        return (min(x0, x1), max(x0, x1))
    }

    /// Можно ли прорубить лаз наверх за торцом E в сторону d. Возвращает, на какой ступени он выйдет на поверхность.
    func shaftPlan(_ s: Sim, _ E: Int, _ d: Int, except id: Int) -> Int? {
        let g = shaftGeo(s)
        let kmax = max(2, Int(75 * u * s.inv) / g.run)
        for k in 1...kmax {
            let cols = shaftCols(s, E, d, k)
            let top = s.H - k * g.rise - g.hb
            guard cols.a > 1, cols.b < s.W - 2, top >= 1 else { return nil }
            var out = true
            for c in cols.a...cols.b {
                let x = (Float(c) + 0.5) * s.cell
                if isStair(s, c, s.H - 1) || reserved(s, c) || inDock(s, c) || overDock(s, x, pad: 6) { return nil }
                for t in trees where abs(t.x - x) < 10 * u { return nil }
                for T in tunnels where !T.dead && T.id != id && c >= T.c0 - 2 && c <= T.c1 + 2 { return nil }
                for r in top..<(s.H - k * g.rise) where s.ledge[r * s.W + c] != 0 { return nil }
                if pile(s, c, s.H) > k * g.rise + 1 { out = false }      // выше ступени ещё снег — рубить дальше
            }
            if out { return k >= 3 ? k - 1 : nil }  // эта ступень уже на поверхности; совсем рядом с ней — прорубать нечего
        }
        return nil
    }

    /// Где рыть новое. Вход — там, где снег невысок (см. throwMax), рядом с местом, где над ходом будет хотя бы
    /// две ячейки свода. За бугром снова низко — ход сквозной (в широком бугре — в два пролёта, с перемычкой
    /// посередине); дальше сплошной высокий снег — нора в один конец, а если массив позволяет — с комнаткой
    /// в конце. strict — только там, где свод удержится, и в стороне от недавних раскопок.
    /// want: 0 — что получится, 1 — сквозной, 2 — нора, 3 — нора с комнаткой. walker — кто будет рыть: вход
    /// выбирают с той стороны, куда он дойдёт.
    func tunnelSite(_ s: Sim, near x: Float, strict: Bool, reach: Float = 150, want: Int = 0, for walker: Person? = nil) -> Tunnel? {
        let rows = tunnelRows(s), rr = denRows(s)
        let W = s.W, H = s.H
        guard H > rr + 5, W > 16 else { return nil }
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
        let pad = 2 * maxL + Int(18 * cu) + body + 4
        let g0 = max(0, lo - pad), g1 = min(W - 1, hi + pad)
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
        func taken(_ a: Int, _ b: Int) -> Bool {            // рядом с другим ходом и со снеговиком не роют
            if strict ? dugNear(s, a, b) : tunnels.contains(where: { !$0.dead && $0.c1 + body >= a && $0.c0 - body <= b }) { return true }
            if let st = site, st.finished < 0, st.x > Float(a - body) * s.cell, st.x < Float(b + body + 1) * s.cell { return true }
            return false
        }
        func holds(_ a: Int, _ b: Int) -> Bool { roofHolds(s, min(a, b), max(a, b), rows: rows) }
        func pick(_ p: Float) -> Bool { !strict || rng.f() < p }            // для разнообразия: не всегда самое длинное
        func make(_ sup: [Int], _ d: Int, through: Bool, room: Int = -1, roomRows: Int = 0) -> Tunnel {
            var T = Tunnel(id: 0, c0: 0, c1: 0, rows: rows, born: s.time)
            T.sup = sup.sorted()
            T.seg = [Bool](repeating: false, count: sup.count - 1)
            T.open0 = d > 0 || through
            T.open1 = d < 0 || through
            T.room = room
            T.roomRows = roomRows
            T.used = s.time
            T.f0 = T.open0 ? T.r0 - body : T.r0
            T.f1 = T.open1 ? T.r1 + body : T.r1
            T.c0 = T.f0; T.c1 = T.f1                        // откосы: пока не выйдут на поверхность
            if T.open0 { while T.f0 - T.c0 < low && T.c0 - 1 >= 2 && pile(s, T.c0 - 1, H) > T.f0 - T.c0 + 1 && canDig(s, T.c0 - 1, rows: rows) { T.c0 -= 1 } }
            if T.open1 { while T.c1 - T.f1 < low && T.c1 + 1 <= W - 3 && pile(s, T.c1 + 1, H) > T.c1 - T.f1 + 1 && canDig(s, T.c1 + 1, rows: rows) { T.c1 += 1 } }
            return T
        }
        func roomAt(_ e: Int, _ d: Int) -> (w: Int, rr: Int)? {    // комнатка за торцом e: её дальняя стенка и высота
            let wc = max(3, Int(rng.range(12, 16.5) * cu))
            let w = e + d * (wc + 1)
            guard w > g0 + 1, w < g1 - 1 else { return nil }
            for j in 1...(wc + 1) where !okDig[e + d * j - g0] { return nil }
            guard let h = roomFit(s, min(e + d, w), max(e + d, w)), roofHolds(s, min(e, w), max(e, w), rows: h, packed: true) else { return nil }
            return (w, h)
        }
        func near(_ T: Tunnel) -> Bool { walker.map { tunnelEntry(T, $0, toward: 0, s).ok } ?? true }
        let kc = max(lo, min(hi, Int(x * s.inv)))
        let rough = Int(24 * cu)                            // длина хода, если на то, удержится ли свод, не смотрят
        var soft: Tunnel? = nil                             // запасной вариант: свод не удержится
        var k = 0
        while kc - k >= lo || kc + k <= hi {
            for a in (k == 0 ? [kc] : [kc - k, kc + k]) where a >= lo && a <= hi && deep(a) {
                for d in [1, -1] where entry(a, d) {
                    var run = 1                             // сколько столбцов вглубь можно рыть под сводом
                    while run <= 2 * maxL && deep(a + d * run) { run += 1 }
                    guard run >= minL else { continue }
                    if want <= 1 {
                        if run > maxL && pick(0.6) {        // широкий бугор: длинный ход в два пролёта
                            var L = min(run, 2 * maxL)
                            while L > maxL {
                                let b = a + d * (L - 1), m = a + d * (L / 2)
                                if entry(b, -d) && holds(a, m) && holds(m, b) && !taken(min(a, b), max(a, b)) {
                                    let T = make([a, m, b], d, through: true)
                                    if near(T) { return T }
                                }
                                L -= step
                            }
                        }
                        var L = min(run, maxL)
                        while L >= minL {                   // сквозной: за бугром снова можно выйти
                            let b = a + d * (L - 1)
                            if entry(b, -d) && holds(a, b) && !taken(min(a, b), max(a, b)) && (L - step < minL || pick(0.65)) {
                                let T = make([a, b], d, through: true)
                                if near(T) { return T }
                            }
                            L -= step
                        }
                    }
                    if want != 1 {
                        var L = min(run - 1, maxL)
                        while L >= minL {                   // нора: дальше сплошной снег, свод опирается на него
                            let e = a + d * L
                            if holds(a, e) && !taken(min(a, e), max(a, e)) {
                                if want != 2 && (want == 3 || pick(0.5)), let R = roomAt(e, d), !taken(min(a, R.w), max(a, R.w)) {
                                    let T = make([a, e, R.w], d, through: false, room: d > 0 ? 1 : 0, roomRows: R.rr)
                                    if near(T) { return T }
                                }
                                if want != 3 && (L - step < minL || pick(0.6)) {
                                    let T = make([a, e], d, through: false)
                                    if near(T) { return T }
                                }
                            }
                            L -= step
                        }
                    }
                    if soft == nil && want != 3 {
                        let b = a + d * (min(run, max(minL, rough)) - 1), e = a + d * min(run - 1, max(minL, rough))
                        if want <= 1 && entry(b, -d) && !taken(min(a, b), max(a, b)) { soft = make([a, b], d, through: true) }
                        else if want != 1 && run > minL && !taken(min(a, e), max(a, e)) { soft = make([a, e], d, through: false) }
                        if let T = soft, !near(T) { soft = nil }
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

    /// Продолжить ход k с его глухого конца d (−1 — левый, +1 — правый). what: 1 — удлинить, 2 — вывести второе
    /// устье, 3 — вырыть комнатку, 4 — дорыться до соседнего хода и соединить, 5 — прорубить лаз наверх.
    /// Запись меняется сразу (новые отрезки помечены невырытыми). false — так здесь нельзя.
    func growTunnel(_ k: Int, side d: Int, what: Int, _ s: Sim) -> Bool {
        var T = tunnels[k]
        guard !T.dead, T.sup.count >= 2, d > 0 ? !T.open1 : !T.open0, T.shaft != d else { return false }
        let W = s.W, H = s.H, rows = T.rows, rr = denRows(s)
        guard H > rr + 5 else { return false }
        let cu = u * s.inv
        let body = Int((16 * cu).rounded(.up)) + 1
        let minL = max(4, Int((16 * cu).rounded(.up)))
        let maxL = max(minL, Int(28 * cu))
        let step = max(1, Int(2 * cu))
        let low = throwMax(s)
        let y = H - rows - 1
        let E = d > 0 ? T.r1 : T.r0                         // торец, от которого роем дальше
        func deep(_ c: Int) -> Bool { c > 2 && c < W - 3 && canDig(s, c, rows: rows) && s.snow[y * W + c] != 0 && s.snow[(y - 1) * W + c] != 0 }
        func entry(_ a: Int, _ dd: Int) -> Bool {
            for j in 1...body {
                let c = a - dd * j
                if c < 2 || c > W - 3 || !canDig(s, c, rows: rows) || pile(s, c, H) > low { return false }
            }
            return true
        }
        func holds(_ a: Int, _ b: Int) -> Bool { roofHolds(s, min(a, b), max(a, b), rows: rows) }
        func others(_ a: Int, _ b: Int, except: Int = -1) -> Bool {         // не влезть в чужой ход
            tunnels.contains { !$0.dead && $0.id != T.id && $0.id != except && $0.c1 + 2 >= min(a, b) && $0.c0 - 2 <= max(a, b) }
        }
        var run = 0                                         // сколько столбцов за торцом можно рыть под сводом
        while run <= 2 * maxL + 1 && deep(E + d * (run + 1)) { run += 1 }
        func add(_ c: Int) {                                // новая опора с этого конца
            if d > 0 { T.sup.append(c); T.seg.append(false) }
            else { T.sup.insert(c, at: 0); T.seg.insert(false, at: 0); if T.room >= 0 { T.room += 1 } }
        }
        var gone = -1                                       // запись соседнего хода, влившегося в этот
        switch what {
        case 1:     // удлинить; если впереди пустота под настом — дорыться до неё
            guard run > minL else { return false }
            var L = min(run - 1, maxL), ok = false
            var hole = 0
            for j in 1...min(run - 1, maxL) {
                let c = E + d * j
                for r in (H - rows)..<H where s.cave[r * W + c] != 0 || (s.snow[r * W + c] == 0 && s.ledge[r * W + c] == 0) { hole = j; break }
            }
            if hole > 0 { L = min(L, max(minL, hole + 2)) }
            while L >= max(3, minL / 2) {
                let e = E + d * L
                if holds(E, e) && !others(E, e) { add(e); ok = true; if hole > 0 { T.links += 1 }; break }
                L -= step
            }
            guard ok else { return false }
        case 2:     // второе устье: за бугром снова низко
            var L = min(run, maxL), ok = false
            while L >= max(3, minL / 2) {
                let b = E + d * (L - 1)
                if entry(b, -d) && holds(E, b) && !others(E, b + d * body) { add(b); ok = true; break }
                L -= step
            }
            guard ok else { return false }
            if d > 0 {
                T.open1 = true; T.f1 = T.r1 + body; T.c1 = T.f1
                while T.c1 - T.f1 < low && T.c1 + 1 <= W - 3 && pile(s, T.c1 + 1, H) > T.c1 - T.f1 + 1 && canDig(s, T.c1 + 1, rows: rows) { T.c1 += 1 }
            } else {
                T.open0 = true; T.f0 = T.r0 - body; T.c0 = T.f0
                while T.f0 - T.c0 < low && T.c0 - 1 >= 2 && pile(s, T.c0 - 1, H) > T.f0 - T.c0 + 1 && canDig(s, T.c0 - 1, rows: rows) { T.c0 -= 1 }
            }
        case 3:     // комнатка за торцом
            guard T.room < 0 else { return false }
            let wc = max(3, Int(rng.range(12, 16.5) * cu))
            let w = E + d * (wc + 1)
            for j in 1...(wc + 1) where !(E + d * j > 2 && E + d * j < W - 3 && canDig(s, E + d * j, rows: rows)) { return false }
            guard let h = roomFit(s, min(E + d, w), max(E + d, w)), roofHolds(s, min(E, w), max(E, w), rows: h, packed: true), !others(E, w) else { return false }
            add(w)
            T.room = d > 0 ? T.seg.count - 1 : 0
            T.roomRows = h
        case 4:     // соединить с соседним ходом, который упирается в тот же снег с другой стороны
            var best: (j: Int, F: Int, gap: Int)? = nil
            for (j, R) in tunnels.enumerated() where j != k && !R.dead && R.rows == rows && R.sup.count >= 2 && !tunnelBusy(R.id) {
                guard d > 0 ? (!R.open0 && R.shaft != -1) : (!R.open1 && R.shaft != 1) else { continue }
                let F = d > 0 ? R.r0 : R.r1                 // обращённый к нам торец
                let gap = (F - E) * d
                if gap >= 3 && gap <= 2 * maxL && gap - 1 <= run && (best == nil || gap < best!.gap) { best = (j, F, gap) }
            }
            guard let B = best else { return false }
            let R = tunnels[B.j]
            var mids: [Int] = []
            if !(B.gap <= maxL + 1 && holds(E, B.F)) {
                let m = E + d * (B.gap / 2)
                guard holds(E, m), holds(m, B.F) else { return false }
                mids = [m]
            }
            guard !others(E, B.F, except: R.id) else { return false }
            let fresh = [Bool](repeating: false, count: mids.count + 1)
            if d > 0 {
                let shift = T.seg.count + fresh.count
                if T.room < 0 && R.room >= 0 { T.room = R.room + shift; T.roomRows = R.roomRows }
                T.sup += mids + R.sup; T.seg += fresh + R.seg
                T.open1 = R.open1; T.f1 = R.f1; T.c1 = R.c1
                if R.shaft > 0 { T.shaft = R.shaft; T.shaftN = R.shaftN }
            } else {
                let shift = R.seg.count + fresh.count
                if T.room >= 0 { T.room += shift } else if R.room >= 0 { T.room = R.room; T.roomRows = R.roomRows }
                T.sup = R.sup + mids + T.sup; T.seg = R.seg + fresh + T.seg
                T.open0 = R.open0; T.f0 = R.f0; T.c0 = R.c0
                if R.shaft < 0 { T.shaft = R.shaft; T.shaftN = R.shaftN }
            }
            for (id, n) in R.seen { T.seen[id] = max(T.seen[id] ?? 0, n) }
            T.links += 1 + R.links
            T.kinds |= R.kinds
            packColumn(s, B.F)
            for m in mids { packColumn(s, m) }
            T.packed += R.packed + mids + [B.F]
            gone = R.id
        case 5:     // лаз наверх
            guard T.shaft == 0, shaftPlan(s, E, d, except: T.id) != nil else { return false }
            T.shaft = d
            T.shaftN = 0
        default:
            return false
        }
        if what != 5 { packColumn(s, E); T.packed.append(E) }       // бывший торец теперь перемычка: сквозь него пролезают
        if !T.open0 { T.f0 = T.r0; T.c0 = T.r0 }           // с глухой стороны размах хода — до торца
        if !T.open1 { T.f1 = T.r1; T.c1 = T.r1 }
        T.kinds |= 1 << what
        T.used = s.time
        T.old = false
        T.fails = 0
        tunnels[k] = T
        if gone >= 0 { tunnels.removeAll { $0.id == gone } }
        return true
    }

    /// Эту ячейку нельзя прорубать (ядро спрашивает в `carve`): опора живого хода или свод над ним —
    /// иначе тот, кто упёрся в стенку у устья и рубит себе ступеньки, обрушил бы нору.
    func tunnelKeep(_ s: Sim, _ c: Int, _ r: Int) -> Bool {
        for T in tunnels where !T.dead && c >= T.r0 && c <= T.r1 {
            if T.sup.contains(c) { return true }
            let rr = T.room >= 0 && T.room + 1 < T.sup.count && c > T.sup[T.room] && c < T.sup[T.room + 1] ? T.roomRows : T.rows
            if r < s.H - rr && r >= s.H - rr - 6 { return true }
        }
        return false
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

    /// Комнатка вырыта: утрамбовать её свод и стенки до наста, чтобы держали.
    func packRoom(_ s: Sim, _ T: Tunnel) {
        guard T.room >= 0, T.room + 1 < T.sup.count else { return }
        let a = max(0, T.sup[T.room]), b = min(s.W - 1, T.sup[T.room + 1])
        let y = s.H - T.roomRows - 1
        guard a <= b, y >= 3 else { return }
        for c in a...b {
            for r in (y - 3)...y {
                let i = r * s.W + c
                if s.snow[i] != 0 && s.hard[i] < 235 { s.hard[i] = 235 }
            }
        }
        packColumn(s, a)
        packColumn(s, b)
        s.hardDirty = true
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
        if any { s.hardDirty = true }
        s.snowDisturbed(c - 1, s.H - h - 1, c + 1, s.H - 1)        // и рыхлый столбик будим: бывает, стоит «уснувший»
    }

    /// Стойки наста сами собой не бывают и не падают (наст по склону не осыпается). Какая бы ни осталась —
    /// столбик в одну-две ячейки заметно выше снега с обеих сторон или «ножка» на высоту хода, по бокам от
    /// которой пусто (перемычка хода, от которого ничего не осталось), — она рыхлеет и осыпается.
    func sweepSpikes(_ s: Sim) {
        guard s.W >= 5 else { return }
        let lim = 4, rows = tunnelRows(s)
        func free(_ c: Int) -> Bool {       // не чужая постройка и не опора живого хода
            if isStair(s, c, s.H - 1) || reserved(s, c) { return false }
            if wallTop >= 0 && c >= wallCol - 1 && c <= wallCol + 3 { return false }     // стенка от ветра
            for T in tunnels where !T.dead && T.sup.contains(c) { return false }
            return true
        }
        func stem(_ c: Int) -> Bool {       // сплошной от пола на высоту хода, а с обеих сторон на эту высоту пусто
            guard s.H > rows + 1 else { return false }
            for r in (s.H - rows)..<s.H {
                if s.snow[r * s.W + c] == 0 || s.snow[r * s.W + c - 1] != 0 || s.snow[r * s.W + c + 1] != 0 { return false }
                if s.ledge[r * s.W + c - 1] != 0 || s.ledge[r * s.W + c + 1] != 0 { return false }
            }
            return true
        }
        var a = pile(s, 0, s.H), b = pile(s, 1, s.H), d = pile(s, 2, s.H)
        for c in 1..<(s.W - 2) {
            let e = pile(s, c + 2, s.H)
            if b - max(a, d) > lim {
                if free(c) { soften(s, c, above: max(a, d)) }
            } else if b - max(a, e) > lim && d - max(a, e) > lim {
                if free(c) && free(c + 1) { soften(s, c, above: max(a, e)); soften(s, c + 1, above: max(a, e)) }
            } else if b >= rows && stem(c) && free(c) {
                soften(s, c, above: 0)
            }
            a = b; b = d; d = e
        }
    }

    /// Какие строки столбца c надо освободить: под сводом — ход (в комнатке — на её высоту), в траншее — весь
    /// столбец (на откосе — всё, что выше откоса), опоры свода — ничего.
    func tunnelSpan(_ s: Sim, _ T: Tunnel, _ c: Int) -> (r0: Int, r1: Int)? {
        guard c >= max(0, T.c0), c <= min(s.W - 1, T.c1), T.rows < s.H, !T.sup.contains(c) else { return nil }
        if c > T.r0 && c < T.r1 {
            let rr = T.room >= 0 && T.room + 1 < T.sup.count && c > T.sup[T.room] && c < T.sup[T.room + 1] ? min(T.roomRows, s.H - 1) : T.rows
            return (s.H - rr, s.H - 1)
        }
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

    /// С какого конца лезть в ход (1 — с левого, ползти вправо) и дойдёт ли туда человечек: в обход бугра,
    /// через стенку выше груди, к устью не ходят.
    func tunnelEntry(_ T: Tunnel, _ p: Person, toward: Int, _ s: Sim) -> (dir: Float, ok: Bool) {
        var dir: Float
        if !T.open1 { dir = 1 } else if !T.open0 { dir = -1 }
        else if toward != 0 { dir = Float(toward) }
        else { dir = p.x <= tunnelMid(T, s) ? 1 : -1 }      // в сквозной ход — с ближнего конца
        let inX = dir > 0 ? Float(T.c0) * s.cell : Float(T.c1 + 1) * s.cell
        return (dir, pathClear(s, from: p.x, to: clampX(inX - dir * max(3 * u, 2.5 * s.cell), s), tall: p.tall))
    }

    /// Откосы траншей — до поверхности: у устья за это время могло намести или навалить выкопанного.
    func fitRamps(_ k: Int, _ s: Sim) {
        var T = tunnels[k]
        let low = throwMax(s)
        if T.open0 { while T.f0 - T.c0 < low && T.c0 - 1 >= 2 && pile(s, T.c0 - 1, s.H) > T.f0 - T.c0 + 1 && canDig(s, T.c0 - 1, rows: T.rows) { T.c0 -= 1 } }
        if T.open1 { while T.c1 - T.f1 < low && T.c1 + 1 <= s.W - 3 && pile(s, T.c1 + 1, s.H) > T.c1 - T.f1 + 1 && canDig(s, T.c1 + 1, rows: T.rows) { T.c1 += 1 } }
        tunnels[k].c0 = T.c0
        tunnels[k].c1 = T.c1
    }

    /// Отправить человечка в ход k с заданием task: 0 — пролезть (в норе с комнаткой — посидеть), 1 — рыть
    /// задуманное, 2 — пережидать буран в комнатке, 3 — прорубить лаз наверх. toward — к какому концу ползти
    /// (0 — всё равно).
    func enterTunnel(_ p: inout Person, _ k: Int, task: Int, toward: Int = 0, _ s: Sim) {
        fitRamps(k, s)
        let T = tunnels[k]
        let dir = tunnelEntry(T, p, toward: toward, s).dir
        p.job = .tunnel
        p.obj = T.id
        p.stage = task
        p.aux = 0
        p.aux2 = dir
        p.throwsLeft = 0
        p.blockT = 0
        tunnels[k].used = s.time
        next(&p, 0)
    }

    /// Взяться за тоннели: продолжить то, что уже вырыто поблизости (удлинить, вывести второе устье, вырыть
    /// комнатку, соединить два хода, прорубить лаз наверх), пролезть по готовому или начать новый — в стороне
    /// от недавних раскопок. kind — для самотеста: "new", "through", "burrow", "den", "longer", "mouth",
    /// "room", "join", "shaft", "visit".
    func startTunnel(_ p: inout Person, _ s: Sim, strict: Bool, at: Float? = nil, kind: String? = nil) -> Bool {
        // что можно сделать: (вес, запись, конец, что)
        var opts: [(key: Float, k: Int, d: Int, what: Int)] = []
        func offer(_ w: Float, _ k: Int, _ d: Int, _ what: Int) { opts.append((-logf(max(1e-6, rng.f())) / w, k, d, what)) }
        let digging = folks.contains(where: { $0.job == .tunnel && ($0.stage == 1 || $0.stage == 3) && !$0.gone })
        for k in tunnels.indices where !tunnels[k].dead && tunnels[k].done && tunnels[k].fails < 2 && abs(tunnelMid(tunnels[k], s) - (at ?? p.x)) < 240 * u {
            fitRamps(k, s)
            let T = tunnels[k]
            let busy = tunnelBusy(T.id)
            let cap = denCap(T, s)
            // пролезть: раз-другой, потом надоедает; в комнатку — пока есть место
            if kind == nil || kind == "visit" {
                let n = T.seen[p.id] ?? 0
                let guests = folks.filter { $0.job == .tunnel && $0.obj == T.id && !$0.gone }.count
                if (!T.old || kind != nil) && (n < 2 || kind != nil) && (cap > 0 ? guests < cap : !busy) && tunnelEntry(T, p, toward: 0, s).ok {
                    offer(cap > 0 ? 2.5 : (n == 0 ? 2 : 0.7), k, 0, 0)
                }
            }
            // продолжить — пока в ходе никого нет и никто не роет
            if !busy && (!digging || !strict) && !(strict && T.old) {
                for d in [-1, 1] where (d > 0 ? !T.open1 : !T.open0) && T.shaft != d && tunnelEntry(T, p, toward: d, s).ok {
                    if kind == nil || kind == "join" { offer(3, k, d, 4) }
                    if kind == nil || kind == "mouth" { offer(1.5, k, d, 2) }
                    if kind == nil || kind == "longer" { offer(1.5, k, d, 1) }
                    if kind == nil || kind == "room" { offer(2, k, d, 3) }
                    if kind == nil || kind == "shaft" { offer(1, k, d, 5) }
                }
            }
        }
        let fresh = kind == nil || ["new", "through", "burrow", "den"].contains(kind!)
        let live = tunnels.filter { !$0.dead && !$0.old }.count
        if fresh && (!strict || (!digging && live < 4)) { offer(opts.isEmpty ? 100 : 2.5, -1, 0, -1) }
        for o in opts.sorted(by: { $0.key < $1.key }) {
            if o.what == -1 {
                let want = kind == "through" ? 1 : (kind == "burrow" ? 2 : (kind == "den" ? 3 : 0))
                guard var T = tunnelSite(s, near: at ?? p.x, strict: strict, reach: at != nil ? 30 : 150, want: want, for: p) else { continue }
                T.id = nextObjId
                nextObjId += 1
                T.kinds = 1 << (T.room >= 0 ? 8 : (T.open0 && T.open1 ? (T.sup.count > 2 ? 7 : 6) : 9))
                tunnels.append(T)
                enterTunnel(&p, tunnels.count - 1, task: 1, s)
                People.funLog["new", default: 0] += 1
                return true
            }
            guard o.k < tunnels.count else { continue }
            if o.what == 0 {
                enterTunnel(&p, o.k, task: 0, s)
                People.funLog["visit", default: 0] += 1
                return true
            }
            let id = tunnels[o.k].id
            if growTunnel(o.k, side: o.d, what: o.what, s), let k = tunnels.firstIndex(where: { $0.id == id }) {
                enterTunnel(&p, k, task: o.what == 5 ? 3 : 1, toward: o.d, s)
                People.funLog["grow \(o.what)", default: 0] += 1
                return true
            }
        }
        return false
    }

    /// Буран: спрятаться в норе с комнаткой, если такая есть поблизости (до ~150u) и в ней ещё есть место.
    /// Годится только нора с устьем с подветренной стороны: наветренное заметает на глазах, в нём самого
    /// завалит. Человечек заползает внутрь и сидит, пока буран не стихнет. false — прятаться негде.
    func denShelter(_ p: inout Person, _ s: Sim) -> Bool {
        guard p.stand == -2, p.mode == .ground, !p.gone else { return false }
        if let t = People.denShy[p.id] {
            if s.time < t { return false }
            People.denShy[p.id] = nil
        }
        var best = -1, side = 0
        var bd = 150 * u
        let lee = s.wind.dir >= 0 ? 1 : -1                  // с какой стороны бугра затишье
        for (k, T) in tunnels.enumerated() where !T.dead && T.fails < 2 && denCap(T, s) > 0 {
            guard folks.filter({ $0.job == .tunnel && $0.obj == T.id && !$0.gone }).count < denCap(T, s) else { continue }
            guard lee > 0 ? T.open1 : T.open0 else { continue }
            let d = abs((lee > 0 ? Float(T.c1 + 1) : Float(T.c0)) * s.cell - p.x)
            if d < bd && tunnelAlive(s, T) && tunnelEntry(T, p, toward: -lee, s).ok { bd = d; best = k; side = lee }
        }
        guard best >= 0 else { return false }
        release(&p, s)
        enterTunnel(&p, best, task: 2, toward: -side, s)
        return true
    }

    /// Закончил с тоннелями: какое-то время к ним не тянет (у гостей поле stayUntil свободно).
    func leaveTunnel(_ p: inout Person, _ s: Sim) {
        if p.home == -1 { p.stayUntil = s.time + rng.range(20, 50) }
    }

    /// Вылезти наверх прямо отсюда (ход пропал или застрял).
    func popOut(_ p: inout Person, _ s: Sim) {
        if p.mode == .crawl || p.mode == .hop {
            p.mode = .ground
            p.stand = -2
            p.y = min(p.y, surface(s, x: p.x, stand: -2) ?? p.y)
            puff(s, p.x, p.y, n: 4, stand: -2)
        }
        leaveTunnel(&p, s)
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

    /// Выкопанный наст — уже не наст: раскрошен. (Комья наста, упав, не осыпались бы и вставали столбиками.)
    func crumbled(_ hard: UInt8) -> UInt8 { min(hard, 190) }

    /// Свалить n ячеек снега комьями на поверхность вокруг x: объём выкопанного не теряется.
    func dumpAt(_ s: Sim, _ x: Float, spread: Float, _ n: Int, hard: UInt8) {
        guard n > 0 else { return }
        for _ in 0..<min(n, 120) {
            let cx = clampX(x + rng.range(-1, 1) * spread, s)
            let y = (surface(s, x: cx, stand: -2) ?? Float(s.H) * s.cell) - rng.range(1, 4) * u
            chunk(s, cx, y, rng.range(-40, 40), -rng.range(10, 50), hard: crumbled(hard))
        }
    }

    /// Свалить n ячеек снега комьями сразу за внешним краем траншеи side: объём выкопанного не теряется.
    func dumpOutside(_ s: Sim, _ T: Tunnel, side: Float, _ n: Int, hard: UInt8) {
        guard n > 0 else { return }
        let outerX = (side < 0 ? Float(T.c0) : Float(T.c1 + 1)) * s.cell
        let floorY = Float(s.H) * s.cell
        let cap = Float(s.H - throwMax(s)) * s.cell         // кучу выше не насыпают (в неё потом не врыться): несут дальше
        for _ in 0..<min(n, 120) {
            var x = clampX(outerX + side * rng.range(4, 30) * u, s)
            var y = surface(s, x: x, stand: -2) ?? floorY
            if y < cap { x = clampX(outerX + side * rng.range(30, 62) * u, s); y = surface(s, x: x, stand: -2) ?? floorY }
            if y < cap { x = clampX(outerX + side * rng.range(62, 100) * u, s); y = surface(s, x: x, stand: -2) ?? floorY }
            chunk(s, x, y - rng.range(1, 4) * u, side * rng.range(10, 60), -rng.range(10, 50), hard: crumbled(hard))
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
            chunk(s, x0 + rng.range(-1, 1) * u, y0 + rng.range(-1, 1) * u, side * dist / t * 1.2, -vy * 1.1, hard: crumbled(dug.hard))
        }
    }

    /// Снег, выбранный под сводом: свод и стенки над этим местом при этом утаптываются (крепче держат),
    /// а сам снег вытаскивают наружу через устье out и сваливают за краем траншеи — объём не пропадает.
    func stowSnow(_ s: Sim, _ T: Tunnel, _ c: Int, _ dug: (n: Int, hard: UInt8, top: Int), out: Float) {
        guard dug.n > 0 else { return }
        let rr = tunnelSpan(s, T, c).map { s.H - $0.r0 } ?? T.rows
        let y = s.H - rr - 1
        if y >= 3 {
            for cc in max(T.r0, c - 1)...min(T.r1, c + 1) {
                for r in (y - 3)...y {
                    let i = r * s.W + cc
                    if s.snow[i] != 0 && s.hard[i] < 255 { s.hard[i] = UInt8(min(255, Int(s.hard[i]) + 40)) }
                }
            }
            s.hardDirty = true
        }
        let side: Float = (out < 0 ? T.open0 : T.open1) ? out : -out      // через то устье, которое есть
        dumpOutside(s, T, side: side, dug.n, hard: dug.hard)
    }

    /// Рыть траншею side одним проходом от столбца goalX к stop (за спиной её уже понемногу заносит — назад
    /// не возвращается). Роет слоями, в такт взмахам рук, понемногу подаваясь вперёд; выбранное бросает за край.
    /// В goalX — докуда дошёл. true — дошёл до конца.
    func digTrench(_ p: inout Person, _ s: Sim, _ T: Tunnel, side: Float, to stop: Int, _ dt: Float) -> Bool {
        let from = max(T.c0, min(T.c1, Int(p.goalX)))
        guard let c = firstBlocked(s, T, from: from, to: stop) else { return true }
        p.goalX = Float(c)
        let d: Float = stop > from ? 1 : -1
        var standX = (d > 0 ? Float(c) : Float(c + 1)) * s.cell - d * max(3 * u, 2 * s.cell)
        // роет от перемычки наружу — стоять не ближе, чем вплотную к ней (в саму перемычку не пятиться)
        if d > 0 && c > T.r1 { standX = max(standX, Float(T.r1 + 1) * s.cell + 1.5 * u) }
        if d < 0 && c < T.r0 { standX = min(standX, Float(T.r0) * s.cell - 1.5 * u) }
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
    func giveUp(_ p: inout Person, _ k: Int, _ s: Sim) {
        tunnels[k].fails += 1
        leaveTunnel(&p, s)
        idle(&p, 0.5)
    }

    /// Вылез: радуется. Ход запоминает, кто по нему лазил.
    func tunnelDone(_ p: inout Person, _ k: Int, _ s: Sim) {
        tunnels[k].seen[p.id, default: 0] += 1
        tunnels[k].used = s.time
        leaveTunnel(&p, s)
        p.job = .cheer
        p.wait = 1.8
        next(&p, 0)
    }

    /// Рядом ли ноги с опорой свода. Пока человечек протискивается сквозь перемычку, это не «ползёт под
    /// снегом»: утоптанный столбец у самых ног иначе сошёл бы за завал (PeopleRescue меряет снег вокруг ног).
    func atSupport(_ T: Tunnel, _ x: Float, _ s: Sim) -> Bool {
        let zone = 1.5 * u + s.cell * 0.5 + 1
        for c in T.sup where abs(x - (Float(c) + 0.5) * s.cell) < zone { return true }
        return false
    }

    func runTunnel(_ p: inout Person, _ s: Sim, _ dt: Float) {
        guard let k = tunnels.firstIndex(where: { $0.id == p.obj && !$0.dead }), tunnels[k].sup.count >= 2 else { popOut(&p, s); return }
        tunnels[k].used = s.time
        let T = tunnels[k]
        let dir: Float = p.aux2 >= 0 ? 1 : -1               // куда ползёт
        let di = dir > 0 ? 1 : -1
        let floorY = Float(s.H) * s.cell
        let off = max(3 * u, 2.5 * s.cell)
        let inX = dir > 0 ? Float(T.c0) * s.cell : Float(T.c1 + 1) * s.cell         // внешний край траншеи позади
        let outX = dir > 0 ? Float(T.c1 + 1) * s.cell : Float(T.c0) * s.cell        // и впереди
        let near = dir > 0 ? T.r0 : T.r1, far = dir > 0 ? T.r1 : T.r0               // опоры: ближняя и дальняя по ходу
        var openFar = dir > 0 ? T.open1 : T.open0
        if openFar && p.stage != 4 && s.H >= 2 {            // у дальнего устья выросли чужие ступеньки или стенка от
            for j in 1...3 {                                // ветра: их не ломают — тупик, вылезать, откуда влез
                let c = far + di * j
                if c >= 0 && c < s.W && (isStair(s, c, s.H - 1) || isStair(s, c, s.H - 2)) { openFar = false; break }
            }
        }
        let mouth = dir > 0 ? Float(T.r0) * s.cell : Float(T.r1 + 1) * s.cell       // устье: внешний бок перемычки у входа
        var lieX = mouth - dir * (p.tall * u + 2)           // лёжа у входа: голова у самой перемычки
        lieX = dir > 0 ? max(lieX, inX + 1) : min(lieX, inX - 1)
        let digT = 0.22 * min(1, s.cell / 3)                // столбец под сводом
        let hasRoom = T.room >= 0 && T.room + 1 < T.sup.count
        let ra = hasRoom ? (dir > 0 ? T.sup[T.room] : T.sup[T.room + 1]) : 0        // стенки комнатки: ближняя по ходу
        let rb = hasRoom ? (dir > 0 ? T.sup[T.room + 1] : T.sup[T.room]) : 0        // и дальняя
        switch p.phase {
        case 0:     // к входу
            if walk(&p, s, to: clampX(inX - dir * off, s), speed: 26 * u, dt) {
                if p.mode == .ground { p.aux = 0; p.goalX = Float(dir > 0 ? T.c0 : T.c1); next(&p, 1) }
            } else if p.blockT > 0.3 {                      // на пути выросла стенка: не судьба (ход тут ни при чём)
                p.blockT = 0
                if p.stage == 2 {
                    if People.denShy.count > 64 { People.denShy.removeAll() }
                    People.denShy[p.id] = s.time + 60
                }
                leaveTunnel(&p, s)
                idle(&p, 0.5)
            } else if p.t > 30 {
                giveUp(&p, k, s)
            }
        case 1:     // траншея у входа: откос и дно, до самой перемычки (в готовом ходе — только расчистить)
            if !p.flag {
                p.flag = true
                // утоптать перемычки, пока своды ещё на снегу (если они вообще удержатся); глухие торцы не трогаем
                var firm = true
                for i in 0..<T.seg.count where !roofHolds(s, T.sup[i], T.sup[i + 1], rows: i == T.room ? T.roomRows : T.rows, packed: i == T.room) { firm = false }
                if firm {
                    for (i, c) in T.sup.enumerated() where !(i == 0 && !T.open0) && !(i == T.sup.count - 1 && !T.open1) {
                        packColumn(s, c)
                        tunnels[k].packed.append(c)
                    }
                }
            }
            if digTrench(&p, s, T, side: -dir, to: near, dt) { next(&p, 2) } else if p.t > 40 { giveUp(&p, k, s) }
        case 2:     // отойти на свой рост от перемычки, дочистить место под собой и лечь
            guard tread(&p, s, to: lieX, speed: 20 * u, dt) || p.t > 6 else { return }
            if let c = firstBlocked(s, T, from: Int(lieX * s.inv) - di, to: near) {
                digBeat(&p, s, T, c, side: -dir, face: dir, dt)
                if p.t > 16 { giveUp(&p, k, s) }
                return
            }
            p.mode = .crawl
            p.y = floorY
            p.face = dir
            p.fallDir = dir
            p.aux = digT
            next(&p, 3)
        case 3, 6, 7:   // ползком: 3 — вперёд, выбирая снег перед собой; 6 — в глухом конце; 7 — задом обратно
            guard p.mode == .crawl || p.mode == .hop else { popOut(&p, s); return }
            p.mode = atSupport(T, p.x, s) ? .hop : .crawl
            p.anim = .crawl
            p.y = floorY
            p.face = dir
            p.fallDir = dir
            if p.t > 70 { tunnels[k].fails += 1; popOut(&p, s); return }       // застрял — наверх
            p.aux = min(p.aux + dt, digT)
            if p.phase == 6 {           // добрался до глухого конца: полежал — и назад
                p.walkPhase += dt * 2
                if p.t > 1.2 { next(&p, 7) }
                return
            }
            if p.phase == 7 {           // пятится к входу; что насыпалось за спиной — выгребает ногами наружу
                if dir > 0 ? p.x <= lieX : p.x >= lieX {
                    p.mode = .ground
                    p.stand = -2
                    p.aux2 = -dir       // выходить — туда, откуда пришёл
                    next(&p, 5)
                    p.anim = .getup
                    return
                }
                let cb = Int((p.x - dir * (1.5 * u + s.cell)) * s.inv)
                if tunnelBlocked(s, T, cb) {
                    if p.aux >= digT {
                        p.aux = 0
                        let d = tunnelDig(s, T, cb)
                        if d.n > 0 {
                            dust(s, (Float(cb) + 0.5) * s.cell, floorY - 2 * s.cell)
                            dumpOutside(s, T, side: -dir, d.n, hard: d.hard)
                        }
                    }
                } else {
                    let st = min(s.cell * 0.9, 12 * u * dt)
                    p.x -= dir * st
                    p.walkPhase += st / (3 * u)
                }
                return
            }
            let ch = Int((p.x + dir * (p.tall * u + 1)) * s.inv)        // столбец перед головой
            if let j = T.sup.firstIndex(of: ch) {                       // голова дошла до опоры — отрезок позади вырыт
                let i = dir > 0 ? j - 1 : j
                if i >= 0 && i < T.seg.count && !T.seg[i] {
                    tunnels[k].seg[i] = true
                    if i == T.room { packRoom(s, T); tunnels[k].packed += [T.sup[i], T.sup[i + 1]] }
                }
            }
            let leaving = p.stage == 4
            // комнатка по ходу: гости остаются в ней; тот, кто роет, — если она в самом конце
            if hasRoom && !leaving && (p.stage == 0 || p.stage == 2 || rb == far) && (dir > 0 ? ch >= rb : ch <= rb) {
                tunnels[k].done = true
                tunnels[k].fails = 0
                next(&p, 8)
                return
            }
            // впереди устье: ноги уже за дальней перемычкой — можно вставать
            if openFar && (dir > 0 ? p.x > Float(T.r1 + 1) * s.cell + 1.5 * u : p.x < Float(T.r0) * s.cell - 1.5 * u) {
                tunnels[k].done = true
                tunnels[k].fails = 0
                p.mode = .ground
                p.stand = -2
                p.goalX = Float(Int(p.x * s.inv))
                next(&p, 4)
                p.anim = .getup
                return
            }
            if !openFar && (dir > 0 ? ch >= far : ch <= far) {         // упёрся в глухой торец
                tunnels[k].done = true
                tunnels[k].fails = 0
                if p.stage == 3 && T.shaft == di { p.tries = 0; p.aux = 0; next(&p, 11) } else { next(&p, 6) }
                return
            }
            // что мешает: сначала снег перед головой, потом осыпавшийся на тело
            var target = -1
            var ahead = tunnelBlocked(s, T, ch)
            if ahead { target = ch } else {
                for j in 1...(Int(p.tall * u * s.inv) + 1) where tunnelBlocked(s, T, ch - di * j) { target = ch - di * j; break }
            }
            let digger = p.stage == 1 || p.stage == 3
            // Вылезает по готовому ходу, а устье замело (буран, обвал): пока голова у перемычки, выгребает
            // траншею — выползать из-под свода в сугроб нельзя, завалит. Дно — дочиста, откос — если на нём
            // намело выше хода (мелочь уберёт потом, стоя).
            if target < 0 && !digger && openFar && (dir > 0 ? ch >= T.r1 - 1 : ch <= T.r0 + 1) {
                var c = dir > 0 ? max(ch + 1, T.r1 + 1) : min(ch - 1, T.r0 - 1)
                while dir > 0 ? c <= T.c1 : c >= T.c0 {
                    let k = dir > 0 ? c - T.f1 : T.f0 - c       // сколько ячеек лежит на откосе в этом столбце
                    if k <= 0 ? tunnelBlocked(s, T, c) : pile(s, c, s.H) > k + T.rows { target = c; break }
                    c += di
                }
            }
            let beyond = target >= 0 && (dir > 0 ? target > T.r1 : target < T.r0)
            if target >= 0 && p.aux >= digT {
                p.aux = 0
                let dug = tunnelDig(s, T, target, limit: beyond && !digger ? max(2, T.rows) : .max)
                if target > T.r0 && target < T.r1 {         // под сводом: утоптать свод, снег — наружу
                    stowSnow(s, T, target, dug, out: leaving ? dir : -dir)
                } else if beyond && !digger {
                    // откапывается слой за слоем; снег — за край траншеи, а не перед собой (иначе гнал бы
                    // сугроб до самого откоса)
                    dust(s, (Float(target) + 0.5) * s.cell, Float(dug.top) * s.cell)
                    dumpOutside(s, T, side: dir, dug.n, hard: dug.hard)
                } else if beyond {
                    // за дальней перемычкой: снег вываливается вперёд, туда, где ещё не рыли
                    let over = max(pile(s, target + di, s.H), pile(s, target + 2 * di, s.H), s.H - dug.top)
                    for _ in 0..<min(dug.n, 90) {
                        chunk(s, (Float(target) + 0.5) * s.cell, Float(s.H - over) * s.cell - rng.range(0.5, 1.5) * s.cell,
                              dir * rng.range(50, 130), -rng.range(30, 80), hard: crumbled(dug.hard))
                    }
                } else {                                    // у входа, за спиной: выгребает наружу
                    dust(s, (Float(target) + 0.5) * s.cell, floorY - 2 * s.cell)
                    dumpOutside(s, T, side: -dir, dug.n, hard: dug.hard)
                }
                if target == ch { ahead = tunnelBlocked(s, T, ch) }
            }
            // из-под свода в замётенную траншею не выползают, пока она сыплется на плечи: сперва расчистить
            if beyond && !digger && target != ch { ahead = true }
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
        case 5:     // выйти по откосу — и радоваться
            if p.t < 0.3 { p.anim = .getup; _ = tread(&p, s, to: p.x, speed: 0, dt); return }
            if tread(&p, s, to: clampX(outX + dir * off, s), speed: 22 * u, dt) || p.t > 8 { tunnelDone(&p, k, s) }
        case 8:     // в комнатке: поднялся (пригнувшись) и идёт на своё место
            guard hasRoom else { popOut(&p, s); return }
            p.mode = .crawl
            p.y = floorY
            p.anim = .getup
            let cap = max(1, denCap(T, s))
            if !p.flag {
                p.flag = true
                p.x += dir * p.tall * u * 0.5               // лежал головой к стенке — встаёт там, где была середина тела
                var free = 0                                // первое свободное место
                while free < cap - 1 && folks.contains(where: { $0.id != p.id && $0.job == .tunnel && $0.obj == T.id && ($0.phase == 8 || $0.phase == 9) && $0.throwsLeft == free }) { free += 1 }
                p.throwsLeft = free
            }
            let xl = Float(min(ra, rb) + 1) * s.cell, xr = Float(max(ra, rb)) * s.cell
            let sx = xl + (Float(min(p.throwsLeft, cap - 1)) + 0.5) * (xr - xl) / Float(cap)
            if abs(sx - p.x) > 1 && p.t < 4 {
                p.face = sx > p.x ? 1 : -1
                p.x += max(-10 * u * dt, min(10 * u * dt, sx - p.x))
                p.walkPhase += 10 * u * dt / (4.5 * u)
                return
            }
            if p.stage == 3 && T.shaft != 0 && rb == (T.shaft > 0 ? T.r1 : T.r0) {
                p.tries = 0
                p.aux = 0
                p.aux2 = Float(T.shaft)
                next(&p, 11)
                return
            }
            p.wait = p.stage == 1 ? rng.range(3, 5) : rng.range(10, 22)
            p.face = -dir                                   // лицом к выходу
            next(&p, 9)
        case 9:     // сидит в комнатке: пережидает буран или просто прячется
            guard hasRoom else { popOut(&p, s); return }
            p.mode = .crawl
            p.y = floorY
            let storm = s.wind.storm
            if storm > 0.4 { p.anim = .huddle }
            else if p.look.kid && Float(T.roomRows) * s.cell >= 14 * u && fmodf(s.time + Float(p.id) * 2.3, 5) < 1.3 { p.anim = .gaze }      // выглядывает
            else { p.anim = .getup }
            guard p.stage == 2 ? (storm < 0.4 && p.t > 3) : (p.t > p.wait && storm < 0.55) else { return }
            if T.shaft != 0 && T.shaftN > 0 && T.room == (T.shaft > 0 ? T.seg.count - 1 : 0) && rng.f() < 0.35 {
                p.tries = 0                                 // наружу — через лаз наверх
                p.aux = 0
                p.aux2 = Float(T.shaft)
                next(&p, 11)
                return
            }
            let out: Float = T.open0 && T.open1 ? (rng.f() < 0.5 ? -1 : 1) : (T.open0 ? -1 : 1)
            p.aux2 = out
            p.face = out
            p.fallDir = out
            p.stage = 4                                     // на выход
            p.aux = digT
            next(&p, 3)
        case 11:    // лаз наверх за глухим торцом: ступенька за ступенькой — вырубить (или расчистить) и подняться
            let d = T.shaft
            guard d != 0 else { p.stage = 4; p.aux2 = T.open0 ? -1 : 1; next(&p, 3); return }
            let E = d > 0 ? T.r1 : T.r0
            let g = shaftGeo(s)
            let kNow = p.tries
            // где стоит: 0 — на дне у торца, дальше — на своей ступени
            var sx = d > 0 ? Float(E) * s.cell - 2 * u : Float(E + 1) * s.cell + 2 * u
            var sy = floorY
            if kNow > 0 {
                let cols = shaftCols(s, E, d, kNow)
                sx = Float(cols.a + cols.b + 1) * 0.5 * s.cell
                sy = Float(s.H - kNow * g.rise) * s.cell
            }
            p.mode = atSupport(T, p.x, s) ? .hop : .crawl
            p.face = Float(d)
            p.anim = .climb
            if p.t > 90 { tunnels[k].fails += 1; popOut(&p, s); return }
            if abs(sx - p.x) > 1 || abs(sy - p.y) > 1 {
                p.x += max(-14 * u * dt, min(14 * u * dt, sx - p.x))
                p.y += max(-30 * u * dt, min(30 * u * dt, sy - p.y))
                p.walkPhase += dt * 3
                return
            }
            // вышел на поверхность? (дальше снег не выше следующей ступени — можно просто шагнуть)
            if kNow >= 2 {
                let cols = shaftCols(s, E, d, kNow + 1)
                var out = true
                for c in max(1, cols.a)...min(s.W - 2, cols.b) where pile(s, c, s.H) > (kNow + 1) * g.rise + 1 { out = false }
                if out || kNow > max(2, Int(85 * u * s.inv) / g.run) {
                    tunnels[k].shaftN = max(T.shaftN, kNow)
                    tunnels[k].done = true
                    p.mode = .ground
                    p.stand = -2
                    p.y = min(p.y, surface(s, x: p.x, stand: -2) ?? p.y)
                    tunnelDone(&p, k, s)
                    return
                }
            }
            // следующая ступень
            let cols = shaftCols(s, E, d, kNow + 1)
            let top = s.H - (kNow + 1) * g.rise - g.hb
            guard cols.a > 1, cols.b < s.W - 2, top >= 1 else { tunnels[k].shaftN = max(T.shaftN, kNow); popOut(&p, s); return }
            var need = false
            for c in cols.a...cols.b { for r in top..<(s.H - (kNow + 1) * g.rise) where s.snow[r * s.W + c] != 0 && s.ledge[r * s.W + c] == 0 { need = true } }
            if !need { p.tries = kNow + 1; return }
            p.anim = .dig
            p.aux += dt
            if p.aux >= 0.3 {
                p.aux = 0
                var n = 0, hd = 0
                for c in cols.a...cols.b {
                    for r in top..<(s.H - (kNow + 1) * g.rise) {
                        let i = r * s.W + c
                        if s.snow[i] != 0 && s.ledge[i] == 0 { s.snow[i] = 0; n += 1; hd += Int(s.hard[i]) }
                    }
                    // свод лаза и ступень утоптать
                    for r in max(0, top - 3)..<top where s.snow[r * s.W + c] != 0 && s.hard[r * s.W + c] < 215 { s.hard[r * s.W + c] = UInt8(min(255, Int(s.hard[r * s.W + c]) + 40)) }
                }
                if n > 0 {
                    s.gridDirty = true
                    s.hardDirty = true
                    s.snowDisturbed(cols.a - 1, top - 2, cols.b + 1, s.H - (kNow + 1) * g.rise)
                    // снег — наверх, на сугроб за будущим выходом
                    let steps = shaftPlan(s, E, d, except: T.id) ?? (kNow + 4)
                    dumpAt(s, Float(E + d * ((steps + 1) * g.run)) * s.cell + Float(d) * 34 * u, spread: 28 * u, n, hard: UInt8(hd / n))
                }
                p.tries = kNow + 1
            }
        default:
            popOut(&p, s)
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
        for T in tunnels where !T.dead && T.c0 <= b && T.c1 >= a { return false }
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
        for T in tunnels where !T.dead && T.c0 <= b && T.c1 >= a { return false }
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
            guard tunnels[k].acc >= 0.5 else { k += 1; continue }
            tunnels[k].acc = 0
            let T = tunnels[k]
            if T.dead {                                     // память места стирается через семь минут
                if s.time - T.used > 420 { tunnels.remove(at: k) } else { k += 1 }
                continue
            }
            if tunnelBusy(T.id) { k += 1; continue }
            if s.time - T.used > 300 { tunnels[k].old = true }
            let parts = tunnelParts(s, T)
            if parts.count == 1 && parts[0].sup == T.sup { k += 1; continue }
            // Обвалился, засыпан или брошен недорытым — целиком или частью. Утоптанные опоры, которые больше
            // ничего не держат, рыхлеют (иначе стояли бы столбиками наста вечно); от самого хода остаётся то,
            // во что ещё можно попасть через устье, или только память места.
            var keep: [Int] = []
            for P in parts { keep += P.sup }
            for c in T.sup where !keep.contains(c) && T.packed.contains(c) { soften(s, c, above: 0) }
            tunnels.remove(at: k)
            if parts.isEmpty {
                var G = T
                G.dead = true
                G.used = s.time
                tunnels.insert(G, at: k)
                k += 1
            } else {
                for (i, var P) in parts.enumerated() {
                    if i > 0 { P.id = nextObjId; nextObjId += 1 }
                    P.fails = 0
                    P.packed = P.packed.filter { P.sup.contains($0) }
                    tunnels.insert(P, at: k)
                    k += 1
                }
            }
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

    /// Что от хода осталось целым. Отрезок цел, если засыпан меньше чем наполовину и свод над ним на месте;
    /// задуманный, но невырытый ждёт полторы минуты. Целы все — возвращает сам ход; иначе — части, в которые
    /// ещё можно попасть через устье (ни одной — хода больше нет).
    func tunnelParts(_ s: Sim, _ T: Tunnel) -> [Tunnel] {
        guard T.done, T.fails < 2, T.sup.count >= 2, T.seg.count == T.sup.count - 1, T.rows < s.H, T.r0 >= 0, T.r1 < s.W else { return [] }
        let n = T.seg.count
        var ok = [Bool](repeating: true, count: n)
        var any = false
        for i in 0..<n {
            if !T.seg[i] { ok[i] = s.time - T.used < 90; continue }
            let a = T.sup[i], b = T.sup[i + 1]
            let rr = i == T.room ? min(T.roomRows, s.H - 1) : T.rows
            guard b - a >= 2 else { ok[i] = false; continue }
            var filled = 0, roof = 0
            for c in (a + 1)..<b {
                for r in (s.H - rr)..<s.H where s.snow[r * s.W + c] != 0 { filled += 1 }
                if pile(s, c, s.H) > rr { roof += 1 }
            }
            let m = b - a - 1
            ok[i] = filled * 2 <= m * rr && roof * 2 >= m
            if ok[i] { any = true }
        }
        if !ok.contains(false) { return any ? [T] : [] }
        var out: [Tunnel] = []
        if T.open0, let i = ok.firstIndex(of: false), i >= 1, T.seg[0..<i].contains(true) {
            var L = T                                       // слева: от устья до первого негодного отрезка
            L.sup = Array(T.sup[0...i])
            L.seg = Array(T.seg[0..<i])
            L.open1 = false; L.f1 = L.r1; L.c1 = L.r1
            L.room = T.room < i ? T.room : -1
            L.shaft = 0; L.shaftN = 0
            out.append(L)
        }
        if T.open1, let j = ok.lastIndex(of: false), j < n - 1, T.seg[(j + 1)..<n].contains(true) {
            var R = T                                       // справа: от последнего негодного до устья
            R.sup = Array(T.sup[(j + 1)...n])
            R.seg = Array(T.seg[(j + 1)..<n])
            R.open0 = false; R.f0 = R.r0; R.c0 = R.r0
            R.room = T.room > j ? T.room - (j + 1) : -1
            R.shaft = 0; R.shaftN = 0
            out.append(R)
        }
        return out
    }

    /// Ход цел весь, как задуман.
    func tunnelAlive(_ s: Sim, _ T: Tunnel) -> Bool { tunnelParts(s, T).first?.sup == T.sup }

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
