import Foundation

// Дома: пара гостей остаётся жить — строит иглу, убирает снег, греется у костра; уходит — иглу заметает.
//
// Иглу — отдельный объект, а не ячейки сетки: купол из снежных блоков, нарисованный «пикселями»
// человечков. Блоки делают из снега сетки: набрали, утоптали и вырезали брусок, отнесли, уложили
// (блок стоит несколько ячеек). Выбитый блок разлетается комьями обратно в сетку, занесённое
// брошенное иглу становится обычным сугробом.
//
// Стоит иглу на площадке: ячейки сетки под ним выровнены и утоптаны до наста. Низ дома (`baseY`)
// задаётся при закладке и сам не двигается: нападавший снег дом заносит, а не поднимает. Жители за
// площадкой следят (подсыпают, срезают бугры, убирают намёт). Опора ушла из-под части дома — блоки
// над провалом выпадают; осела вся площадка — дом рывком садится на новый уровень.
//
// Для падающего снега купол твёрдый: силуэт уложенных блоков отмечен в `Sim.mask` (значения 251…254),
// снег ложится на него и скатывается к стенам. Настоящий снег с купола жители счищают лопатой; если
// дом завалило так, что вход закрыт, запертых откапывают снаружи (а сами они — изнутри).
//
// Семья: оставшийся один горюет, но живёт дальше и может сойтись с одиноким гостем; у пары появляются
// дети (до двух), дети вырастают и строят своё иглу рядом.
//
// Два дома и больше — поселение: общий костёр, тропинки между домами, ледяные фонарики у входов,
// верёвка с флажками.
//
// Житель — тот, у кого `home == id` и кто записан в `Igloo.residents`. О переменах (позвали в пару,
// пора уходить) каждый узнаёт сам в своём хуке — по записи об иглу.

struct Igloo {
    var id: Int
    var x: Float                // середина
    var baseY: Float            // низ
    var blocks: [Bool] = []     // какие снежные блоки уже уложены (по порядку кладки)
    var built = false
    var cover: Float = 0        // 0…1: насколько занесло снегом
    var residents: [Int32] = [] // жители и те, кого позвали жить
    var abandoned: Float = -1   // когда из него ушли (-1 — живут)
    var born: Float
    var stock = 0               // рыхлый снег, сложенный у стены (на подсыпку основания)
    var door: Float = -1        // с какой стороны от середины вход
    var until: Float = 0        // когда жители надумают уйти
    var invited: Float = 0      // когда позвали пару
    var inside = 0              // сколько человечков сейчас внутри
    var stalled: Float = 0      // секунд без дела на стройке (пока не достроено)
    var hitCD: Float = 0        // пауза между ударами курсора
    var acc: Float = 0
    // площадка
    var c0 = 0, c1 = 0          // её столбцы
    var floorRow = -1           // строка её верха (по baseY): с неё и ниже — утоптанный снег
    var based = false           // выровнена и утоптана
    var baseT: Float = 9        // когда последний раз осматривали
    var baseNeed = 0            // сколько ячеек в ней не хватает (просело, пустота)
    var baseExtra = 0           // сколько лишних сверху (намело, бугры)
    // стройка
    var stack = 0               // готовых блоков в штабеле у стройки
    var stool = false           // снежная приступка у стены — для верхнего ряда
    var doneAt: Float = -100    // когда уложили последний блок
    var ruinedAt: Float = -100  // когда рухнуло (жители отстраивают)
    var mourned: [Int32] = []   // кто уже постоял над развалинами
    var noSnow: Float = -100    // когда не нашли снега на починку
    // благоустройство
    var lantern: Float = -1     // когда поставили ледяной фонарик у входа (-1 — нет)
    var flagTo = -1             // id соседа справа, к которому тянется верёвка с флажками
    var flagK: Float = 0        // насколько она натянута, 0…1
    var pathTo = -1             // id соседа справа, к которому протоптана тропинка
    // твёрдый купол (Sim.mask)
    var mk: UInt8 = 0           // чем отмечены его ячейки: 251…254
    var maskSig = -1            // по чему маска поставлена (блоки и уровень); -1 — не стоит
    var mBox = (c0: 0, r0: 0, c1: -1, r1: -1)
    var mProbe = -1             // одна из её ячеек — проверять, не сбросили ли маску
    var bury: Float = 0         // 0…1: насколько дом завален настоящим снегом
    var roof = 0                // сколько ячеек снега лежит на куполе
    var roofCol = -1            // и где его больше всего
    // завалило вход
    var trappedAt: Float = -1   // с какого времени внутри заперты (-1 — нет)
    var freedAt: Float = -100   // когда откопали
    var digAcc: Float = 0
    var alertT: Float = 0
    // семья
    var adults = 0              // сколько взрослых жителей было при последнем осмотре
    var since: Float = -1       // с какого времени живут вдвоём в готовом доме (-1 — нет)
    var nextKid: Float = -1     // когда появится ребёнок
    var kidsBorn = 0            // сколько детей уже родилось
    var kids: [Int32] = []      // дети, которые ещё не выросли
    var grow: [Float] = []      // и когда каждый вырастет
    var grown: [Int32] = []     // выросшие: ищут пару, чтобы построить свой дом
    var griefUntil: Float = 0   // до какого времени оставшийся один горюет
    var court: Int32 = -1       // гость, с которым одинокий житель проводит время
    var courtT: Float = 0       // сколько секунд они провели рядом
    var courtCD: Float = 0      // до какого времени не знакомится

    var laid: Int { var n = 0; for b in blocks where b { n += 1 }; return n }
}

struct Fire {
    var id: Int
    var x: Float
    var y: Float = 0            // поверхность снега под костром
    var born: Float
    var until: Float
    var acc: Float = 0
    var big = false             // общий костёр поселения
    var gather: Float = 0       // до какого времени у него собираются
}

/// Ручки для самотеста.
enum HomeTune {
    static var coverSpeed: Float = 1    // во сколько раз быстрее заносит
    static var siteX: Float? = nil      // где искать место для иглу (вместо «рядом с человечком»)
    static var evening: Bool? = nil     // вечер ли (nil — по часам)
    static var eveAt: Float = -1000, eve = false
    static var trapLimit: Float = 150   // сколько секунд запертые в заваленном доме ждут помощи
    static var family: Float = 1        // во сколько раз быстрее идёт семейная жизнь (дети, взросление, знакомства)
    static var masked = Set<ObjectIdentifier>()     // у чьих симуляций в маске могут быть ячейки иглу
}

/// «Пиксель» иглу: x — от середины, y — вверх от низа, в единицах u.
struct IglooPx {
    var x: Int8, y: Int8
    var kind: UInt8             // см. IglooGeo.k…
    var block: UInt8            // номер блока в порядке кладки
    var tone: Float             // яркость (оттенок блока и объём купола)
    var th: Float               // при каком заносе пиксель уже под снегом
    var glow: Float             // вход: 0…1 — насколько близко к огню внутри
}

/// Форма иглу: считается один раз для каждой стороны входа.
final class IglooGeo {
    static let hw = 17, h = 20              // полуширина и высота купола
    static let kBody: UInt8 = 0, kSeam: UInt8 = 1, kLight: UInt8 = 2, kDark: UInt8 = 3, kDoor: UInt8 = 4, kFrame: UInt8 = 5
    let px: [IglooPx]
    let count: Int                          // сколько блоков
    let cx: [Float], cy: [Float]            // середины блоков
    let row: [Int]                          // в каком ряду блок
    let top: [Int8]                         // верх купола по столбцам (индекс x + hw), -1 — нет
    let topTh: [Float]
    let topBlock: [UInt8]
    let doorX: Float                        // середина входа
    let x0: [Int], x1: [Int]                // края блоков по x (x1 — включительно)
    let grid: [UInt8]                       // какой блок в «пикселе» (x, y): индекс (x + hw) * h + y; 255 — вне купола

    static let left = IglooGeo(door: -1), right = IglooGeo(door: 1)
    static func of(_ door: Float) -> IglooGeo { door < 0 ? left : right }

    static func inDome(_ x: Int, _ y: Int) -> Bool {
        guard y >= 0, y < h else { return false }
        let fx = abs(Float(x) + 0.5) / Float(hw), fy = (Float(y) + 0.5) / Float(h)
        return powf(fx, 2.2) + powf(fy, 2.2) <= 1
    }

    /// Точка (в u от середины низа, y вверх) внутри купола, раздутого на grow.
    static func hit(_ x: Float, _ y: Float, grow: Float) -> Bool {
        guard y > -grow, y < Float(h) + grow else { return false }
        let fx = x / (Float(hw) + grow), fy = max(0, y) / (Float(h) + grow)
        return fx * fx + fy * fy <= 1
    }

    /// Неровный край снежной шапки.
    static func wob(_ x: Int) -> Float { 1.3 * sinf(Float(x) * 1.9) + 0.8 * sinf(Float(x) * 0.7 + 1.3) }

    init(door: Int) {
        let hw = IglooGeo.hw, h = IglooGeo.h
        let dc = door * 6
        doorX = Float(dc) + 0.5
        func isDoor(_ x: Int, _ y: Int) -> Bool {
            guard y >= 0, y <= 9 else { return false }
            return abs(x - dc) <= (y == 9 ? 1 : (y == 8 ? 2 : 3))
        }
        // кладка: ряды по 4, блоки по 6, через ряд — со сдвигом на полблока
        let rows = h / 4
        func slot(_ x: Int, _ y: Int) -> Int { (x + 18 + ((y / 4) % 2 == 0 ? 0 : 3)) / 6 }
        var cnt = [[Int]](repeating: [Int](repeating: 0, count: 8), count: rows)
        var all = [[Int]](repeating: [Int](repeating: 0, count: 8), count: rows)
        for y in 0..<h {
            for x in -hw..<hw where IglooGeo.inDome(x, y) {
                all[y / 4][slot(x, y)] += 1
                if !isDoor(x, y) { cnt[y / 4][slot(x, y)] += 1 }
            }
        }
        // обрезки у краёв купола и блок, целиком попавший во вход, — часть соседнего блока
        var remap = [[Int]](repeating: Array(0..<8), count: rows)
        for r in 0..<rows {
            for k in 0..<8 where all[r][k] > 0 && (all[r][k] < 8 || cnt[r][k] == 0) {
                let mid = Float(k * 6 - 18 - (r % 2 == 0 ? 0 : 3)) + 3
                let t = mid < 0 ? k + 1 : k - 1
                if t >= 0 && t < 8 && all[r][t] > 0 { remap[r][k] = t }
            }
        }
        // порядок кладки: снизу вверх, ряды — навстречу друг другу
        var ids = [[Int]](repeating: [Int](repeating: -1, count: 8), count: rows)
        var n = 0
        var rowOf: [Int] = []
        for r in 0..<rows {
            for j in 0..<8 {
                let k = r % 2 == 0 ? j : 7 - j
                if all[r][k] > 0 && remap[r][k] == k { ids[r][k] = n; n += 1; rowOf.append(r) }
            }
        }
        func blockAt(_ x: Int, _ y: Int) -> Int { ids[y / 4][remap[y / 4][slot(x, y)]] }
        count = n
        row = rowOf
        var sx = [Float](repeating: 0, count: n), sy = [Float](repeating: 0, count: n), sn = [Float](repeating: 0, count: n)
        var lo = [Int](repeating: 99, count: n), hi = [Int](repeating: -99, count: n)
        var list: [IglooPx] = []
        var gr = [UInt8](repeating: 255, count: hw * 2 * h)
        var tops = [Int8](repeating: -1, count: hw * 2), tth = [Float](repeating: 2, count: hw * 2), tb = [UInt8](repeating: 0, count: hw * 2)
        for y in 0..<h {
            for x in -hw..<hw where IglooGeo.inDome(x, y) {
                let b = blockAt(x, y)
                guard b >= 0 else { continue }
                sx[b] += Float(x) + 0.5; sy[b] += Float(y) + 0.5; sn[b] += 1
                gr[(x + hw) * h + y] = UInt8(b)
                lo[b] = min(lo[b], x); hi[b] = max(hi[b], x)
                let cap = max(0.03, min(0.97, 1 - (Float(y) + IglooGeo.wob(x)) / Float(h)))
                var kind = IglooGeo.kBody
                var th = cap
                var glow: Float = 0
                if isDoor(x, y) {
                    kind = IglooGeo.kDoor
                    th = min(cap, 0.5 + 0.025 * Float(y))               // вход заметает и снизу
                    glow = max(0, 1 - hypotf(Float(x - dc), Float(y - 2) * 0.8) / 7)
                } else {
                    var nearDoor = false
                    for dy in -1...1 { for dx in -1...1 where isDoor(x + dx, y + dy) { nearDoor = true } }
                    let up = !IglooGeo.inDome(x, y + 1), l = !IglooGeo.inDome(x - 1, y), r = !IglooGeo.inDome(x + 1, y)
                    if nearDoor { kind = IglooGeo.kFrame }
                    else if l || (up && x <= 7) { kind = IglooGeo.kLight }
                    else if r || up { kind = IglooGeo.kDark }
                    else if (y % 4 == 0 && y > 0) || (IglooGeo.inDome(x - 1, y) && blockAt(x - 1, y) != b) { kind = IglooGeo.kSeam }
                }
                let hsh = Float((b &* 97 &+ 13) % 11) / 10                      // у каждого блока свой оттенок
                let tone = (0.95 + 0.085 * hsh) * (1 - 0.07 * Float(x) / Float(hw) + 0.03 * Float(y) / Float(h))
                list.append(IglooPx(x: Int8(x), y: Int8(y), kind: kind, block: UInt8(b), tone: tone, th: th, glow: glow))
                if Int(tops[x + hw]) < y { tops[x + hw] = Int8(y); tth[x + hw] = th; tb[x + hw] = UInt8(b) }
            }
        }
        px = list
        cx = (0..<n).map { sx[$0] / max(1, sn[$0]) }
        cy = (0..<n).map { sy[$0] / max(1, sn[$0]) }
        top = tops; topTh = tth; topBlock = tb
        x0 = lo; x1 = hi
        grid = gr
    }
}

extension Igloo {
    /// Площадке нужен уход: ещё не готова, просела, под ней пустота или на неё намело.
    var baseBad: Bool { floorRow >= 0 && (!based || baseNeed >= 3 || (!built && baseExtra >= c1 - c0 + 1)) }
}

/// Что с площадкой под иглу (см. People.baseScan).
struct BaseState {
    var need = 0                // пустых ячеек там, где должен быть утоптанный снег
    var extra = 0               // ячеек снега выше площадки
    var soft = 0                // столбцов, где верх не утоптан
    var drop = 0                // на сколько ячеек просел верх, суммой по столбцам
    var deep = (0, 0, 0, 0)     // в скольких столбцах верх просел не меньше чем на 1, 2, 3, 4 ячейки
    var col = -1                // ближайший столбец, где что-то не так
    var colExtra = false        // в нём лишний снег (а не яма)
}

extension People {
    // MARK: - Служебное

    func iglooIndex(_ id: Int) -> Int? { id < 0 ? nil : igloos.firstIndex(where: { $0.id == id }) }

    /// Иглу, в котором p живёт на самом деле: оно есть, не брошено, и p в нём записан.
    func homeIndex(_ p: Person) -> Int? {
        guard let k = iglooIndex(p.home), igloos[k].abandoned < 0, igloos[k].residents.contains(p.id) else { return nil }
        return k
    }

    /// Сколько ячеек снега уходит на один блок (при вокселе 3 и «пикселе» 2 — шесть).
    func blockCost(_ s: Sim) -> Int { max(3, min(12, Int((13.5 * u * u / (s.cell * s.cell)).rounded()))) }

    /// Больше не житель.
    func unhome(_ p: inout Person, _ s: Sim) {
        if let k = iglooIndex(p.home) {
            igloos[k].residents.removeAll { $0 == p.id }
            if igloos[k].residents.isEmpty && igloos[k].abandoned < 0 { igloos[k].abandoned = s.time }
        }
        p.home = -1
        p.partner = -1
        if p.mode == .inside {
            p.mode = .ground
            p.stand = -2
            p.y = ground(s, x: p.x, feet: p.y, up: 20 * u) ?? p.y
        }
    }

    /// Для самотеста: жителям пора уходить.
    func debugHurry(_ s: Sim) { for k in igloos.indices { igloos[k].until = s.time } }

    /// Для самотеста: поставить иглу сразу — площадка готова, уложено laid блоков (nil — все).
    @discardableResult
    func debugPlace(_ s: Sim, x: Float, door: Float, laid: Int? = nil) -> Int {
        var g = Igloo(id: nextObjId, x: x, baseY: 0, born: s.time)
        nextObjId += 1
        g.door = door
        let geo = IglooGeo.of(door)
        g.blocks = (0..<geo.count).map { $0 < (laid ?? geo.count) }
        g.built = laid == nil
        g.c0 = max(0, Int((x - 18 * u) * s.inv))
        g.c1 = min(s.W - 1, Int((x + 18 * u) * s.inv))
        var sum = 0
        for c in g.c0...g.c1 { sum += pile(s, c, s.H) }
        g.floorRow = max(1, min(s.H - 1, s.H - max(1, Int((Float(sum) / Float(g.c1 - g.c0 + 1)).rounded()))))
        g.baseY = Float(g.floorRow) * s.cell
        for c in g.c0...g.c1 {
            for r in 0..<s.H where s.ledge[r * s.W + c] == 0 {
                let i = r * s.W + c
                if r < g.floorRow { if r >= g.floorRow - Int(24 * u * s.inv) { s.snow[i] = 0 } }
                else { if s.snow[i] == 0 { s.snow[i] = rng.shade() }; if r < g.floorRow + 2 { s.hard[i] = People.packedHard } }
            }
        }
        s.gridDirty = true
        s.hardDirty = true
        g.based = true
        g.until = s.time + 100000
        igloos.append(g)
        return igloos.count - 1
    }

    /// Для самотеста: готовое иглу с парой жителей рядом.
    @discardableResult
    func debugHouse(_ s: Sim, x: Float, door: Float) -> Int {
        let k = debugPlace(s, x: x, door: door)
        for (i, girl) in [false, true].enumerated() {
            var p = Person(id: nextId, look: makeLook(kid: false, girl: girl))
            nextId += 1
            p.x = clampX(x + (i == 0 ? -26 : 26) * u, s)
            p.y = ground(s, x: p.x, feet: igloos[k].baseY - 20 * u, up: 0) ?? igloos[k].baseY
            folks.append(p)
            igloos[k].residents.append(p.id)
        }
        for j in folks.indices where igloos[k].residents.contains(folks[j].id) {
            var p = folks[j]
            moveIn(&p, s, k)
            folks[j] = p
        }
        igloos[k].until = s.time + 100000
        return k
    }

    /// Для самотеста: строка о домах.
    var homeSummary: String {
        igloos.map { g in
            String(format: "igloo#%d x=%.0f %d/%d%@%@ cover=%.2f res=%d in=%d base(need %d extra %d row %d)%@%@%@%@%@", g.id, g.x, g.laid, g.blocks.count,
                   g.built ? " built" : "", g.based ? "" : " unbased", g.cover, g.residents.count, g.inside, g.baseNeed, g.baseExtra, g.floorRow,
                   g.stack > 0 ? " stack=\(g.stack)" : "", g.lantern >= 0 ? " lantern" : "",
                   g.flagTo >= 0 ? String(format: " flags=%.2f", g.flagK) : "", g.pathTo >= 0 ? " path" : "",
                   g.abandoned >= 0 ? " abandoned" : "")
        }.joined(separator: "; ") + (fires.isEmpty ? "" : " fires=\(fires.count)\(fires.contains(where: { $0.big }) ? " (common)" : "")")
    }

    /// Вечер: зажигают фонарики, собираются у общего костра. По часам компьютера (с 17 до часа ночи).
    func evening(_ s: Sim) -> Bool {
        if let e = HomeTune.evening { return e }
        if abs(s.time - HomeTune.eveAt) > 60 {
            HomeTune.eveAt = s.time
            let h = Calendar.current.component(.hour, from: Date())
            HomeTune.eve = h >= 17 || h < 1
        }
        return HomeTune.eve
    }

    /// Сосед справа: ближайшее жилое достроенное иглу не дальше 80u.
    func rightOf(_ k: Int) -> Int? {
        guard k >= 0, k < igloos.count else { return nil }
        let g = igloos[k]
        guard g.abandoned < 0, g.built else { return nil }
        var best: Int? = nil
        for j in igloos.indices where j != k && igloos[j].x > g.x && igloos[j].x - g.x < 80 * u
            && igloos[j].abandoned < 0 && igloos[j].built {
            if best == nil || igloos[j].x < igloos[best!].x { best = j }
        }
        return best
    }

    /// Сосед слева: тот, для кого это иглу — сосед справа.
    func leftOf(_ k: Int) -> Int? { igloos.indices.first(where: { $0 != k && rightOf($0) == k }) }

    /// Столбец занят постройкой (под иглу, под костром, тропинка): снег отсюда не берут и ничего здесь не строят.
    func reserved(_ s: Sim, _ c: Int) -> Bool {
        if igloos.isEmpty && fires.isEmpty { return false }
        let x = (Float(c) + 0.5) * s.cell
        for g in igloos {
            if abs(x - g.x) < 19 * u { return true }
            if g.pathTo >= 0 && x > g.x, let r = iglooIndex(g.pathTo), x < igloos[r].x { return true }
        }
        for f in fires where abs(x - f.x) < (f.big ? 7 : 5) * u { return true }
        return false
    }

    // MARK: - Остаться жить

    /// Годится ли место с серединой в x под иглу. Возвращает неровность пола, pt; nil — не годится.
    func siteRough(_ s: Sim, _ x: Float) -> Float? {
        let half = 20 * u
        guard x - half >= 30 * u, x + half <= s.wPt - 30 * u else { return nil }
        let c0 = Int((x - half) * s.inv), c1 = Int((x + half) * s.inv)
        guard c0 >= 1, c1 < s.W - 1, c0 < c1 else { return nil }
        for g in igloos where abs(g.x - x) < 40 * u { return nil }
        for f in fires where abs(f.x - x) < 24 * u { return nil }
        for sg in s.segs where sg.kind == 2 && x + half > sg.x0 - 10 && x - half < sg.x1 + 10 { return nil }
        if inDock(s, c0) || inDock(s, c1) || inDock(s, (c0 + c1) / 2) { return nil }       // полоса Dock, даже когда он спрятан
        for L in ladders where L.base == -2 {
            let cols = stairCols(L, s)
            if cols.upperBound + 4 >= c0 && cols.lowerBound - 4 <= c1 { return nil }
        }
        if let st = site, abs(st.x - x) < half + 12 * u { return nil }
        for b in s.balls where abs(b.x - x) < half + b.r && b.y > s.hPt - 70 * u { return nil }
        var lo = Int.max, hi = 0
        let up = Int(24 * u * s.inv) + 1
        for c in c0...c1 {
            let h = pile(s, c, s.H)
            if isStair(s, c, s.H - max(1, h)) { return nil }               // чьи-то ступеньки
            lo = min(lo, h); hi = max(hi, h)
            let r1 = min(s.H - 1, s.H - h - 1), r0 = max(0, r1 - up)        // над полом свободно: ни карнизов, ни Dock
            if r1 >= r0 { for r in r0...r1 where s.ledge[r * s.W + c] != 0 { return nil } }
        }
        let rough = Float(hi - lo) * s.cell
        return rough <= 7 * u ? rough : nil
    }

    /// Место для нового иглу: рядом с соседними (поселение), иначе неподалёку от x0.
    func homeSite(_ s: Sim, near x0: Float) -> Float? {
        var best: Float? = nil
        var bestScore = Float.infinity
        for k in 0..<18 {
            var x: Float
            if !igloos.isEmpty && k < 12 {
                let g = igloos[Int(rng.next() % UInt64(igloos.count))]
                x = g.x + (rng.f() < 0.5 ? -1 : 1) * rng.range(46, 72) * u      // между домами — место для тропинки и костра
            } else {
                x = x0 + rng.range(-1, 1) * Float(20 + k * 8) * u
            }
            x = (x / u).rounded() * u
            guard let rough = siteRough(s, x) else { continue }
            let score = rough * 3 + abs(x - x0) * 0.05 + (k < 12 ? 0 : 40)
            if score < bestScore { bestScore = score; best = x }
        }
        return best
    }

    /// Поселиться в иглу k: с этого момента p — житель.
    func moveIn(_ p: inout Person, _ s: Sim, _ k: Int) {
        release(&p, s)
        let g = igloos[k]
        p.home = g.id
        p.partner = g.residents.first(where: { $0 != p.id }) ?? -1
        p.stayUntil = g.until
        p.job = .igloo
        p.tries = 0
        p.stage = 0
        next(&p, 0)
    }

    /// Гость решает, не остаться ли жить (найти пару и начать иглу). true — решил.
    func chooseSettle(_ p: inout Person, _ s: Sim) -> Bool {
        // позвали жить вместе — согласиться
        if let k = igloos.firstIndex(where: { $0.abandoned < 0 && $0.residents.contains(p.id) }) {
            moveIn(&p, s, k)
            return true
        }
        guard s.cfg.peopleStay, settleWish, !p.look.kid, p.stand == -2, p.mode == .ground, s.time - visitStart >= 25,
              s.wind.storm < 0.2 else { return false }
        var lived = 0
        for g in igloos where g.abandoned < 0 { lived += 1 }
        guard lived < 4, let mj = findMate(p), settle(&p, s, with: mj) != nil else { return false }
        settleWish = false
        visitEnd = max(visitEnd, s.time + 25)
        return true
    }

    /// p и folks[mj] селятся вместе: занимают брошенное иглу или закладывают новое. nil — негде.
    func settle(_ p: inout Person, _ s: Sim, with mj: Int) -> Int? {
        guard mj >= 0, mj < folks.count else { return nil }
        let k: Int
        if let a = igloos.firstIndex(where: { $0.abandoned >= 0 && $0.cover < 0.9 && $0.laid > 0 }) {
            k = a                               // брошенное иглу можно занять: откопать и починить
            igloos[k].abandoned = -1
            igloos[k].until = s.time + rng.range(480, 1500)
            igloos[k].invited = s.time
            igloos[k].kids = []; igloos[k].grow = []; igloos[k].grown = []
            igloos[k].kidsBorn = 0; igloos[k].adults = 0; igloos[k].since = -1
        } else {
            guard igloos.count < 4, let x = homeSite(s, near: HomeTune.siteX ?? p.x) else { return nil }
            k = found(s, x: x, door: p.x < x ? -1 : 1)
        }
        var m = folks[mj]
        for q in [p, m] where q.home != -1 {    // выросшие дети уходят из родительского дома
            if let j = iglooIndex(q.home) {
                igloos[j].residents.removeAll { $0 == q.id }
                igloos[j].grown.removeAll { $0 == q.id }
            }
        }
        p.home = -1
        m.home = -1
        igloos[k].residents = [p.id, m.id]
        igloos[k].stalled = 0
        moveIn(&m, s, k)
        folks[mj] = m
        moveIn(&p, s, k)
        return k
    }

    // MARK: - Жизнь жителей

    func shovelling(_ g: Igloo, but id: Int32) -> Bool {
        folks.contains(where: { $0.job == .shovel && $0.phase < 10 && $0.home == g.id && $0.id != id && !$0.gone })
    }

    /// Занят ли уже кто-то площадкой этого иглу.
    func baseWorker(_ g: Igloo, but id: Int32) -> Bool {
        folks.contains(where: { $0.job == .igloo && $0.home == g.id && $0.id != id && !$0.gone
            && (($0.phase >= 20 && $0.phase <= 22) || ($0.phase >= 1 && $0.phase <= 3 && $0.stage == 1)) })
    }

    /// Житель выбирает, чем заняться. true — занятие выбрано.
    func chooseHome(_ p: inout Person, _ s: Sim) -> Bool {
        guard let k = homeIndex(p) else { unhome(&p, s); return false }
        let g = igloos[k]
        if s.time >= g.until {                          // пора уходить: дождаться пару у дома
            p.job = .home
            next(&p, 10)
            return true
        }
        if s.wind.storm > 0.4 { p.job = .home; return true }               // буран — домой
        let laid = g.laid, all = g.blocks.count
        let eve = evening(s)
        let big = fires.first(where: { $0.big && s.time < $0.until - 8 })
        if p.look.kid {                                 // дети: играют, греются у общего костра, к вечеру — домой
            if let f = big, s.time < f.gather - 6, abs(p.x - f.x) > 24 * u, rng.f() < 0.5 {
                p.job = .fire; p.obj = f.id; next(&p, 2)
                return true
            }
            if g.built && laid == all && max(g.cover, g.bury) < 0.55 && rng.f() < (eve ? 0.45 : 0.1) { p.job = .home; return true }
            if abs(p.x - g.x) > 160 * u && rng.f() < 0.6 {
                p.job = .wander
                p.goalX = clampX(g.x + rng.range(-40, 40) * u, s)
                return true
            }
            return false
        }
        if g.trappedAt >= 0 { p.job = .shovel; p.obj = g.id; next(&p, 30); return true }   // своих завалило — откапывать
        if g.grown.contains(p.id) && grownChoice(&p, s) { return true }
        // сначала дом: площадка, стены, снег на крыше
        if !g.built { p.job = .igloo; p.stage = 0; return true }
        if (g.cover > 0.12 || g.roof >= g.c1 - g.c0 + 1) && (!shovelling(g, but: p.id) || g.bury > 0.3) { p.job = .shovel; return true }
        if g.baseBad && !baseWorker(g, but: p.id) { p.job = .igloo; p.stage = 0; return true }
        if laid < all && s.time - g.noSnow > 30 { p.job = .igloo; p.stage = 0; return true }
        // остался один: горюет у дома
        if g.adults == 1 && !g.grown.contains(p.id) && s.time < g.griefUntil && rng.f() < 0.55 {
            p.job = .home
            next(&p, 30)
            return true
        }
        // свободное время
        if let f = big, s.time < f.gather - 6, abs(p.x - f.x) > 24 * u, rng.f() < 0.75 {     // у общего костра сбор
            p.job = .fire; p.obj = f.id; next(&p, 2)
            return true
        }
        var village = 0
        for q in igloos where q.abandoned < 0 && q.built { village += 1 }
        let r = rng.f()
        if r < 0.2 {
            if laid == all && g.cover < 0.55 { p.job = .home; return true }
        } else if r < (eve ? 0.46 : 0.32) {
            if village >= 2 {
                if let f = big { p.job = .fire; p.obj = f.id; next(&p, 2); return true }
                if fires.count < 4, rng.f() < (eve ? 0.9 : 0.4) { p.job = .fire; p.obj = -1; p.stage = 1; return true }
            } else {
                let fire = fires.first(where: { abs($0.x - g.x) < 70 * u && s.time < $0.until - 6 })
                if let f = fire { p.job = .fire; p.obj = f.id; next(&p, 2); return true }
                if fires.count < 4 { p.job = .fire; p.obj = -1; p.stage = 0; return true }
            }
        } else if r < (eve ? 0.62 : 0.5) {
            if chore(&p, s, k) { return true }
        } else if g.adults == 1 && r < 0.8 && s.time > g.griefUntil && !g.grown.contains(p.id),
                  let q = folks.filter({ $0.home == -1 && !$0.gone && !$0.look.kid && $0.mode == .ground && $0.stand == -2
                                         && $0.job != .leave && abs($0.x - p.x) < 260 * u })
                               .min(by: { abs($0.x - p.x) < abs($1.x - p.x) }) {
            p.job = .wander                             // одному скучно — поближе к гостям
            p.goalX = clampX(q.x + (p.x < q.x ? -1 : 1) * 10 * u, s)
            return true
        } else if abs(p.x - g.x) > 130 * u && r < 0.9 {  // далеко ушёл — вернуться к дому
            p.job = .wander
            p.goalX = clampX(g.x + rng.range(-34, 34) * u, s)
            return true
        }
        return false
    }

    /// Выросший ребёнок ищет пару, чтобы построить свой дом рядом; домов уже предел — уходит. true — решил.
    func grownChoice(_ p: inout Person, _ s: Sim) -> Bool {
        var lived = 0
        for q in igloos where q.abandoned < 0 { lived += 1 }
        if s.wind.storm < 0.2, let mj = findMate(p) {
            if lived < 4 && settle(&p, s, with: mj) != nil { return true }
            if lived < 4 { return false }               // места пока не нашлось
        } else if rng.f() > 0.03 {
            return false
        }
        unhome(&p, s)                                   // не сложилось: уходит искать счастья в другом месте
        release(&p, s)
        p.job = .leave
        next(&p, 0)
        return true
    }

    /// Благоустройство: фонарик у входа, тропинка к соседям, верёвка с флажками. true — взялся.
    func chore(_ p: inout Person, _ s: Sim, _ k: Int) -> Bool {
        let g = igloos[k]
        if g.lantern < 0 && !folks.contains(where: { $0.job == .fire && $0.phase >= 30 && $0.home == g.id && !$0.gone }) {
            p.job = .fire
            next(&p, 30)
            return true
        }
        // пары «левый — правый», в которых участвует этот дом
        for li in [k, leftOf(k) ?? -1] where li >= 0 {
            guard let ri = rightOf(li) else { continue }
            let L = igloos[li], R = igloos[ri]
            guard L.based, R.based else { continue }
            if let st = pathState(s, li, near: p.x), st.need >= (L.pathTo == R.id ? st.c1 - st.c0 + 1 : 1),
               !folks.contains(where: { $0.job == .shovel && $0.phase >= 10 && $0.obj == L.id && !$0.gone }) {
                p.job = .shovel
                p.obj = L.id
                p.aux = s.time
                next(&p, 10)
                return true
            }
            if (L.flagTo != R.id || L.flagK < 1) && s.wind.storm < 0.1
                && !folks.contains(where: { $0.job == .home && $0.phase >= 20 && $0.obj == L.id && !$0.gone }) {
                if L.flagTo != R.id { igloos[li].flagTo = R.id; igloos[li].flagK = 0 }
                p.job = .home
                p.obj = L.id
                next(&p, 20)
                return true
            }
        }
        return false
    }

    // MARK: - Площадка

    /// Осмотреть площадку: чего не хватает, что лишнее, где ближайшая к x беда.
    func baseScan(_ s: Sim, _ g: Igloo, near x: Float) -> BaseState {
        var st = BaseState()
        guard g.floorRow >= 1, g.floorRow < s.H, g.c0 <= g.c1, g.c0 >= 0, g.c1 < s.W else { return st }
        let pc = Int(x * s.inv)
        var bestD = Int.max
        let lim = max(0, g.floorRow - Int(22 * u * s.inv) - 1)
        for c in g.c0...g.c1 {
            var bad = 0, extra = 0, drop = 0
            var r = g.floorRow - 1
            while r >= lim && s.snow[r * s.W + c] != 0 { extra += 1; r -= 1 }
            var seen = false
            r = g.floorRow
            while r < s.H {
                let i = r * s.W + c
                if s.snow[i] != 0 { seen = true }
                else if s.ledge[i] == 0 { st.need += 1; bad += 1; if !seen { drop += 1 } }
                else { seen = true }
                r += 1
            }
            let top = g.floorRow * s.W + c
            if !g.based && s.snow[top] != 0 && s.hard[top] < People.packedHard - 30 { st.soft += 1; bad += 1 }
            st.extra += extra
            if extra > 0 { bad += 1 } else {
                st.drop += drop
                if drop >= 1 { st.deep.0 += 1 }
                if drop >= 2 { st.deep.1 += 1 }
                if drop >= 3 { st.deep.2 += 1 }
                if drop >= 4 { st.deep.3 += 1 }
            }
            if bad > 0 && abs(c - pc) < bestD { bestD = abs(c - pc); st.col = c; st.colExtra = extra > 0 }
        }
        return st
    }

    /// Выровнять и утоптать площадку в столбцах c-1…c+1: бугры и намёт срезать (снег — в запас у стены,
    /// лишнее — в сторону), ямы и пустоты засыпать (из запаса и из рук), верх утоптать до наста.
    /// false — снега не хватило.
    func tampBase(_ p: inout Person, _ s: Sim, _ k: Int, at c: Int) -> Bool {
        let g = igloos[k]
        guard g.floorRow >= 1, g.floorRow < s.H, g.c0 <= g.c1, g.c0 >= 0, g.c1 < s.W else { return true }
        let a = max(g.c0, c - 1), b = min(g.c1, c + 1)
        guard a <= b else { return true }
        let had = g.stock + p.carry
        var have = had
        var ok = true
        var rTop = s.H
        let lim = max(0, g.floorRow - Int(22 * u * s.inv) - 1)
        for col in a...b {
            var r = g.floorRow - 1
            while r >= lim && s.snow[r * s.W + col] != 0 {      // срезать
                s.snow[r * s.W + col] = 0
                have += 1
                rTop = min(rTop, r)
                r -= 1
            }
            r = s.H - 1
            while r >= g.floorRow {                             // подсыпать
                let i = r * s.W + col
                if s.snow[i] == 0 && s.ledge[i] == 0 {
                    if have > 0 {
                        s.snow[i] = rng.shade()
                        s.hard[i] = People.packedHard
                        have -= 1
                        rTop = min(rTop, r)
                    } else { ok = false }
                }
                r -= 1
            }
            for d in 0..<2 where g.floorRow + d < s.H {         // утоптать
                let i = (g.floorRow + d) * s.W + col
                if s.snow[i] != 0 && s.hard[i] < People.packedHard { s.hard[i] = People.packedHard }
            }
        }
        if have < had {                                         // потратили: сначала то, что в руках
            let used = had - have
            let hands = min(p.carry, used)
            p.carry -= hands
            igloos[k].stock = max(0, g.stock - (used - hands))
        } else {
            let total = g.stock + (have - had)
            igloos[k].stock = min(60, total)
            let out: Float = p.x < g.x ? -1 : 1                 // запас полон — остальное лопатой подальше от дома
            let kv = sqrtf(u / 2)
            for _ in 0..<min(24, max(0, total - 60)) {
                chunk(s, g.x + out * rng.range(21, 24) * u, g.baseY - rng.range(6, 12) * u, out * rng.range(60, 190) * kv, -rng.range(120, 220) * kv)
            }
        }
        s.gridDirty = true
        s.hardDirty = true
        if rTop < s.H { s.snowDisturbed(a - 1, rTop - 1, b + 1, s.H - 1) }
        return ok
    }

    // MARK: - Стройка

    /// Где набрать снега: поближе к иглу и где его побольше; не из-под построек.
    func snowSpot(_ s: Sim, _ g: Igloo, from x: Float) -> Float? {
        var best: Float? = nil
        var bestScore = -Float.infinity
        let mine: Float = x < g.x ? -1 : 1
        let need = s.cell >= 5 ? 1 : 2
        for k in 0..<16 {
            let d = rng.range(26, 200) * u
            let gx = g.x + (k < 10 ? mine : -mine) * d
            if gx < 12 || gx > s.wPt - 12 { continue }
            let c = Int(gx * s.inv)
            guard c >= 0, c < s.W else { continue }
            let h = pile(s, c, s.H)
            if h < need || isStair(s, c, s.H - h) || reserved(s, c) { continue }
            let score = Float(min(h, 8)) * 12 - abs(gx - x) * 0.1 - d * 0.07
            if score > bestScore { bestScore = score; best = gx }
        }
        return best
    }

    /// Блок b встаёт в стену. На экране он ещё доезжает из рук на место (см. emitIgloo): откуда — в aux/aux2.
    func lay(_ p: inout Person, _ s: Sim, _ k: Int, _ b: Int) {
        let g = igloos[k]
        let geo = IglooGeo.of(g.door)
        guard b >= 0, b < geo.count, b < g.blocks.count else { return }
        igloos[k].blocks[b] = true
        igloos[k].stalled = 0
        if igloos[k].blocks.firstIndex(of: false) == nil { igloos[k].doneAt = s.time }
        p.carry = 0
        p.obj = b
        p.aux = (p.x + p.face * 3 * u - (g.x + geo.cx[b] * u)) / u
        p.aux2 = ((g.baseY - geo.cy[b] * u) - (p.y - 16 * u)) / u
    }

    /// Где лежит штабель готовых блоков.
    func stackX(_ g: Igloo, _ s: Sim) -> Float { clampX(g.x - g.door * 25 * u, s) }

    /// Строит (и чинит) иглу. Фазы: 0 — решить; 1–3 — набрать снега; 4–5 — утоптать и вырезать блок, поднять;
    /// 6 — нести к стене; 7 — уложить; 8–9 — в штабель и из штабеля; 10 — приступка; 11 — верхний ряд с приступки;
    /// 20–22 — площадка; 30 — постоять над развалинами.
    func runIgloo(_ p: inout Person, _ s: Sim, _ dt: Float) {
        guard let k = homeIndex(p) else { release(&p, s); unhome(&p, s); idle(&p, 0.5); return }
        if s.wind.storm > 0.4 && p.phase != 11 && p.mode == .ground {      // буран — всё бросить и домой
            release(&p, s)
            p.job = .home
            next(&p, 0)
            return
        }
        let g = igloos[k]
        let geo = IglooGeo.of(g.door)
        let cost = blockCost(s)
        let nb = g.blocks.firstIndex(of: false)
        switch p.phase {
        case 0:
            settle(&p, s, dt)
            if p.mode != .ground { return }
            if g.cover > 0.3 && !shovelling(g, but: p.id) {     // стройку заносит — сначала откопать
                release(&p, s)
                p.job = .shovel
                p.tries = 0
                next(&p, 0)
                return
            }
            if s.time - g.ruinedAt < 90 && !g.mourned.contains(p.id) {      // дом рухнул: постоять, опустив голову
                igloos[k].mourned.append(p.id)
                release(&p, s)
                next(&p, 30)
                return
            }
            if g.baseBad && (!g.based || !baseWorker(g, but: p.id)) && p.carry < cost {
                p.tries = 0
                next(&p, 20)
                return
            }
            guard let b = nb, b < geo.count else {              // стена цела
                if !g.built { igloos[k].built = true }
                if g.stool {                                    // приступка больше не нужна
                    igloos[k].stool = false
                    for _ in 0..<4 { dust(s, g.x + rng.range(-6, 6) * u, g.baseY - rng.range(0, 5) * u) }
                }
                if p.carry >= cost && g.stack < 3 { next(&p, 8); return }       // лишний блок — в штабель
                igloos[k].stock = min(90, g.stock + p.carry)
                p.carry = 0
                if s.time - g.doneAt < 4 { p.job = .cheer; p.wait = 1.8; next(&p, 0) } else { idle(&p, 0.5) }
                return
            }
            if p.carry >= cost { next(&p, 6); return }
            if geo.row[b] == 4 && !g.stool && !folks.contains(where: { $0.job == .igloo && $0.phase == 10 && $0.home == g.id && !$0.gone }) {
                next(&p, 10)
                return
            }
            var takers = 0
            for q in folks where q.job == .igloo && q.phase == 9 && q.home == g.id && !q.gone { takers += 1 }
            if g.stack > takers { next(&p, 9); return }
            p.stage = 0
            if let gx = snowSpot(s, g, from: p.x) {
                p.goalX = gx
                p.tries = 0
                next(&p, 1)
            } else if p.t > 2 {
                p.t = 0
                p.tries += 1
                if p.tries > 3 {                                // снега рядом нет: попозже
                    release(&p, s)
                    if g.built { igloos[k].noSnow = s.time }
                    idle(&p, 3)
                }
            }
        case 1:
            if walk(&p, s, to: p.goalX, speed: 30 * u, dt) || p.t > 25 || p.blockT > 0.3 { p.blockT = 0; next(&p, 2) }
        case 2, 3:  // два гребка
            p.anim = .scoop
            settle(&p, s, dt)
            if p.t > 0.25 && !p.flag {
                p.flag = true
                let want = p.stage == 1 ? cost + 2 : max(1, cost + 1 - p.carry)
                p.carry += scoop(s, x: p.x + p.face * 2 * u, stand: -2, want: want, half: p.phase == 2 ? 4 : 7)
            }
            if p.t > 0.45 {
                if p.phase == 2 { next(&p, 3) }
                else if p.stage == 1 { next(&p, p.carry > 0 ? 20 : 0) }
                else if p.carry >= cost {
                    p.aux = clampX(p.x + p.face * 7 * u, s)     // здесь будет брусок
                    p.aux2 = 0
                    next(&p, 4)
                } else { next(&p, 0) }                          // мало — добрать в другом месте
            }
        case 4:     // утоптать снег в брусок и вырезать блок
            settle(&p, s, dt)
            if p.mode != .ground { return }
            p.face = p.aux >= p.x ? 1 : -1
            p.anim = p.t < 1.2 ? .pat : .scoop
            p.aux2 = min(1, p.t / 1.8)
            if p.t > 1.8 {
                igloos[k].stock = min(90, g.stock + p.carry - cost)
                p.carry = cost
                next(&p, 5)
            }
        case 5:     // поднять
            settle(&p, s, dt)
            p.anim = p.t < 0.2 ? .scoop : .hold
            if p.t > 0.45 { next(&p, 6) }
        case 6:     // нести к стене
            guard p.carry >= cost else { next(&p, 0); return }                  // уронил
            guard let b = nb, b < geo.count else { next(&p, 0); return }        // стену уже закончили
            let top = geo.row[b] == 4
            if top && !g.stool {
                if folks.contains(where: { $0.job == .igloo && $0.phase == 10 && $0.home == g.id && $0.id != p.id && !$0.gone }) {
                    // приступку уже делают — подождать рядом с блоком в руках
                    _ = walk(&p, s, to: clampX(g.x + (p.x < g.x ? -1 : 1) * 13 * u, s), speed: 20 * u, dt)
                    p.anim = .hold
                    if p.t > 20 { next(&p, 8) }
                } else {
                    p.tries = 77                                // блок — в штабель, самому — делать приступку
                    next(&p, 8)
                }
                return
            }
            let tx = top ? g.x + max(-4, min(4, geo.cx[b])) * u
                         : clampX(g.x + (max(-14, min(14, geo.cx[b])) + (p.id & 1 == 0 ? -3 : 3)) * u, s)
            let wx = top ? clampX(g.x + (p.x < g.x ? -1 : 1) * 9 * u, s) : tx
            let arrived = walk(&p, s, to: wx, speed: 20 * u, dt)
            if !arrived { p.anim = .hold }
            if arrived || p.t > 25 {
                if abs(p.x - wx) > 8 * u { release(&p, s); next(&p, 0); return }     // не дошёл
                if top {
                    p.obj = b
                    p.hop0 = SIMD2(p.x, p.y)
                    p.hop1 = SIMD2(tx, g.baseY - 5 * u)
                    next(&p, 11)
                } else {
                    p.face = g.x + geo.cx[b] * u >= p.x ? 1 : -1
                    lay(&p, s, k, b)
                    next(&p, 7)
                }
            }
        case 7:     // уложить: нижние ряды — нагнувшись, верхние — дотягиваясь
            settle(&p, s, dt)
            if p.mode != .ground { return }
            if p.obj >= 0 && p.obj < geo.count {
                if geo.row[p.obj] >= 2 { p.anim = .handUp } else {
                    p.anim = .pat
                    p.face = g.x + geo.cx[p.obj] * u >= p.x ? 1 : -1
                }
            }
            if p.t > 1.2 { next(&p, 0) }
        case 8:     // положить блок в штабель
            let sx = stackX(g, s) + g.door * 5 * u
            if !p.flag {
                let arrived = walk(&p, s, to: sx, speed: 20 * u, dt)
                if !arrived { p.anim = .hold }
                if arrived || p.t > 20 || p.blockT > 0.3 { p.blockT = 0; p.flag = true; p.t = 0 }
            } else {
                settle(&p, s, dt)
                p.anim = .pat
                p.face = -g.door
                if p.t > 0.6 {
                    if p.carry >= cost && g.stack < 3 && abs(p.x - sx) < 8 * u { igloos[k].stack += 1; p.carry = 0 } else { release(&p, s) }
                    let stool = p.tries == 77
                    p.tries = 0
                    next(&p, stool ? 10 : 0)
                }
            }
        case 9:     // взять блок из штабеля
            let sx = stackX(g, s) + g.door * 5 * u
            if !p.flag {
                if walk(&p, s, to: sx, speed: 26 * u, dt) || p.t > 20 || p.blockT > 0.3 { p.blockT = 0; p.flag = true; p.t = 0 }
            } else {
                settle(&p, s, dt)
                p.anim = .scoop
                p.face = -g.door
                if p.t > 0.5 {
                    if igloos[k].stack > 0 && abs(p.x - sx) < 8 * u {
                        igloos[k].stack -= 1
                        p.carry = cost
                        next(&p, 6)
                    } else { next(&p, 0) }
                }
            }
        case 10:    // утоптать приступку у стены
            if g.stool { next(&p, 0); return }
            if !p.flag {
                if walk(&p, s, to: clampX(g.x + (p.x < g.x ? -1 : 1) * 5 * u, s), speed: 22 * u, dt) || p.t > 20 || p.blockT > 0.3 {
                    p.blockT = 0; p.flag = true; p.t = 0
                }
            } else {
                settle(&p, s, dt)
                p.anim = .pat
                p.face = g.x >= p.x ? 1 : -1
                if p.t > 1.6 {
                    igloos[k].stool = true
                    igloos[k].stalled = 0
                    dust(s, g.x, g.baseY - 4 * u)
                    next(&p, 0)
                }
            }
        case 11:    // верхний ряд: встать на приступку и дотянуться
            if !g.stool { next(&p, 0); return }
            if !p.flag {
                if hop(&p, dur: 0.4) {
                    p.flag = true
                    p.t = 0
                    var b = p.obj
                    if b < 0 || b >= geo.count || g.blocks[b] { b = nb ?? -1 }
                    if b >= 0 && b < geo.count && geo.row[b] == 4 && p.carry >= cost { lay(&p, s, k, b) } else { p.obj = -1 }
                }
            } else {
                p.y = g.baseY - 5 * u
                p.anim = .handUp
                if p.t > 1.2 || p.obj < 0 { next(&p, 0) }       // спрыгнет сам
            }
        case 20:    // площадка: к месту, где что-то не так
            let st = baseScan(s, g, near: p.x)
            // снег вокруг живой (осыпается с краёв, сдувается) — до последней ячейки не вылизывают
            let slack = max(2, (g.c1 - g.c0 + 1) / 5)
            if st.col < 0 || (st.need <= 1 && st.extra <= slack && (g.based || st.soft <= slack)) {
                if !g.based { igloos[k].based = true }
                igloos[k].stalled = 0
                igloos[k].baseT = 9
                igloos[k].stock = min(90, igloos[k].stock + p.carry)
                p.carry = 0
                next(&p, 0)
                return
            }
            p.tries += 1
            if p.tries > 2000 { igloos[k].baseT = 9; release(&p, s); idle(&p, 2); return }
            let tx = (Float(st.col) + 0.5) * s.cell
            if abs(tx - p.x) < 3 * u || walk(&p, s, to: tx, speed: 20 * u, dt) || p.t > 8 || p.blockT > 0.3 {
                p.blockT = 0
                p.aux = Float(st.col)
                p.aux2 = st.colExtra ? 1 : 0
                next(&p, 21)
            }
        case 21:    // срезать, подсыпать, утоптать
            settle(&p, s, dt)
            if p.mode != .ground { return }
            p.anim = p.aux2 > 0 ? .shovel : .pat                // намёт — лопатой, яму — подсыпать и утоптать
            if p.t > 0.34 {
                let ok = tampBase(&p, s, k, at: Int(p.aux))
                igloos[k].stalled = 0
                p.tries += 30
                if !ok && p.carry == 0 && igloos[k].stock == 0 { next(&p, 22) } else { next(&p, 20) }
            }
        case 22:    // за снегом на подсыпку
            settle(&p, s, dt)
            p.stage = 1
            if let gx = snowSpot(s, g, from: p.x) {
                p.goalX = gx
                next(&p, 1)
            } else if p.t > 2 {
                p.t = 0
                p.tries += 500
                if p.tries > 2000 { if g.built { igloos[k].noSnow = s.time }; idle(&p, 3) }
            }
        case 30:    // над развалинами
            if !p.flag {
                if walk(&p, s, to: clampX(g.x + (p.x < g.x ? -1 : 1) * 23 * u, s), speed: 16 * u, dt) || p.t > 8 || p.blockT > 0.3 {
                    p.blockT = 0; p.flag = true; p.t = 0
                }
            } else {
                settle(&p, s, dt)
                p.face = g.x >= p.x ? 1 : -1
                p.anim = .mourn
                if p.t > 2.6 { next(&p, 0) }
            }
        default:
            next(&p, 0)
        }
    }

    // MARK: - Дом, уход, флажки

    /// В дом и из дома (фазы 0–2); сборы в дорогу (10–11); верёвка с флажками к соседям (20–23).
    func runHome(_ p: inout Person, _ s: Sim, _ dt: Float) {
        guard let k = homeIndex(p) else {                   // дома больше нет
            let was = p.mode == .inside
            unhome(&p, s)
            if was { p.flinch = 0.6 }
            idle(&p, was ? 0.8 : 0.4)
            return
        }
        let g = igloos[k]
        let geo = IglooGeo.of(g.door)
        let doorX = g.x + geo.doorX * u
        let storm = s.wind.storm > 0.4
        switch p.phase {
        case 0:     // к входу
            if p.mode != .ground { return }
            let fit = g.built && max(g.cover, g.bury) < 0.6 && g.laid * 10 >= g.blocks.count * (storm ? 7 : 10)
            if storm && !fit { p.job = .shelter; next(&p, 0); return }     // дом не укроет — пережидать с остальными
            if walk(&p, s, to: doorX, speed: (storm ? 34 : 20) * u, dt) || p.t > 25 || p.blockT > 0.4 {
                p.blockT = 0
                if p.mode != .ground { return }
                if abs(p.x - doorX) < 5 * u && fit { next(&p, 1) }
                else if storm { p.job = .shelter; next(&p, 0) }
                else { idle(&p, 0.5) }
            }
        case 1:     // пригнуться и войти
            p.anim = .getup
            settle(&p, s, dt)
            if p.mode != .ground { return }
            if p.t > 0.35 {
                release(&p, s)
                p.mode = .inside
                p.x = doorX
                p.y = g.baseY
                p.wait = rng.range(15, 50) * (evening(s) ? 2 : 1)
                next(&p, 2)
            }
        case 2:     // сидит дома; в буран — пока не стихнет
            p.x = doorX
            p.y = g.baseY
            if p.mode != .inside { idle(&p, 0.4); return }
            // в буран — пока не стихнет; вход завалило — пока не откопают
            let calm = s.wind.storm < 0.15, stuck = blocked(g)
            let freed = !stuck && s.time - g.freedAt < 2.5
            let want = p.t > p.wait || s.time >= g.until || g.cover > 0.5 || g.laid < g.blocks.count || (g.baseBad && !p.look.kid)
            if g.laid * 10 < g.blocks.count * 7 || freed || (calm && !stuck && want) {
                p.mode = .ground
                p.stand = -2
                p.y = g.baseY
                p.face = g.door
                p.anim = .getup
                if freed { p.job = .cheer; p.wait = 2; next(&p, 0) } else { idle(&p, 0.4) }
            }
        case 10:    // собрались уходить: встать у дома
            if !p.flag {
                p.flag = true
                p.goalX = clampX(g.x + (g.x < s.wPt * 0.5 ? -1 : 1) * rng.range(21, 27) * u, s)
            }
            if walk(&p, s, to: p.goalX, speed: 22 * u, dt) || p.t > 20 || p.blockT > 0.4 { p.blockT = 0; next(&p, 11) }
        case 11:    // ждёт пару; дождался (или её уже нет) — уходят в одну сторону
            settle(&p, s, dt)
            if p.mode != .ground { return }
            p.face = g.x >= p.x ? 1 : -1
            // вся семья в сборе (или ждать уже некого)
            let waiting = folks.contains(where: { $0.id != p.id && !$0.gone && $0.home == g.id && g.residents.contains($0.id)
                && !($0.job == .home && $0.phase == 11) })
            if !waiting || p.t > 25 {
                unhome(&p, s)
                release(&p, s)
                p.job = .leave
                next(&p, 0)
                p.flag = true
                p.goalX = g.x < s.wPt * 0.5 ? -50 : s.wPt + 50
            } else if p.t > 1.5 {
                p.anim = .gaze                              // прощальный взгляд на дом
            }
        case 20, 21, 22, 23:    // верёвка с флажками от левого дома (obj) к правому
            guard !storm, let li = iglooIndex(p.obj), let ri = rightOf(li), igloos[li].flagTo == igloos[ri].id else { idle(&p, 0.4); return }
            let L = igloos[li], R = igloos[ri]
            let ax = L.x + 12 * u, bx = R.x - 12 * u
            guard bx - ax > 6 * u else { igloos[li].flagTo = -1; idle(&p, 0.4); return }
            switch p.phase {
            case 20:    // к тому месту, где верёвка кончается
                if walk(&p, s, to: ax + (bx - ax) * L.flagK - 2 * u, speed: 22 * u, dt) || p.t > 20 || p.blockT > 0.4 { p.blockT = 0; next(&p, 21) }
            case 21:    // привязать
                settle(&p, s, dt)
                p.anim = .handUp
                if p.t > 1.2 {
                    igloos[li].flagK = max(L.flagK, 0.04)
                    next(&p, 22)
                }
            case 22:    // тянуть к соседнему дому
                let arrived = walk(&p, s, to: bx - 2 * u, speed: 13 * u, dt)
                if p.mode != .ground { return }
                if !arrived { p.anim = .hold }
                igloos[li].flagK = max(igloos[li].flagK, min(0.97, (p.x + 2 * u - ax) / (bx - ax)))
                if arrived || p.t > 30 || p.blockT > 0.4 { p.blockT = 0; next(&p, arrived ? 23 : 0); if !arrived { idle(&p, 0.5) } }
            default:    // привязать второй конец
                settle(&p, s, dt)
                p.anim = .handUp
                if p.t > 1.2 {
                    igloos[li].flagK = 1
                    p.job = .cheer
                    p.wait = 1.4
                    next(&p, 0)
                }
            }
        case 30:    // остался один: стоит у дома, опустив голову
            if !p.flag {
                if walk(&p, s, to: clampX(doorX + g.door * 9 * u, s), speed: 14 * u, dt) || p.t > 15 || p.blockT > 0.4 {
                    p.blockT = 0; p.flag = true; p.t = 0
                    p.wait = rng.range(4, 8)
                }
            } else {
                settle(&p, s, dt)
                if p.mode != .ground { return }
                p.face = -g.door
                p.anim = .mourn
                if p.t > p.wait { idle(&p, rng.range(1, 3)) }
            }
        case 40:    // знакомство: сошлись, радуются — и вместе в дом
            guard let mate = folks.first(where: { Int($0.id) == p.obj && !$0.gone && $0.home == g.id }) else { idle(&p, 0.4); return }
            if !p.flag {
                let gx = clampX(mate.x + (p.x < mate.x ? -1 : 1) * 7 * u, s)
                if abs(p.x - mate.x) < 9 * u || walk(&p, s, to: gx, speed: 18 * u, dt) || p.t > 12 || p.blockT > 0.4 {
                    p.blockT = 0; p.flag = true; p.t = 0
                }
            } else {
                settle(&p, s, dt)
                if p.mode != .ground { return }
                p.face = mate.x >= p.x ? 1 : -1
                p.anim = .cheer
                if p.t > 2.4 { next(&p, 0) }
            }
        default:
            idle(&p, 0.4)
        }
    }

    // MARK: - Лопата: снег с крыши, тропинка

    /// Тропинка от иглу li к его соседу справа: столбцы, строка дна, сколько ячеек снега выше дна
    /// и ближайший к x столбец, где они есть. nil — тропинки нет (нет соседа, дома вплотную).
    func pathState(_ s: Sim, _ li: Int, near x: Float) -> (c0: Int, c1: Int, row: Int, need: Int, col: Int)? {
        guard let ri = rightOf(li) else { return nil }
        let L = igloos[li], R = igloos[ri]
        let a = L.c1 + 1, b = R.c0 - 1
        guard L.floorRow >= 1, R.floorRow >= 1, a <= b, a >= 0, b < s.W, !inDock(s, a), !inDock(s, b), !inDock(s, (a + b) / 2) else { return nil }
        let row = min(s.H - 1, max(L.floorRow, R.floorRow) + (s.cell <= 3 ? 2 : 1))
        let pc = Int(x * s.inv)
        var need = 0, col = -1, bestD = Int.max
        for c in a...b {
            var r = row - 1, n = 0
            while r >= 0 && n < 60 && s.snow[r * s.W + c] != 0 { n += 1; r -= 1 }
            if n > 0 {
                need += n
                if abs(c - pc) < bestD { bestD = abs(c - pc); col = c }
            }
        }
        return (a, b, row, need, col)
    }

    /// Откапывают заваленный вход иглу p.obj (фазы 30–31): жители — лопатой, гости — руками. Снег летит в стороны.
    func digOut(_ p: inout Person, _ s: Sim, _ dt: Float) {
        guard let k = iglooIndex(p.obj) else { idle(&p, 0.4); return }
        let g = igloos[k]
        let doorX = g.x + IglooGeo.of(g.door).doorX * u
        if p.phase == 30 {
            if g.trappedAt < 0 { idle(&p, 0.4); return }
            if !p.flag { p.flag = true; p.goalX = clampX(doorX + rng.range(-9, 9) * u, s) }
            if walk(&p, s, to: p.goalX, speed: 36 * u, dt) || p.t > 20 || p.blockT > 0.4 { p.blockT = 0; p.acc = 0; next(&p, 31) }
            return
        }
        settle(&p, s, dt)
        if p.mode != .ground { return }
        if g.trappedAt < 0 {                                // откопали (или уже некого)
            if s.time - g.freedAt < 3 { p.job = .cheer; p.wait = 2; next(&p, 0) } else { idle(&p, 0.5) }
            return
        }
        p.anim = p.home != -1 ? .shovel : .dig
        p.face = abs(doorX - p.x) > 2 * u ? (doorX >= p.x ? 1 : -1) : g.door
        p.acc += dt
        if p.acc > 0.22 {
            p.acc = 0
            igloos[k].cover = max(0, g.cover - 0.012)
            let n = takeRoof(s, g, near: doorX, n: 2)
            let side: Float = p.x < g.x ? -1 : 1
            let kv = sqrtf(u / 2)
            for _ in 0..<max(1, n) {
                chunk(s, g.x + side * rng.range(21, 24) * u, g.baseY - rng.range(8, 16) * u, side * rng.range(70, 190) * kv, -rng.range(100, 190) * kv)
            }
        }
        if p.t > 300 { idle(&p, 1) }
    }

    /// Счищает снег с дома (фазы 0–1), расчищает тропинку к соседям (10–11), откапывает заваленный вход (30–31).
    func runShovel(_ p: inout Person, _ s: Sim, _ dt: Float) {
        if p.phase >= 30 { digOut(&p, s, dt); return }      // откапывать могут и не жители
        guard let k = homeIndex(p) else { unhome(&p, s); idle(&p, 0.4); return }
        if s.wind.storm > 0.4 && p.mode == .ground { p.job = .home; next(&p, 0); return }
        let g = igloos[k]
        switch p.phase {
        case 0:
            if !p.flag {
                p.flag = true
                p.acc = 0
                let side: Float = p.tries % 2 == 0 ? (p.x < g.x ? -1 : 1) : (p.x < g.x ? 1 : -1)
                p.goalX = clampX(g.x + side * rng.range(15, 21) * u, s)
            }
            if walk(&p, s, to: p.goalX, speed: 24 * u, dt) || p.t > 20 || p.blockT > 0.4 { p.blockT = 0; next(&p, 1) }
        case 1:
            settle(&p, s, dt)
            if p.mode != .ground { return }
            p.anim = .shovel
            p.face = g.x >= p.x ? 1 : -1
            igloos[k].cover = max(0, g.cover - dt * (0.028 + g.cover * 0.06))
            p.acc += dt
            if p.acc > 0.28 {                               // снег с лопаты летит в сторону от дома
                p.acc = 0
                let side: Float = p.x < g.x ? -1 : 1
                let kv = sqrtf(u / 2)
                let n = takeRoof(s, g, near: p.x, n: 2)     // настоящий снег с купола — тоже
                if n > 0 { igloos[k].roof = max(0, g.roof - n) }
                if n > 0 || g.cover > 0.004 {
                    for _ in 0..<max(1, n) {
                        chunk(s, g.x + side * rng.range(21, 24) * u, g.baseY - rng.range(10, 16) * u, side * rng.range(60, 170) * kv, -rng.range(90, 170) * kv)
                    }
                }
            }
            if igloos[k].cover <= 0.004 && igloos[k].roof < 3 {
                igloos[k].cover = 0
                idle(&p, rng.range(0.3, 1))
            } else if p.t > 3.2 {                           // перейти на другую сторону
                p.tries += 1
                if p.tries > 16 { idle(&p, 0.5) } else { next(&p, 0) }
            }
        case 10:    // тропинка: к ближайшему месту, где намело
            guard let li = iglooIndex(p.obj), let st = pathState(s, li, near: p.x), st.col >= 0, s.time - p.aux < 40 else {
                idle(&p, rng.range(0.3, 1))
                return
            }
            if igloos[li].pathTo < 0, let ri = rightOf(li) { igloos[li].pathTo = igloos[ri].id }
            let tx = (Float(st.col) + 0.5) * s.cell
            if abs(tx - p.x) < 3 * u || walk(&p, s, to: tx, speed: 20 * u, dt) || p.t > 10 || p.blockT > 0.4 {
                p.blockT = 0
                p.acc = 0
                next(&p, 11)
            }
        case 11:    // расчистить и утоптать
            settle(&p, s, dt)
            if p.mode != .ground { return }
            p.anim = .shovel
            p.acc += dt
            guard p.acc > 0.24 else { return }
            p.acc = 0
            guard let li = iglooIndex(p.obj), let st = pathState(s, li, near: p.x), st.col >= 0 else { idle(&p, rng.range(0.3, 1)); return }
            if abs((Float(st.col) + 0.5) * s.cell - p.x) > 5 * u { next(&p, 10); return }
            let c = st.col
            var r = st.row - 1, n = 0
            var rTop = st.row
            while r >= 0 && n < 60 && s.snow[r * s.W + c] != 0 {            // большую часть утаптывает, остальное — лопатой в сторону
                s.snow[r * s.W + c] = 0
                rTop = r
                if n % 3 == 2 {
                    let out: Float = p.x < s.wPt * 0.5 ? -1 : 1
                    chunk(s, p.x, p.y - 12 * u, out * rng.range(120, 240) * sqrtf(u / 2), -rng.range(180, 260) * sqrtf(u / 2))
                }
                n += 1
                r -= 1
            }
            for d in 0..<2 where st.row + d < s.H {
                let i = (st.row + d) * s.W + c
                if s.snow[i] != 0 && s.hard[i] < People.packedHard { s.hard[i] = People.packedHard }
            }
            p.face = -p.face
            s.gridDirty = true
            s.hardDirty = true
            s.snowDisturbed(c - 1, rTop - 1, c + 1, st.row)
        default:
            idle(&p, 0.4)
        }
    }

    // MARK: - Костры и фонарики

    /// Место для костра у своего дома: сбоку, лучше со стороны входа.
    func fireSpot(_ s: Sim, _ g: Igloo) -> Float? {
        for k in 0..<6 {
            let side: Float = k % 2 == 0 ? g.door : -g.door
            let x = ((g.x + side * rng.range(27, 34) * u) / u).rounded() * u
            if fireOK(s, x) { return x }
        }
        return nil
    }

    func fireOK(_ s: Sim, _ x: Float) -> Bool {
        guard x > 22 * u, x < s.wPt - 22 * u else { return false }
        if igloos.contains(where: { abs($0.x - x) < 23 * u }) || fires.contains(where: { abs($0.x - x) < 20 * u }) { return false }
        if s.segs.contains(where: { $0.kind == 2 && x > $0.x0 - 12 && x < $0.x1 + 12 }) { return false }
        let c = Int(x * s.inv)
        guard c >= 1, c < s.W - 1, !inDock(s, c) else { return false }
        return !isStair(s, c, s.H - max(1, pile(s, c, s.H)))
    }

    /// Место для общего костра: посередине между двумя соседними домами, а если тесно — с краю поселения.
    func commonSpot(_ s: Sim) -> Float? {
        for li in igloos.indices {
            guard let ri = rightOf(li) else { continue }
            let x = (((igloos[li].x + igloos[ri].x) * 0.5) / u).rounded() * u
            if fireOK(s, x) { return x }
        }
        var lo = Float.infinity, hi = -Float.infinity
        for g in igloos where g.abandoned < 0 && g.built { lo = min(lo, g.x); hi = max(hi, g.x) }
        guard lo <= hi else { return nil }
        for x in [hi + 32 * u, lo - 32 * u] where fireOK(s, (x / u).rounded() * u) { return (x / u).rounded() * u }
        return nil
    }

    /// Развести костёр (фазы 0, 1, 5; stage 1 — общий), греться (2, 3), поставить фонарик у входа (30, 31).
    func runFire(_ p: inout Person, _ s: Sim, _ dt: Float) {
        guard let k = homeIndex(p) else { unhome(&p, s); idle(&p, 0.4); return }
        if s.wind.storm > 0.4 && p.mode == .ground { p.job = .home; next(&p, 0); return }
        let g = igloos[k]
        switch p.phase {
        case 0:
            guard let fx = p.stage == 1 ? commonSpot(s) : fireSpot(s, g) else { idle(&p, 0.5); return }
            p.aux = fx
            p.goalX = clampX(fx + (p.x < fx ? -1 : 1) * 7 * u, s)
            next(&p, 1)
        case 1:
            if walk(&p, s, to: p.goalX, speed: 22 * u, dt) || p.t > 25 || p.blockT > 0.4 {
                p.blockT = 0
                if abs(p.x - p.goalX) > 4 * u { idle(&p, 0.5) } else { next(&p, 5) }
            }
        case 5:     // складывает поленья, разжигает
            settle(&p, s, dt)
            if p.mode != .ground { return }
            p.face = p.aux >= p.x ? 1 : -1
            p.anim = .pat
            if p.t > 2.2 {
                if let f = fires.first(where: { abs($0.x - p.aux) < 20 * u && s.time < $0.until }) {
                    p.obj = f.id                            // пока возился, костёр уже развели
                } else if fires.count < 4 {
                    var f = Fire(id: nextObjId, x: p.aux, y: ground(s, x: p.aux, feet: p.y, up: 8 * u) ?? p.y, born: s.time,
                                 until: s.time + rng.range(90, 150))
                    if p.stage == 1 {                       // общий: горит дольше, к нему сходятся
                        f.big = true
                        f.gather = s.time + rng.range(70, 120)
                        f.until = f.gather + rng.range(20, 40)
                    }
                    fires.append(f)
                    p.obj = nextObjId
                    nextObjId += 1
                } else {
                    idle(&p, 0.5)
                    return
                }
                p.wait = rng.range(8, 18)
                next(&p, 3)
            }
        case 2:     // подойти к костру
            guard let f = fires.first(where: { $0.id == p.obj }), s.time < f.until else { idle(&p, 0.4); return }
            if !p.flag {
                p.flag = true
                var l = 0, r = 0
                for q in folks where q.id != p.id && q.job == .fire && q.obj == f.id && q.phase <= 3 && !q.gone { if q.x < f.x { l += 1 } else { r += 1 } }
                let side: Float = l == r ? (p.x < f.x ? -1 : 1) : (l < r ? -1 : 1)
                let n = Float(side < 0 ? l : r)
                p.goalX = clampX(f.x + side * ((f.big ? 10 : 8) + n * 6 + rng.range(-0.5, 0.5)) * u, s)
                p.wait = f.big ? max(10, f.gather - s.time + rng.range(-8, 6)) : rng.range(8, 20)
            }
            if walk(&p, s, to: p.goalX, speed: 20 * u, dt) || p.t > 25 || p.blockT > 0.4 { p.blockT = 0; next(&p, 3) }
        case 3:     // греет руки
            guard let f = fires.first(where: { $0.id == p.obj }), s.time < f.until, abs(f.x - p.x) < 34 * u else { idle(&p, 0.4); return }
            settle(&p, s, dt)
            if p.mode != .ground { return }
            p.face = f.x >= p.x ? 1 : -1
            p.anim = abs(f.x - p.x) < 13 * u ? .warm : (Int(s.time * 0.25 + Float(p.id)) % 3 == 0 ? .gaze : .stand)
            if p.t > p.wait || s.time >= g.until { idle(&p, rng.range(0.3, 1)) }
        case 30:    // фонарик: к месту у входа
            let lx = g.x + (IglooGeo.of(g.door).doorX + g.door * 7) * u
            if walk(&p, s, to: clampX(lx - g.door * 5 * u, s), speed: 20 * u, dt) || p.t > 20 || p.blockT > 0.4 {
                p.blockT = 0
                if g.lantern >= 0 || !g.built { idle(&p, 0.4) } else { next(&p, 31) }
            }
        case 31:    // вылепить ледяной кубик, поставить в него огонёк
            settle(&p, s, dt)
            if p.mode != .ground { return }
            p.face = g.door
            p.anim = .pat
            if p.t > 2.4 {
                if igloos[k].lantern < 0 { igloos[k].lantern = s.time }
                idle(&p, rng.range(0.4, 1.2))
            }
        default:
            idle(&p, 0.4)
        }
    }

    // MARK: - Раз в кадр

    /// Блок b вылетает из стены комьями.
    func shedBlock(_ g: Igloo, _ s: Sim, _ b: Int, vx: Float, vy: Float, n: Int) {
        let geo = IglooGeo.of(g.door)
        guard b >= 0, b < geo.count else { return }
        let x = g.x + geo.cx[b] * u, y = g.baseY - geo.cy[b] * u
        for _ in 0..<n {
            chunk(s, x + rng.range(-2.5, 2.5) * u, y + rng.range(-1.5, 1.5) * u,
                  vx * rng.range(0.15, 0.5) + rng.range(-45, 45), vy * 0.3 - rng.range(0, 110), hard: 60)
        }
        dust(s, x, y)
    }

    /// Блоки, под которыми не осталось ни одного блока ряда ниже, падают.
    func unsupported(_ g: inout Igloo, _ s: Sim) {
        let geo = IglooGeo.of(g.door)
        let n = min(geo.count, g.blocks.count)
        let cost = blockCost(s)
        for b in 0..<n where g.blocks[b] && geo.row[b] > 0 {       // блоки идут по рядам снизу вверх
            var held = false
            for a in 0..<b where g.blocks[a] && geo.row[a] == geo.row[b] - 1 && geo.x1[a] >= geo.x0[b] && geo.x0[a] <= geo.x1[b] { held = true; break }
            if !held {
                g.blocks[b] = false
                shedBlock(g, s, b, vx: rng.range(-40, 40), vy: 0, n: cost)
            }
        }
    }

    /// Удар в точку (x, y) радиуса r: выбивает до n ближайших блоков. Возвращает, сколько выбито.
    func strike(_ g: inout Igloo, _ s: Sim, x: Float, y: Float, r: Float, vx: Float, vy: Float, n: Int) -> Int {
        let geo = IglooGeo.of(g.door)
        let lx = (x - g.x) / u, ly = (g.baseY - y) / u, grow = r / u
        guard IglooGeo.hit(lx, ly, grow: grow) else { return 0 }
        let cost = blockCost(s)
        var out = 0
        for _ in 0..<n {
            var best = -1
            var bestD = (6 + grow) * (6 + grow)
            for b in 0..<min(geo.count, g.blocks.count) where g.blocks[b] {
                let d = (geo.cx[b] - lx) * (geo.cx[b] - lx) + (geo.cy[b] - ly) * (geo.cy[b] - ly) + rng.range(0, 6)
                if d < bestD { bestD = d; best = b }
            }
            guard best >= 0 else { break }
            g.blocks[best] = false
            shedBlock(g, s, best, vx: vx, vy: vy, n: cost)
            out += 1
        }
        if out > 0 { unsupported(&g, s) }
        return out
    }

    /// У жилого дома утоптанная площадка сама не оседает (как ступени лестниц): столбец, просевший на
    /// ячейку, но целый — верх по-прежнему наст, — подрастает обратно. Настоящие ямы чинят жители.
    func retamp(_ s: Sim, _ g: Igloo) {
        guard g.floorRow >= 1, g.floorRow < s.H - 1, g.c0 >= 0, g.c1 < s.W, g.c0 <= g.c1 else { return }
        for c in g.c0...g.c1 {
            let i = g.floorRow * s.W + c
            guard s.snow[i] == 0, s.ledge[i] == 0, s.snow[i - s.W] == 0, s.snow[i + s.W] != 0,
                  s.hard[i + s.W] >= People.packedHard - 8 else { continue }
            s.snow[i] = rng.shade()
            s.hard[i] = People.packedHard
            s.gridDirty = true
            s.hardDirty = true
        }
    }

    /// Опора под частью дома ушла (глубже, чем осела площадка в среднем — avg ячеек): блоки нижнего ряда
    /// над провалом и всё, что стояло на них, выпадают.
    func sag(_ g: inout Igloo, _ s: Sim, avg: Float) {
        let geo = IglooGeo.of(g.door)
        let n = min(geo.count, g.blocks.count)
        let limit = max(4 * u / 3, 0.6 * s.cell)
        let cost = blockCost(s)
        var fell = false
        for b in 0..<n where g.blocks[b] && geo.row[b] == 0 {
            let ca = max(g.c0, Int((g.x + Float(geo.x0[b]) * u) * s.inv)), cb = min(g.c1, Int((g.x + Float(geo.x1[b] + 1) * u - 0.01) * s.inv))
            guard ca <= cb, ca >= 0, cb < s.W else { continue }
            var drop = 0
            for c in ca...cb { drop += max(0, s.H - pile(s, c, s.H) - g.floorRow) }
            guard (Float(drop) / Float(cb - ca + 1) - avg) * s.cell > limit else { continue }
            for a in b..<n where g.blocks[a] && (a == b || (geo.cx[a] >= Float(geo.x0[b]) - 0.5 && geo.cx[a] <= Float(geo.x1[b]) + 1.5)) {
                g.blocks[a] = false
                shedBlock(g, s, a, vx: rng.range(-30, 30), vy: 60, n: cost)
            }
            fell = true
        }
        if fell { unsupported(&g, s) }
    }

    /// Иглу рушится: все блоки, штабель и приступка — комьями. Жилое разлетается шире: тех, кто внутри, заваливает не с головой.
    func crumble(_ g: Igloo, _ s: Sim) {
        let laid = max(1, g.laid)
        let cost = blockCost(s)
        let per = max(1, min(cost, 250 / laid))
        let wide: Float = g.abandoned < 0 ? 520 : 160
        for b in g.blocks.indices where g.blocks[b] {
            shedBlock(g, s, b, vx: rng.range(-wide, wide), vy: rng.range(-60, 200) - (g.abandoned < 0 ? 240 : 0), n: per)
        }
        for _ in 0..<min(g.stock + g.stack * cost, 40) {
            chunk(s, stackX(g, s) + rng.range(-6, 6) * u, g.baseY - 3 * u, rng.range(-50, 50), -rng.range(20, 90))
        }
    }

    /// Занесённое иглу становится настоящим сугробом в сетке.
    func drift(_ g: Igloo, _ s: Sim) {
        let frac = sqrtf(Float(g.laid) / Float(max(1, g.blocks.count)))
        let half: Float = 27
        let c0 = max(0, Int((g.x - half * u) * s.inv)), c1 = min(s.W - 1, Int((g.x + half * u) * s.inv))
        guard c0 <= c1 else { return }
        var rMin = s.H
        for c in c0...c1 {
            let lx = ((Float(c) + 0.5) * s.cell - g.x) / (half * u)
            guard abs(lx) < 1 else { continue }
            let hu = 17 * powf(cosf(lx * .pi / 2), 0.8) * frac
            var n = Int((hu * u * s.inv).rounded())
            var r = s.H - pile(s, c, s.H) - 1
            while n > 0 && r >= 1 && r < s.H {
                let i = r * s.W + c
                if s.snow[i] != 0 || s.ledge[i] != 0 { break }
                s.snow[i] = rng.shade()
                s.hard[i] = 60
                rMin = min(rMin, r)
                r -= 1
                n -= 1
            }
        }
        s.gridDirty = true
        s.hardDirty = true
        if rMin < s.H { s.snowDisturbed(c0 - 1, rMin - 1, c1 + 1, s.H - 1) }
    }

    /// Раз в кадр: жители, площадка, занос, повреждения, костры.
    func stepHome(_ s: Sim, _ dt: Float) {
        if igloos.isEmpty { sweepMasks(s) }
        if igloos.isEmpty && fires.isEmpty { return }
        let snowing = max(s.cfg.intensity, s.cfg.flakeRate / 30)
        var k = 0
        while k < igloos.count {
            var g = igloos[k]
            // кто живёт и кто дома
            var live = 0
            g.inside = 0
            for q in folks where q.home == g.id && !q.gone && g.residents.contains(q.id) {
                live += 1
                if q.mode == .inside { g.inside += 1 }
            }
            g.acc += dt
            if g.acc > 0.5 {                    // ушедших и не пришедших на зов — вычеркнуть
                g.acc = 0
                let gid = g.id, late = s.time - g.invited > 90
                g.residents.removeAll { id in
                    guard let q = folks.first(where: { $0.id == id }), !q.gone else { return true }
                    if q.home == gid { return false }
                    return q.home != -1 || q.job == .leave || late
                }
            }
            if g.abandoned < 0 {
                if g.residents.isEmpty && live == 0 { g.abandoned = s.time }
                else if !g.built {
                    g.stalled += dt
                    if g.stalled > 240 { g.residents = []; g.abandoned = s.time }       // отстроить не выходит
                }
            }
            // площадка. Низ дома сам не двигается (его может сдвинуть только Dock — см. People.floorShifted).
            // Осела вся площадка — дом рывком садится на новый уровень; ушла из-под части дома — блоки над провалом падают.
            g.floorRow = max(1, min(s.H, Int((g.baseY * s.inv).rounded())))
            g.baseT += dt
            let tick = g.baseT >= 0.5
            if tick {
                g.baseT = 0
                if g.based && g.abandoned < 0 { retamp(s, g) }
                var st = baseScan(s, g, near: g.x)
                if g.based {
                    let n = Float(g.c1 - g.c0 + 1)
                    // осела вся площадка: верх ушёл вниз самое меньшее в трёх четвертях столбцов
                    let most = Int(n * 0.75)
                    let down = st.deep.3 >= most ? 4 : (st.deep.2 >= most ? 3 : (st.deep.1 >= most ? 2 : (st.deep.0 >= most ? 1 : 0)))
                    if down >= 1 && g.floorRow < s.H {
                        clearMask(&g, s)
                        g.floorRow = min(s.H, g.floorRow + down)
                        g.baseY = Float(g.floorRow) * s.cell
                        for _ in 0..<8 { dust(s, g.x + rng.range(-17, 17) * u, g.baseY - rng.range(0, 3) * u) }
                        st = baseScan(s, g, near: g.x)
                    }
                    if g.laid > 0 { sag(&g, s, avg: Float(st.drop) / n) }
                }
                g.baseNeed = st.need
                g.baseExtra = st.extra
                roofScan(s, &g)
                if g.mProbe < 0 { g.maskSig = -1 }          // маску не удалось поставить — попробовать ещё раз
            }
            // занос
            g.cover = min(1, g.cover + dt * snowing / 540 * HomeTune.coverSpeed)
            // удары: быстрый шар и резкий взмах курсора
            g.hitCD = max(0, g.hitCD - dt)
            var laid = g.laid
            if laid > 0 {
                for bi in s.balls.indices {
                    let b = s.balls[bi]
                    if b.parent != -1 || b.hasChild || (b.held && b.id != s.heldId) || b.vx * b.vx + b.vy * b.vy < 250 * 250 { continue }
                    if strike(&g, s, x: b.x, y: b.y, r: b.r, vx: b.vx, vy: b.vy, n: 1 + Int(rng.next() % 4)) > 0 && !b.held {
                        s.balls[bi].vx *= 0.45
                        s.balls[bi].vy *= 0.45
                    }
                }
                if s.cfg.sweep && s.cursorOn && s.heldId == -1 && g.hitCD <= 0 && s.cvx * s.cvx + s.cvy * s.cvy > 1100 * 1100 {
                    if strike(&g, s, x: s.cx, y: s.cy, r: 0, vx: s.cvx, vy: s.cvy, n: 1 + Int(rng.next() % 3)) > 0 { g.hitCD = 0.3 }
                }
                laid = g.laid
            }
            // соседские связи: верёвка и тропинка держатся, пока оба дома стоят и в них живут
            if g.flagTo >= 0 {
                let ok = g.built && g.abandoned < 0 && (iglooIndex(g.flagTo).map { igloos[$0].built && igloos[$0].abandoned < 0 } ?? false)
                if !ok { g.flagTo = -1; g.flagK = 0 }
            }
            if g.pathTo >= 0 && (g.abandoned >= 0 || iglooIndex(g.pathTo) == nil) { g.pathTo = -1 }
            if g.built && laid * 100 < g.blocks.count * 55 {        // не устояло
                crumble(g, s)
                clearMask(&g, s)
                if g.abandoned >= 0 {
                    igloos.remove(at: k)
                    continue
                }
                // жители отстроят: запись остаётся, стены — заново
                for b in g.blocks.indices { g.blocks[b] = false }
                g.built = false
                g.based = false                     // площадку — заново: разобрать завал, выровнять, утоптать
                g.stack = 0
                g.stock = 0
                g.stool = false
                g.cover = 0
                g.lantern = -1
                g.stalled = 0
                g.trappedAt = -1
                g.ruinedAt = s.time
                g.mourned = []
                for j in folks.indices where folks[j].home == g.id && folks[j].mode == .inside {     // кто был дома — под обломками
                    var q = folks[j]
                    q.mode = .ground
                    q.stand = -2
                    q.y = g.baseY
                    q.x = g.x + rng.range(-8, 8) * u
                    knock(&q, s, dir: rng.f() < 0.5 ? -1 : 1)
                    folks[j] = q
                }
                g.inside = 0
                laid = 0
            }
            if g.abandoned >= 0 && ((laid == 0 && g.stack == 0) || g.cover >= 1) {
                clearMask(&g, s)
                if laid > 0 { drift(g, s) }
                igloos.remove(at: k)
                continue
            }
            updateMask(&g, s)
            trapped(s, &g, dt)
            if tick { familyTick(s, &g) }
            igloos[k] = g
            k += 1
        }
        // костры
        var i = 0
        while i < fires.count {
            var f = fires[i]
            if s.time > f.until + 8 { fires.remove(at: i); continue }
            if let y = ground(s, x: f.x, feet: f.y, up: 6 * u) { f.y += max(-20 * u * dt, min(40 * u * dt, y - f.y)) }
            if s.wind.storm > 0.6 && s.time < f.until { f.until = s.time }      // буран задувает
            if s.time < f.until {
                f.acc += dt
                if f.acc >= 12 {                // снег под костром подтаивает
                    f.acc = 0
                    let c = Int((f.x + rng.range(-2.5, 2.5) * u) * s.inv)
                    if c >= 0 && c < s.W {
                        let h = pile(s, c, s.H), r = s.H - h
                        if h > 1 && r >= 0 && r < s.H && s.snow[r * s.W + c] != 0 {
                            s.snow[r * s.W + c] = 0
                            s.gridDirty = true
                            s.snowDisturbed(c - 1, r - 1, c + 1, r + 1)
                        }
                    }
                }
            }
            fires[i] = f
            i += 1
        }
    }

    // MARK: - Твёрдый купол

    /// Поставить (или переставить) в Sim.mask силуэт уложенных блоков: снег ложится на купол и скатывается с него.
    func updateMask(_ g: inout Igloo, _ s: Sim) {
        if g.mk == 0 {
            for v in UInt8(251)...UInt8(254) where !igloos.contains(where: { $0.mk == v && $0.id != g.id }) { g.mk = v; break }
            if g.mk == 0 { return }
        }
        var bits = 0
        for b in g.blocks.indices where g.blocks[b] && b < 40 { bits |= 1 << b }
        let sig = bits ^ (g.floorRow << 42) ^ (Int(g.x) << 52)
        if sig == g.maskSig {
            if bits == 0 || g.mProbe < 0 || (g.mProbe < s.mask.count && s.mask[g.mProbe] == g.mk) { return }     // на месте
        }
        clearMask(&g, s)
        g.maskSig = sig
        guard bits != 0 else { return }
        let geo = IglooGeo.of(g.door)
        let hw = IglooGeo.hw, h = IglooGeo.h
        let c0 = max(0, Int((g.x - Float(hw) * u) * s.inv)), c1 = min(s.W - 1, Int((g.x + Float(hw) * u) * s.inv))
        let r0 = max(0, Int((g.baseY - Float(h) * u) * s.inv)), r1 = min(s.H - 1, g.floorRow - 1)
        guard c0 <= c1, r0 <= r1 else { return }
        g.mBox = (c0, r0, c1, r1)
        for r in r0...r1 {
            let ly = Int(((g.baseY - (Float(r) + 0.5) * s.cell) / u).rounded(.down))
            guard ly >= 0, ly < h else { continue }
            for c in c0...c1 {
                let lx = Int((((Float(c) + 0.5) * s.cell - g.x) / u).rounded(.down))
                guard lx >= -hw, lx < hw else { continue }
                let b = Int(geo.grid[(lx + hw) * h + ly])
                guard b < g.blocks.count, g.blocks[b] else { continue }
                let i = r * s.W + c
                if s.snow[i] == 0 && s.ledge[i] == 0 && s.mask[i] == 0 { s.mask[i] = g.mk; g.mProbe = i }
            }
        }
        HomeTune.masked.insert(ObjectIdentifier(self))
    }

    /// Снять свою маску: снег, лежавший на куполе, упадёт.
    func clearMask(_ g: inout Igloo, _ s: Sim) {
        let b = g.mBox
        if g.mk != 0 && b.c0 <= b.c1 && b.r0 <= b.r1 && b.c0 >= 0 && b.c1 < s.W && b.r0 >= 0 && b.r1 < s.H {
            var any = false
            for r in b.r0...b.r1 {
                for c in b.c0...b.c1 where s.mask[r * s.W + c] == g.mk { s.mask[r * s.W + c] = 0; any = true }
            }
            if any { s.snowDisturbed(b.c0 - 1, b.r0 - 2, b.c1 + 1, b.r1 + 1) }
        }
        g.mBox = (0, 0, -1, -1)
        g.mProbe = -1
        g.maskSig = -1
    }

    /// Домов больше нет (их убрали не здесь — «Прогнать всех»): подобрать за ними маску.
    func sweepMasks(_ s: Sim) {
        let me = ObjectIdentifier(self)
        guard HomeTune.masked.contains(me) else { return }
        HomeTune.masked.remove(me)
        var x0 = s.W, y0 = s.H, x1 = -1, y1 = -1
        for i in s.mask.indices where s.mask[i] >= 251 {
            s.mask[i] = 0
            let c = i % s.W, r = i / s.W
            x0 = min(x0, c); x1 = max(x1, c); y0 = min(y0, r); y1 = max(y1, r)
        }
        if x1 >= 0 { s.snowDisturbed(x0 - 1, y0 - 2, x1 + 1, y1 + 1) }
    }

    /// Настоящий снег на куполе и у стен: сколько ячеек лежит выше площадки и где его больше всего.
    func roofScan(_ s: Sim, _ g: inout Igloo) {
        g.roof = 0
        g.roofCol = -1
        g.bury = 0
        // пока дом не достроен, снег внутри стен — забота тех, кто ровняет площадку
        guard g.floorRow >= 1, g.floorRow <= s.H, g.c0 >= 0, g.c1 < s.W, g.c0 <= g.c1, g.based, g.built else { return }
        let r0 = max(0, g.floorRow - Int(34 * u * s.inv)), r1 = g.floorRow - 1
        guard r0 <= r1 else { return }
        var best = 0
        for c in g.c0...g.c1 {
            var n = 0
            for r in r0...r1 where s.snow[r * s.W + c] != 0 { n += 1 }
            g.roof += n
            if n > best { best = n; g.roofCol = c }
        }
        g.bury = min(1, Float(g.roof) / (Float(g.c1 - g.c0 + 1) * 10 * u * s.inv))
    }

    /// Снять с купола до n ячеек снега — из столбцов поближе к x. Возвращает, сколько снято.
    func takeRoof(_ s: Sim, _ g: Igloo, near x: Float, n: Int) -> Int {
        guard g.floorRow >= 1, g.floorRow <= s.H, g.c0 >= 0, g.c1 < s.W, g.c0 <= g.c1 else { return 0 }
        let r0 = max(0, g.floorRow - Int(34 * u * s.inv)), r1 = g.floorRow - 1
        guard r0 <= r1 else { return 0 }
        let pc = max(g.c0, min(g.c1, Int(x * s.inv)))
        var got = 0
        var k = 0
        while got < n && k <= (g.c1 - g.c0) * 2 + 1 {
            let c = pc + (k + 1) / 2 * (k % 2 == 0 ? -1 : 1)
            k += 1
            guard c >= g.c0, c <= g.c1 else { continue }
            for r in r0...r1 where s.snow[r * s.W + c] != 0 {
                s.snow[r * s.W + c] = 0
                s.gridDirty = true
                s.snowDisturbed(c - 1, r - 2, c + 1, r + 1)
                got += 1
                break
            }
        }
        return got
    }

    // MARK: - Завалило вход

    /// Вход закрыт снегом: изнутри не выйти.
    func blocked(_ g: Igloo) -> Bool { g.built && max(g.cover, g.bury) > 0.7 }

    /// Раз в кадр: если в заваленном доме кто-то заперт — они откапываются изнутри, снаружи сбегаются на помощь;
    /// не дождались — погибают.
    func trapped(_ s: Sim, _ g: inout Igloo, _ dt: Float) {
        guard g.inside > 0 && blocked(g) else {
            if g.trappedAt >= 0 { g.trappedAt = -1; if g.inside > 0 { g.freedAt = s.time } }
            return
        }
        let doorX = g.x + IglooGeo.of(g.door).doorX * u
        if g.trappedAt < 0 { g.trappedAt = s.time; g.alertT = 1; g.digAcc = 0 }
        // изнутри: медленно, снег вылетает из входа
        g.digAcc += dt * Float(g.inside)
        if g.digAcc > 1.4 {
            g.digAcc = 0
            g.cover = max(0, g.cover - 0.004)
            if takeRoof(s, g, near: doorX, n: 1) > 0 || g.cover > 0.7 {
                chunk(s, g.x + g.door * 21 * u, g.baseY - rng.range(3, 8) * u, g.door * rng.range(60, 150) * sqrtf(u / 2), -rng.range(40, 120))
            }
        }
        // зовут на помощь: свои и те, кто рядом и свободен
        g.alertT += dt
        if g.alertT > 1 {
            g.alertT = 0
            var helpers = 0
            for q in folks where q.job == .shovel && q.phase >= 30 && q.obj == g.id && !q.gone { helpers += 1 }
            for j in folks.indices where helpers < 4 {
                let q = folks[j]
                guard !q.gone, q.mode == .ground, q.stand == -2, !q.look.kid, abs(q.x - g.x) < (q.home == g.id ? 2000 : 240) * u else { continue }
                let free = q.job == .idle || q.job == .wander || q.job == .gaze || q.job == .cheer || q.job == .wave || q.job == .fight
                    || q.job == .snowman || ((q.job == .igloo || q.job == .fire || q.job == .shovel && q.phase < 30) && q.home == g.id)
                guard free else { continue }
                var h = q
                release(&h, s)
                h.job = .shovel
                h.obj = g.id
                next(&h, 30)
                folks[j] = h
                helpers += 1
            }
        }
        // не дождались
        if s.time - g.trappedAt > HomeTune.trapLimit {
            var scarf = SIMD4<Float>(0.8, 0.2, 0.2, 1)
            var victim: Int32 = -1
            for j in folks.indices where folks[j].home == g.id && folks[j].mode == .inside && !folks[j].gone {
                scarf = folks[j].look.pal[Int(cScarf)]
                victim = folks[j].id
                folks[j].gone = true
                let id = folks[j].id
                g.residents.removeAll { $0 == id }
            }
            g.inside = 0
            g.trappedAt = -1
            g.lantern = -1
            var gr = Grave(id: nextObjId, x: doorX + g.door * 6 * u, stand: -2, topY: g.baseY - 9 * u, scarf: scarf, born: s.time)
            nextObjId += 1
            gr.victim = victim
            graves.append(gr)
            // свои и те, кто откапывал, — оплакивают
            for j in folks.indices where !folks[j].gone && folks[j].mode == .ground && folks[j].stand == -2
                && (folks[j].home == g.id || (folks[j].job == .shovel && folks[j].phase >= 30 && folks[j].obj == g.id)) {
                var q = folks[j]
                release(&q, s)
                mourn(&q, s, gr)
                folks[j] = q
            }
            if g.residents.isEmpty { g.abandoned = s.time }
        }
    }

    // MARK: - Семья

    /// Новое иглу с серединой в x: запись с размеченной площадкой. Возвращает его номер в igloos.
    func found(_ s: Sim, x: Float, door: Float) -> Int {
        var g = Igloo(id: nextObjId, x: x, baseY: 0, born: s.time)
        nextObjId += 1
        g.door = door
        g.blocks = [Bool](repeating: false, count: IglooGeo.of(g.door).count)
        // площадка — на средней высоте снега под будущим домом: срезанного хватит на подсыпку
        g.c0 = max(0, Int((x - 18 * u) * s.inv))
        g.c1 = max(g.c0, min(s.W - 1, Int((x + 18 * u) * s.inv)))
        var sum = 0
        for c in g.c0...g.c1 { sum += pile(s, c, s.H) }
        let lvl = max(1, Int((Float(sum) / Float(g.c1 - g.c0 + 1)).rounded()))
        g.floorRow = max(1, min(s.H - 1, s.H - lvl))
        g.baseY = Float(g.floorRow) * s.cell
        g.until = s.time + rng.range(480, 1500)
        g.invited = s.time
        igloos.append(g)
        return igloos.count - 1
    }

    /// Свободный взрослый для пары: гость на полу или выросший ребёнок из другого дома. Лучше — мальчик с девочкой.
    func findMate(_ p: Person) -> Int? {
        var best: Int? = nil
        for j in folks.indices {
            let q = folks[j]
            guard q.id != p.id, !q.gone, !q.look.kid, q.stand == -2, q.mode == .ground,
                  q.job == .idle || q.job == .wander || q.job == .gaze || q.job == .cheer || q.job == .fight else { continue }
            if q.home == -1 {
                if igloos.contains(where: { $0.residents.contains(q.id) }) { continue }
            } else {
                guard q.home != p.home, let k = iglooIndex(q.home), igloos[k].grown.contains(q.id) else { continue }
            }
            guard let b = best else { best = j; continue }
            let m = folks[b]
            let qPair = q.look.girl != p.look.girl, mPair = m.look.girl != p.look.girl
            if (qPair && !mPair) || (qPair == mPair && abs(q.x - p.x) < abs(m.x - p.x)) { best = j }
        }
        return best
    }

    /// Раз в полсекунды: кто в доме живёт — пара, один, дети; рождение, взросление, знакомство.
    func familyTick(_ s: Sim, _ g: inout Igloo) {
        guard g.abandoned < 0 else { return }
        let fam = max(0.01, HomeTune.family)
        var adults = 0, lone = -1, other = -1
        var parentHome = false
        for j in folks.indices where folks[j].home == g.id && !folks[j].gone && g.residents.contains(folks[j].id) {
            if folks[j].look.kid || g.grown.contains(folks[j].id) { continue }
            adults += 1
            other = lone
            lone = j
            if folks[j].mode == .inside { parentHome = true }
        }
        if adults == 1 && g.adults == 2 && g.built {                // остался один: горюет
            g.griefUntil = s.time + rng.range(50, 100)
            g.court = -1
            g.courtT = 0
            g.courtCD = s.time + 40 / fam
        }
        if adults == 2 && g.built {
            if g.since < 0 { g.since = s.time; g.nextKid = s.time + rng.range(240, 480) / fam }
        } else {
            g.since = -1
        }
        g.adults = adults
        // дети: кто вырос, кого уже нет
        var i = 0
        while i < g.kids.count && i < g.grow.count {
            let id = g.kids[i]
            guard let j = folks.firstIndex(where: { $0.id == id && !$0.gone && $0.home == g.id }) else {
                g.kids.remove(at: i); g.grow.remove(at: i)
                continue
            }
            if s.time >= g.grow[i] && folks[j].mode == .ground {
                folks[j].look.kid = false                           // вырос
                g.grown.append(id)
                g.kids.remove(at: i); g.grow.remove(at: i)
                continue
            }
            i += 1
        }
        let gid = g.id
        g.grown.removeAll { id in !folks.contains(where: { $0.id == id && !$0.gone && $0.home == gid }) }
        if adults == 0 && g.grown.isEmpty && !g.kids.isEmpty {      // взрослых не осталось — дети уходят
            for j in folks.indices where folks[j].home == g.id && folks[j].look.kid && !folks[j].gone
                && folks[j].job != .buried && (folks[j].mode == .ground || folks[j].mode == .inside) {
                var q = folks[j]
                release(&q, s)
                if q.mode == .inside { q.mode = .ground; q.y = g.baseY }
                q.home = -1
                q.job = q.stand == -2 ? .leave : .goDown
                next(&q, 0)
                folks[j] = q
                let id = q.id
                g.residents.removeAll { $0 == id }
            }
        }
        // ребёнок: у пары, которая пожила вместе; выходит из дома, когда кто-то из родителей внутри
        if adults == 2 && g.since >= 0 && s.time >= g.nextKid && g.kidsBorn < 2 && folks.count < 11 && parentHome
            && g.trappedAt < 0 && s.wind.storm < 0.2 && max(g.cover, g.bury) < 0.5 && g.laid == g.blocks.count && other >= 0 {
            let a = folks[lone], b = folks[other]
            var look = makeLook(kid: true, girl: rng.f() < 0.5)
            for c in [cJacket, cJacketD, cSleeve] { look.pal[Int(c)] = a.look.pal[Int(c)] }     // куртка — как у одного
            for c in [cHat, cHat2] { look.pal[Int(c)] = b.look.pal[Int(c)] }                    // шапка — как у другого
            var kid = Person(id: nextId, look: look)
            nextId += 1
            kid.x = g.x + IglooGeo.of(g.door).doorX * u
            kid.y = g.baseY
            kid.face = g.door
            kid.home = g.id
            kid.stayUntil = g.until
            idle(&kid, 1.2)
            folks.append(kid)
            g.residents.append(kid.id)
            g.kids.append(kid.id)
            g.grow.append(s.time + rng.range(900, 1500) / fam)
            g.kidsBorn += 1
            g.nextKid = s.time + rng.range(240, 480) / fam
            for j in [lone, other] where folks[j].mode == .ground && folks[j].stand == -2
                && (folks[j].job == .idle || folks[j].job == .wander || folks[j].job == .gaze || folks[j].job == .fire) {
                folks[j].job = .cheer; folks[j].wait = 1.8; folks[j].phase = 0; folks[j].t = 0; folks[j].flag = false
            }
        }
        // знакомство: одинокий житель и одинокий гость подолгу оказываются рядом
        guard adults == 1, lone >= 0, g.built, s.time > g.griefUntil, s.time > g.courtCD else { return }
        let a = folks[lone]
        guard a.mode == .ground, a.stand == -2, a.job != .buried, a.job != .leave else { return }
        var best = -1
        for j in folks.indices {
            let q = folks[j]
            guard q.home == -1, !q.gone, !q.look.kid, q.mode == .ground, q.stand == -2, q.job != .leave, q.job != .buried,
                  abs(q.x - a.x) < 34 * u, !igloos.contains(where: { $0.residents.contains(q.id) }) else { continue }
            if best < 0 || abs(q.x - a.x) < abs(folks[best].x - a.x) { best = j }
        }
        guard best >= 0 else { g.courtT = max(0, g.courtT - 0.25); return }
        let b = folks[best]
        if g.court != b.id { g.court = b.id; g.courtT = 0 }
        var gain: Float = 0.5
        if (a.job == .fight && a.target == b.id) || (b.job == .fight && b.target == a.id) { gain += 0.6 }     // играют в снежки друг с другом
        if b.job == .shovel || b.job == .rescue { gain += 1 }                                                   // гость помогает
        g.courtT += gain * fam
        if g.courtT > 5 { visitEnd = max(visitEnd, s.time + 25) }      // гость не спешит уходить
        guard g.courtT >= 16 else { return }
        func free(_ q: Person) -> Bool { q.job == .idle || q.job == .wander || q.job == .gaze || q.job == .cheer || q.job == .wave || q.job == .fight }
        guard free(b), free(a) || (a.job == .fire && a.phase == 3) else { return }
        if rng.f() > 0.65 {                                             // не сложилось
            g.court = -1
            g.courtT = 0
            g.courtCD = s.time + 60 / fam
            return
        }
        // сошлись: гость остаётся жить
        var q = b
        release(&q, s)
        q.home = g.id
        q.partner = a.id
        q.stayUntil = g.until
        q.job = .home
        q.obj = Int(a.id)
        next(&q, 40)
        folks[best] = q
        var r = a
        release(&r, s)
        r.partner = b.id
        r.job = .home
        r.obj = Int(b.id)
        next(&r, 40)
        folks[lone] = r
        g.residents.append(b.id)
        g.court = -1
        g.courtT = 0
        g.griefUntil = 0
        g.until = max(g.until, s.time + rng.range(480, 1200))
    }

    // MARK: - Отрисовка

    /// Иглу, костры и всё, что вокруг них (позади человечков).
    func emitHome(_ s: Sim, into out: inout [PxInst]) {
        if igloos.isEmpty { sweepMasks(s) }     // дома убрали, а шаг человечков уже не идёт — маску подобрать здесь
        if igloos.isEmpty && fires.isEmpty { return }
        for g in igloos { emitIgloo(g, s, into: &out) }
        for g in igloos where g.flagTo >= 0 && g.flagK > 0 { emitFlags(g, s, into: &out) }
        for f in fires { emitFire(f, s, into: &out) }
        emitBlocks(s, into: &out)
    }

    /// Снежный блок 6×4 «пикселя»: левый верхний угол в (x, y).
    func emitBlock(_ out: inout [PxInst], _ x: Float, _ y: Float) {
        out.append(PxInst(rect: SIMD4(x, y, 6 * u, 4 * u), color: SIMD4(0.79, 0.895, 0.985, 1)))
        out.append(PxInst(rect: SIMD4(x, y, 6 * u, u), color: SIMD4(0.90, 0.955, 1, 1)))               // верх светлее
        out.append(PxInst(rect: SIMD4(x, y + 3 * u, 6 * u, u), color: SIMD4(0.58, 0.73, 0.92, 1)))     // низ и бок — в тени
        out.append(PxInst(rect: SIMD4(x + 5 * u, y, u, 4 * u), color: SIMD4(0.58, 0.73, 0.92, 1)))
    }

    /// Блоки в работе: брусок, который утаптывают и вырезают на снегу, и блок в руках у того, кто несёт.
    func emitBlocks(_ s: Sim, into out: inout [PxInst]) {
        for q in folks where q.job == .igloo && !q.gone && q.phase >= 4 && q.phase <= 11 {
            let px0 = (q.x / u).rounded() * u, py0 = ((q.y + u) / u).rounded() * u
            let handX = px0 + (q.face > 0 ? 0 : -6 * u), handY = py0 - 19 * u       // блок над головой, чуть впереди
            let barX = (q.aux / u).rounded() * u - 3 * u
            switch q.phase {
            case 4:
                let k = q.aux2
                if k < 0.45 {                           // куча снега, которую утаптывают
                    let h = Float(1 + Int(k / 0.45 * 3)) * u
                    out.append(PxInst(rect: SIMD4(barX, py0 - h, 6 * u, h), color: SIMD4(0.97, 0.985, 1, 1)))
                    out.append(PxInst(rect: SIMD4(barX, py0 - u, 6 * u, u), color: SIMD4(0.84, 0.90, 0.98, 1)))
                } else {                                // брусок: обрезки ещё лежат сверху
                    emitBlock(&out, barX, py0 - 4 * u)
                    if k < 0.8 {
                        out.append(PxInst(rect: SIMD4(barX + u, py0 - 5 * u, 2 * u, u), color: SIMD4(0.97, 0.985, 1, 1)))
                        out.append(PxInst(rect: SIMD4(barX - u, py0 - u, u, u), color: SIMD4(0.97, 0.985, 1, 1)))
                        out.append(PxInst(rect: SIMD4(barX + 6 * u, py0 - 2 * u, u, 2 * u), color: SIMD4(0.97, 0.985, 1, 1)))
                    }
                }
            case 5:
                let k = min(1, q.t / 0.45)
                emitBlock(&out, ((barX + (handX - barX) * k) / u).rounded() * u, ((py0 - 4 * u + (handY - py0 + 4 * u) * k) / u).rounded() * u)
            case 6, 8:
                if q.carry > 0 { emitBlock(&out, handX, handY) }
            case 11:
                if !q.flag && q.carry > 0 { emitBlock(&out, handX, handY) }
            default:
                break
            }
        }
    }

    func emitIgloo(_ g: Igloo, _ s: Sim, into out: inout [PxInst]) {
        let geo = IglooGeo.of(g.door)
        let bx = (g.x / u).rounded() * u, by = (g.baseY / u).rounded() * u
        let cov = max(g.cover, g.bury)                          // иней и шапка от снегопада или настоящий завал
        let n = min(g.blocks.count, geo.count)
        let lit = g.inside > 0
        // свет: ровно мерцает; когда внутри заперты — тревожно мигает
        let fl: Float = g.trappedAt >= 0 ? (Int(s.time * 5) & 1 == 0 ? 1.0 : 0.25)
                                         : 0.86 + 0.09 * sinf(s.time * 11 + Float(g.id)) + 0.05 * sinf(s.time * 23.7 + Float(g.id) * 2.1)
        let white = SIMD3<Float>(0.97, 0.985, 1), shade = SIMD3<Float>(0.83, 0.89, 0.975)
        // блоки, которые сейчас доезжают из рук на своё место в стене
        var a1 = -1, a2 = -1
        var o1 = SIMD2<Float>(0, 0), o2 = SIMD2<Float>(0, 0)
        for q in folks where q.job == .igloo && q.home == g.id && !q.gone && q.obj >= 0 && (q.phase == 7 || (q.phase == 11 && q.flag)) {
            let kk = min(1, q.t / 0.9), e = 1 - kk * kk * (3 - 2 * kk)
            let off = SIMD2((q.aux * e).rounded() * u, -(q.aux2 * e).rounded() * u)
            if a1 < 0 { a1 = q.obj; o1 = off } else if a2 < 0 { a2 = q.obj; o2 = off }
        }
        // дальняя стенка купола видна там, где передних блоков ещё (или уже) нет: тёмный лёд, внизу — утоптанный пол
        var topRow = -1
        for b in 0..<n where g.blocks[b] { topRow = max(topRow, geo.row[b]) }
        let backH = g.built ? IglooGeo.h : (topRow < 0 ? 0 : min(IglooGeo.h, (topRow + 1) * 4 + 2))
        for q in geo.px {
            let b = Int(q.block)
            guard b < n else { continue }
            let y = Int(q.y)
            let x0 = bx + Float(q.x) * u, y0 = by - Float(y + 1) * u
            let laid = g.blocks[b]
            if laid && cov >= q.th {                            // под снегом; у кромки шапки — тень
                var c = cov - q.th < 0.07 ? shade : white
                if lit && q.kind == IglooGeo.kDoor && g.built { c = c * 0.62 + SIMD3<Float>(1.0, 0.70, 0.30) * (0.38 * fl) }  // свет сквозь снег
                out.append(PxInst(rect: SIMD4(x0, y0, u, u), color: SIMD4(c.x, c.y, c.z, 1)))
                continue
            }
            let flying = laid && (b == a1 || b == a2)
            let front = laid && !(q.kind == IglooGeo.kDoor && !g.built)        // пока строят, вход — просто проём
            if !front || flying {
                if y < backH {
                    let hy = Float(y) / Float(IglooGeo.h)
                    var c = y == 0 ? SIMD3<Float>(0.70, 0.80, 0.95)
                                   : SIMD3<Float>(0.43, 0.56, 0.82) * (0.88 + 0.12 * hy) * (q.kind == IglooGeo.kSeam ? 0.94 : 1)
                    if lit { c = (SIMD3<Float>(0.78, 0.50, 0.24) + (SIMD3<Float>(0.40, 0.27, 0.24) - SIMD3<Float>(0.78, 0.50, 0.24)) * hy) * (0.8 + 0.2 * fl) }  // изнутри светит огонь
                    out.append(PxInst(rect: SIMD4(x0, y0, u, u), color: SIMD4(c.x, c.y, c.z, 1)))
                }
                if !front { continue }
            }
            var c: SIMD3<Float>
            switch q.kind {
            case IglooGeo.kSeam: c = SIMD3(0.58, 0.73, 0.92) * q.tone
            case IglooGeo.kLight: c = SIMD3(0.87, 0.94, 1.0)
            case IglooGeo.kDark: c = SIMD3(0.62, 0.75, 0.92)
            case IglooGeo.kFrame: c = SIMD3(0.89, 0.95, 1.0)
            case IglooGeo.kDoor:
                if lit {                                        // дома кто-то есть: тёплый свет
                    let k = min(1, q.glow * 1.25) * fl
                    c = SIMD3(0.50, 0.20, 0.09) + (SIMD3(1.0, 0.84, 0.42) - SIMD3(0.50, 0.20, 0.09)) * k
                } else {
                    c = SIMD3(0.15, 0.19, 0.33) - SIMD3(0.08, 0.10, 0.15) * q.glow
                }
            default: c = SIMD3(0.79, 0.895, 0.985) * q.tone
            }
            let o = b == a1 ? o1 : (b == a2 ? o2 : SIMD2<Float>(0, 0))
            out.append(PxInst(rect: SIMD4(x0 + o.x, y0 + o.y, u, u), color: SIMD4(min(c.x, 1), min(c.y, 1), min(c.z, 1), 1)))
        }
        if lit && cov < 0.5 && g.built {                        // отсвет на снегу перед входом
            let a: Float = 0.22 * fl
            out.append(PxInst(rect: SIMD4(bx + (geo.doorX - 4.5) * u, by, 9 * u, u), color: SIMD4(1.0 * a, 0.72 * a, 0.3 * a, a)))
        }
        if g.stool {                                            // приступка из утоптанного снега
            out.append(PxInst(rect: SIMD4(bx - 8 * u, by - 2 * u, 16 * u, 2 * u), color: SIMD4(0.90, 0.95, 1, 1)))
            out.append(PxInst(rect: SIMD4(bx - 5 * u, by - 5 * u, 10 * u, 3 * u), color: SIMD4(0.90, 0.95, 1, 1)))
            out.append(PxInst(rect: SIMD4(bx - 5 * u, by - 5 * u, 10 * u, u), color: SIMD4(0.98, 0.99, 1, 1)))
            out.append(PxInst(rect: SIMD4(bx - 8 * u, by - 2 * u, 3 * u, u), color: SIMD4(0.98, 0.99, 1, 1)))
            out.append(PxInst(rect: SIMD4(bx + 5 * u, by - 2 * u, 3 * u, u), color: SIMD4(0.98, 0.99, 1, 1)))
            out.append(PxInst(rect: SIMD4(bx - 8 * u, by - u, 16 * u, u), color: SIMD4(0.78, 0.86, 0.97, 1)))
        }
        if g.stack > 0 {                                        // штабель готовых блоков
            let sx = (stackX(g, s) / u).rounded() * u
            emitBlock(&out, sx - 6 * u, by - 4 * u)
            if g.stack > 1 { emitBlock(&out, sx, by - 4 * u) }
            if g.stack > 2 { emitBlock(&out, sx - 3 * u, by - 8 * u) }
        }
        if g.lantern >= 0 && cov < 0.8 {                        // ледяной фонарик у входа
            let l = bx + (geo.doorX + g.door * 7 - 2).rounded() * u
            let on = g.abandoned < 0 && g.built && (lit || evening(s))
            if on {
                let a: Float = 0.2 * fl
                out.append(PxInst(rect: SIMD4(l - 3 * u, by, 10 * u, u), color: SIMD4(1.0 * a, 0.72 * a, 0.3 * a, a)))
            }
            out.append(PxInst(rect: SIMD4(l, by - 5 * u, 4 * u, 5 * u), color: SIMD4(0.72, 0.86, 0.98, 1)))
            out.append(PxInst(rect: SIMD4(l, by - 5 * u, 4 * u, u), color: SIMD4(0.92, 0.97, 1, 1)))
            out.append(PxInst(rect: SIMD4(l, by - u, 4 * u, u), color: SIMD4(0.56, 0.72, 0.92, 1)))
            if on {
                out.append(PxInst(rect: SIMD4(l + u, by - 4 * u, 2 * u, 3 * u), color: SIMD4(1.0, 0.70 * fl, 0.22, 1)))
                out.append(PxInst(rect: SIMD4(l + u, by - 3 * u, 2 * u, 2 * u), color: SIMD4(1.0, 0.92 * fl, 0.50, 1)))
            } else {
                out.append(PxInst(rect: SIMD4(l + u, by - 4 * u, 2 * u, 3 * u), color: SIMD4(0.86, 0.94, 1, 1)))
            }
            if cov > 0.3 { out.append(PxInst(rect: SIMD4(l, by - 6 * u, 4 * u, u), color: SIMD4(white.x, white.y, white.z, 1))) }
        }
        if cov > 0.02 {
            // шапка: снег лежит и поверх купола
            let hw = IglooGeo.hw
            for x in -hw..<hw {
                let t = Int(geo.top[x + hw])
                guard t >= 0, cov >= geo.topTh[x + hw], Int(geo.topBlock[x + hw]) < n, g.blocks[Int(geo.topBlock[x + hw])] else { continue }
                let th = Int(cov * (2.6 + 0.5 * IglooGeo.wob(x + 5)))
                if th > 0 {
                    out.append(PxInst(rect: SIMD4(bx + Float(x) * u, by - Float(t + 1 + th) * u, u, Float(th) * u),
                                      color: SIMD4(white.x, white.y, white.z, 1)))
                }
            }
            // намёт у боков
            let d = Int((cov - 0.15) * 11)
            if d > 0 && g.laid * 2 > n {
                for j in 0..<d {
                    let hgt = Float(max(1, Int(Float(d - j) * 0.75))) * u
                    let col = j == d - 1 ? shade : white
                    out.append(PxInst(rect: SIMD4(bx + Float(-hw - 1 - j) * u, by - hgt, u, hgt), color: SIMD4(col.x, col.y, col.z, 1)))
                    out.append(PxInst(rect: SIMD4(bx + Float(hw + j) * u, by - hgt, u, hgt), color: SIMD4(col.x, col.y, col.z, 1)))
                }
            }
        }
    }

    /// Верёвка с флажками от этого иглу к соседу справа; пока тянут — до того места, куда дотянули.
    func emitFlags(_ g: Igloo, _ s: Sim, into out: inout [PxInst]) {
        guard let ri = iglooIndex(g.flagTo) else { return }
        let R = igloos[ri]
        let ax = ((g.x + 12 * u) / u).rounded() * u, ay = g.baseY - 15 * u
        let ex = ax + (R.x - 12 * u - ax) * g.flagK, ey = ay + (R.baseY - 15 * u - ay) * g.flagK
        let steps = Int((ex - ax) / u)
        guard steps >= 2, steps < 400 else { return }
        let dip = (2 + 0.07 * Float(steps)) * u
        let wave = Int(s.time * 4)
        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let x = ax + Float(i) * u
            let y = ((ay + (ey - ay) * t + dip * 4 * t * (1 - t)) / u).rounded() * u
            out.append(PxInst(rect: SIMD4(x, y, u, u), color: SIMD4(0.33, 0.26, 0.22, 1)))
            if i % 5 == 3 && i + 2 <= steps {           // флажок: два «пикселя» и хвостик, который треплет ветер
                let col: SIMD4<Float>
                switch (i / 5) % 5 {
                case 0: col = SIMD4(0.90, 0.25, 0.25, 1)
                case 1: col = SIMD4(0.98, 0.80, 0.22, 1)
                case 2: col = SIMD4(0.27, 0.72, 0.40, 1)
                case 3: col = SIMD4(0.26, 0.50, 0.92, 1)
                default: col = SIMD4(0.95, 0.48, 0.70, 1)
                }
                out.append(PxInst(rect: SIMD4(x, y + u, 2 * u, 2 * u), color: col))
                out.append(PxInst(rect: SIMD4(x + Float((wave + i) & 1) * u, y + 3 * u, u, u), color: col))
            }
        }
    }

    func emitFire(_ f: Fire, _ s: Sim, into out: inout [PxInst]) {
        let bx = (f.x / u).rounded() * u, by = (f.y / u).rounded() * u + u
        func px(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ c: SIMD3<Float>, _ a: Float = 1) {
            out.append(PxInst(rect: SIMD4(bx + x * u, by - (y + h) * u, w * u, h * u), color: SIMD4(c.x * a, c.y * a, c.z * a, a)))
        }
        let left = f.until - s.time
        let life = max(0, min(1, left / 12)) * min(1, (s.time - f.born) / 1.5)
        let w: Float = f.big ? 6 : 4                            // полуширина поленьев
        if life > 0 {                                           // отсвет на снегу
            let a = (0.14 + 0.05 * sinf(s.time * 13 + Float(f.id))) * life
            px(-w - 5, -1, 2 * w + 10, 1, SIMD3(1, 0.62, 0.22), a)
            px(-w - 2, 0, 2 * w + 4, 1, SIMD3(1, 0.62, 0.22), a * 0.7)
        }
        // поленья; у общего костра — ещё и камни по краям
        px(-w, 0, 2 * w, 1, SIMD3(0.33, 0.20, 0.11))
        px(-w + 1, 1, 2 * w - 2, 1, SIMD3(0.46, 0.30, 0.17))
        px(-w, 0, 1, 1, SIMD3(0.62, 0.46, 0.28)); px(w - 1, 0, 1, 1, SIMD3(0.62, 0.46, 0.28))
        if f.big {
            px(-w - 2, 0, 2, 2, SIMD3(0.52, 0.55, 0.62)); px(w, 0, 2, 2, SIMD3(0.52, 0.55, 0.62))
            px(-w - 2, 1, 1, 1, SIMD3(0.68, 0.71, 0.78)); px(w, 1, 1, 1, SIMD3(0.68, 0.71, 0.78))
        }
        guard life > 0 else {                                   // прогорел: угли и дымок
            let e = 0.5 + 0.5 * sinf(s.time * 3 + Float(f.id))
            px(-1, 1, 2, 1, SIMD3(0.75 * e + 0.2, 0.18, 0.08))
            let k = (s.time - f.until) * 0.5
            let ph = k - k.rounded(.down)
            px(sinf(ph * 5) * 1.5, 3 + ph * 9, 1, 1, SIMD3(0.75, 0.78, 0.84), 0.35 * (1 - ph))
            return
        }
        // пламя: языки, высота каждого дёргается
        let tick = Int(s.time * 9)
        let n = f.big ? 7 : 5
        for i in 0..<n {
            let m = abs(i - n / 2)
            let v = (tick &* 7 &+ i &* 13 &+ f.id &* 5 &+ (tick / 3) &* i) % 3          // 0…2
            let hgt = max(1, Int(Float((f.big ? 10 : 7) - 2 * m + v - 1) * (0.35 + 0.65 * life)))
            let x = Float(i - n / 2) - 0.5
            let tip = max(1, hgt / 3), core = m <= (f.big ? 2 : 1) ? max(0, hgt - tip - 2) : 0
            px(x, 2, 1, Float(hgt), SIMD3(1.0, 0.56, 0.11))                             // оранжевое
            px(x, 2 + Float(hgt - tip), 1, Float(tip), SIMD3(0.93, 0.30, 0.08))         // красные кончики
            if core > 0 { px(x, 2, 1, Float(core), SIMD3(1.0, 0.90, 0.38)) }            // жёлтая сердцевина
        }
        for j in 0..<(f.big ? 3 : 2) {                          // искры
            let k = s.time * 0.8 + Float(j) * 0.47 + Float(f.id) * 0.3
            let ph = k - k.rounded(.down)
            px(sinf(k * 7 + Float(j)) * 2.5, (f.big ? 12 : 9) + ph * 9, 1, 1, SIMD3(1, 0.75, 0.25), (1 - ph) * life)
        }
    }
}
