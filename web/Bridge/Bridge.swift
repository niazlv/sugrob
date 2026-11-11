import WASILibc

// Мост между страницей и ядром Сугроба. Здесь то, что в приложении делают Overlay.swift и App.swift:
// настройки -> SimConfig, рамки окон -> опоры для снега, курсор и «варежка», и выдача кадра
// (сетка, частицы, шары, человечки) в виде плоских массивов, которые страница читает из памяти wasm.

private var sim: Sim!

// MARK: - Настройки (то же, что Settings.simConfig() в приложении)

private struct WebSettings {
    var weather = 1
    var wind = 0
    var depth = 1
    var autoFill = true
    var openOnly = false
    var floor = true
    var sweep = true
    var aging = true
    var people = 2
    var peopleLadders = true
    var peopleStay = true
    var storms = true
    var peopleEvents = true
    var peopleSize = 2
    var agingRate: Float = 1
    // Множитель предела для «огромных» сугробов (ключ 15 — для подбора). Подобран прогонами: при 2.2 валы
    // до 80 pt, и тоннель начинают в 5 случаях из 5; с 2.6 ложбины между валами уже слишком узки для входа (0 из 5).
    var hugeScale: Float = 2.2

    func simConfig() -> SimConfig {
        var c = SimConfig()
        var windK: Float = 1
        switch weather {
        case 0: c.flakeRate = 5; c.fallMin = 20; c.fallMax = 52; c.gust = 4; c.intensity = 0.5
        case 2: c.flakeRate = 110; c.fallMin = 60; c.fallMax = 130; c.gust = 60; c.intensity = 2.2; windK = 2.2
        default: c.flakeRate = 14; c.fallMin = 22; c.fallMax = 64; c.gust = 6; c.intensity = 1
        }
        c.wind = Float(wind) * 45 * windK
        // 3 — «огромные»: только на странице. Предел сугроба волнистый (Sim.lobe), и при таком множителе
        // на полу сами получаются валы до 80 pt с ложбинами между ними: в ложбине вход, под валом ход.
        c.capScale = depth == 0 ? 0.6 : (depth == 2 ? 1.8 : (depth == 3 ? hugeScale : 1))
        if !autoFill { c.intensity = 0 }
        c.openOnly = openOnly
        c.floor = floor
        c.sweep = sweep
        c.aging = aging
        c.agingRate = agingRate
        c.people = people
        c.peopleLadders = peopleLadders
        c.peopleStay = peopleStay
        c.storms = storms
        c.peopleEvents = peopleEvents
        c.peopleSize = Float(peopleSize)
        return c
    }
}

private var settings = WebSettings()

// MARK: - Окна

private struct WebWin {
    var id: Int
    var x: Float, y: Float, w: Float, h: Float
    var shown: Bool
}

private var pending: [WebWin] = []
private var prevWins: [Int: (x: Float, y: Float)] = [:]
private var stashes: [Int: PileStash] = [:]
private var dockShown = false
private var freshFill = true

// MARK: - Курсор и варежка

private var curX: Float = -1000, curY: Float = -1000
private var curOn = false
private var handsKey = false
private var pressed = false
private var wasPressed = false
private var holding = false
private var hands = false

// MARK: - Буферы кадра

private var gridCap = 0
private var bufSnow: UnsafeMutablePointer<UInt8>?
private var bufHard: UnsafeMutablePointer<UInt8>?
private var bufCave: UnsafeMutablePointer<UInt8>?

private struct FloatBuf {
    var p: UnsafeMutablePointer<Float>?
    var cap = 0
    mutating func need(_ n: Int) -> UnsafeMutablePointer<Float> {
        if let p, cap >= n { return p }
        var c = max(1024, cap)
        while c < n { c <<= 1 }
        p?.deallocate()
        p = UnsafeMutablePointer<Float>.allocate(capacity: c)
        cap = c
        return p!
    }
}

private var bufParts = FloatBuf()
private var bufBalls = FloatBuf()
private var bufPx = FloatBuf()
private var nParts = 0, nBalls = 0, nUnder = 0, nPx = 0
private var pxInsts: [PxInst] = []

// MARK: - Вызовы со страницы

@_expose(wasm, "sg_init")
@_cdecl("sg_init")
func sg_init(_ w: Float, _ h: Float, _ cell: Float) {
    sim = Sim(widthPt: w, heightPt: h, cell: cell)
    sim.cfg = settings.simConfig()
    sim.prefill()
    prevWins = [:]
    stashes = [:]
    dockShown = false
    freshFill = true
    holding = false; hands = false; wasPressed = false
    wishes = []; settleUntil = -1; hills = []
    People.funWish.removeAll(); People.funWishAt = nil
    let n = sim.W * sim.H
    if n > gridCap {
        bufSnow?.deallocate(); bufHard?.deallocate(); bufCave?.deallocate()
        bufSnow = .allocate(capacity: n)
        bufHard = .allocate(capacity: n)
        bufCave = .allocate(capacity: n)
        gridCap = n
    }
    sim.gridDirty = true; sim.hardDirty = true; sim.caveDirty = true
}

@_expose(wasm, "sg_dim")
@_cdecl("sg_dim")
func sg_dim(_ k: Int32) -> Int32 { Int32(k == 0 ? sim.W : sim.H) }

@_expose(wasm, "sg_hour")
@_cdecl("sg_hour")
func sg_hour(_ h: Int32) { webLocalHour = Int(h) }

/// Настройка по номеру: 0 погода, 1 ветер, 2 высота сугробов, 3 растут сами, 4 только где над краем свободно,
/// 5 низ экрана, 6 курсор смахивает, 7 слёживается, 8 человечки, 9 лестницы, 10 остаются жить, 11 бураны,
/// 12 происшествия, 13 размер человечков, 14 ускорение старения.
@_expose(wasm, "sg_set")
@_cdecl("sg_set")
func sg_set(_ key: Int32, _ v: Float) {
    let i = Int(v), on = v != 0
    switch key {
    case 0: settings.weather = i
    case 1: settings.wind = i
    case 2: settings.depth = i
    case 3: settings.autoFill = on
    case 4: settings.openOnly = on
    case 5:
        settings.floor = on
        if !on, sim != nil { _ = sim.extractFloor(x0: 0, x1: sim.wPt) }
    case 6: settings.sweep = on
    case 7:
        settings.aging = on
        if !on, sim != nil { sim.resetHardness() }
    case 8: settings.people = i
    case 9: settings.peopleLadders = on
    case 10: settings.peopleStay = on
    case 11: settings.storms = on
    case 12: settings.peopleEvents = on
    case 13: settings.peopleSize = i
    case 14: settings.agingRate = v
    case 15: settings.hugeScale = v
    default: break
    }
    if sim != nil { sim.cfg = settings.simConfig() }
}

/// 0 буран сейчас, 1 позвать человечков, 2 прогнать и убрать постройки, 3 насыпать снег, 4 лопата.
@_expose(wasm, "sg_action")
@_cdecl("sg_action")
func sg_action(_ k: Int32) {
    guard sim != nil else { return }
    switch k {
    case 0: sim.wind.startStorm()
    case 1: sim.people.summon()
    case 2: sim.people.clearAll(sim)
    case 3: sim.forceFill = true; sim.fillSurfaces(); sim.forceFill = false
    case 4: sim.clearAll()
    default: break
    }
}

@_expose(wasm, "sg_win_begin")
@_cdecl("sg_win_begin")
func sg_win_begin() { pending.removeAll(keepingCapacity: true) }

/// Окна передаются от переднего к заднему. shown = 0 — окно существует, но не на экране (свёрнуто):
/// его сугроб уходит вместе с ним и вернётся.
@_expose(wasm, "sg_win_add")
@_cdecl("sg_win_add")
func sg_win_add(_ id: Int32, _ x: Float, _ y: Float, _ w: Float, _ h: Float, _ shown: Int32) {
    pending.append(WebWin(id: Int(id), x: x, y: y, w: w, h: h, shown: shown != 0))
}

/// Перенос Overlay.updateWindows: сдвиг сугробов вслед за окнами, опоры с вычетом закрытых участков, Dock.
@_expose(wasm, "sg_win_end")
@_cdecl("sg_win_end")
func sg_win_end(_ menuBar: Float, _ radius: Float, _ dockX0: Float, _ dockX1: Float, _ dockTop: Float,
                _ dockR: Float, _ dtIn: Float) {
    guard sim != nil else { return }
    let dt = max(0.01, dtIn)
    let wins = pending.filter { $0.shown }
    var cur: [Int: (x: Float, y: Float)] = [:]
    for w in wins {
        cur[w.id] = (w.x, w.y)
        if let old = prevWins[w.id], old.x != w.x || old.y != w.y {
            let dx = w.x - old.x, dy = w.y - old.y
            func cellOf(_ v: Float) -> Int { Int((v / sim.cell).rounded()) }
            let cols = cellOf(w.x) - cellOf(old.x)
            let rows = cellOf(w.y) - cellOf(old.y)
            for s in sim.segs where s.win == w.id {
                sim.shiftPile(s, cols: cols, rows: rows, vx: dx / dt, vy: dy / dt)
            }
        }
    }
    prevWins = cur

    let gone = Set(sim.segs.lazy.filter { $0.win >= 0 && cur[$0.win] == nil }.map { $0.win })
    if !gone.isEmpty {
        let alive = Set(pending.map { $0.id })
        for id in gone where alive.contains(id) { stashes[id] = sim.extractPile(win: id) }
        stashes = stashes.filter { alive.contains($0.key) }
    }

    let open = sim.cfg.openOnly
    sim.topLimit = menuBar + 1
    sim.minRoom = 9
    var out: [Ledge] = []
    for (i, w) in wins.enumerated() {
        let y = w.y
        let edge = max(3, radius * 0.3)
        guard w.w >= 60, w.h >= 40 else { continue }
        guard y > menuBar - 1, y > 6, y < sim.hPt - 12 else { continue }
        var ivs: [(Float, Float)] = [(max(w.x + edge, 0), min(w.x + w.w - edge, sim.wPt))]
        for j in 0..<i {
            let f = wins[j]
            guard f.y <= y + 3, f.y + f.h > y - (open ? 14 : 3) else { continue }
            let a = f.x - 3, b = f.x + f.w + 3
            var next: [(Float, Float)] = []
            for iv in ivs {
                if b <= iv.0 || a >= iv.1 { next.append(iv); continue }
                if a > iv.0 { next.append((iv.0, a)) }
                if b < iv.1 { next.append((b, iv.1)) }
            }
            ivs = next
            if ivs.isEmpty { break }
        }
        for iv in ivs where iv.1 - iv.0 >= 18 {
            out.append(Ledge(y: y, x0: iv.0, x1: iv.1, kind: 1, win: w.id, ox: w.x, wr: w.x + w.w, r: radius))
        }
    }

    var dl: Ledge?
    if dockTop > 0, dockX1 - dockX0 > 40 {
        let edge = max(3, dockR * 0.3)
        dl = Ledge(y: dockTop, x0: dockX0 + edge, x1: dockX1 - edge, kind: 2, win: -1, ox: dockX0, wr: dockX1, r: dockR)
    }
    if let dl, !dockShown {
        sim.liftFloor(x0: dl.x0, x1: dl.x1, toY: dl.y)
    } else if dl == nil, dockShown {
        sim.dropDock()
    } else if let dl, let old = sim.segs.first(where: { $0.win == -1 }) {
        let rows = Int((dl.y / sim.cell).rounded()) - Int((old.y / sim.cell).rounded())
        if rows != 0 { sim.shiftPile(old, cols: 0, rows: rows, vx: 0, vy: 0) }
    }
    if let dl { out.append(dl) }
    let boxes = wins.map { WinBox(x0: $0.x, x1: $0.x + $0.w, y0: $0.y, y1: $0.y + $0.h, win: $0.id) }
    sim.setLedges(out, windows: boxes)
    dockShown = dl != nil
    if !stashes.isEmpty {
        for id in Set(out.map { $0.win }) {
            guard let st = stashes[id], let r = cur[id] else { continue }
            sim.insertPile(st, ox: r.x, y: r.y)
            stashes[id] = nil
        }
    }
    if freshFill {
        sim.forceFill = true
        sim.fillSurfaces()
        sim.forceFill = false
        freshFill = false
    }
}

@_expose(wasm, "sg_cursor")
@_cdecl("sg_cursor")
func sg_cursor(_ x: Float, _ y: Float, _ on: Int32) { curX = x; curY = y; curOn = on != 0 }

/// key — зажата клавиша «варежки», down — нажата кнопка мыши.
@_expose(wasm, "sg_hands")
@_cdecl("sg_hands")
func sg_hands(_ key: Int32, _ down: Int32) { handsKey = key != 0; pressed = down != 0 }

/// Шаг симуляции и сбор кадра. steps — сколько шагов сделать за этот кадр (ускорение времени).
/// Возвращает биты: 1 сетка, 2 слежалость, 4 пустоты изменились; 8 — режим варежки, 16 — в руке шар.
@_expose(wasm, "sg_step")
@_cdecl("sg_step")
func sg_step(_ dtIn: Float, _ steps: Int32) -> Int32 {
    guard sim != nil else { return 0 }
    let dt = min(max(dtIn, 0.001), 1.0 / 20)
    for _ in 0..<max(1, Int(steps)) {
        sim.setCursor(x: curX, y: curY, dt: dt, on: curOn)
        hands = (handsKey && curOn) || holding
        sim.handsMode = hands
        if hands && pressed && !wasPressed && !holding && curOn {
            sim.grabBegin()
            holding = sim.heldId != -1
        }
        if holding && !pressed {
            sim.grabEnd()
            holding = false
        }
        wasPressed = pressed
        sim.step(dt)
        pushWishes()
    }

    var flags: Int32 = 0
    let n = sim.W * sim.H
    if sim.gridDirty, let b = bufSnow {
        sim.snow.withUnsafeBufferPointer { b.update(from: $0.baseAddress!, count: n) }
        sim.gridDirty = false
        flags |= 1
    }
    if sim.hardDirty, let b = bufHard {
        sim.hard.withUnsafeBufferPointer { b.update(from: $0.baseAddress!, count: n) }
        sim.hardDirty = false
        flags |= 2
    }
    if sim.caveDirty, let b = bufCave {
        sim.cave.withUnsafeBufferPointer { b.update(from: $0.baseAddress!, count: n) }
        sim.caveDirty = false
        flags |= 4
    }

    // частицы: x, y, размер, прозрачность (2 — ком)
    nParts = sim.parts.count
    if nParts > 0 {
        let dst = bufParts.need(nParts * 4)
        sim.parts.withUnsafeBufferPointer { src in
            for i in 0..<nParts {
                let p = src[i]
                dst[i * 4] = p.x; dst[i * 4 + 1] = p.y; dst[i * 4 + 2] = p.size
                dst[i * 4 + 3] = p.kind == 1 ? 2 : p.alpha
            }
        }
    }

    // шары: стоящие (под снегом) — первыми, движущиеся и кольцо варежки — после
    let ring = sim.handsMode && sim.heldId == -1 && sim.cursorOn
    nBalls = sim.balls.count + (ring ? 1 : 0)
    nUnder = 0
    if nBalls > 0 {
        let dst = bufBalls.need(nBalls * 12)
        var k = 0
        func put(_ b: Ball) {
            let o = k * 12
            dst[o] = b.x; dst[o + 1] = b.y; dst[o + 2] = b.r; dst[o + 3] = b.angle
            dst[o + 4] = Float(b.decor); dst[o + 5] = b.seed; dst[o + 6] = 0; dst[o + 7] = 0
            dst[o + 8] = b.cutA; dst[o + 9] = b.cutD; dst[o + 10] = min(1, b.rest / 240); dst[o + 11] = b.angle - b.decorA
            k += 1
        }
        for b in sim.balls where b.slot != 0 { put(b) }
        nUnder = k
        for b in sim.balls where b.slot == 0 { put(b) }
        if ring {
            let o = k * 12
            for j in 0..<12 { dst[o + j] = 0 }
            dst[o] = sim.cx; dst[o + 1] = sim.cy; dst[o + 2] = 15; dst[o + 4] = 8
        }
    }

    // человечки и постройки: прямоугольник + цвет
    pxInsts.removeAll(keepingCapacity: true)
    sim.people.emit(sim, into: &pxInsts)
    nPx = pxInsts.count
    if nPx > 0 {
        let dst = bufPx.need(nPx * 8)
        for i in 0..<nPx {
            let q = pxInsts[i]
            let o = i * 8
            dst[o] = q.rect.x; dst[o + 1] = q.rect.y; dst[o + 2] = q.rect.z; dst[o + 3] = q.rect.w
            dst[o + 4] = q.color.x; dst[o + 5] = q.color.y; dst[o + 6] = q.color.z; dst[o + 7] = q.color.w
        }
    }

    if hands { flags |= 8 }
    if holding { flags |= 16 }
    return flags
}

/// Адрес буфера: 0 снег, 1 слежалость, 2 пустоты, 3 частицы, 4 шары, 5 человечки.
@_expose(wasm, "sg_ptr")
@_cdecl("sg_ptr")
func sg_ptr(_ k: Int32) -> Int32 {
    switch k {
    case 0: return Int32(Int(bitPattern: bufSnow))
    case 1: return Int32(Int(bitPattern: bufHard))
    case 2: return Int32(Int(bitPattern: bufCave))
    case 3: return Int32(Int(bitPattern: bufParts.p))
    case 4: return Int32(Int(bitPattern: bufBalls.p))
    default: return Int32(Int(bitPattern: bufPx.p))
    }
}

/// Сколько записей в буфере: 0 частицы, 1 шары всего, 2 шары под снегом, 3 прямоугольники человечков.
@_expose(wasm, "sg_count")
@_cdecl("sg_count")
func sg_count(_ k: Int32) -> Int32 {
    switch k {
    case 0: return Int32(nParts)
    case 1: return Int32(nBalls)
    case 2: return Int32(nUnder)
    default: return Int32(nPx)
    }
}

/// Сколько человечков сейчас на экране (для подписи на странице).
@_expose(wasm, "sg_people")
@_cdecl("sg_people")
func sg_people() -> Int32 { sim == nil ? 0 : Int32(sim.people.folks.count) }

// MARK: - Сцена и поручения
//
// В приложении человечки сами решают, чем заняться, и многое зависит от того, давно ли лежит снег.
// На странице у посетителя нет получаса, поэтому здесь: стартовая сцена со слежавшимся снегом и горками,
// и поручения — те же рычаги, которыми пользуются самотесты ядра (желание рыть, остаться жить, план лестницы).

private var hills: [Float] = []

/// Срезать сугроб на полу до заданной высоты (в ячейках над полом). Снег на окнах не трогается.
private func levelFloor(from x0: Float, to x1: Float, cells: Int) {
    let s = sim!
    let a = max(0, Int(x0 * s.inv)), b = min(s.W - 1, Int(x1 * s.inv))
    guard a <= b, cells < s.H else { return }
    for c in a...b {
        var r = s.H - 1
        while r >= 0 && s.snow[r * s.W + c] != 0 && s.ledge[r * s.W + c] == 0 {
            if s.H - r > cells { s.snow[r * s.W + c] = 0 }
            r -= 1
        }
    }
}

/// Горка на полу — как в самотесте тоннелей: под ней помещается ход и остаётся свод.
private func hill(x: Float, hard: UInt8) {
    let s = sim!, u = max(2, s.cfg.peopleSize), cell = s.cell
    let rows = s.people.tunnelRows(s)
    let top = Float(rows) * cell + max(16, 5 * cell)
    let half = 15 * u, slope = 6 * u
    var rng = Rng(seed: 99)
    let a = max(0, Int((x - half - slope) / cell)), b = min(s.W - 1, Int((x + half + slope) / cell))
    guard a <= b else { return }
    levelFloor(from: x - 80 * u, to: x + 80 * u, cells: rows + 1)
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
        var r = s.H - 1
        while r >= 0 && s.snow[r * s.W + c] != 0 { s.hard[r * s.W + c] = hard; r -= 1 }
    }
}

/// Стартовая сцена: снег на полу уже полежал (плотный), а в точках x1 и x2 намело по слежавшейся горке.
/// Отрицательный x — горки нет. На окнах снег остаётся свежим: его приятнее смахивать.
@_expose(wasm, "sg_scene")
@_cdecl("sg_scene")
func sg_scene(_ x1: Float, _ x2: Float) {
    guard sim != nil else { return }
    let s = sim!
    // Сугроб на полу — давний: чем глубже, тем дольше лежит и тем плотнее. Сверху плотный снег,
    // в глубине наст — он и держит свод над ходом; под тонким валом свод слабее и может сесть.
    for c in 0..<s.W {
        var top = s.H
        while top - 1 >= 0 && s.snow[(top - 1) * s.W + c] != 0 && s.ledge[(top - 1) * s.W + c] == 0 { top -= 1 }
        guard top < s.H else { continue }
        for r in top..<s.H {
            s.hard[r * s.W + c] = UInt8(min(236, 96 + (r - top) * 11))
        }
    }
    hills = [x1, x2].filter { $0 > 0 }
    for x in hills { hill(x: x, hard: 232) }
    s.gridDirty = true
    s.hardDirty = true
    s.recheckHanging()
}

private struct Wish {
    var job: Person.Job
    var id: Int32
    var until: Float
    var site: Float = -1        // тоннель: где рыть (x середины хода)
}
private var wishes: [Wish] = []
private var settleUntil: Float = -1
private var igloosWere = 0

private func freeGuest(_ p: Person) -> Bool {
    // носильщики снега для лестницы тоже годятся: между ходками они заново выбирают занятие
    !p.gone && p.home == -1 && p.stand == -2 && p.mode == .ground && p.job != .leave && p.job != .buried
        && p.job != .tunnel && p.job != .igloo && p.job != .panic && p.job != .rescue
}

/// Гости не расходятся, пока есть дело; если никого нет — позвать.
private func keepGuests(_ seconds: Float) {
    let pp = sim.people
    if !pp.folks.contains(where: { !$0.gone && $0.job != .leave }) { pp.summon() }
    pp.visitEnd = max(pp.visitEnd, sim.time + seconds)
}

/// Желание действует, только когда человечек выбирает новое занятие, — поэтому повторяем его,
/// пока он не возьмётся (или пока не выйдет время).
private func pushWishes() {
    guard sim != nil else { return }
    let pp = sim.people
    if settleUntil > 0 {
        if pp.igloos.count > igloosWere || sim.time > settleUntil { settleUntil = -1 }
        else if !pp.settleWish { pp.settleWish = true; pp.visitStart = min(pp.visitStart, sim.time - 30) }
    }
    guard !wishes.isEmpty else { return }
    var k = 0
    while k < wishes.count {
        var w = wishes[k]
        let cur = pp.folks.first(where: { $0.id == w.id })
        if w.job == .tunnel && w.site >= 0 {
            // Тоннель — дело долгое, и землекопа легко отвлечь (попали снежком — бросил). Поручение держится,
            // пока ход не прокопан: если никто не роет, зовём ближайшего свободного снова.
            let dug = pp.tunnels.contains(where: { $0.done && abs(pp.tunnelMid($0, sim) - w.site) < 60 })
            if dug || sim.time > w.until {
                if w.id >= 0 { People.funWish[w.id] = nil }
                wishes.remove(at: k)
                continue
            }
            if pp.folks.contains(where: { $0.job == .tunnel && !$0.gone }) { k += 1; continue }
            // место осело или занято — в последнюю минуту пусть роет, где сам найдёт
            People.funWishAt = w.until - sim.time < 60 ? nil : w.site
            if cur == nil || !freeGuest(cur!) {
                let near = pp.folks.filter { freeGuest($0) }.min(by: { abs($0.x - w.site) < abs($1.x - w.site) })
                w.id = near?.id ?? -1
                wishes[k] = w
            }
            if w.id >= 0 { People.funWish[w.id] = .tunnel }
            k += 1
            continue
        }
        if let cur, cur.job == w.job {              // взялся
            People.funWish[w.id] = nil
            wishes.remove(at: k)
            continue
        }
        if sim.time > w.until {
            People.funWish[w.id] = nil
            wishes.remove(at: k)
            continue
        }
        if cur == nil || cur!.gone || cur!.job == .leave {      // некому — ищем свободного (для забав охотнее дети)
            let taken = Set(wishes.map { $0.id })
            let free = pp.folks.filter { freeGuest($0) && !taken.contains($0.id) }
            if let q = free.first(where: { $0.look.kid }) ?? free.first { w.id = q.id; wishes[k] = w }
        }
        if w.id >= 0 { People.funWish[w.id] = w.job }
        k += 1
    }
    if wishes.isEmpty { People.funWishAt = nil }
}

/// Поручение: 0 лестница, 1 тоннель, 2 иглу, 3 снежный ангел, 4 санки, 5 ёлка, 6 снег с карниза.
/// Возвращает 1 — взялись (или возьмутся, как освободятся), 0 — сейчас негде или нечем.
@_expose(wasm, "sg_task")
@_cdecl("sg_task")
func sg_task(_ k: Int32) -> Int32 {
    guard sim != nil else { return 0 }
    let s = sim!, pp = s.people
    switch k {
    case 0:
        if let i = pp.ladders.firstIndex(where: { $0.base == -2 && !$0.done && !$0.broken }) {
            pp.ladders[i].active = true         // достроить начатую
            pp.ladders[i].stalled = 0
            pp.ladders[i].empty = 0
        } else {
            guard var L = pp.findSite(s) else { return 0 }
            L.id = pp.nextLadderId
            pp.nextLadderId += 1
            L.active = true
            L.usedAt = s.time
            pp.ladders.append(L)
        }
        keepGuests(200)
        if pp.folks.count < 4 { pp.startVisit(s, extra: true) }
        pp.planned = true
        return 1
    case 1, 3:
        keepGuests(200)
        // все заняты стройкой — на подмогу приходят ещё двое (гостей не больше семи)
        if !pp.folks.contains(where: { freeGuest($0) && $0.job != .gather && $0.job != .lift }) { pp.startVisit(s, extra: true) }
        var who: Int32 = -1
        var siteX: Float = -1
        if k == 1 {
            // Место ищем сами по всему низу экрана и берём то, где над ходом больше всего снега:
            // человечек, которому просто «захотелось», смотрит только рядом с собой и часто не находит.
            let u = max(2, s.cfg.peopleSize)
            var best: (x: Float, roof: Int)? = nil
            for i in 1...11 {
                let x = s.wPt * Float(i) / 12
                guard let T = pp.tunnelSite(s, near: x, strict: false, reach: s.wPt / (24 * u) + 8) else { continue }
                var roof = 0
                for c in T.r0...T.r1 { roof += pp.pile(s, c, s.H) }
                roof /= max(1, T.r1 - T.r0 + 1)
                if best == nil || roof > best!.roof { best = (pp.tunnelMid(T, s), roof) }
            }
            guard let site = best else { return 0 }
            People.funWishAt = site.x
            siteX = site.x
            // зовём того, кто ближе к месту
            let near = pp.folks.filter { freeGuest($0) }.min(by: { abs($0.x - site.x) < abs($1.x - site.x) })
            who = near?.id ?? -1
            wishes.removeAll { $0.job == .tunnel }      // рыть — в одном месте за раз
        }
        wishes.append(Wish(job: k == 1 ? .tunnel : .angel, id: who, until: s.time + (k == 1 ? 300 : 150), site: siteX))
        return 1
    case 2:
        keepGuests(200)
        if pp.folks.filter({ !$0.gone && !$0.look.kid && $0.home == -1 }).count < 2 { pp.startVisit(s, extra: true) }
        // стройка лестницы забирает всех свободных — пока закладывают дом, она подождёт (потом достроят сами)
        for i in pp.ladders.indices where pp.ladders[i].active && !pp.ladders[i].done { pp.ladders[i].active = false }
        pp.planned = true
        igloosWere = pp.igloos.count
        settleUntil = s.time + 120
        pp.settleWish = true
        pp.visitStart = min(pp.visitStart, s.time - 30)
        return 1
    case 4: return pp.startSled(s) ? 1 : 0
    case 5: return pp.startTree(s) ? 1 : 0
    case 6: return pp.avalanche(s) ? 1 : 0
    default: return 0
    }
}

/// Снег «полежал» ещё minutes минут: слёживается так же, как сам со временем (плотный с ~3 мин, наст с ~7,5).
@_expose(wasm, "sg_age")
@_cdecl("sg_age")
func sg_age(_ minutes: Float) {
    guard sim != nil else { return }
    let add = Int(minutes * 26.7)
    for i in sim.snow.indices where sim.snow[i] != 0 { sim.hard[i] = UInt8(min(255, Int(sim.hard[i]) + add)) }
    sim.hardDirty = true
}

/// Кто чем занят: 0 лестница, 1 тоннель, 2 иглу и хозяйство, 3 снеговик, 4 снежки, 5 ангел, 6 санки,
/// 7 ёлка, 8 беда (завалило, спасают), 9 остальные (гуляют, смотрят, приходят и уходят).
@_expose(wasm, "sg_jobs")
@_cdecl("sg_jobs")
func sg_jobs(_ k: Int32) -> Int32 {
    guard sim != nil else { return 0 }
    var n: Int32 = 0
    for p in sim.people.folks where !p.gone {
        let g: Int32
        switch p.job {
        case .gather, .lift, .goTop, .top, .goDown, .steps: g = 0
        case .tunnel: g = 1
        case .igloo, .home, .shovel, .fire: g = 2
        case .snowman: g = 3
        case .fight, .hit: g = 4
        case .angel: g = 5
        case .sled, .ride: g = 6
        case .tree: g = 7
        case .buried, .panic, .rescue, .mourn, .shelter: g = 8
        default: g = 9
        }
        if g == k { n += 1 }
    }
    return n
}

/// Что построено: 0 лестницы, 1 иглу, 2 тоннели, 3 ёлки.
@_expose(wasm, "sg_built")
@_cdecl("sg_built")
func sg_built(_ k: Int32) -> Int32 {
    guard sim != nil else { return 0 }
    let pp = sim.people
    switch k {
    case 0: return Int32(pp.ladders.count)
    case 1: return Int32(pp.igloos.count)
    case 2: return Int32(pp.tunnels.count)
    default: return Int32(pp.trees.count)
    }
}
