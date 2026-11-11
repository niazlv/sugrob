import Foundation

// Человечки. Время от времени из-за края экрана приходит компания в куртках и шапках:
// играют в снежки, катают снеговиков, строят лестницу к окну и лезут на него.
//
// Снег у них настоящий, тот же, что лежит в сетке `Sim.snow`: снежок лепится из ячеек,
// снятых с поверхности, и рассыпается обратно в комья; шары снеговика — обычные `Ball`.
//
// Лестница к окну:
//  - внизу — ступени из снега, утоптанного до наста: обычные ячейки сетки с высокой слежалостью,
//    стоят на низу экрана и живут по общим законам (их можно расколоть, они со временем оседают);
//  - выше — приставная лестница, прилепленная снегом к боку окна. Она хранится здесь, а не в сетке
//    (`Ladder.rows`): держится она не на снегу под собой, а на окне. Лепят её, только когда окно
//    стоит на месте; сдвинули или закрыли окно — она обваливается комьями и снежной пылью.
//    Курсор и брошенный шар выбивают из неё куски.

/// Цветной прямоугольник для отрисовки (человечки рисуются «пикселями»).
struct PxInst {
    var rect: SIMD4<Float>
    var color: SIMD4<Float>
}

struct Look {
    var pal: [SIMD4<Float>]
    var hatKind: Int        // 0 — с помпоном, 1 — ушанка, 2 — капюшон, 3 — с полоской
    var kid = false         // ребёнок: ниже ростом
    var girl = false        // косички и пальто подлиннее
}

struct Person {
    enum Mode { case ground, ladder, air, hop, crawl, inside }       // crawl — ползёт в тоннеле, inside — в иглу (не виден)
    enum Job {
        case arrive, idle, wander, fight, hit, snowman, gather, lift, goTop, top, goDown, leave, gaze, wave, cheer
        case buried, panic, rescue, mourn           // PeopleRescue.swift
        case igloo, home, shovel, fire              // PeopleHome.swift
        case tunnel, angel, sled, ride, tree        // PeopleFun.swift
        case steps                                  // выбирается из ямы: зовёт на помощь, утаптывает или прорубает ступеньки
        case shelter                                // пережидает буран: сбиваются в кучку, лепят стенку от ветра
    }
    enum Anim {
        case stand, walk, run, carry, scoop, pat, pack, windup, thrown, flinch, flail, down, getup
        case cheer, hop, wave, sit, gaze, push, climb, hang, handUp, reachDown, hold
        case dig, mourn, crawl, shovel, panic, pull, ride, warm, carryTree, angel, huddle
    }

    var id: Int32
    var look: Look
    var x: Float = 0, y: Float = 0      // ноги
    var vx: Float = 0, vy: Float = 0
    var face: Float = 1
    var mode = Mode.ground
    var stand = -2                      // на чём стоит: -2 — низ экрана, иначе номер окна (-1 — Dock)
    var job = Job.arrive
    var anim = Anim.stand
    var phase = 0
    var t: Float = 0                    // секунд в текущей фазе
    var flag = false                    // «в этой фазе уже сделал»
    var goalX: Float = 0
    var wait: Float = 0
    var walkPhase: Float = 0
    var carry = 0                       // ячеек снега в руках
    var ball: Int32 = -1                // шар, который катит или несёт
    var acc: Float = 0
    var stage = 0                       // какой шар снеговика лепит: 0 — низ, 2 — голова
    var rollDir: Float = 1
    var target: Int32 = -1              // в кого кидает: id человечка, -2 — курсор, -3 — шар targetBall
    var targetBall: Int32 = -1
    var throwsLeft = 0
    var grudge: Int32 = -1              // кто попал снежком (-2 — курсор)
    var ladder = -1
    var tries = 0
    var topUntil: Float = 0
    var snowHat: Float = 0              // секунд, пока на шапке снег
    var flinch: Float = 0
    var pokeCD: Float = 0
    var waveCD: Float = 0
    var fallDir: Float = 1
    var hop0 = SIMD2<Float>(0, 0), hop1 = SIMD2<Float>(0, 0)
    var gone = false
    var stamp: Float = -1
    // жизнь (PeopleRescue / PeopleHome / PeopleFun)
    var home = -1                       // id иглу, где живёт; -1 — гость
    var partner: Int32 = -1             // с кем живёт
    var stayUntil: Float = 0            // когда надумает уйти из дома
    var depth0: Float = 0               // на сколько завалило вначале, pt
    var obj = -1                        // id того, чем занят: могила, тоннель, ёлка, костёр
    var aux: Float = 0, aux2: Float = 0 // запасные поля для модулей
    // передвижение
    var blockT: Float = 0               // сколько секунд упирается в стенку, на которую не влезть
    var blockAt: Float = -10
    var blockDir: Float = 1
    var low = false                     // над головой низкий свод: ползёт
    var resume = Job.idle               // чем заняться, когда выберется
    /// Рост в «пикселях».
    var tall: Float { look.kid ? 14 : 17 }
    /// Занят тем, что нельзя прерывать снежком или тревогой: завален, в доме, едет мимо.
    var away: Bool { job == .buried || mode == .inside || mode == .crawl || job == .sled || job == .ride || job == .leave }
}

struct Shot {
    var x: Float, y: Float, vx: Float, vy: Float
    var cells: Int
    var from: Int32
    var target: Int32
    var age: Float = 0
}

/// Место, где лепят снеговика.
struct Site {
    var x: Float
    var balls: [Int32] = [-1, -1, -1]
    var owner: [Int32] = [-1, -1, -1]
    var placed = 0
    var born: Float
    var finished: Float = -1
}

/// Ступеньки из утоптанного снега вдоль стенки, чтобы выбраться из ямы.
struct StepWork {
    var id: Int
    var stand: Int
    var wallCol: Int            // первый столбец стенки
    var dir: Int                // в какую сторону стенка
    var topRow: Int             // строка верха стенки
    var rise: Int, run: Int
    var born: Float
    var owner: Int32 = -1       // кто застрял
    var doneAt: Float = -1
}

struct Ladder {
    var id: Int
    var win: Int
    var out: Int                // куда от окна уходят ступени: -1 — влево (лестница слева от окна), +1 — вправо
    var c0: Int, c1: Int        // столбцы приставной лестницы; под ней — площадка ступеней
    var hs: Int                 // высота площадки над низом экрана, ячеек
    var run: Int, rise: Int     // ширина и высота ступени, ячеек
    var rs: Int                 // шаг перекладин
    var topRow: Int             // верхняя строка лестницы
    var ledgeY: Float           // верх окна (линия карниза)
    var edgeX: Float            // бок окна, к которому прилеплена
    var boxY0: Float            // верх рамки окна — чтобы заметить, что окно сдвинули
    var boxY1: Float = .infinity // низ рамки окна: ниже лестнице держаться не за что
    var usedAt: Float = 0       // когда по ней последний раз лазили
    var wear: Float = 0         // накопленный износ от ветра и времени
    var frost: Float = 0        // 0…1: насколько занесло перекладины
    var checkAt: Float = 0
    var dirty = true            // что-то отломилось или добавилось: проверить, что держится
    var docked = false          // под ней поднят Dock: ступени временно уехали вверх, всё ждёт
    var base = -2               // на чём стоит: -2 — низ экрана (со ступенями), иначе номер окна (ярус: с его карниза)
    var baseY: Float = 0        // линия карниза окна-основания
    var bot = 0                 // нижняя строка приставной лестницы
    var active = false          // идёт стройка
    var done = false
    var broken = false          // прилепленная часть обвалилась
    var stock = 0               // снег, сложенный на площадке
    var lifters: [Int32] = []   // кто стоит на лестнице и передаёт снег, снизу вверх
    var missing: Float = 0
    var orphan: Float = 0
    var erode: Float = 0
    var stalled: Float = 0
    var empty: Float = 0
    var doneAt: Float = -1000
    var rows: [UInt16] = []     // приставная лестница: биты — ячейки, строки снизу вверх от площадки
    var front = 0               // сколько строк снизу достроено целиком (rows.count — готова вся)
    var stairsDone = false
    var platformOK = false      // площадка под лестницей цела
    var nextStair: (c: Int, r: Int)? = nil
}

struct Canvas {
    static let w = 36, h = 34, ox = 18, oy = 26
    var px = [UInt8](repeating: 0, count: Canvas.w * Canvas.h)
    mutating func clear() { for i in px.indices { px[i] = 0 } }
    mutating func set(_ x: Int, _ y: Int, _ c: UInt8) {
        let cx = x + Canvas.ox, cy = y + Canvas.oy
        if cx >= 0 && cx < Canvas.w && cy >= 0 && cy < Canvas.h { px[cy * Canvas.w + cx] = c }
    }
    mutating func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: UInt8) {
        if w <= 0 || h <= 0 { return }
        for yy in y..<(y + h) { for xx in x..<(x + w) { set(xx, yy, c) } }
    }
    mutating func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: UInt8) {
        let n = max(abs(x1 - x0), abs(y1 - y0))
        if n == 0 { set(x0, y0, c); return }
        for k in 0...n {
            let f = Float(k) / Float(n)
            set(x0 + Int((Float(x1 - x0) * f).rounded()), y0 + Int((Float(y1 - y0) * f).rounded()), c)
        }
    }
}

struct Pose {
    var bob = 0                 // тело выше (минус) или ниже
    var jump = 0                // весь человечек подпрыгнул, px
    var crouch = 0              // присел
    var lean: Float = 0         // наклон вперёд, px на уровне плеч
    var footA = 0, footB = 0    // вынос стоп вперёд
    var liftA = 0, liftB = 0    // стопа приподнята
    var handA = (0, 4)          // кисть дальней руки относительно плеча
    var handB = (0, 4)          // ближней
    var back = false            // вид со спины
    var sit = false
    var mouth = false
    var eyesShut = false
    var lying = false
    var lump = 0                // размер кома в руках, px
    var lumpX = 0, lumpY = 0    // левый верхний угол кома: x от середины, y от строки плеч
    var shovel = 0              // лопата в ближней руке: 1 — совком вниз, 2 — вверх (бросает снег)
}

let cSkin: UInt8 = 1, cEye: UInt8 = 2, cHat: UInt8 = 3, cHat2: UInt8 = 4, cPom: UInt8 = 5
let cJacket: UInt8 = 6, cJacketD: UInt8 = 7, cSleeve: UInt8 = 8, cScarf: UInt8 = 9, cMitten: UInt8 = 10
let cPants: UInt8 = 11, cBoots: UInt8 = 12, cSnow: UInt8 = 13, cSnowD: UInt8 = 14, cMouth: UInt8 = 15
let cHair: UInt8 = 16, cWood: UInt8 = 17, cMetal: UInt8 = 18

final class People {
    var folks: [Person] = []            // менять чужого человечка — через folks[j]; удалять — только gone = true
    var ladders: [Ladder] = []
    var shots: [Shot] = []
    var site: Site?
    var rng: Rng
    var nextId: Int32 = 1
    var nextLadderId = 1
    var nextVisit: Float = -1
    var visitEnd: Float = 0
    var visited = false
    var planned = true
    var planAfter: Float = 0
    var summonAsked = false
    var forced = false          // позвали из меню, хотя человечки выключены
    var u: Float = 2            // размер «пикселя» человечка, pt
    var boxes: [Int: (box: WinBox, still: Float)] = [:]
    var boxAcc: Float = 1
    var ballHits: [Int32: Int] = [:]
    var cursorStill: Float = 0
    var canvas = Canvas()
    // жизнь: завалы (PeopleRescue), дома (PeopleHome), забавы и происшествия (PeopleFun)
    var graves: [Grave] = []
    var igloos: [Igloo] = []
    var fires: [Fire] = []
    var tunnels: [Tunnel] = []
    var trees: [Tree] = []
    var nextObjId = 1
    var stepWorks: [StepWork] = []      // ступеньки, которые утаптывают, чтобы выбраться из ямы
    var dock: Ledge? = nil              // поднятый Dock (его карниз) — на этом шаге
    var dockStamp: Float = -1
    var windStorm: Float = 0            // сила бурана на этом шаге (копия sim.wind.storm)
    var shelterX: Float = -1            // где пережидают буран (-1 — бурана нет)
    var wallTop = -1                    // стенка от ветра: строка её верха (-1 — не начата)
    var wallCol = 0
    var nextEvent: Float = -1
    var settleWish = false              // в этот приход кто-то надумал остаться жить
    var visitStart: Float = 0

    init() { rng = Rng(seed: UInt64(Date().timeIntervalSince1970 * 1000) ^ 0xA5A5_5A5A_1234) }

    func reseed(_ v: UInt64) { rng = Rng(seed: v) }

    /// Позвать компанию прямо сейчас (пункт меню).
    func summon() { summonAsked = true }

    /// Для самотеста: строка о том, кто чем занят.
    var summary: String {
        var jobs: [String: Int] = [:]
        for p in folks { jobs["\(p.job)", default: 0] += 1 }
        let lad = ladders.map { "ladder#\($0.id) win \($0.win) active=\($0.active) done=\($0.done) broken=\($0.broken) stairs=\($0.stairsDone) rows=\($0.front)/\($0.rows.count) stock=\($0.stock) lifters=\($0.lifters.count)" }
        let life = "graves=\(graves.count) igloos=\(igloos.count) fires=\(fires.count) tunnels=\(tunnels.filter { !$0.dead }.count) trees=\(trees.count)"
        return "people \(folks.count) [\(life)] \(jobs.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: " ")) shots=\(shots.count) \(lad.joined(separator: "; "))"
    }

    // MARK: - Шаг

    func step(_ s: Sim, _ dt: Float) {
        if s.cfg.people == 0 && folks.isEmpty && ladders.isEmpty && shots.isEmpty && !summonAsked
            && graves.isEmpty && igloos.isEmpty && fires.isEmpty && tunnels.isEmpty && trees.isEmpty {
            nextVisit = -1
            return
        }
        u = max(2, s.cfg.peopleSize)
        windStorm = s.wind.storm
        dock = s.segs.first(where: { $0.kind == 2 })
        trackWindows(s, dt)
        validate(s, dt)
        stepWorks.removeAll { s.time - $0.born > 240 || ($0.doneAt >= 0 && s.time - $0.doneAt > 120) }
        if s.wind.storm < 0.1 { shelterX = -1; wallTop = -1 }
        schedule(s)
        stepRescue(s, dt)
        stepHome(s, dt)
        stepFun(s, dt)
        stepEvents(s, dt)
        cursorStill = (s.cursorOn && s.cvx * s.cvx + s.cvy * s.cvy < 900) ? cursorStill + dt : 0
        if let st = site {
            let baseGone = st.placed > 0 && !s.balls.contains(where: { $0.id == st.balls[0] })
            if (st.finished >= 0 && s.time - st.finished > 3) || s.time - st.born > 240 || baseGone { site = nil }
        }
        var i = 0
        while i < folks.count {         // по ходу шага могут прийти новые — они добавляются в конец
            var p = folks[i]
            stepPerson(&p, s, dt)
            folks[i] = p
            i += 1
        }
        folks.removeAll { $0.gone }
        if folks.isEmpty { forced = false }
        stepShots(s, dt)
        userBalls(s)
    }

    func gap(_ level: Int) -> Float {
        switch level {
        case 1: return rng.range(360, 720)
        case 3: return rng.range(25, 70)
        default: return rng.range(110, 260)
        }
    }

    func schedule(_ s: Sim) {
        if summonAsked {
            summonAsked = false
            if s.cfg.people == 0 { forced = true }
            startVisit(s, extra: folks.contains(where: { $0.home == -1 }))     // жители не в счёт: гости приходят как обычно
        }
        guard s.cfg.people > 0, !folks.contains(where: { $0.home == -1 }) else { nextVisit = -1; return }
        if nextVisit < 0 {
            nextVisit = s.time + (visited ? gap(s.cfg.people) : rng.range(10, 25))      // первый раз заходят скоро
        } else if s.time >= nextVisit {
            startVisit(s, extra: false)
        }
    }

    func startVisit(_ s: Sim, extra: Bool) {
        let room = min(7 - folks.filter { $0.home == -1 }.count, 12 - folks.count)     // гостей до 7, всего до 12
        guard room > 0 else { return }
        let n = min(room, extra ? 2 : [2, 3, 3, 4][Int(rng.next() % 4)])
        let fromLeft = rng.f() < 0.5
        let split = !extra && n >= 3 && rng.f() < 0.35
        let center = rng.range(s.wPt * 0.25, s.wPt * 0.75)
        var offL: Float = 14, offR: Float = 14
        for k in 0..<n {
            let left = split ? (k % 2 == 0) : fromLeft
            var p = Person(id: nextId, look: makeLook(kid: rng.f() < 0.3, girl: rng.f() < 0.45))
            nextId += 1
            if left { p.x = -offL; offL += rng.range(20, 44) } else { p.x = s.wPt + offR; offR += rng.range(20, 44) }
            p.y = surface(s, x: left ? 2 : s.wPt - 2, stand: -2) ?? s.hPt
            p.face = left ? 1 : -1
            p.job = .arrive
            p.goalX = clampX(center + rng.range(-55, 55) * u, s)
            folks.append(p)
        }
        if !extra {
            visitEnd = s.time + rng.range(100, 190)
            visitStart = s.time
            settleWish = s.cfg.peopleStay && rng.f() < 0.5
            planned = false
            visited = true
        }
    }

    func makeLook(kid: Bool = false, girl: Bool = false) -> Look {
        let bright: [SIMD3<Float>] = [
            SIMD3(0.87, 0.23, 0.24), SIMD3(0.96, 0.56, 0.16), SIMD3(0.97, 0.80, 0.22), SIMD3(0.27, 0.70, 0.38),
            SIMD3(0.14, 0.66, 0.70), SIMD3(0.24, 0.47, 0.90), SIMD3(0.60, 0.38, 0.84), SIMD3(0.94, 0.46, 0.67)]
        let pants: [SIMD3<Float>] = [SIMD3(0.25, 0.29, 0.45), SIMD3(0.35, 0.37, 0.43), SIMD3(0.42, 0.31, 0.27), SIMD3(0.20, 0.35, 0.40)]
        let skins: [SIMD3<Float>] = [SIMD3(1.0, 0.85, 0.74), SIMD3(0.96, 0.77, 0.63), SIMD3(0.68, 0.49, 0.38)]
        let j = Int(rng.next() % 8)
        var h = Int(rng.next() % 8)
        if h == j { h = (h + 3) % 8 }
        var sc = Int(rng.next() % 8)
        while sc == j || sc == h { sc = (sc + 1) % 8 }
        func c(_ v: SIMD3<Float>, _ k: Float = 1) -> SIMD4<Float> { SIMD4(min(1, v.x * k), min(1, v.y * k), min(1, v.z * k), 1) }
        var pal = [SIMD4<Float>](repeating: SIMD4(0, 0, 0, 1), count: 20)
        let kind = girl ? (rng.next() & 1 == 0 ? 0 : 3) : Int(rng.next() % 4)
        let hair: [SIMD3<Float>] = [SIMD3(0.36, 0.22, 0.12), SIMD3(0.86, 0.66, 0.30), SIMD3(0.72, 0.30, 0.14), SIMD3(0.16, 0.13, 0.12)]
        pal[Int(cHair)] = c(hair[Int(rng.next() % 4)])
        pal[Int(cWood)] = SIMD4(0.47, 0.31, 0.18, 1)
        pal[Int(cMetal)] = SIMD4(0.72, 0.76, 0.82, 1)
        pal[Int(cSkin)] = c(skins[Int(rng.next() % 3)])
        pal[Int(cEye)] = SIMD4(0.10, 0.10, 0.17, 1)
        pal[Int(cHat)] = c(bright[h])
        pal[Int(cHat2)] = kind == 1 ? SIMD4(0.93, 0.90, 0.84, 1) : c(bright[h], 0.76)
        pal[Int(cPom)] = rng.f() < 0.5 ? SIMD4(0.98, 0.98, 1, 1) : c(bright[sc])
        pal[Int(cJacket)] = c(bright[j])
        pal[Int(cJacketD)] = c(bright[j], 0.78)
        pal[Int(cSleeve)] = c(bright[j], 0.88)
        pal[Int(cScarf)] = c(bright[sc])
        pal[Int(cMitten)] = rng.f() < 0.5 ? c(bright[h]) : c(bright[sc], 0.9)
        pal[Int(cPants)] = c(pants[Int(rng.next() % 4)])
        pal[Int(cBoots)] = SIMD4(0.13, 0.12, 0.17, 1)
        pal[Int(cSnow)] = SIMD4(0.97, 0.985, 1, 1)
        pal[Int(cSnowD)] = SIMD4(0.80, 0.86, 0.96, 1)
        pal[Int(cMouth)] = SIMD4(0.55, 0.18, 0.20, 1)
        return Look(pal: pal, hatKind: kind, kid: kid, girl: girl)
    }

    /// Какие окна стоят на месте и как давно.
    func trackWindows(_ s: Sim, _ dt: Float) {
        boxAcc += dt
        guard boxAcc >= 0.2 else { return }
        var seen = Set<Int>()
        for b in s.windowBoxes {
            seen.insert(b.win)
            if let o = boxes[b.win], abs(o.box.x0 - b.x0) < 0.6, abs(o.box.x1 - b.x1) < 0.6,
               abs(o.box.y0 - b.y0) < 0.6, abs(o.box.y1 - b.y1) < 0.6 {
                boxes[b.win]!.still += boxAcc
            } else {
                boxes[b.win] = (b, 0)
            }
        }
        if boxes.count != seen.count { boxes = boxes.filter { seen.contains($0.key) } }
        boxAcc = 0
    }

    // Dock. Когда он выезжает, Sim поднимает на него весь снег с пола в его полосе (liftFloor), пока он
    // едет — двигает его карниз (shiftPile), прячется — опускает снег обратно (dropDock). Всё, что стоит
    // на этом снегу — человечки, дома, костры, палочки, — едет вместе с ним (`dockMoved`), а опорой
    // «пола» в полосе Dock считается его верх (`pile`). У Dock во всю ширину экрана это весь пол.

    /// Dock выехал (dy < 0) или спрятался (dy > 0) и повёз снег на участке x0…x1 (Sim.liftFloor, Sim.dropDock).
    func floorShifted(_ s: Sim, x0: Float, x1: Float, dy: Float) {
        let base = dy < 0 ? Float(s.H) * s.cell : (s.segs.first(where: { $0.kind == 2 })?.y ?? Float(s.H) * s.cell + dy)
        dockMoved(s, x0: x0, x1: x1, baseY: base, dy: dy)
    }

    /// Снег на Dock в полосе x0…x1, лежавший на высоте baseY, сдвинулся на dy — и всё, что на нём стоит.
    func dockMoved(_ s: Sim, x0: Float, x1: Float, baseY: Float, dy: Float) {
        guard dy != 0, dockStamp != s.time else { return }
        dockStamp = s.time
        for i in folks.indices where folks[i].stand == -2 && folks[i].x > x0 && folks[i].x < x1 && folks[i].y < baseY + 8
            && (folks[i].mode == .ground || folks[i].mode == .crawl || folks[i].mode == .inside) {
            folks[i].y += dy
        }
        for k in graves.indices where graves[k].stand == -2 && graves[k].x > x0 && graves[k].x < x1 { graves[k].topY += dy }
        for k in igloos.indices where igloos[k].x > x0 && igloos[k].x < x1 {
            var g = igloos[k]
            clearMask(&g, s)            // купол как опора для снега переедет вместе с домом (поставится заново на шаге)
            g.baseY += dy
            igloos[k] = g
        }
        for k in fires.indices where fires[k].x > x0 && fires[k].x < x1 { fires[k].y += dy }
        for k in s.balls.indices where s.balls[k].held && s.balls[k].x > x0 && s.balls[k].x < x1 { s.balls[k].y += dy }   // шар в руках у человечка
        // ходы и ступеньки из ям привязаны к строкам сетки — их записи больше не годятся (сам снег переехал целым)
        stepWorks.removeAll { Float($0.wallCol) * s.cell > x0 - 60 && Float($0.wallCol) * s.cell < x1 + 60 }
        tunnels.removeAll { Float($0.c1 + 1) * s.cell > x0 && Float($0.c0) * s.cell < x1 }
        dock = nil      // до следующего шага неизвестно, где он
    }

    /// Над столбцом сейчас поднят Dock: пока он не спрячется, ничего нового здесь не начинают.
    func inDock(_ s: Sim, _ c: Int) -> Bool {
        guard let d = dock else { return false }
        let x = (Float(c) + 0.5) * s.cell
        return x > d.x0 - 6 && x < d.x1 + 6
    }

    /// Окно сдвинулось вместе со своим сугробом (см. Sim.shiftPile): человечки на нём едут с ним.
    func pileShifted(_ s: Sim, _ seg: Ledge, dx: Float, dy: Float) {
        if seg.kind == 2 {      // Dock едет: стоящие на нём числятся стоящими на полу
            dockMoved(s, x0: seg.x0, x1: seg.x1, baseY: seg.y, dy: dy)
            return
        }
        for i in folks.indices where folks[i].mode == .ground && folks[i].stand == seg.win && folks[i].stamp != s.time
            && folks[i].x >= seg.x0 - 4 && folks[i].x <= seg.x1 + 4 {
            folks[i].x += dx
            folks[i].y += dy
            folks[i].stamp = s.time
        }
    }

    // MARK: - Сетка

    /// Высота сугроба над строкой base в столбце c.
    /// Строка, на которой лежит снег «пола» в столбце c: низ экрана, а в полосе поднятого Dock — его верх.
    func floorBottom(_ s: Sim, _ c: Int) -> Int {
        if let d = dock {
            let x = (Float(c) + 0.5) * s.cell
            if x >= d.x0 && x <= d.x1 { return ledgeRow(s, d, c) }
        }
        return s.H
    }

    /// Для пола (base == s.H) в полосе поднятого Dock опора — его верх: высота считается от низа экрана
    /// вместе с самим Dock, так что `s.H - pile(...)` по-прежнему строка верхней ячейки снега.
    func pile(_ s: Sim, _ c: Int, _ base: Int) -> Int {
        if base >= s.H, let d = dock {
            let x = (Float(c) + 0.5) * s.cell
            if x >= d.x0 && x <= d.x1 {
                let b = ledgeRow(s, d, c)
                return s.snowHeight(c, b) + (s.H - b)
            }
        }
        return s.snowHeight(c, base)
    }

    /// Эта ячейка — часть чьих-то ступеней: из них снег не берут.
    func isStair(_ s: Sim, _ c: Int, _ r: Int) -> Bool {
        for L in ladders where s.H - r <= stairH(L, c) { return true }
        for w in stepWorks {
            let d = (w.wallCol - c) * w.dir - 1
            if d >= 0 && d < 60 && r >= w.topRow + (d / w.run + 1) * w.rise { return true }
        }
        if wallTop >= 0 && c >= wallCol && c <= wallCol + 2 && r >= wallTop { return true }    // стенка от ветра
        return false
    }

    /// Строка карниза в столбце c (у скруглённого угла окна она ниже верхнего края).
    func ledgeRow(_ s: Sim, _ seg: Ledge, _ c: Int) -> Int {
        let r0 = max(1, min(s.H - 1, Int((seg.y * s.inv).rounded())))
        guard c >= 0, c < s.W else { return r0 }
        for k in 0...(Int(seg.r * s.inv) + 2) {
            let r = r0 + k
            if r >= s.H { break }
            let v = s.ledge[r * s.W + c]
            if v == 1 || v == 2 { return r }
        }
        return r0
    }

    func segFor(_ s: Sim, win: Int, x: Float) -> Ledge? {
        s.segs.first(where: { $0.win == win && x >= $0.x0 - 3 && x <= $0.x1 + 3 })
    }

    /// Верх снега под ногами в точке x. nil — опоры больше нет (окно ушло).
    func surface(_ s: Sim, x: Float, stand: Int) -> Float? {
        let c = max(0, min(s.W - 1, Int(x * s.inv)))
        if stand == -2 {
            var sum = 0, n = 0
            for k in max(0, c - 1)...min(s.W - 1, c + 1) { sum += pile(s, k, s.H); n += 1 }
            return (Float(s.H) - Float(sum) / Float(n)) * s.cell
        }
        guard let seg = segFor(s, win: stand, x: x) else { return nil }
        let row = ledgeRow(s, seg, c)
        return Float(row - pile(s, c, row)) * s.cell
    }

    /// Снять верхние ячейки снега вокруг x (не больше per из столбца). Утоптанное не трогает.
    func scoop(_ s: Sim, x: Float, stand: Int, want: Int, half: Int, per: Int = 2) -> Int {
        let c = Int(x * s.inv)
        var seg: Ledge? = nil
        if stand != -2 {
            seg = segFor(s, win: stand, x: x)
            if seg == nil { return 0 }
        }
        var got = 0
        var rMin = s.H, rMax = 0
        for k in 0...(half * 2) {
            if got >= want { break }
            let col = c + (k + 1) / 2 * (k % 2 == 0 ? -1 : 1)
            guard col >= 0, col < s.W else { continue }
            let base = seg != nil ? ledgeRow(s, seg!, col) : s.H
            for _ in 0..<per {
                if got >= want { break }
                let h = pile(s, col, base)
                if h == 0 { break }
                let i = (base - h) * s.W + col
                if i < 0 || s.snow[i] == 0 || (seg == nil && (isStair(s, col, base - h) || reserved(s, col))) { break }
                s.snow[i] = 0
                rMin = min(rMin, base - h); rMax = max(rMax, base - h)
                got += 1
            }
        }
        if got > 0 {
            s.gridDirty = true
            s.snowDisturbed(c - half - 1, rMin - 2, c + half + 1, rMax + 1)
        }
        return got
    }

    func chunk(_ s: Sim, _ x: Float, _ y: Float, _ vx: Float, _ vy: Float, hard: UInt8 = 0) {
        guard s.parts.count < s.maxParts else { return }
        s.parts.append(Particle(x: x, y: y, vx: vx, vy: vy, fall: 0, phase: 0, size: s.cell, alpha: 1, kind: 1,
                                shade: rng.shade(), passer: false, ghost: 0.06, hard: hard))
    }

    /// Снежная пыль: обычные снежинки, которые разлетаются и тают.
    func dust(_ s: Sim, _ x: Float, _ y: Float) {
        guard s.parts.count < s.maxParts else { return }
        let e = rng.f()
        s.parts.append(Particle(x: x, y: y, vx: rng.range(-40, 40), vy: rng.range(-30, 30), fall: rng.range(18, 40),
                                phase: rng.range(0, 6.28), size: 2.5 + e * 2.5, alpha: 0.45 + e * 0.4, kind: 0, shade: 1,
                                passer: true, ghost: 0, drift: rng.range(-8, 8)))
    }

    /// Облачко снега из-под ног.
    func puff(_ s: Sim, _ x: Float, _ y: Float, n: Int, stand: Int) {
        let got = scoop(s, x: x, stand: stand, want: n, half: 3, per: 1)
        for _ in 0..<got { chunk(s, x + rng.range(-6, 6), y - 3, rng.range(-90, 90), -rng.range(60, 190)) }
    }

    func clampX(_ x: Float, _ s: Sim) -> Float { max(14, min(s.wPt - 14, x)) }

    // MARK: - Движение

    func next(_ p: inout Person, _ phase: Int) { p.phase = phase; p.t = 0; p.flag = false }
    func idle(_ p: inout Person, _ wait: Float) { p.job = .idle; p.wait = wait; next(&p, 0) }

    /// Всё, что было в руках, бросает; с лестницы и со стройки снеговика выбывает.
    func release(_ p: inout Person, _ s: Sim) {
        if p.carry > 0 {
            for _ in 0..<min(p.carry, 24) {
                chunk(s, p.x + rng.range(-4, 4), p.y - 9 * u + rng.range(-4, 4), rng.range(-60, 60), -rng.range(20, 120))
            }
            p.carry = 0
        }
        if p.job == .snowman, var st = site, p.stage < 3, st.owner[p.stage] == p.id, st.balls[p.stage] == -1 {
            st.owner[p.stage] = -1
            site = st
        }
        if p.ball != -1 {
            if s.heldId != p.ball, let bi = s.balls.firstIndex(where: { $0.id == p.ball }) { s.balls[bi].held = false }
            p.ball = -1
        }
        for k in ladders.indices where !ladders[k].lifters.isEmpty { ladders[k].lifters.removeAll { $0 == p.id } }
    }

    func drop(_ p: inout Person, _ s: Sim) {
        release(&p, s)
        p.mode = .air
        p.vx = p.face * 12
        p.vy = 0
    }

    /// Ноги следуют за поверхностью; если опоры нет — человечек падает.
    // Как ходят. Опора — то, что на самом деле под ногами (`ground`), а не верх сугроба: в пещере
    // это её пол, под низким сводом человечек ползёт. Шагнуть можно на высоту `stepMax` (по колено),
    // вскарабкаться — на `climbMax` (по грудь). Стенку выше не одолеть: `walk` копит `blockT`,
    // и человечек принимается выбираться (см. `startSteps`): зовёт на помощь и утаптывает ступеньки.

    func solid(_ s: Sim, _ c: Int, _ r: Int) -> Bool {
        if r >= s.H { return true }
        if c < 0 || c >= s.W || r < 0 { return false }
        return s.snow[r * s.W + c] != 0 || s.ledge[r * s.W + c] != 0
    }

    /// Низ иглу, перед которым проходит точка x (nil — здесь дома нет). Снег, насыпанный на купол,
    /// для идущего мимо не препятствие: он идёт перед домом.
    func iglooBase(_ x: Float) -> Float? {
        for g in igloos where abs(x - g.x) < 18 * u { return g.baseY }
        return nil
    }

    /// Высота шага: по колено, но не меньше ступени лестницы.
    func stepMax(_ s: Sim) -> Float { max(4 * u, (Float(max(1, Int((8 / s.cell).rounded()))) + 0.3) * s.cell) }
    func climbMax(_ p: Person) -> Float { 0.7 * p.tall * u }

    /// Опора под ногами в столбце x для того, чьи ноги на высоте feet и кто может подняться на up.
    /// nil — там стенка выше.
    func ground(_ s: Sim, x: Float, feet: Float, up: Float) -> Float? {
        if let by = iglooBase(x), abs(feet - by) < 30 * u { return by }     // мимо дома идут перед ним, по его основанию
        let c = max(0, min(s.W - 1, Int(x * s.inv)))
        let top = max(0, Int(((feet - up) * s.inv).rounded(.up)))
        if top >= 1 && solid(s, c, top - 1) { return nil }
        var r = top
        while r < s.H && !solid(s, c, r) { r += 1 }
        return Float(r) * s.cell
    }

    /// Сколько свободного места над опорой gy в столбце x (не больше limit), pt.
    func headroom(_ s: Sim, x: Float, over gy: Float, limit: Float) -> Float {
        if iglooBase(x) != nil { return limit }
        let c = max(0, min(s.W - 1, Int(x * s.inv)))
        var r = Int((gy * s.inv).rounded()) - 1
        var n = 0
        let maxN = Int(limit * s.inv) + 1
        while r >= 0 && n < maxN && !solid(s, c, r) { n += 1; r -= 1 }
        return r < 0 ? limit : Float(n) * s.cell
    }

    /// Ноги следуют за опорой. fast — идёт сам; стоящего на месте поднимает медленно, а если снега
    /// насыпало выше колен — он остаётся в нём (не завалило ли — решает PeopleRescue).
    func settle(_ p: inout Person, _ s: Sim, _ dt: Float, fast: Bool = false) {
        if p.stand != -2 && segFor(s, win: p.stand, x: p.x) == nil { drop(&p, s); return }   // окно ушло
        guard let gy = ground(s, x: p.x, feet: p.y, up: stepMax(s)) else { return }
        let d = gy - p.y
        if d > 14 * u { drop(&p, s); return }       // под ногами обрыв
        p.y += max(-(fast ? 40 : 6) * u * dt, min(80 * u * dt, d))
    }

    /// Идти к gx по тому, что под ногами. true — дошёл.
    func walk(_ p: inout Person, _ s: Sim, to gx: Float, speed: Float, _ dt: Float) -> Bool {
        let dx = gx - p.x
        if abs(dx) < 1.5 {
            p.anim = p.carry > 3 ? .carry : .stand
            settle(&p, s, dt, fast: true)
            return true
        }
        p.face = dx > 0 ? 1 : -1
        var step = min(abs(dx), speed * dt)
        let ax = p.x + p.face * max(step, 1.5 * u)
        let onEdge = p.stand != -2 && segFor(s, win: p.stand, x: ax) == nil      // дальше карниз кончается
        if !onEdge {
            guard let ga = ground(s, x: ax, feet: p.y, up: climbMax(p)),
                  headroom(s, x: ax, over: ga, limit: 8 * u) >= 6 * u else {
                p.blockT += dt                      // стенка выше груди или лаз слишком низкий
                p.blockAt = s.time
                p.blockDir = p.face
                p.anim = .stand
                settle(&p, s, dt)
                return false
            }
            if p.y - ga > stepMax(s) {              // вскарабкаться: сначала подтянуться, потом шагнуть
                p.anim = .climb
                p.walkPhase += dt * 3
                p.y -= 16 * u * dt
                if p.y <= ga + stepMax(s) * 0.5 { p.x += p.face * min(step, s.cell) }
                return false
            }
        }
        if p.low { step *= 0.5 }
        if s.wind.storm > 0.2 { step *= 1 - 0.55 * s.wind.storm * (p.face * s.wind.dir < 0 ? 1 : -0.3) }     // против бурана идти тяжело
        p.x += p.face * step
        p.walkPhase += step / (4.5 * u)
        p.anim = p.carry > 3 ? .carry : (speed > 30 * u ? .run : .walk)
        settle(&p, s, dt, fast: true)
        return false
    }

    // MARK: - Выбраться из ямы

    /// Упёрся в стенку выше роста. Если над стенкой небо — зовёт на помощь и утаптывает вдоль неё
    /// снежные ступеньки (`StepWork`); если зажат под сводом или стенка слишком высока — прорубает
    /// ступеньки сам (`carve`).
    func startSteps(_ p: inout Person, _ s: Sim) {
        let dir = p.blockDir >= 0 ? 1 : -1
        let was = p.job
        release(&p, s)
        p.resume = was == .arrive || was == .leave ? was : .idle
        p.job = .steps
        p.obj = -1
        p.face = Float(dir)
        next(&p, 10)                                // по умолчанию — прорубаться
        // стенка: первый столбец впереди, где на уровне груди снег
        let feetRow = Int((p.y * s.inv).rounded())
        let c0 = max(0, min(s.W - 1, Int(p.x * s.inv)))
        var wc = -1
        for k in 1...6 {
            let c = c0 + dir * k
            if c < 1 || c >= s.W - 1 { break }
            if solid(s, c, feetRow - Int(climbMax(p) * s.inv) - 1) { wc = c; break }
        }
        guard wc >= 0 else { return }
        // у этой стенки уже утаптывают ступеньки — помочь
        if let w = stepWorks.first(where: { $0.stand == p.stand && $0.dir == dir && abs($0.wallCol - wc) <= 6 && $0.doneAt < 0 }) {
            p.obj = w.id
            next(&p, 1)
            return
        }
        var r = feetRow - 1                         // верх стенки
        let limit = feetRow - Int(48 * u * s.inv)
        while r >= max(0, limit) && solid(s, wc, r) { r -= 1 }
        guard r >= max(0, limit), r >= 2 else { return }           // слишком высоко или до самого верха экрана
        let bodyRows = Int((p.tall * u * s.inv).rounded(.up))
        for k in 0..<bodyRows where solid(s, wc, r - k) { return } // над стенкой свод, а не небо
        let rise = max(1, Int((8 / s.cell).rounded()))
        var w = StepWork(id: nextObjId, stand: p.stand, wallCol: wc, dir: dir, topRow: r + 1, rise: rise, run: rise, born: s.time)
        let need = stepNeed(s, w)
        guard need > 0, need <= 320 else { return }
        nextObjId += 1
        w.owner = p.id
        stepWorks.append(w)
        p.obj = w.id
        next(&p, 0)
        // позвать на помощь тех, кто рядом и ничем не занят
        var called = 0
        for j in folks.indices where called < 2 && folks[j].id != p.id && !folks[j].gone && folks[j].mode == .ground
            && folks[j].stand == p.stand && abs(folks[j].x - p.x) < 150 * u {
            let q = folks[j]
            guard q.job == .idle || q.job == .wander || q.job == .gaze || q.job == .cheer || q.job == .fight else { continue }
            folks[j].job = .steps
            folks[j].obj = w.id
            folks[j].resume = .idle
            folks[j].phase = 1; folks[j].t = 0; folks[j].flag = false
            called += 1
        }
    }

    /// Где должен быть верх ступеньки в столбце на расстоянии d от стенки (строка).
    func stepTop(_ w: StepWork, _ d: Int) -> Int { w.topRow + (d / w.run + 1) * w.rise }

    /// Сколько ячеек ещё не хватает до готовых ступенек.
    func stepNeed(_ s: Sim, _ w: StepWork) -> Int {
        var need = 0
        for d in 0..<60 {
            let c = w.wallCol - w.dir * (d + 1)
            let t = stepTop(w, d)
            if c < 0 || c >= s.W || t >= s.H { break }
            var r = t
            var n = 0
            while r < s.H && !solid(s, c, r) { n += 1; r += 1 }
            if n == 0 { break }                      // дно здесь уже не ниже ступеньки
            need += n
        }
        return need
    }

    /// Утоптать до n ячеек в ступеньки: слоями снизу вверх, в каждом слое — от стенки.
    func placeSteps(_ s: Sim, _ w: StepWork, _ n: Int) -> Int {
        var used = 0
        while used < n {
            var bestI = -1, bestR = -1
            for d in 0..<60 {
                let c = w.wallCol - w.dir * (d + 1)
                let t = stepTop(w, d)
                if c < 0 || c >= s.W || t >= s.H { break }
                var bottom = t
                while bottom < s.H && !solid(s, c, bottom) { bottom += 1 }
                if bottom == t { break }            // дно здесь уже не ниже ступеньки
                if bottom - 1 > bestR { bestR = bottom - 1; bestI = (bottom - 1) * s.W + c }
            }
            guard bestI >= 0 else { break }
            s.snow[bestI] = rng.shade()
            s.hard[bestI] = People.packedHard
            used += 1
        }
        if used > 0 {
            s.gridDirty = true
            s.hardDirty = true
            // кто стоял на этом месте — оказывается сверху, а не внутри
            for j in folks.indices where folks[j].mode == .ground && folks[j].stand == w.stand { lift(&folks[j], s) }
        }
        return used
    }

    /// Для самотестов: поставить человечка в точку x на то, что там под ногами на высоте y.
    func debugSpawn(_ s: Sim, x: Float, y: Float, kid: Bool = false) -> Int32 {
        var p = Person(id: nextId, look: makeLook(kid: kid, girl: rng.f() < 0.5))
        nextId += 1
        p.x = x
        p.y = ground(s, x: x, feet: y, up: 0) ?? y
        idle(&p, 0.5)
        folks.append(p)
        visitEnd = max(visitEnd, s.time + 200)
        return p.id
    }

    /// Если ноги оказались внутри снега, который только что уложили, — встать на него.
    func lift(_ p: inout Person, _ s: Sim) {
        let c = max(0, min(s.W - 1, Int(p.x * s.inv)))
        var r = Int((p.y * s.inv).rounded()) - 1
        var n = 0
        while r >= 0 && n < 40 && solid(s, c, r) { r -= 1; n += 1 }
        if n > 0 && n < 40 { p.y = Float(r + 1) * s.cell }
    }

    /// Прорубить ступеньку в стенке впереди: проход в рост человечка, пол — на шаг выше ног.
    /// false — рубить нечего или нельзя (карниз окна, чужая постройка).
    func carve(_ p: inout Person, _ s: Sim) -> Bool {
        let dir = p.face >= 0 ? 1 : -1
        let feetRow = Int((p.y * s.inv).rounded())
        let stepRows = max(1, Int(stepMax(s) * s.inv))
        let bodyRows = Int((p.tall * u * s.inv).rounded(.up)) + 1
        let c0 = max(0, min(s.W - 1, Int(p.x * s.inv)))
        var cut = 0
        var rigid = false
        let half = max(1, Int((2 * u * s.inv).rounded()))
        for k in 1...(half + 1) {
            let c = c0 + dir * k
            if c < 0 || c >= s.W { rigid = true; break }
            for r in (feetRow - stepRows - bodyRows)..<(feetRow - stepRows) where r >= 0 && r < s.H {
                let i = r * s.W + c
                if s.ledge[i] != 0 { rigid = true; continue }
                if s.snow[i] == 0 { continue }
                if isStair(s, c, r) || reserved(s, c) || tunnelKeep(s, c, r) { rigid = true; continue }   // не рубить сквозь чужую нору
                s.snow[i] = 0
                cut += 1
                if cut <= 14 {      // выбрасывает снег назад
                    chunk(s, p.x - Float(dir) * rng.range(2, 8), p.y - rng.range(6, 14) * u,
                          -Float(dir) * rng.range(50, 130), -rng.range(40, 140), hard: s.hard[i])
                }
            }
        }
        if cut > 0 {
            s.gridDirty = true
            s.snowDisturbed(c0 - half - 2, feetRow - stepRows - bodyRows - 2, c0 + half + 2, feetRow)
        }
        return cut > 0 || !rigid
    }

    func runSteps(_ p: inout Person, _ s: Sim, _ dt: Float) {
        func done(_ p: inout Person) {
            release(&p, s)
            p.blockT = 0
            if p.resume == .arrive || p.resume == .leave { p.job = p.resume; next(&p, 0) } else { idle(&p, 0.4) }
        }
        if p.phase >= 10 {      // прорубается сам
            switch p.phase {
            case 10:
                p.anim = .dig
                settle(&p, s, dt)
                if p.t > 0.45 {
                    if !carve(&p, s) { done(&p); return }           // дальше не прорубить
                    p.tries += 1
                    next(&p, 11)
                }
            default:
                let before = p.blockT
                p.blockT = 0
                _ = walk(&p, s, to: p.x + p.face * 3 * s.cell, speed: 14 * u, dt)
                if p.mode != .ground { return }
                if p.blockT > 0 { p.blockT = before; next(&p, 10) }  // снова стенка — рубить дальше
                else if p.t > 0.5 {
                    // вышел на открытое место (над головой небо и впереди не стенка) — хватит
                    if ground(s, x: p.x + p.face * 3 * u, feet: p.y, up: climbMax(p)) != nil
                        && headroom(s, x: p.x, over: p.y, limit: 40 * u) >= 39 * u { done(&p) }
                    else if p.tries > 60 { done(&p) }
                    else { next(&p, 11) }
                }
            }
            return
        }
        guard let k = stepWorks.firstIndex(where: { $0.id == p.obj }) else { done(&p); return }
        let w = stepWorks[k]
        let wallX = (Float(w.wallCol) + 0.5) * s.cell
        if stepNeed(s, w) == 0 {                    // готово: ступеньки до самого верха
            stepWorks[k].doneAt = s.time
            if w.owner == p.id {                    // тот, кто застрял, поднимается по ним наверх
                if walk(&p, s, to: wallX + Float(w.dir) * 6 * u, speed: 20 * u, dt) || p.t > 12 {
                    p.job = .cheer; p.wait = 1.2; next(&p, 0)
                    if p.resume == .arrive || p.resume == .leave { p.job = p.resume; p.flag = false }
                }
            } else {
                p.job = .cheer; p.wait = 1.2; next(&p, 0)
            }
            return
        }
        if s.time - w.born > 90 {                   // не вышло — прорубаться
            if w.owner == p.id { p.obj = -1; p.face = Float(w.dir); next(&p, 10) } else { done(&p) }
            return
        }
        switch p.phase {
        case 0:     // зовёт на помощь
            p.anim = .panic
            p.face = Int(p.t * 4) & 1 == 0 ? 1 : -1
            settle(&p, s, dt)
            if p.t > 1.1 { next(&p, 1) }
        case 1:     // отойти от стенки туда, где есть снег
            if !p.flag {
                p.flag = true
                p.goalX = clampX(wallX - Float(w.dir) * rng.range(14, 34) * u, s)
            }
            if walk(&p, s, to: p.goalX, speed: 24 * u, dt) || p.t > 2.5 || p.blockT > 0.3 { p.blockT = 0; next(&p, 2) }
        case 2, 3:  // два гребка
            p.anim = .scoop
            settle(&p, s, dt)
            if p.t > 0.25 && !p.flag {
                p.flag = true
                p.carry += scoop(s, x: p.x - Float(w.dir) * 2 * u, stand: p.stand, want: 8, half: p.phase == 2 ? 4 : 7)
            }
            if p.t > 0.45 {
                if p.phase == 2 { next(&p, 3) }
                else if p.carry >= 4 { p.tries = 0; next(&p, 4) }
                else { p.tries += 1; if p.tries > 4 { stepWorks[k].born = -1000 }; next(&p, 1) }    // снега нет
            }
        case 4:     // к стенке
            if walk(&p, s, to: wallX - Float(w.dir) * 5 * u, speed: 22 * u, dt) || p.t > 4 || p.blockT > 0.3 { p.blockT = 0; next(&p, 5) }
        default:    // утоптать
            p.anim = .pat
            p.face = Float(w.dir)
            settle(&p, s, dt)
            if p.t > 0.2 && !p.flag {
                p.flag = true
                p.carry -= placeSteps(s, w, p.carry)
                lift(&p, s)
                if p.carry > 0 { release(&p, s) }
            }
            if p.t > 0.45 { next(&p, 1) }
        }
    }

    // MARK: - Буран

    /// Пережидает буран. На полу сбиваются в кучку с подветренной стороны чего-нибудь высокого
    /// (иглу, насыпь) или просто вместе, спиной к ветру; первые двое лепят стенку от ветра.
    /// На окне — садятся на корточки там, где стоят.
    func runShelter(_ p: inout Person, _ s: Sim, _ dt: Float) {
        let wdir: Float = s.wind.dir >= 0 ? 1 : -1
        if s.wind.storm < 0.4 {                     // стихает — отряхнуться и за дела
            p.snowHat = 4
            p.job = .cheer
            p.wait = 1
            next(&p, 0)
            return
        }
        if p.stand != -2 {
            p.anim = .huddle
            p.face = wdir
            settle(&p, s, dt)
            return
        }
        if shelterX < 0 {                           // выбрать место: за иглу, иначе там, где стоит большинство
            if let ig = igloos.min(by: { abs($0.x - p.x) < abs($1.x - p.x) }), abs(ig.x - p.x) < 250 * u {
                shelterX = clampX(ig.x + wdir * 24 * u, s)
            } else {
                let mine = folks.filter { $0.stand == -2 && !$0.gone && $0.mode == .ground && !$0.away }
                shelterX = clampX(mine.isEmpty ? p.x : mine.reduce(0) { $0 + $1.x } / Float(mine.count), s)
            }
        }
        let slot = shelterX + wdir * Float(Int(p.id) % 6) * 7.5 * u
        switch p.phase {
        case 0:
            if walk(&p, s, to: slot, speed: 30 * u, dt) || p.t > 12 || p.blockT > 0.4 { p.blockT = 0; next(&p, 1) }
        case 1:
            p.anim = .huddle
            p.face = wdir
            settle(&p, s, dt)
            // стенка от ветра: её лепят, пока не дорастёт
            let builders = folks.filter { $0.job == .shelter && $0.phase >= 2 && !$0.gone }.count
            if p.t > 1.5 && builders < 2 && !igloos.contains(where: { abs($0.x - shelterX) < 40 * u }) && wallNeed(s) > 0 { next(&p, 2) }
        case 2:     // набрать снега с подветренной стороны
            if walk(&p, s, to: clampX(shelterX + wdir * rng.range(10, 22) * u, s), speed: 22 * u, dt) || p.t > 3 || p.blockT > 0.3 { p.blockT = 0; next(&p, 3) }
        case 3:
            p.anim = .scoop
            settle(&p, s, dt)
            if p.t > 0.25 && !p.flag { p.flag = true; p.carry += scoop(s, x: p.x + wdir * 2 * u, stand: -2, want: 10, half: 5) }
            if p.t > 0.5 { next(&p, p.carry > 0 ? 4 : 1) }
        case 4:     // отнести к стенке
            if walk(&p, s, to: (Float(wallCol) + 0.5) * s.cell + wdir * 5 * u, speed: 20 * u, dt) || p.t > 4 || p.blockT > 0.3 { p.blockT = 0; next(&p, 5) }
        default:
            p.anim = .pat
            p.face = -wdir
            settle(&p, s, dt)
            if p.t > 0.2 && !p.flag {
                p.flag = true
                p.carry -= placeWall(s, p.carry)
                if p.carry > 0 { release(&p, s) }
            }
            if p.t > 0.45 { next(&p, wallNeed(s) > 0 ? 2 : 1) }
        }
    }

    /// Стенка от ветра: три столбца с наветренной стороны кучки, высотой человечку по плечи.
    func wallNeed(_ s: Sim) -> Int {
        guard shelterX >= 0 else { return 0 }
        let wdir = s.wind.dir >= 0 ? 1 : -1
        if wallTop < 0 {
            wallCol = max(2, min(s.W - 5, Int((shelterX - Float(wdir) * 9 * u) * s.inv)))
            var top = s.H
            for c in wallCol...(wallCol + 2) {
                var r = 0
                while r < s.H && !solid(s, c, r) { r += 1 }
                top = min(top, r)
            }
            wallTop = max(2, top - Int((11 * u * s.inv).rounded()))
        }
        var need = 0
        for c in wallCol...(wallCol + 2) where c >= 0 && c < s.W {
            var r = wallTop
            while r < s.H && !solid(s, c, r) { need += 1; r += 1 }
        }
        return need
    }

    func placeWall(_ s: Sim, _ n: Int) -> Int {
        guard wallTop >= 0 else { return 0 }
        var used = 0
        while used < n {
            var bestI = -1, bestR = -1
            for c in wallCol...(wallCol + 2) where c >= 0 && c < s.W {
                var r = wallTop
                while r < s.H && !solid(s, c, r) { r += 1 }
                if r - 1 >= wallTop && r - 1 > bestR { bestR = r - 1; bestI = (r - 1) * s.W + c }
            }
            guard bestI >= 0 else { break }
            s.snow[bestI] = rng.shade()
            s.hard[bestI] = People.packedHard
            used += 1
        }
        if used > 0 {
            s.gridDirty = true
            s.hardDirty = true
            for j in folks.indices where folks[j].mode == .ground && folks[j].stand == -2 { lift(&folks[j], s) }
        }
        return used
    }

    func stepAir(_ p: inout Person, _ s: Sim, _ dt: Float) {
        p.anim = .flail
        p.vy += 900 * dt
        let prevY = p.y
        p.x = max(4, min(s.wPt - 4, p.x + p.vx * dt))
        p.y += p.vy * dt
        guard p.vy > 0 else { return }
        var best: (y: Float, stand: Int)? = nil
        if let fy = surface(s, x: p.x, stand: -2), p.y >= fy { best = (fy, -2) }
        for seg in s.segs where p.x >= seg.x0 && p.x <= seg.x1 {
            guard let sy = surface(s, x: p.x, stand: seg.win) else { continue }
            if prevY <= sy + 2 && p.y >= sy && (best == nil || sy < best!.y) { best = (sy, seg.win) }
        }
        guard let b = best else { return }
        let impact = p.vy
        p.y = b.y; p.stand = b.stand; p.mode = .ground
        p.vx = 0; p.vy = 0
        if impact > 300 {
            puff(s, p.x, p.y, n: 5, stand: b.stand)
            p.job = .hit
            next(&p, 2)
            p.wait = rng.range(0.8, 1.4)
            p.fallDir = p.face
            p.anim = .down
        } else {
            idle(&p, 0.4)
            p.anim = .getup
        }
    }

    /// Прыжок по дуге из hop0 в hop1. true — допрыгнул.
    func hop(_ p: inout Person, dur: Float) -> Bool {
        let k = min(1, p.t / dur)
        p.x = p.hop0.x + (p.hop1.x - p.hop0.x) * k
        p.y = p.hop0.y + (p.hop1.y - p.hop0.y) * k - sinf(k * .pi) * 5 * u
        p.face = p.hop1.x >= p.hop0.x ? 1 : -1
        p.anim = .hop
        return k >= 1
    }

    /// Лезть по лестнице до высоты h над площадкой. true — долез.
    func climb(_ p: inout Person, _ s: Sim, _ L: Ladder, toH h: Float, speed: Float, _ dt: Float) -> Bool {
        let plat = platformY(L, s)
        p.x = footX(L, s)
        let d = h - (plat - p.y)
        if abs(d) < 1 { p.y = plat - h; p.anim = .hang; return true }
        let st = min(abs(d), speed * dt * (1 - 0.6 * windStorm))     // в буран по лестнице лезут медленно, цепляясь
        p.y -= d > 0 ? st : -st
        p.walkPhase += st / (4 * u)
        p.anim = .climb
        return false
    }

    /// Держится ли ещё лестница под руками и ногами.
    func grip(_ p: Person, _ s: Sim, _ L: Ladder) -> Bool {
        let h = platformY(L, s) - p.y
        if h < footH(L, s) + 2 * s.cell { return true }       // ещё стоит на том, с чего лезут
        let lo = max(0, Int(h * s.inv)), hi = min(L.rows.count - 1, Int((h + 12 * u) * s.inv))
        guard lo <= hi else { return true }
        var have = 0, need = 0
        for k in lo...hi {
            let m = mask(L, k)
            need += m.nonzeroBitCount
            have += (L.rows[k] & m).nonzeroBitCount
        }
        return need == 0 || have * 5 >= need * 2
    }

    func fallOff(_ p: inout Person, _ s: Sim, _ L: Ladder?) {
        release(&p, s)
        p.mode = .air
        p.stand = -2
        p.vx = Float(L?.out ?? 0) * rng.range(8, 30)
        p.vy = 0
    }

    // MARK: - Человечек

    func wantLeave(_ s: Sim) -> Bool {
        if s.cfg.people == 0 && !forced { return true }
        if s.time < visitEnd { return false }
        return !(ladders.contains(where: { $0.active }) && s.time < visitEnd + 360)
    }

    func stepPerson(_ p: inout Person, _ s: Sim, _ dt: Float) {
        p.t += dt
        p.snowHat = max(0, p.snowHat - dt)
        p.flinch = max(0, p.flinch - dt)
        p.pokeCD = max(0, p.pokeCD - dt)
        p.waveCD = max(0, p.waveCD - dt)
        p.anim = .stand

        switch p.mode {
        case .air:
            stepAir(&p, s, dt)
            return
        case .ladder:
            let L = ladders.first(where: { $0.id == p.ladder })
            if L == nil || L!.broken || !grip(p, s, L!) { fallOff(&p, s, L); return }
            if let k = ladderIndex(p.ladder) { ladders[k].usedAt = s.time }
        default:
            break
        }
        if p.job != .buried && cursorPoke(&p, s) { return }
        if p.mode == .ground {
            // низкий свод над головой — ползёт
            if let gy = ground(s, x: p.x, feet: p.y, up: stepMax(s)) {
                p.low = headroom(s, x: p.x, over: gy, limit: p.tall * u) < (p.tall - 3) * u
            } else {
                p.low = false
            }
            if p.blockT > 0 && s.time - p.blockAt > 0.3 { p.blockT = 0 }
        } else {
            p.low = false
            p.blockT = 0
        }
        if p.low {              // для проверки завала ползущий занимает меньше места
            p.mode = .crawl
            let buried = rescueGuard(&p, s, dt)
            if buried { return }
            p.mode = .ground
        } else if rescueGuard(&p, s, dt) { return }  // не завалило ли снегом
        // буран: бросают игры и прячутся; на лестнице — вцепляются и ждут
        let storm = s.wind.storm
        if storm > 0.55 {
            if p.mode == .ground && p.job != .shelter {
                let free = p.job == .idle || p.job == .wander || p.job == .fight || p.job == .gaze || p.job == .wave
                    || p.job == .cheer || p.job == .snowman || p.job == .top || p.job == .angel || p.job == .gather
                if free {
                    release(&p, s)
                    if p.home != -1 && p.stand == -2 { p.job = .home; next(&p, 0) }      // жители — домой
                    else if p.stand != -2 || !denShelter(&p, s) { p.job = .shelter; next(&p, 0) }    // рядом нора — в неё, иначе в кучку
                }
            }
        }
        // упёрся в стенку, на которую не влезть
        if p.blockT > 0.5 && p.mode == .ground && p.job != .steps && p.job != .buried && p.job != .hit {
            if p.job == .wander || p.job == .top || p.job == .gaze { p.blockT = 0; idle(&p, 0.5) }   // гулял — пойдёт в другую сторону
            else { startSteps(&p, s) }
        }

        // человечков выключили — все расходятся
        if s.cfg.people == 0 && !forced && p.job != .leave && p.job != .goDown && p.job != .hit && p.mode != .hop
            && p.job != .buried {
            release(&p, s)
            p.home = -1
            if p.mode == .inside || p.mode == .crawl { p.mode = .ground }
            if p.mode == .ladder { p.job = .goDown; next(&p, 2) }
            else { p.job = p.stand == -2 ? .leave : .goDown; next(&p, 0) }
        }

        switch p.job {
        case .arrive:
            if walk(&p, s, to: p.goalX, speed: 44 * u, dt) || p.t > 40 { idle(&p, rng.range(0.2, 1.2)) }
        case .idle:
            settle(&p, s, dt)
            if p.mode != .ground || tryWave(&p, s) { return }
            if p.t >= p.wait { choose(&p, s) }
        case .wander:
            if tryWave(&p, s) { return }
            if walk(&p, s, to: p.goalX, speed: 18 * u, dt) || p.t > 12 { idle(&p, rng.range(0.4, 2)) }
        case .fight: runFight(&p, s, dt)
        case .hit: runHit(&p, s, dt)
        case .snowman: runSnowman(&p, s, dt)
        case .gather: runGather(&p, s, dt)
        case .lift: runLift(&p, s, dt)
        case .goTop: runGoTop(&p, s, dt)
        case .top: runTop(&p, s, dt)
        case .goDown: runGoDown(&p, s, dt)
        case .leave:
            if !p.flag {
                p.flag = true
                release(&p, s)
                p.goalX = p.x < s.wPt * 0.5 ? -50 : s.wPt + 50
            }
            _ = walk(&p, s, to: p.goalX, speed: (s.cfg.people == 0 ? 50 : 30) * u, dt)
            if p.x < -30 || p.x > s.wPt + 30 || p.t > 120 { p.gone = true }
        case .gaze:
            p.anim = .gaze
            settle(&p, s, dt)
            if p.t > p.wait { idle(&p, 0.3) }
        case .wave:
            p.anim = .wave
            settle(&p, s, dt)
            if p.t > 1.5 { idle(&p, 0.2) }
        case .cheer:
            p.anim = .cheer
            settle(&p, s, dt)
            if p.t > p.wait { idle(&p, 0.3) }
        case .buried: runBuried(&p, s, dt)
        case .panic: runPanic(&p, s, dt)
        case .rescue: runRescue(&p, s, dt)
        case .mourn: runMourn(&p, s, dt)
        case .igloo: runIgloo(&p, s, dt)
        case .home: runHome(&p, s, dt)
        case .shovel: runShovel(&p, s, dt)
        case .fire: runFire(&p, s, dt)
        case .tunnel: runTunnel(&p, s, dt)
        case .angel: runAngel(&p, s, dt)
        case .sled: runSled(&p, s, dt)
        case .ride: runRide(&p, s, dt)
        case .tree: runTree(&p, s, dt)
        case .steps: runSteps(&p, s, dt)
        case .shelter: runShelter(&p, s, dt)
        }
    }

    /// Зимние происшествия: время от времени что-нибудь случается само.
    func stepEvents(_ s: Sim, _ dt: Float) {
        guard s.cfg.people > 0, s.cfg.peopleEvents else { nextEvent = -1; return }
        if nextEvent < 0 { nextEvent = s.time + rng.range(50, 140); return }
        guard s.time >= nextEvent else { return }
        nextEvent = s.time + rng.range(70, 200)
        var kinds = [0, 1, 2]
        while !kinds.isEmpty {              // пробуем в случайном порядке, пока что-нибудь не получится
            let k = kinds.remove(at: Int(rng.next() % UInt64(kinds.count)))
            let ok = k == 0 ? avalanche(s) : (k == 1 ? startSled(s) : startTree(s))
            if ok { return }
        }
        nextEvent = s.time + rng.range(20, 50)
    }

    /// «Прогнать всех»: убрать человечков и всё, что они построили (снег в сетке остаётся как есть).
    func clearAll(_ s: Sim) {
        for i in folks.indices { var p = folks[i]; release(&p, s); folks[i] = p }
        folks.removeAll()
        shots.removeAll()
        for k in ladders.indices { var L = ladders[k]; collapse(&L, s); ladders[k] = L }
        site = nil
        graves.removeAll(); igloos.removeAll(); fires.removeAll(); tunnels.removeAll(); trees.removeAll()
        sweepMasks(s)                   // купола больше не опора для снега
        stepWorks.removeAll()
        nextVisit = -1
        forced = false
    }

    /// Быстрый курсор сбивает человечка с ног (и с лестницы).
    func cursorPoke(_ p: inout Person, _ s: Sim) -> Bool {
        guard s.cursorOn, p.pokeCD <= 0, !p.away, s.cvx * s.cvx + s.cvy * s.cvy > 500 * 500,
              abs(s.cx - p.x) < 5 * u, s.cy > p.y - 17 * u, s.cy < p.y + u else { return false }
        if p.job == .hit && p.phase >= 2 { return false }
        let dir: Float = s.cvx >= 0 ? 1 : -1
        switch p.mode {
        case .ground:
            knock(&p, s, dir: dir)
        case .ladder:
            fallOff(&p, s, ladders.first(where: { $0.id == p.ladder }))
            p.vx = dir * 60
        default:
            return false
        }
        p.pokeCD = 2.5
        p.grudge = -2
        return true
    }

    /// Курсор остановился рядом — помахать ему.
    func tryWave(_ p: inout Person, _ s: Sim) -> Bool {
        guard cursorStill > 0.7, p.waveCD <= 0, p.mode == .ground,
              abs(s.cx - p.x) < 45 * u, abs(s.cy - (p.y - 8 * u)) < 45 * u else { return false }
        p.waveCD = 30
        p.face = s.cx >= p.x ? 1 : -1
        p.job = .wave
        next(&p, 0)
        return true
    }

    func knock(_ p: inout Person, _ s: Sim, dir: Float) {
        release(&p, s)
        puff(s, p.x, p.y, n: 4, stand: p.stand)
        p.job = .hit
        next(&p, 2)
        p.wait = rng.range(0.9, 1.6)
        p.fallDir = dir
        p.anim = .down
    }

    func hitPerson(_ i: Int, from: Int32, dir: Float, strong: Bool, _ s: Sim) {
        var p = folks[i]
        if p.away { return }
        p.snowHat = 5
        p.grudge = from
        switch p.mode {
        case .air, .hop, .crawl, .inside:
            break
        case .ladder:
            p.flinch = 0.35
            if strong { fallOff(&p, s, ladders.first(where: { $0.id == p.ladder })) }
        case .ground:
            if p.job == .hit && p.phase >= 2 { break }
            let free = p.job == .idle || p.job == .wander || p.job == .fight || p.job == .gaze || p.job == .wave
                || p.job == .cheer || p.job == .top || p.job == .hit
            let busy = !free
            if strong || (!busy && rng.f() < 0.3) {
                knock(&p, s, dir: dir)
            } else if busy {
                p.flinch = 0.35
            } else {
                p.job = .hit
                next(&p, 0)
                p.fallDir = dir
            }
        }
        folks[i] = p
    }

    func runHit(_ p: inout Person, _ s: Sim, _ dt: Float) {
        switch p.phase {
        case 0:
            p.anim = .flinch
            p.x = clampX(p.x + p.fallDir * 10 * u * dt, s)
            settle(&p, s, dt)
            if p.t > 0.35 { idle(&p, 0.2) }
        case 2:
            p.anim = .down
            settle(&p, s, dt)
            if p.t > p.wait { next(&p, 3) }
        default:
            p.anim = .getup
            settle(&p, s, dt)
            if p.t > 0.4 { idle(&p, rng.range(0.2, 0.8)) }
        }
    }

    /// Чем заняться дальше.
    func choose(_ p: inout Person, _ s: Sim) {
        next(&p, 0)
        p.tries = 0
        if p.stand != -2 {                  // стоит на окне
            let up = ladders.contains(where: { $0.win == p.stand && $0.done && !$0.broken })
            p.job = up && s.time < p.topUntil && !(s.cfg.people == 0 && !forced) ? .top : .goDown
            return
        }
        if p.home != -1 {
            if chooseHome(&p, s) { return }         // у жителей свои дела
        } else if wantLeave(s) {
            p.job = .leave
            return
        }
        if p.grudge != -1 {                 // ответить тому, кто попал
            let g = p.grudge
            p.grudge = -1
            let alive = g == -2 ? s.cursorOn : folks.contains(where: { $0.id == g && !$0.gone && $0.job != .leave })
            if alive && rng.f() < 0.75 {
                p.job = .fight; p.target = g; p.throwsLeft = 1 + Int(rng.next() % 2)
                return
            }
        }
        if p.home == -1 && chooseSettle(&p, s) { return }       // остаться жить
        if chooseFun(&p, s) { return }                          // тоннель, снежный ангел
        if !planned || (rng.f() < 0.04 && s.time < visitEnd - 60) { planned = plan(s) }
        if let L = ladders.first(where: { $0.active && $0.base == -2 }) {
            let workers = folks.filter { ($0.job == .gather || $0.job == .lift) && $0.ladder == L.id && !$0.gone }.count
            if workers < 5 && rng.f() < 0.85 { p.job = .gather; p.ladder = L.id; return }
        }
        if let L = ladders.first(where: { $0.done && !$0.broken && $0.base == -2 }),
           folks.filter({ $0.stand == L.win || ($0.job == .goTop && $0.ladder == L.id) }).count < 4,
           rng.f() < (s.time - L.doneAt < 25 ? 0.8 : 0.3) {
            p.job = .goTop; p.ladder = L.id
            return
        }
        if var st = site, st.finished < 0, rng.f() < 0.6,
           let k = (0..<3).first(where: { st.owner[$0] == -1 && st.balls[$0] == -1 }) {
            st.owner[k] = p.id
            site = st
            p.job = .snowman; p.stage = k
            return
        }
        let snowmen = s.balls.filter { $0.parent == -1 && $0.hasChild && !$0.held }
        let r = rng.f()
        if r < 0.42, let q = pickTarget(p) {
            p.job = .fight; p.target = q; p.throwsLeft = 1 + Int(rng.next() % 3)
        } else if r < 0.57 && snowmen.count < 2 && site == nil && pile(s, Int(p.x * s.inv), s.H) >= 2
                    && !s.segs.contains(where: { $0.kind == 2 && p.x > $0.x0 - 40 && p.x < $0.x1 + 40 }) {
            var st = Site(x: clampX(p.x + rng.range(-20, 20) * u, s), born: s.time)
            st.owner[0] = p.id
            site = st
            p.job = .snowman; p.stage = 0
        } else if r < (snowmen.count >= 2 ? 0.75 : 0.61), let sm = snowmen.first,
                  let head = s.balls.first(where: { $0.parent != -1 && !$0.hasChild && rootOf(s, $0.id) == sm.id }),
                  !(site?.balls.contains(sm.id) ?? false) {
            p.job = .fight; p.target = -3; p.targetBall = head.id; p.throwsLeft = 3      // снежками по снеговику
        } else if r < 0.80 {
            p.job = .wander
            p.goalX = clampX(p.x + rng.range(-60, 60) * u, s)
        } else if r < 0.92 {
            p.job = .gaze
            p.wait = rng.range(2, 3.5)
        } else {
            p.job = .cheer
            p.wait = 1.2
        }
    }

    func pickTarget(_ p: Person) -> Int32? {
        var c: [Int32] = []
        for q in folks where q.id != p.id && !q.gone && q.mode == .ground && abs(q.x - p.x) < 330 * u {
            let free = q.job == .idle || q.job == .wander || q.job == .fight || q.job == .gaze || q.job == .wave
                || q.job == .cheer || q.job == .top || (q.job == .hit && q.phase < 2)
            if !free { continue }
            c.append(q.id)
            if q.stand != p.stand { c.append(q.id) }       // в тех, кто на другом уровне, целятся охотнее
        }
        return c.isEmpty ? nil : c[Int(rng.next() % UInt64(c.count))]
    }

    // MARK: - Снежки

    func runFight(_ p: inout Person, _ s: Sim, _ dt: Float) {
        var aim: SIMD2<Float>
        switch p.target {
        case -2:
            guard s.cursorOn else { idle(&p, 0.3); return }
            aim = SIMD2(s.cx, s.cy)
        case -3:
            guard let b = s.balls.first(where: { $0.id == p.targetBall }) else { idle(&p, 0.3); return }
            aim = SIMD2(b.x, b.y)
        default:
            guard let q = folks.first(where: { $0.id == p.target }), !q.gone, q.job != .leave else { idle(&p, 0.3); return }
            aim = SIMD2(q.x, q.y - 9 * u)
        }
        let dx = aim.x - p.x
        switch p.phase {
        case 0:     // встать на удобное расстояние
            if p.stand != -2 { next(&p, 1); break }
            if !p.flag {
                p.flag = true
                let d = abs(dx)
                p.goalX = p.x
                if d < 28 * u { p.goalX = clampX(aim.x - (dx >= 0 ? 1 : -1) * rng.range(45, 70) * u, s) }
                else if d > 125 * u { p.goalX = clampX(aim.x - (dx >= 0 ? 1 : -1) * rng.range(60, 110) * u, s) }
            }
            if walk(&p, s, to: p.goalX, speed: 34 * u, dt) || p.t > 5 { next(&p, 1) }
        case 1:     // зачерпнуть
            p.face = dx >= 0 ? 1 : -1
            p.anim = .scoop
            settle(&p, s, dt)
            if p.t > 0.25 && !p.flag {
                p.flag = true
                p.carry = scoop(s, x: p.x + p.face * 2 * u, stand: p.stand, want: 3, half: 2)
                if p.carry == 0 {           // снега под ногами нет
                    if p.stand == -2 { p.job = .wander; p.goalX = clampX(p.x + rng.range(-60, 60) * u, s); next(&p, 0) }
                    else { idle(&p, 1) }
                    return
                }
            }
            if p.t > 0.45 { next(&p, 2) }
        case 2:     // слепить
            p.anim = .pack
            settle(&p, s, dt)
            if p.t > 0.4 { next(&p, 3) }
        case 3:     // замах
            p.face = dx >= 0 ? 1 : -1
            p.anim = .windup
            settle(&p, s, dt)
            if p.t > 0.22 {
                throwShot(p, s, at: aim)
                p.carry = 0
                next(&p, 4)
            }
        default:
            p.anim = .thrown
            settle(&p, s, dt)
            if p.t > 0.3 {
                p.throwsLeft -= 1
                if p.throwsLeft > 0 { next(&p, p.stand == -2 && rng.f() < 0.4 ? 0 : 1) } else { idle(&p, rng.range(0.3, 1.2)) }
            }
        }
    }

    func throwShot(_ p: Person, _ s: Sim, at aim: SIMD2<Float>) {
        let sx = p.x + p.face * 3 * u, sy = p.y - 14 * u
        let dist = hypotf(aim.x - sx, aim.y - sy)
        let dx = aim.x + rng.range(-1, 1) * (4 * u + dist * 0.07) - sx
        let dy = aim.y + rng.range(-1, 1) * (2 * u + dist * 0.04) - sy
        let g: Float = 900
        var T = max(0.42, abs(dx) / (75 * u + 110))
        if dy < 0 { T = max(T, sqrtf(2 * -dy / g) * 0.95) }     // вверх — навесом
        T = min(T, 1.7)
        shots.append(Shot(x: sx, y: sy, vx: dx / T, vy: dy / T - g * T / 2, cells: max(1, p.carry), from: p.id, target: p.target))
    }

    func rootOf(_ s: Sim, _ id: Int32) -> Int32 {
        var cur = id
        for _ in 0..<8 {
            guard let b = s.balls.first(where: { $0.id == cur }), b.parent != -1 else { break }
            cur = b.parent
        }
        return cur
    }

    func stepShots(_ s: Sim, _ dt: Float) {
        var i = 0
        while i < shots.count {
            var sh = shots[i]
            sh.age += dt
            sh.vy += 900 * dt
            var dead = false
            let h = dt / 2
            sub: for _ in 0..<2 {
                sh.x += sh.vx * h
                sh.y += sh.vy * h
                if sh.x < -30 || sh.x > s.wPt + 30 || sh.y > s.hPt + 20 { shots.remove(at: i); dead = true; break sub }
                var hit = false
                for j in folks.indices {
                    let q = folks[j]
                    if q.id == sh.from || q.gone || q.mode == .hop || q.away { continue }
                    let lying = q.job == .hit && q.phase >= 2
                    if abs(sh.x - q.x) < 3.6 * u && sh.y < q.y && sh.y > q.y - (lying ? 5 : 16) * u {
                        hitPerson(j, from: sh.from, dir: sh.vx >= 0 ? 1 : -1, strong: false, s)
                        hit = true
                        break
                    }
                }
                if !hit {
                    for b in s.balls where !b.held {
                        let ddx = sh.x - b.x, ddy = sh.y - b.y
                        if ddx * ddx + ddy * ddy < (b.r + 1.5) * (b.r + 1.5) {
                            hit = true
                            if b.parent != -1 || b.hasChild {       // по снеговику: с третьего попадания разваливается
                                let root = rootOf(s, b.id)
                                ballHits[root, default: 0] += 1
                                if ballHits[root]! >= 3 { demolish(s, root: root) }
                            }
                            break
                        }
                    }
                }
                if !hit && sh.target == -2 && s.cursorOn && hypotf(sh.x - s.cx, sh.y - s.cy) < 9 { hit = true }
                if !hit && sh.age > 0.08 && sh.y >= 0 && sh.x >= 0 && sh.x < s.wPt {
                    let c = min(s.W - 1, Int(sh.x * s.inv)), r = Int(sh.y * s.inv)
                    if r >= s.H { hit = true } else {
                        let v = s.ledge[r * s.W + c]
                        if s.snow[r * s.W + c] != 0 || (v == 1 && sh.vy > 0) || v == 2 { hit = true }
                    }
                }
                if hit {
                    for _ in 0..<sh.cells {
                        chunk(s, sh.x - sh.vx * h, sh.y - sh.vy * h, -sh.vx * 0.15 + rng.range(-70, 70), -rng.range(30, 150))
                    }
                    dust(s, sh.x, sh.y)
                    shots.remove(at: i)
                    dead = true
                    break sub
                }
            }
            if !dead {
                shots[i] = sh
                i += 1
            }
        }
    }

    func demolish(_ s: Sim, root: Int32) {
        var ids: Set<Int32> = [root]
        var grew = true
        while grew {
            grew = false
            for b in s.balls where b.parent != -1 && ids.contains(b.parent) && !ids.contains(b.id) { ids.insert(b.id); grew = true }
        }
        if ids.contains(s.heldId) { return }
        for b in s.balls where ids.contains(b.id) {
            let n = min(160, max(4, Int(Float.pi * b.r * b.r / (s.cell * s.cell) * 0.7)))
            for _ in 0..<n {
                let a = rng.range(0, 6.283), rad = b.r * sqrtf(rng.f())
                chunk(s, b.x + cosf(a) * rad, b.y + sinf(a) * rad, cosf(a) * rng.range(30, 200), sinf(a) * rng.range(30, 160) - 80)
            }
        }
        s.balls.removeAll { ids.contains($0.id) }
        ballHits[root] = nil
    }

    /// Шар, брошенный пользователем, сбивает человечка с ног; соседи обижаются на курсор.
    func userBalls(_ s: Sim) {
        guard !folks.isEmpty else { return }
        for bi in s.balls.indices {
            let b = s.balls[bi]
            if b.held || b.parent != -1 || b.vx * b.vx + b.vy * b.vy < 220 * 220 { continue }
            for i in folks.indices {
                let p = folks[i]
                if p.gone || p.away || p.mode == .air || p.mode == .hop || (p.job == .hit && p.phase >= 2) { continue }
                if abs(b.x - p.x) < b.r + 3.5 * u && b.y + b.r > p.y - 16 * u && b.y - b.r < p.y {
                    hitPerson(i, from: -2, dir: b.vx >= 0 ? 1 : -1, strong: true, s)
                    s.balls[bi].vx *= 0.35
                    s.balls[bi].vy *= 0.35
                    for k in folks.indices where k != i && abs(folks[k].x - p.x) < 200 * u && rng.f() < 0.5 { folks[k].grudge = -2 }
                    break
                }
            }
        }
    }

    // MARK: - Снеговик

    func runSnowman(_ p: inout Person, _ s: Sim, _ dt: Float) {
        guard var st = site else { release(&p, s); idle(&p, 0.5); return }
        if st.finished >= 0 { release(&p, s); p.job = .cheer; p.wait = 1.6; next(&p, 0); return }
        let radii: [Float] = [4.6 * u, 3.5 * u, 2.7 * u]
        var bi = -1
        if p.ball != -1 {
            bi = s.balls.firstIndex(where: { $0.id == p.ball }) ?? -1
            if bi < 0 || s.heldId == p.ball {       // шар разбили или его забрала варежка
                p.ball = -1
                st.owner[p.stage] = -1
                site = st
                p.flinch = 0.4
                idle(&p, 1)
                return
            }
        }
        func quit(_ p: inout Person) { release(&p, s); idle(&p, 0.6) }
        switch p.phase {
        case 0:     // отойти в сторонку, где начать катать
            if !p.flag {
                p.flag = true
                p.goalX = clampX(st.x + (rng.f() < 0.5 ? -1 : 1) * rng.range(25, 60) * u, s)
            }
            if walk(&p, s, to: p.goalX, speed: 22 * u, dt) || p.t > 10 {
                p.face = st.x > p.x ? 1 : -1
                next(&p, 1)
            }
        case 1:     // слепить комок
            p.anim = .scoop
            settle(&p, s, dt)
            if p.t > 0.3 && !p.flag {
                p.flag = true
                let n = scoop(s, x: p.x + p.face * 2 * u, stand: -2, want: 4, half: 2)
                if n == 0 { quit(&p); return }
                let r = sqrtf(Float(n) * s.cell * s.cell * 0.7 / .pi)
                p.ball = s.addBall(x: p.x + p.face * (r + 3 * u), y: p.y - r, r: r, held: true)
                p.acc = 0
            }
            if p.t > 0.55 { p.rollDir = p.face; next(&p, 2) }
        case 2:     // катать туда-сюда, пока не вырастет
            guard bi >= 0 else { quit(&p); return }
            let r = s.balls[bi].r
            if r >= radii[p.stage] || (p.t > 26 && r >= radii[p.stage] * 0.7) { next(&p, 3); break }
            if p.t > 26 { quit(&p); return }                    // катать не из чего
            let x0 = p.x
            if walk(&p, s, to: clampX(st.x + p.rollDir * 70 * u, s), speed: 15 * u, dt) { p.rollDir = -p.rollDir }
            if p.mode != .ground { return }
            p.anim = .push
            rollBall(&p, s, moved: abs(p.x - x0))
        case 3:
            guard bi >= 0 else { quit(&p); return }
            if p.stage == 0 {               // прикатить низ на место
                let bx = s.balls[bi].x
                if abs(bx - st.x) < 3 || p.t > 20 {
                    s.balls[bi].held = false
                    s.balls[bi].vx = 0; s.balls[bi].vy = 0
                    st.x = bx
                    st.balls[0] = p.ball
                    st.placed = 1
                    site = st
                    p.ball = -1
                    next(&p, 5)
                } else {
                    let x0 = p.x
                    _ = walk(&p, s, to: p.x + (st.x > bx ? 20 : -20), speed: 15 * u, dt)
                    if p.mode != .ground { return }
                    p.anim = .push
                    rollBall(&p, s, moved: abs(p.x - x0), grow: false)
                }
            } else {                        // подкатить поближе и ждать, пока поставят то, что ниже
                let wx = clampX(st.x + (p.stage == 1 ? -18 : 18) * u, s)
                if abs(p.x - wx) > 3 && p.t < 12 {
                    let x0 = p.x
                    _ = walk(&p, s, to: wx, speed: 15 * u, dt)
                    if p.mode != .ground { return }
                    p.anim = .push
                    rollBall(&p, s, moved: abs(p.x - x0), grow: false)
                    break
                }
                settle(&p, s, dt)
                p.face = st.x > p.x ? 1 : -1
                if st.placed == p.stage && s.balls.contains(where: { $0.id == st.balls[p.stage - 1] }) { next(&p, 4); p.acc = 0 }
                else if p.t > 45 { quit(&p) }
            }
        case 4:     // поднять шар и поставить сверху
            guard bi >= 0, p.stage > 0, let below = s.balls.first(where: { $0.id == st.balls[p.stage - 1] }) else { quit(&p); return }
            let r = s.balls[bi].r
            let dir: Float = below.x >= p.x ? 1 : -1
            let arrived = walk(&p, s, to: below.x - dir * (below.r + 4 * u), speed: 14 * u, dt)
            if p.mode != .ground { return }
            p.anim = .hold
            p.acc = min(1, p.acc + dt / 0.35)
            let low = SIMD2(p.x + p.face * (r + 3 * u), p.y - r), high = SIMD2(p.x + p.face * u, p.y - 18 * u - r)
            var pos = low + (high - low) * p.acc
            if arrived {
                p.face = dir
                if !p.flag { p.flag = true; p.t = 0 }
                let k = min(1, p.t / 0.5)
                let fin = SIMD2(below.x, below.y - (below.r + r) * 0.95)
                pos = high + (fin - high) * k
                if k >= 1 {
                    s.balls[bi].held = false
                    s.balls[bi].parent = below.id
                    s.balls[bi].offX = 0
                    s.balls[bi].offY = -(below.r + r) * 0.95
                    s.balls[bi].x = fin.x; s.balls[bi].y = fin.y
                    s.balls[bi].vx = 0; s.balls[bi].vy = 0
                    s.balls[bi].grounded = false
                    st.balls[p.stage] = p.ball
                    st.placed += 1
                    if st.placed == 3 { st.finished = s.time }
                    site = st
                    p.ball = -1
                    next(&p, 5)
                    return
                }
            } else {
                p.flag = false
            }
            s.balls[bi].x = pos.x; s.balls[bi].y = pos.y
            s.balls[bi].held = true
            s.balls[bi].vx = 0; s.balls[bi].vy = 0
        default:    // взяться за следующий шар или ждать остальных
            if let k = (0..<3).first(where: { st.owner[$0] == -1 && st.balls[$0] == -1 }) {
                st.owner[k] = p.id
                site = st
                p.stage = k
                next(&p, 0)
            } else {
                if !p.flag { p.flag = true; p.goalX = clampX(st.x + (p.x < st.x ? -1 : 1) * rng.range(22, 30) * u, s) }
                if walk(&p, s, to: p.goalX, speed: 18 * u, dt) { p.face = st.x > p.x ? 1 : -1 }
                if p.t > 60 { idle(&p, 0.5) }
            }
        }
    }

    /// Шар катится перед человечком и наматывает верхний слой снега.
    func rollBall(_ p: inout Person, _ s: Sim, moved: Float, grow: Bool = true) {
        guard let bi = s.balls.firstIndex(where: { $0.id == p.ball }) else { return }
        var b = s.balls[bi]
        let want = max(b.r, min(s.wPt - b.r, p.x + p.face * (b.r + 3 * u)))
        let dx = max(-150 * u * 0.016, min(150 * u * 0.016, want - b.x))
        b.x += dx
        b.angle += dx / max(b.r, 4)
        b.y = (surface(s, x: b.x, stand: -2) ?? s.hPt) - b.r + min(1.5, s.cell * 0.4)
        b.held = true
        b.vx = 0; b.vy = 0
        b.grounded = false
        let layer = max(s.cell, min(s.cell * 3, b.r * 0.3))
        p.acc += grow ? min(moved, 6) * layer / (s.cell * s.cell) : 0
        var eaten = 0
        while p.acc >= 1 {
            if scoop(s, x: b.x, stand: -2, want: 1, half: 1, per: 1) == 0 { p.acc = min(p.acc, 1); break }
            eaten += 1
            p.acc -= 1
        }
        if eaten > 0 { b.r = sqrtf((Float.pi * b.r * b.r + Float(eaten) * s.cell * s.cell * 0.7) / .pi) }
        s.balls[bi] = b
    }

    // MARK: - Лестница: геометрия

    func ladderIndex(_ id: Int) -> Int? { ladders.firstIndex(where: { $0.id == id }) }
    func bottomRow(_ L: Ladder, _ s: Sim) -> Int { L.bot }
    func platformY(_ L: Ladder, _ s: Sim) -> Float { Float(L.bot + 1) * s.cell }
    /// На какой высоте над низом лестницы стоят ноги того, кто только встал на неё (на карнизе — поверх шапки снега).
    func footH(_ L: Ladder, _ s: Sim) -> Float {
        L.base == -2 ? 0 : max(0, platformY(L, s) - (surface(s, x: footX(L, s), stand: L.base) ?? platformY(L, s)))
    }
    /// Сошёл с лестницы на то, на чём она стоит.
    func stepOff(_ p: inout Person, _ s: Sim, _ L: Ladder) {
        p.mode = .ground
        p.stand = L.base
        if let sy = surface(s, x: p.x, stand: L.base) { p.y = min(p.y, sy) }
    }
    func footX(_ L: Ladder, _ s: Sim) -> Float { Float(L.c0 + L.c1 + 1) * 0.5 * s.cell }
    /// Верхняя ступенька рядом с площадкой: сюда приносят снег.
    func handX(_ L: Ladder, _ s: Sim) -> Float {
        footX(L, s) + Float(L.out) * (Float(L.c1 - L.c0 + 1) * 0.5 + Float(L.run) * 0.5 + 0.5) * s.cell
    }

    func stairCols(_ L: Ladder, _ s: Sim) -> ClosedRange<Int> {
        if L.base != -2 { return L.c0...L.c1 }      // на карнизе ступеней нет
        let n = ((L.hs + L.rise - 1) / L.rise - 1) * L.run
        return L.out < 0 ? max(0, L.c0 - n)...L.c1 : L.c0...min(s.W - 1, L.c1 + n)
    }

    /// Высота ступеней в столбце c, ячеек над низом экрана.
    func stairH(_ L: Ladder, _ c: Int) -> Int {
        if L.base != -2 { return 0 }
        if c >= L.c0 && c <= L.c1 { return L.hs }
        let d = L.out < 0 ? L.c0 - 1 - c : c - L.c1 - 1
        if d < 0 { return 0 }
        return max(0, L.hs - (d / L.run + 1) * L.rise)
    }

    /// Какие ячейки строки k приставной лестницы должны быть из снега: две стойки и перекладины.
    func mask(_ L: Ladder, _ k: Int) -> UInt16 {
        let lw = L.c1 - L.c0 + 1
        return k % L.rs == L.rs - 1 ? (UInt16(1) << UInt16(lw)) - 1 : 1 | (UInt16(1) << UInt16(lw - 1))
    }

    func hopX(_ L: Ladder, _ s: Sim) -> Float {
        let x = L.edgeX - Float(L.out) * 20
        if let seg = s.segs.first(where: { $0.win == L.win && x >= $0.x0 - 30 && x <= $0.x1 + 30 }) {
            return max(seg.x0 + 3, min(seg.x1 - 3, L.edgeX - Float(L.out) * (seg.r * 0.8 + 9)))
        }
        return x
    }

    /// Что ещё не достроено.
    func refresh(_ L: inout Ladder, _ s: Sim) {
        L.nextStair = nil
        let cols = stairCols(L, s)
        outer: for k in 1...max(1, L.hs) {
            let r = s.H - k
            if r < 0 { break }
            var c = L.out < 0 ? cols.upperBound : cols.lowerBound
            let end = L.out < 0 ? cols.lowerBound - 1 : cols.upperBound + 1
            while c != end {
                if stairH(L, c) >= k {
                    let i = r * s.W + c
                    if s.snow[i] == 0 && s.ledge[i] == 0 && pile(s, c, s.H) < k { L.nextStair = (c, r); break outer }
                }
                c += L.out
            }
        }
        L.stairsDone = L.nextStair == nil
        L.platformOK = true
        for c in L.c0...L.c1 where pile(s, c, s.H) < L.hs - 2 { L.platformOK = false }
        L.front = L.rows.count
        for k in L.rows.indices where L.rows[k] & mask(L, k) != mask(L, k) { L.front = k; break }
    }

    /// Слежалость утоптанных ступеней: наст — держит отвесную стенку и не смахивается курсором.
    static let packedHard: UInt8 = 220

    /// Уложить и утоптать до n ячеек в ступени. Снег, который там уже лежит, утаптывается даром.
    func placeStairs(_ s: Sim, _ L: Ladder, _ n: Int) -> Int {
        var used = 0
        let cols = stairCols(L, s)
        fill: for k in 1...max(1, L.hs) {
            let r = s.H - k
            if r < 0 { break }
            for c in cols where stairH(L, c) >= k {
                let i = r * s.W + c
                if s.ledge[i] != 0 { continue }
                if s.snow[i] == 0 {
                    if used >= n { break fill }
                    s.snow[i] = rng.shade()
                    used += 1
                }
                if s.hard[i] < People.packedHard { s.hard[i] = People.packedHard }
            }
        }
        s.gridDirty = true
        s.hardDirty = true
        return used
    }

    /// Утоптанные ступени не оседают, как обычный старый снег: если столбец просел (осел под весом
    /// или провалился в пустоту у основания), а сам цел (верх по-прежнему наст), он подрастает
    /// обратно — по ячейке за кадр. Выбитое курсором или шаром
    /// так не восстанавливается — это чинят сами человечки.
    func tamp(_ L: Ladder, _ s: Sim) {
        for c in stairCols(L, s) {
            let want = stairH(L, c)
            let h = pile(s, c, s.H)
            guard want >= 2, h < want, h >= max(1, want - 4) else { continue }
            let top = (s.H - h) * s.W + c, i = top - s.W
            guard i >= 0, s.snow[top] != 0, s.hard[top] >= People.packedHard - 5, s.snow[i] == 0, s.ledge[i] == 0 else { continue }
            s.snow[i] = rng.shade()
            s.hard[i] = People.packedHard
            s.gridDirty = true
            s.hardDirty = true
        }
    }

    /// Прилепить до n ячеек приставной лестницы, не выше строки maxK (докуда дотягиваются руки).
    func placeLadder(_ idx: Int, _ n: Int, maxK: Int) -> Int {
        var used = 0
        var k = ladders[idx].front
        while k < ladders[idx].rows.count && k <= maxK && used < n {
            let m = mask(ladders[idx], k)
            var bit: UInt16 = 1
            while bit <= m && used < n {
                if m & bit != 0 && ladders[idx].rows[k] & bit == 0 {
                    ladders[idx].rows[k] |= bit
                    used += 1
                }
                bit <<= 1
            }
            k += 1
        }
        return used
    }

    /// Ячейка приставной лестницы отваливается: комом или снежной пылью.
    func shed(_ L: Ladder, _ s: Sim, _ k: Int, _ b: Int, vx: Float, vy: Float, dusty: Float) {
        let x = (Float(L.c0 + b) + 0.5) * s.cell, y = (Float(bottomRow(L, s) - k) + 0.5) * s.cell
        chunk(s, x, y, vx, vy, hard: 120)           // утоптанный снег не исчезает: каждая ячейка падает комом
        if rng.f() < dusty { dust(s, x, y) }        // пыль — только для вида
    }

    /// Прилепленная часть отрывается от окна: частью комьями, частью снежной пылью.
    func collapse(_ L: inout Ladder, _ s: Sim) {
        let lw = L.c1 - L.c0 + 1
        for k in L.rows.indices where L.rows[k] != 0 {
            for b in 0..<lw where L.rows[k] & (UInt16(1) << UInt16(b)) != 0 {
                shed(L, s, k, b, vx: Float(L.out) * rng.range(0, 60) + rng.range(-25, 25), vy: rng.range(-40, 40), dusty: 0.65)
            }
            L.rows[k] = 0
        }
        for _ in 0..<min(L.stock, 30) {
            chunk(s, handX(L, s) + rng.range(-6, 6), platformY(L, s) - 4, rng.range(-50, 50), -rng.range(20, 90))
        }
        L.stock = 0
        L.broken = true
        L.active = false
        L.done = false
        L.lifters = []
    }

    /// Что из приставной лестницы на самом деле держится. Держат её две вещи: стойка у окна прилеплена
    /// к его боку (на высоте самого окна), а низ стоит на площадке. Всё, что не связано с этим
    /// цепочкой соседних ячеек, — обломки: они падают комьями, а не висят в воздухе.
    func settleLadder(_ L: inout Ladder, _ s: Sim) {
        L.dirty = false
        L.checkAt = s.time
        let lw = L.c1 - L.c0 + 1, n = L.rows.count
        guard n > 0, L.rows.contains(where: { $0 != 0 }) else { return }
        let inner: UInt16 = L.out < 0 ? UInt16(1) << UInt16(lw - 1) : 1
        let all: UInt16 = (UInt16(1) << UInt16(lw)) - 1
        let bot = bottomRow(L, s)
        var ok = [UInt16](repeating: 0, count: n)
        var stack: [(Int, UInt16)] = []
        if L.base != -2 || L.platformOK {            // стоит на площадке
            var bit: UInt16 = 1
            while bit <= all { if L.rows[0] & bit != 0 { stack.append((0, bit)) }; bit <<= 1 }
        }
        if !L.broken {
            for k in 0..<n where L.rows[k] & inner != 0 {
                let y = Float(bot - k) * s.cell
                if y + s.cell > L.boxY0 && y < L.boxY1 { stack.append((k, inner)) }     // прилеплена к боку окна
            }
        }
        while let (k, bit) = stack.popLast() {
            if ok[k] & bit != 0 { continue }
            ok[k] |= bit
            if k + 1 < n && L.rows[k + 1] & bit != 0 && ok[k + 1] & bit == 0 { stack.append((k + 1, bit)) }
            if k > 0 && L.rows[k - 1] & bit != 0 && ok[k - 1] & bit == 0 { stack.append((k - 1, bit)) }
            let l = bit << 1, r = bit >> 1
            if l <= all && L.rows[k] & l != 0 && ok[k] & l == 0 { stack.append((k, l)) }
            if r != 0 && L.rows[k] & r != 0 && ok[k] & r == 0 { stack.append((k, r)) }
        }
        for k in 0..<n where L.rows[k] & ~ok[k] != 0 {
            for b in 0..<lw where (L.rows[k] & ~ok[k]) & (UInt16(1) << UInt16(b)) != 0 {
                shed(L, s, k, b, vx: rng.range(-25, 25) + s.windNow * 0.15, vy: rng.range(0, 40), dusty: 0.15)
            }
            L.rows[k] &= ok[k]
        }
    }

    /// Ветер и время точат лестницу: в буран её треплет заметно, а брошенная понемногу рассыпается сама.
    /// Пока снег идёт и по ней не лазят, перекладины заносит (frost) — это только рисунок.
    func weather(_ L: inout Ladder, _ s: Sim, _ dt: Float) {
        let snowing = max(s.cfg.intensity, s.cfg.flakeRate / 30)
        if s.time - L.usedAt < 3 { L.frost = max(0, L.frost - dt / 4) }
        else if snowing > 0 { L.frost = min(1, L.frost + dt * snowing / 200 * (1 + 3 * s.wind.storm)) }
        var rate = max(0, abs(s.windNow) - 70) / 90
        if !L.active && s.time - L.usedAt > 240 { rate += 0.5 }
        guard rate > 0 else { return }
        L.wear += rate * dt
        let n = L.rows.count, lw = L.c1 - L.c0 + 1
        while L.wear >= 1 {
            L.wear -= 1
            var k = n - 1 - Int(Float(n) * rng.f() * rng.f())      // чаще — сверху
            var tries = 0
            while tries < 14 && (k < 0 || L.rows[k] == 0) { k -= 1; tries += 1 }
            guard k >= 0, L.rows[k] != 0 else { continue }
            let b0 = Int(rng.next() % UInt64(lw))
            for d in 0..<lw {
                let b = (b0 + d) % lw
                if L.rows[k] & (UInt16(1) << UInt16(b)) != 0 {
                    L.rows[k] &= ~(UInt16(1) << UInt16(b))
                    // сдуло: ком уносит ветром, он упадёт в стороне
                    shed(L, s, k, b, vx: s.windNow * 0.5 + rng.range(-20, 20), vy: rng.range(-30, 10), dusty: 0.5)
                    L.dirty = true
                    break
                }
            }
        }
    }

    /// Курсор и брошенные шары выбивают куски из приставной лестницы.
    func damage(_ L: inout Ladder, _ s: Sim) {
        let lw = L.c1 - L.c0 + 1
        let x0 = Float(L.c0) * s.cell, x1 = Float(L.c1 + 1) * s.cell
        let bot = bottomRow(L, s)
        func strike(_ cx: Float, _ cy: Float, _ r: Float, _ vx: Float, _ vy: Float, _ p: Float) {
            guard cx > x0 - r, cx < x1 + r else { return }
            let lo = max(0, bot - Int((cy + r) * s.inv)), hi = min(L.rows.count - 1, bot - Int((cy - r) * s.inv))
            guard lo <= hi else { return }
            for k in lo...hi where L.rows[k] != 0 {
                let y = (Float(bot - k) + 0.5) * s.cell
                for b in 0..<lw where L.rows[k] & (UInt16(1) << UInt16(b)) != 0 {
                    let x = (Float(L.c0 + b) + 0.5) * s.cell
                    if (x - cx) * (x - cx) + (y - cy) * (y - cy) < r * r && rng.f() < p {
                        L.rows[k] &= ~(UInt16(1) << UInt16(b))
                        L.dirty = true
                        shed(L, s, k, b, vx: vx * rng.range(0.3, 0.8) + rng.range(-30, 30), vy: vy * 0.4 - rng.range(0, 80), dusty: 0.25)
                    }
                }
            }
        }
        if s.cfg.sweep && s.cursorOn && s.heldId == -1 {
            let sp = sqrtf(s.cvx * s.cvx + s.cvy * s.cvy)
            if sp > 120 { strike(s.cx, s.cy, s.cfg.sweepRadius, s.cvx, s.cvy, min(0.6, 0.12 + sp / 2500)) }
        }
        for b in s.balls where b.parent == -1 && b.vx * b.vx + b.vy * b.vy > 150 * 150 && !(b.held && b.id != s.heldId) {
            strike(b.x, b.y, b.r + s.cell, b.vx, b.vy, 0.8)
        }
    }

    /// Брошенные ступени понемногу выдувает — до высоты обычного сугроба. false — выдувать больше нечего.
    func erodeOne(_ L: Ladder, _ s: Sim) -> Bool {
        if L.base != -2 { return false }
        let keep = Int(30 * s.cfg.capScale * s.inv) + 1
        var bestC = -1, bestH = keep
        for c in stairCols(L, s) {
            let h = pile(s, c, s.H)
            if h > bestH || (h == bestH && bestC >= 0 && rng.f() < 0.3) { bestH = h; bestC = c }
        }
        guard bestC >= 0 else { return false }
        let r = s.H - bestH
        guard r >= 0, s.snow[r * s.W + bestC] != 0 else { return false }
        let hd = s.hard[r * s.W + bestC]
        s.snow[r * s.W + bestC] = 0
        chunk(s, (Float(bestC) + 0.5) * s.cell, (Float(r) + 0.5) * s.cell,
              s.windNow * 0.4 + rng.range(-40, 40), -rng.range(20, 70), hard: hd > 60 ? hd - 60 : 0)     // сдувает в сторону, а не в никуда
        s.snowDisturbed(bestC - 1, r - 1, bestC + 1, r + 1)
        s.gridDirty = true
        return true
    }

    /// Лестница достроена: кто на ней — лезут наверх, остальные радуются.
    func finish(_ k: Int, _ s: Sim) {
        let id = ladders[k].id
        for i in folks.indices where folks[i].ladder == id {
            if folks[i].job == .lift {
                folks[i].carry = 0
                folks[i].job = .goTop
                folks[i].phase = 2; folks[i].t = 0; folks[i].flag = false
            } else if folks[i].job == .gather {
                var p = folks[i]
                release(&p, s)
                p.job = .cheer
                p.wait = 1.6
                next(&p, 0)
                folks[i] = p
            }
        }
        ladders[k].lifters = []
        ladders[k].stock = 0
        ladders[k].doneAt = s.time
        visitEnd = max(visitEnd, s.time + 70)       // достроили — ещё поиграют наверху
    }

    /// Следит за всеми лестницами: на месте ли окно, цел ли снег, что достроено.
    func validate(_ s: Sim, _ dt: Float) {
        var k = 0
        scan: while k < ladders.count {
            var L = ladders[k]
            let bot = bottomRow(L, s)
            if !L.broken {
                if let b = boxes[L.win]?.box {
                    L.missing = 0
                    let edge = L.out < 0 ? b.x0 : b.x1
                    // окно сдвинули, или оно стало короче и лестнице больше не за что держаться
                    var gone = abs(edge - L.edgeX) > s.cell * 0.6 || abs(b.y0 - L.boxY0) > s.cell * 0.6
                        || min(b.y1, Float(bot + 1) * s.cell) - b.y0 < 36
                    if L.base != -2 {       // ярус: карниз, на котором стоит лестница, должен быть на месте
                        let fx = footX(L, s)
                        let sg = s.segs.first(where: { $0.win == L.base && fx >= $0.x0 - 3 && fx <= $0.x1 + 3 })
                        if sg == nil || abs(sg!.y - L.baseY) > s.cell * 0.6 { gone = true }
                    }
                    if gone { collapse(&L, s) }
                } else {
                    L.missing += dt
                    if L.missing > 0.8 { collapse(&L, s) }
                }
            }
            if !L.rows.isEmpty { damage(&L, s); weather(&L, s, dt) }
            if let b = boxes[L.win]?.box { L.boxY1 = b.y1 }
            L.docked = false
            if L.base == -2, let d = dock {
                let cols = stairCols(L, s)
                L.docked = Float(cols.upperBound + 1) * s.cell > d.x0 && Float(cols.lowerBound) * s.cell < d.x1
            }
            if L.docked {               // ступени вернутся на место, когда Dock спрячется
                L.usedAt = max(L.usedAt, s.time - 200)
                ladders[k] = L
                k += 1
                continue
            }
            if !L.broken { tamp(L, s) }
            refresh(&L, s)
            if L.dirty || s.time - L.checkAt > 0.5 { settleLadder(&L, s); refresh(&L, s) }
            // от лестницы ничего не осталось — её больше нет (ступени потом выдует)
            if !L.active && !L.broken && s.time - L.usedAt > 30 && !L.rows.contains(where: { $0 != 0 }) { L.broken = true }
            if L.active {
                L.stalled += dt
                let workers = folks.contains(where: { ($0.job == .gather || $0.job == .lift) && $0.ladder == L.id })
                L.empty = workers ? 0 : L.empty + dt
                if L.platformOK && L.front >= L.rows.count {
                    L.active = false
                    L.done = true
                    ladders[k] = L
                    finish(k, s)
                    L = ladders[k]
                } else if L.stalled > 70 || L.empty > 25 {
                    L.active = false            // снега не хватает или все разошлись
                }
            } else if L.done && (!L.platformOK || L.front < L.rows.count) {
                L.done = false                  // поломали — в следующий раз починят
            }
            if L.active || (L.done && !L.broken) {
                L.orphan = 0
            } else {
                L.orphan += dt
                if !L.broken && L.orphan > 600 { collapse(&L, s) }
                if L.broken && L.orphan > 150 {
                    L.erode += dt
                    while L.erode > 0.15 {
                        L.erode -= 0.15
                        if !erodeOne(L, s) {
                            ladders.remove(at: k)
                            continue scan
                        }
                    }
                }
            }
            ladders[k] = L
            k += 1
        }
    }

    /// Решить, строить ли лестницу в этот приход.
    /// false — пока негде (окна двигают, снега мало): попробовать ещё раз попозже.
    func plan(_ s: Sim) -> Bool {
        guard s.cfg.peopleLadders, !ladders.contains(where: { $0.active }) else { return true }
        // в этот приход кто-то надумал остаться жить — сначала дом, лестница подождёт
        if settleWish && s.cfg.peopleStay && s.time < visitStart + 70 { return false }
        if s.time < planAfter { return false }
        planAfter = s.time + 6
        if let k = ladders.firstIndex(where: { $0.base == -2 && !$0.done && !$0.broken }), (boxes[ladders[k].win]?.still ?? 0) > 2 {
            ladders[k].active = true            // достроить или починить начатую
            ladders[k].stalled = 0
            ladders[k].empty = 0
        } else if ladders.filter({ $0.base == -2 }).count < 3 {
            if rng.f() > (ladders.contains(where: { $0.done && !$0.broken }) ? 0.35 : 0.9) { return true }     // сегодня без стройки
            guard var L = findSite(s) else { return s.time > visitEnd - 60 }
            L.id = nextLadderId
            nextLadderId += 1
            L.active = true
            L.usedAt = s.time
            ladders.append(L)
        } else {
            return true
        }
        if folks.count < 4 { startVisit(s, extra: true) }       // зовут подмогу
        visitEnd = max(visitEnd, s.time + 150)
        return true
    }

    /// Найти окно, к боку которого можно пристроить лестницу, и прикинуть, сколько на неё уйдёт снега.
    /// base — откуда строить: -2 — с низа экрана (ступени и лестница), иначе с карниза этого окна (ярус).
    /// Лестница стоит на своём основании, а к окну прилеплена верхней частью — поэтому низ окна
    /// может быть как угодно высоко.
    func findSite(_ s: Sim, base: Int = -2) -> Ladder? {
        let cell = s.cell, inv = s.inv
        let all = s.windowBoxes
        let lw = max(4, Int((18 / cell).rounded()))
        let rs = max(2, Int((12 / cell).rounded()))
        let rise = max(1, Int((8 / cell).rounded()))
        let hs = base == -2 ? max(2 * rise, Int((34 / cell).rounded(.up))) : 0
        var best: (L: Ladder, score: Int)? = nil
        for (idx, b) in all.enumerated() {
            guard b.win != base, (boxes[b.win]?.still ?? 0) > 3, b.y0 > s.topLimit + 12, b.y1 - b.y0 > 70, b.x1 - b.x0 > 70,
                  !ladders.contains(where: { $0.win == b.win }) else { continue }
            for out in [-1, 1] {
                let edge = out < 0 ? b.x0 : b.x1
                let c0: Int, c1: Int
                if out < 0 { c1 = Int((edge - cell * 0.5) * inv); c0 = c1 - lw + 1 }
                else { c0 = Int((edge + cell * 0.5) * inv); c1 = c0 + lw - 1 }
                guard c0 >= 2, c1 <= s.W - 3 else { continue }
                // наверху у этого угла должен быть карниз, куда вылезать
                guard let seg = s.segs.first(where: { $0.win == b.win && $0.kind == 1 && $0.x1 - $0.x0 >= 60
                    && (out < 0 ? $0.x0 <= b.x0 + 45 : $0.x1 >= b.x1 - 45) }) else { continue }
                let topRow = Int((seg.y * inv).rounded()) - 2
                let fx = Float(c0 + c1 + 1) * 0.5 * cell
                // на чём лестница стоит
                var bot = s.H - hs - 1
                var baseY: Float = 0
                var baseSeg: Ledge? = nil
                if base != -2 {
                    let hx = fx + Float(out) * (Float(lw) * 0.5 + 2) * cell     // рядом должно быть где встать
                    guard let sg = s.segs.first(where: { $0.win == base && $0.kind == 1 && fx >= $0.x0 + 1 && fx <= $0.x1 + 2
                        && hx >= $0.x0 + 2 && hx <= $0.x1 - 2 }) else { continue }
                    baseSeg = sg
                    baseY = sg.y
                    bot = ledgeRow(s, sg, Int(fx * inv)) - 1
                }
                let botY = Float(bot + 1) * cell
                // держаться есть за что: бок окна перекрывает лестницу хотя бы на 40 pt
                guard topRow >= 2, topRow < bot - 3 * rs, min(b.y1, botY) - b.y0 >= 40 else { continue }
                let run = rise
                var L = Ladder(id: 0, win: b.win, out: out, c0: c0, c1: c1, hs: hs, run: run, rise: rise, rs: rs,
                               topRow: topRow, ledgeY: seg.y, edgeX: edge, boxY0: b.y0)
                L.base = base; L.baseY = baseY; L.bot = bot
                var lo = c0, hi = c1
                if base == -2 {
                    let n = ((hs + rise - 1) / rise - 1) * run
                    let far = out < 0 ? c0 - n : c1 + n
                    guard far >= 1, far <= s.W - 2 else { continue }
                    lo = min(far, c0); hi = max(far, c1)
                }
                // бок окна виден: перед ним нет других окон
                let lx0 = Float(c0) * cell - 3, lx1 = Float(c1 + 1) * cell + 3
                var ok = true
                for j in 0..<idx where all[j].win != base && all[j].x1 > lx0 && all[j].x0 < lx1 && all[j].y1 > b.y0 - 14
                    && all[j].y0 < min(b.y1, botY) { ok = false; break }
                // на пути нет чужих карнизов и Dock, рядом нет другой лестницы
                let x0 = Float(lo) * cell, x1 = Float(hi + 1) * cell, topY = Float(topRow) * cell
                for sg in s.segs where sg.win != b.win && sg.win != base && sg.x1 > x0 - cell && sg.x0 < x1 + cell
                    && sg.y > topY - 24 && sg.y < botY + (base == -2 ? 10000 : 6) { ok = false; break }
                for o in ladders where o.base == base && stairCols(o, s).upperBound + 12 > lo && stairCols(o, s).lowerBound - 12 < hi { ok = false; break }
                if base == -2 && (inDock(s, lo) || inDock(s, hi) || inDock(s, (lo + hi) / 2)) { ok = false }      // Dock поднят — не сейчас
                if !ok { continue }
                var need = 0
                if base == -2 { for c in stairCols(L, s) { need += max(0, stairH(L, c) - pile(s, c, s.H)) } }
                let rows = bot - topRow + 1
                need += rows * 2 + rows / rs * (lw - 2)
                guard need <= 1700 else { continue }
                // запас снега поблизости: на полу вокруг или на шапке окна-основания
                var supply = 0
                if let sg = baseSeg {
                    let a = max(0, Int(sg.x0 * inv)), z = min(s.W - 1, Int(sg.x1 * inv))
                    if a <= z { for c in a...z { supply += max(0, pile(s, c, ledgeRow(s, sg, c)) - 1) } }
                } else {
                    let span = Int(520 * inv)
                    for c in max(0, lo - span)...min(s.W - 1, hi + span) where c < lo || c > hi { supply += max(0, pile(s, c, s.H) - 1) }
                }
                let frac: Float = base != -2 ? 0.7 : (s.cfg.intensity > 0 ? 0.3 : 0.9)
                guard Float(supply) >= Float(need) * frac else { continue }
                let score = need + Int(rng.range(0, 150))
                if best == nil || score < best!.score {
                    L.rows = [UInt16](repeating: 0, count: rows)
                    best = (L, score)
                }
            }
        }
        return best?.L
    }

    /// Те, кто уже на окне, решают строить дальше — к окну повыше, с карниза этого. true — начали.
    func planTier(_ s: Sim, from base: Int) -> Bool {
        guard s.cfg.peopleLadders, !ladders.contains(where: { $0.active }), ladders.count < 6 else { return false }
        if let k = ladders.firstIndex(where: { $0.base == base && !$0.done && !$0.broken }), (boxes[ladders[k].win]?.still ?? 0) > 2 {
            ladders[k].active = true
            ladders[k].stalled = 0
            ladders[k].empty = 0
        } else {
            guard var L = findSite(s, base: base) else { return false }
            L.id = nextLadderId
            nextLadderId += 1
            L.active = true
            L.usedAt = s.time
            ladders.append(L)
        }
        visitEnd = max(visitEnd, s.time + 150)
        return true
    }

    // MARK: - Лестница: работа

    /// Где набрать снега: поближе и где его побольше, сначала со стороны ступеней.
    func gatherSpot(_ s: Sim, _ L: Ladder, from x: Float) -> Float? {
        if L.base != -2 {       // ярус: снег берут с шапки окна, на котором стоят
            let fx = footX(L, s)
            var best: Float? = nil
            var bestScore = -Float.infinity
            // только с того куска карниза, где стоит лестница: через закрытое другим окном место не пройти
            guard let sg = s.segs.first(where: { $0.win == L.base && $0.kind == 1 && fx >= $0.x0 - 3 && fx <= $0.x1 + 3 }),
                  sg.x1 - sg.x0 > 16 else { return nil }
            for _ in 0..<14 {
                let gx = rng.range(sg.x0 + 5, sg.x1 - 5)
                if abs(gx - fx) < 8 * u { continue }
                let c = Int(gx * s.inv)
                let h = pile(s, c, ledgeRow(s, sg, c))
                if h < 2 { continue }
                let score = Float(min(h, 8)) * 12 - abs(gx - x) * 0.1
                if score > bestScore { bestScore = score; best = gx }
            }
            return best
        }
        let cols = stairCols(L, s)
        let far = L.out < 0 ? Float(cols.lowerBound) * s.cell - 8 : Float(cols.upperBound + 1) * s.cell + 8
        let wall = footX(L, s) - Float(L.out) * (Float(L.c1 - L.c0 + 1) * 0.5 * s.cell + 10)
        var best: Float? = nil
        var bestScore = -Float.infinity
        for k in 0..<16 {
            let d = rng.range(0, 210) * u
            let gx = k < 11 ? far + Float(L.out) * d : wall - Float(L.out) * d
            if gx < 12 || gx > s.wPt - 12 { continue }
            let c = Int(gx * s.inv)
            let h = pile(s, c, s.H)
            if h < 2 || isStair(s, c, s.H - h) || reserved(s, c) { continue }
            let score = Float(min(h, 8)) * 12 - abs(gx - x) * 0.1 - d * 0.05 - (k < 11 ? 0 : 25)
            if score > bestScore { bestScore = score; best = gx }
        }
        return best
    }

    func wantLifters(_ L: Ladder, _ s: Sim) -> Int {
        let total = folks.filter { ($0.job == .gather || $0.job == .lift) && $0.ladder == L.id && !$0.gone }.count
        let hp = max(0, Float(L.front) * s.cell - 11 * u)
        let cap = total <= 2 ? 1 : total - max(1, (total + 1) / 3)
        return max(1, min(1 + Int(hp / (65 * u)), cap))
    }

    /// Носит снег к стройке.
    func runGather(_ p: inout Person, _ s: Sim, _ dt: Float) {
        guard let k = ladderIndex(p.ladder), ladders[k].active, ladders[k].base == p.stand else { release(&p, s); idle(&p, 0.5); return }
        let L = ladders[k]
        if L.docked { settle(&p, s, dt); p.t = min(p.t, 1); return }       // Dock поднят — ждут
        switch p.phase {
        case 0:
            settle(&p, s, dt)
            if wantLeave(s) { release(&p, s); idle(&p, 0.3); return }
            if L.stairsDone && L.stock >= 40 {              // снега на площадке хватает
                let others = folks.contains(where: { $0.job == .gather && $0.ladder == L.id && $0.id != p.id && !$0.gone })
                if L.lifters.count < wantLifters(L, s) && others { next(&p, 6) } else { p.face = Float(-L.out) }
                return
            }
            if let gx = gatherSpot(s, L, from: p.x) {
                p.goalX = gx
                p.tries = 0
                next(&p, 1)
            } else if p.t > 2 {
                p.t = 0
                p.tries += 1
                if p.tries > 3 { release(&p, s); idle(&p, 1) }      // снега рядом нет
            }
        case 1:
            if walk(&p, s, to: p.goalX, speed: 30 * u, dt) || p.t > 25 { next(&p, 2) }
        case 2, 3:  // два гребка
            p.anim = .scoop
            settle(&p, s, dt)
            if p.t > 0.25 && !p.flag {
                p.flag = true
                p.carry += scoop(s, x: p.x + p.face * 2 * u, stand: p.stand, want: 8, half: p.phase == 2 ? 4 : 7)
            }
            if p.t > 0.45 { next(&p, p.phase == 2 ? 3 : (p.carry >= 5 ? 4 : 0)) }
        case 4:     // нести
            let tx = L.nextStair != nil ? (Float(L.nextStair!.c) + 0.5) * s.cell : handX(L, s)
            if walk(&p, s, to: tx, speed: 28 * u, dt) || p.t > 25 { next(&p, 5) }
        case 5:
            settle(&p, s, dt)
            if !L.stairsDone {                              // утоптать в ступени
                p.anim = .pat
                if p.t > 0.2 && !p.flag {
                    p.flag = true
                    p.carry -= placeStairs(s, L, p.carry)
                    ladders[k].stalled = 0
                    ladders[k].stock += p.carry             // что не влезло — на площадку
                    p.carry = 0
                }
                if p.t > 0.45 { next(&p, 0) }
            } else {
                let mine = folks.filter { $0.job == .gather && $0.ladder == L.id && !$0.gone }.count
                if L.lifters.count < wantLifters(L, s) && (mine >= 2 || L.lifters.isEmpty) {
                    next(&p, 6)                             // сам полезет наверх
                } else {
                    p.anim = .pat
                    if p.t > 0.3 {
                        ladders[k].stock += p.carry
                        p.carry = 0
                        next(&p, 0)
                    }
                }
            }
        default:    // встать на лестницу
            if walk(&p, s, to: footX(L, s), speed: 22 * u, dt) || p.t > 8 {
                if p.mode != .ground { return }
                // пока шёл, на лестницу уже встали другие — остаться носить снег
                let others = folks.contains(where: { $0.job == .gather && $0.ladder == L.id && $0.id != p.id && !$0.gone })
                if L.lifters.count >= wantLifters(L, s) || (!others && !L.lifters.isEmpty) {
                    ladders[k].stock += p.carry
                    p.carry = 0
                    next(&p, 0)
                    return
                }
                p.x = footX(L, s)
                p.y = min(p.y, platformY(L, s))
                if L.base == -2 { p.y = platformY(L, s) }
                p.mode = .ladder
                p.job = .lift
                next(&p, p.carry > 0 ? 2 : 1)
                ladders[k].lifters.insert(p.id, at: 0)
            }
        }
    }

    /// Стоит на лестнице: принимает снег снизу, поднимает и передаёт выше; верхний лепит лестницу.
    func runLift(_ p: inout Person, _ s: Sim, _ dt: Float) {
        guard let k = ladderIndex(p.ladder), ladders[k].active, let j = ladders[k].lifters.firstIndex(of: p.id) else {
            release(&p, s)                                  // стройка остановилась — вниз
            p.job = .goDown
            next(&p, 2)
            return
        }
        let L = ladders[k]
        if L.docked { p.anim = .hang; p.t = min(p.t, 1); return }           // Dock поднят — ждут
        let K = L.lifters.count
        let plat = platformY(L, s)
        let hp = max(0, Float(L.front) * s.cell - 11 * u)       // где стоит тот, кто лепит
        let gap = 9 * u
        let h0 = footH(L, s)
        func lowOf(_ j: Int) -> Float { j > 0 ? max(h0, min(hp, hp * Float(j) / Float(K) + gap)) : h0 }
        let low = lowOf(j)
        let up = max(low, j < K - 1 ? hp * Float(j + 1) / Float(K) - gap : hp)
        let h = plat - p.y
        let speed = 30 * u
        switch p.phase {
        case 0:
            if climb(&p, s, L, toH: low, speed: speed, dt) { next(&p, 1) }
        case 1:
            if abs(h - low) > 2 { _ = climb(&p, s, L, toH: low, speed: speed, dt); break }
            p.anim = .hang
            p.x = footX(L, s)
            if j == 0 {
                if L.stock > 0 {
                    if !p.flag { p.flag = true; p.t = 0 }
                    p.anim = .reachDown
                    if p.t > 0.3 {
                        let n = min(L.stock, 24)
                        ladders[k].stock -= n
                        p.carry = n
                        next(&p, 2)
                    }
                } else {
                    p.flag = false
                    if wantLeave(s) {
                        release(&p, s)
                        p.job = .goDown
                        next(&p, 2)
                    } else if !folks.contains(where: { $0.job == .gather && $0.ladder == L.id && !$0.gone }) {
                        ladders[k].lifters.removeAll { $0 == p.id }     // носить некому: нижний сам идёт за снегом
                        stepOff(&p, s, L)
                        p.job = .gather
                        next(&p, 0)
                    }
                }
            } else if let g = folks.first(where: { $0.id == L.lifters[j - 1] }), g.phase == 3, g.carry > 0 {
                p.anim = .reachDown
            }
        case 2:
            if p.carry == 0 { next(&p, 0); break }
            if climb(&p, s, L, toH: up, speed: speed * 0.85, dt) { next(&p, 3) }
        default:
            if abs(h - up) > 3 { _ = climb(&p, s, L, toH: up, speed: speed * 0.85, dt); p.t = 0; p.flag = false; break }
            p.x = footX(L, s)
            if j == K - 1 {
                // окно двигают — ждём, пока встанет: к движущемуся снег не прилепить
                guard (boxes[L.win]?.still ?? 0) > 2.5 else { p.anim = .hang; p.t = 0; break }
                p.anim = .pat
                if p.t > 0.22 {
                    p.t = 0
                    let used = placeLadder(k, min(6, p.carry), maxK: Int((h + 15 * u) * s.inv) - 1)
                    p.carry -= used
                    if used > 0 { ladders[k].stalled = 0 }
                    if p.carry == 0 { next(&p, 0) } else if used == 0 { next(&p, 2) }
                }
            } else {
                p.anim = .hang
                let rid = L.lifters[j + 1]
                if let r = folks.firstIndex(where: { $0.id == rid }), folks[r].job == .lift, folks[r].phase == 1,
                   folks[r].carry == 0, folks[r].mode == .ladder, abs((plat - folks[r].y) - lowOf(j + 1)) < 4 {
                    p.anim = .handUp
                    if !p.flag { p.flag = true; p.t = 0 }
                    if p.t > 0.35 {                         // передал наверх
                        folks[r].carry = p.carry
                        folks[r].phase = 2
                        folks[r].t = 0
                        folks[r].flag = false
                        p.carry = 0
                        next(&p, 0)
                    }
                } else {
                    p.flag = false
                }
            }
        }
    }

    /// По ступеням и лестнице — на окно.
    func runGoTop(_ p: inout Person, _ s: Sim, _ dt: Float) {
        guard let k = ladderIndex(p.ladder), ladders[k].done, !ladders[k].broken else {
            if p.mode == .ladder { p.job = .goDown; next(&p, 2) } else if p.mode == .hop { p.mode = .air } else { idle(&p, 0.5) }
            return
        }
        let L = ladders[k]
        switch p.phase {
        case 0:
            if p.stand != L.base { idle(&p, 0.5); return }
            if L.docked { settle(&p, s, dt); p.t = min(p.t, 1); return }    // Dock поднят — подождать
            if walk(&p, s, to: footX(L, s), speed: 24 * u, dt) && p.mode == .ground
                && (L.base == -2 ? abs(p.y - platformY(L, s)) < 3 * s.cell : p.y <= platformY(L, s) + 3) {
                p.x = footX(L, s)
                p.y = min(p.y, platformY(L, s))
                p.mode = .ladder
                next(&p, 2)
            } else if p.t > 30 {
                idle(&p, 0.5)
            }
        case 2:
            if climb(&p, s, L, toH: platformY(L, s) - (L.ledgeY + 4 * u), speed: 30 * u, dt) {
                let hx = hopX(L, s)
                p.hop0 = SIMD2(p.x, p.y)
                p.hop1 = SIMD2(hx, surface(s, x: hx, stand: L.win) ?? L.ledgeY)
                p.mode = .hop
                next(&p, 3)
            }
        default:
            if hop(&p, dur: 0.45) {
                p.mode = .ground
                p.stand = L.win
                p.job = .top
                p.topUntil = s.time + rng.range(35, 80)
                next(&p, 0)
            }
        }
    }

    /// На окне: бродит, сидит на краю, кидается в тех, кто внизу.
    func runTop(_ p: inout Person, _ s: Sim, _ dt: Float) {
        guard let seg = segFor(s, win: p.stand, x: p.x) else { drop(&p, s); return }
        switch p.phase {
        case 0:
            settle(&p, s, dt)
            if p.mode != .ground { return }
            if s.time > p.topUntil || (s.cfg.people == 0 && !forced) { p.job = .goDown; next(&p, 0); return }
            if tryWave(&p, s) { return }
            // стройка следующего яруса с этого окна
            if let L = ladders.first(where: { $0.active && $0.base == p.stand }),
               folks.filter({ ($0.job == .gather || $0.job == .lift) && $0.ladder == L.id && !$0.gone }).count < 5 {
                p.job = .gather; p.ladder = L.id
                p.topUntil = max(p.topUntil, s.time + 60)
                next(&p, 0)
                return
            }
            // выше есть готовая лестница — лезть дальше
            if let L = ladders.first(where: { $0.done && !$0.broken && $0.base == p.stand }), rng.f() < 0.3,
               folks.filter({ $0.stand == L.win }).count < 4 {
                p.job = .goTop; p.ladder = L.id
                next(&p, 0)
                return
            }
            if rng.f() < 0.25 && planTier(s, from: p.stand) { return }      // а не построить ли ещё выше
            let r = rng.f()
            if r < 0.35, let q = pickTarget(p) {
                p.job = .fight; p.target = q; p.throwsLeft = 1 + Int(rng.next() % 2)
                next(&p, 0)
            } else if r < 0.6 {
                p.goalX = rng.range(seg.x0 + 6, max(seg.x0 + 7, seg.x1 - 6))
                next(&p, 1)
            } else if r < 0.82 {
                p.wait = rng.range(4, 9)
                next(&p, 2)
            } else {
                p.job = .gaze
                p.wait = rng.range(2, 3.5)
                next(&p, 0)
            }
        case 1:
            if walk(&p, s, to: max(seg.x0 + 4, min(seg.x1 - 4, p.goalX)), speed: 16 * u, dt) || p.t > 12 {
                p.wait = rng.range(0.3, 1.5)
                next(&p, 3)
            }
        case 2:
            p.anim = .sit
            settle(&p, s, dt)
            if p.t > p.wait || s.time > p.topUntil { next(&p, 0) }
        default:
            settle(&p, s, dt)
            if p.t > p.wait { next(&p, 0) }
        }
    }

    /// Слезть с окна: по лестнице, а если её нет — прыжком в сугроб.
    func runGoDown(_ p: inout Person, _ s: Sim, _ dt: Float) {
        switch p.phase {
        case 0:
            guard let seg = segFor(s, win: p.stand, x: p.x) else { drop(&p, s); return }
            if !p.flag {
                p.flag = true
                if let L = ladders.first(where: { $0.win == p.stand && $0.done && !$0.broken }) {
                    p.ladder = L.id
                    p.goalX = hopX(L, s)
                } else {
                    p.ladder = -1
                    p.goalX = p.x - seg.x0 < seg.x1 - p.x ? seg.x0 + 2 : seg.x1 - 2
                }
            }
            if walk(&p, s, to: p.goalX, speed: 22 * u, dt) || p.t > 20 {
                if p.mode != .ground { return }
                if let k = ladderIndex(p.ladder), ladders[k].done, !ladders[k].broken {
                    let L = ladders[k]
                    p.hop0 = SIMD2(p.x, p.y)
                    p.hop1 = SIMD2(footX(L, s), L.ledgeY + 4 * u)
                    p.mode = .hop
                    next(&p, 1)
                } else {
                    let dir: Float = p.x - seg.x0 < seg.x1 - p.x ? -1 : 1
                    release(&p, s)
                    p.mode = .air
                    p.face = dir
                    p.vx = dir * 28 * u
                    p.vy = -75 * u
                }
            }
        case 1:
            if hop(&p, dur: 0.45) {
                p.mode = .ladder
                next(&p, 2)
            }
        case 2:
            guard let k = ladderIndex(p.ladder) else { fallOff(&p, s, nil); return }
            let L = ladders[k]
            if climb(&p, s, L, toH: footH(L, s), speed: 34 * u, dt) {
                stepOff(&p, s, L)
                if L.base != -2 {           // спустился на окно ниже — там и остаётся
                    p.job = .top
                    p.topUntil = max(p.topUntil, s.time + rng.range(8, 30))
                    next(&p, 0)
                    return
                }
                let cols = stairCols(L, s)
                p.goalX = clampX((L.out < 0 ? Float(cols.lowerBound) : Float(cols.upperBound + 1)) * s.cell
                                 + Float(L.out) * rng.range(10, 40) * u, s)
                next(&p, 3)
            }
        default:
            if walk(&p, s, to: p.goalX, speed: 22 * u, dt) || p.t > 15 { idle(&p, 0.3) }
        }
    }

    // MARK: - Отрисовка

    func pose(_ p: Person, _ time: Float) -> Pose {
        var po = Pose()
        let f = Int(p.walkPhase * 2) & 3
        let beat = Int(time * 7 + Float(p.id)) & 1
        func legs(_ amp: Int) {
            switch f {
            case 0: po.footA = amp; po.footB = -amp
            case 1: po.liftB = 1; po.bob = -1
            case 2: po.footA = -amp; po.footB = amp
            default: po.liftA = 1; po.bob = -1
            }
        }
        func swing(_ amp: Int) {
            let k = f == 0 ? 1 : (f == 2 ? -1 : 0)
            po.handA = (k * amp, 4 - abs(k))
            po.handB = (-k * amp, 4 - abs(k))
        }
        func lump(_ n: Int) -> (w: Int, h: Int) { n <= 3 ? (2, 2) : (n <= 9 ? (3, 2) : (n <= 16 ? (4, 3) : (5, 4))) }
        func onHead() {
            guard p.carry > 0 else { return }
            let l = lump(p.carry)
            po.lump = l.w; po.lumpX = -l.w / 2; po.lumpY = -8 - l.h
        }
        switch p.anim {
        case .stand:
            break
        case .walk:
            legs(2); swing(1)
        case .run:
            legs(3); swing(2); po.lean = 1
        case .carry:
            legs(2)
            po.handA = (6, 2); po.handB = (1, 2)
            let l = lump(p.carry)
            po.lump = l.w; po.lumpX = 3; po.lumpY = 3 - l.h
        case .scoop:
            po.crouch = 2; po.lean = 2
            po.footA = 1; po.footB = 1
            po.handA = (6, 4); po.handB = (2, 5)
        case .pat:
            if p.mode == .ladder {
                po.back = true
                po.handA = (0, -6 + beat); po.handB = (0, -5 - beat)
            } else {
                po.crouch = 1; po.lean = 1
                po.handA = (5, 2 + beat); po.handB = (1, 3 - beat)
            }
        case .pack:
            po.handA = (6, 2); po.handB = (1, 2 - beat)
            po.lump = 2; po.lumpX = 3; po.lumpY = 1
        case .windup:
            po.lean = -1
            po.handA = (5, 1); po.handB = (-2, -4)
            po.lump = 2; po.lumpX = 0; po.lumpY = -6
        case .thrown:
            po.lean = 2
            po.handA = (2, 4); po.handB = (3, 0)
            po.footB = 2; po.footA = -1
        case .flinch:
            po.lean = -2
            po.handA = (4, 0); po.handB = (-1, 1)
            po.eyesShut = true
        case .flail:
            po.handA = (-1 - beat, -4); po.handB = (1 + beat, -4)
            po.footA = -2; po.footB = 2
            po.mouth = true
        case .down:
            po.lying = true
            po.eyesShut = p.t < 0.6 || beat == 0
            po.handA = (-1, 3); po.handB = (2, 3)
        case .getup:
            po.crouch = 2; po.lean = 1
        case .cheer:
            po.handA = (-1, -5); po.handB = (1, -5)
            po.jump = beat == 0 ? 2 : 0
            po.mouth = true
        case .hop:
            po.crouch = 1
            po.handA = (5, 1); po.handB = (2, 1)
        case .wave:
            po.handB = (1 + beat, -5)
            po.mouth = true
        case .sit:
            po.sit = true
            let sw = Int(time * 2.2 + Float(p.id)) & 1
            po.footA = sw; po.footB = 1 - sw
            po.handA = (0, 3); po.handB = (0, 3)
        case .gaze:
            po.lean = -1
            po.mouth = true
            po.handA = (-1, 3); po.handB = (1, 3)
        case .push:
            legs(2)
            po.lean = 2
            po.handA = (6, 1); po.handB = (2, 1)
        case .climb:
            po.back = true
            let c = Int(p.walkPhase * 2) & 1
            po.handA = (0, -6 + c * 2); po.handB = (0, -4 - c * 2)
            po.liftA = c == 0 ? 2 : 0; po.liftB = c == 0 ? 0 : 2
            onHead()
        case .hang:
            po.back = true
            po.handA = (0, -5); po.handB = (0, -5)
            onHead()
        case .handUp:
            po.back = true
            po.handA = (1, -7); po.handB = (-1, -7)
            if p.carry > 0 {
                let l = lump(p.carry)
                po.lump = l.w; po.lumpX = -l.w / 2; po.lumpY = -7 - l.h
            }
        case .reachDown:
            po.back = true
            po.handA = (0, -5); po.handB = (1, 5)
        case .hold:
            legs(2)
            po.handA = (5, -5); po.handB = (0, -6)
        case .dig:              // копает руками, отбрасывая снег назад
            po.crouch = 1; po.lean = 2
            po.footA = 1; po.footB = 1
            po.handA = beat == 0 ? (6, 4) : (3, -1)
            po.handB = beat == 0 ? (-3, -2) : (2, 5)
        case .mourn:            // стоит, опустив голову, руки к соседям
            po.lean = 1
            po.eyesShut = true
            po.handA = (-2, 3); po.handB = (2, 3)
        case .crawl:            // ползёт (в тоннеле); голова — по ходу
            po.lying = true
            let c = Int(p.walkPhase * 2) & 1
            po.handA = (0, 3 + c); po.handB = (0, 4 - c)
            po.footA = c; po.footB = 1 - c
        case .shovel:           // машет лопатой
            po.crouch = beat == 0 ? 1 : 0
            po.lean = beat == 0 ? 2 : 0
            po.handA = beat == 0 ? (6, 3) : (5, -1)
            po.handB = beat == 0 ? (2, 3) : (1, -2)
            po.shovel = beat == 0 ? 1 : 2
        case .panic:            // мечется, руки вверх
            legs(3)
            po.handA = (-1 - beat, -5); po.handB = (1 + beat, -5)
            po.mouth = true
        case .pull:             // тянет санки за верёвку
            legs(2)
            po.lean = 1
            po.handA = (-3, 2); po.handB = (1, 3)
        case .ride:             // сидит на санках
            po.sit = true
            po.handA = (1, 3); po.handB = (1, 3)
        case .warm:             // греет руки
            po.handA = (5, 0); po.handB = (2, 0 + beat)
        case .carryTree:        // несёт ёлку на плече
            legs(2)
            po.handA = (1, -2); po.handB = (0, -3)
        case .huddle:           // съёжился и дрожит; время от времени встаёт потопать и подышать на руки
            let shiver = Int(time * 15 + Float(p.id) * 3) & 1
            if fmodf(time + Float(p.id) * 1.9, 6.5) < 1.4 {
                po.handA = (4, -1); po.handB = (2, -1 - beat)
                po.liftA = beat; po.liftB = 1 - beat
                po.mouth = true
            } else {
                po.crouch = 2
                po.lean = 1 + Float(shiver) * 0.6
                po.footA = 1; po.footB = 1
                po.handA = (3, 2 + shiver); po.handB = (-3, 2 + (1 - shiver))
                po.eyesShut = true
            }
        case .angel:            // лёжа машет руками и ногами — снежный ангел
            po.lying = true
            po.handA = (-1 - beat * 2, 1 + beat); po.handB = (1 + beat * 2, 1 + beat)
            po.footA = -1 - beat; po.footB = 1 + beat
            po.mouth = true
        }
        if p.flinch > 0 && !po.lying {
            po.lean -= 1
            po.eyesShut = true
        }
        if p.low && !po.lying && p.mode == .ground {    // под низким сводом — ползком
            po = Pose()
            po.lying = true
            let c = Int(p.walkPhase * 2) & 1
            po.handA = (0, 3 + c); po.handB = (0, 4 - c)
            po.footA = c; po.footB = 1 - c
        }
        if !po.eyesShut && fmodf(time + Float(p.id) * 1.7, 4.3) < 0.13 { po.eyesShut = true }      // моргнул
        return po
    }

    func draw(_ c: inout Canvas, _ po: Pose, _ look: Look, snowHat: Bool) {
        let legLen = look.kid ? 3 : 4, rows = look.kid ? 4 : 5
        let hip = (po.sit ? 0 : -legLen + po.crouch) + po.bob
        func leg(_ hx: Int, _ foot: Int, _ lift: Int, toe: Int) {
            if po.sit {
                c.rect(hx + foot, hip, 2, 3, cPants)
                c.rect(hx + foot, hip + 3, 2, 1, cBoots)
                return
            }
            let boot = -1 - lift
            let n = boot - hip
            if n > 0 {
                for k in 0..<n {
                    c.rect(hx + Int((Float(foot) * Float(k + 1) / Float(n + 1)).rounded()), hip + k, 2, 1, cPants)
                }
            }
            c.rect(hx + foot, boot, 2 + toe, 1, cBoots)
        }
        leg(-2, po.footA, po.liftA, toe: 0)
        leg(0, po.footB, po.liftB, toe: po.back ? 0 : 1)

        let top = hip - rows                    // строка плеч
        let lx = Int(po.lean.rounded())
        func arm(_ sx: Int, _ hand: (Int, Int)) {
            let ex = sx + hand.0, ey = top + hand.1
            c.line(sx, top, ex, ey, cSleeve)
            c.set(ex, ey, cMitten)
        }
        arm(-4 + lx, po.handA)                  // дальняя рука — под курткой

        for k in 0..<rows {                     // куртка
            let y = hip - 1 - k
            let sx = Int((po.lean * Float(k) / Float(rows - 1)).rounded())
            c.rect(-3 + sx, y, 6, 1, k == 0 ? cJacketD : cJacket)
            c.set(2 + sx, y, cJacketD)
        }
        if look.girl && !po.sit {               // пальто подлиннее
            c.rect(-3, hip - 1, 6, 1, cJacket)
            c.rect(-3, hip, 6, 1, cJacketD)
        }
        c.rect(-3 + lx, top - 1, 6, 1, cScarf)  // шарф
        if po.back { c.rect(lx, top, 1, 2, cScarf) } else { c.rect(-4 + lx, top - 1, 1, 2, cScarf) }

        let hx = Int((po.lean * 1.25).rounded())
        c.rect(-3 + hx, top - 5, 6, 4, cSkin)   // голова
        if po.back {
            c.rect(-3 + hx, top - 5, 6, 3, look.hatKind == 2 ? cJacket : cHat)
            if look.girl { c.rect(-3 + hx, top - 3, 6, 2, cHair); c.rect(-1 + hx, top - 1, 2, 3, cHair) }
        } else {
            c.set(-1 + hx, top - 3, po.eyesShut ? cHair : cEye)      // закрытые глаза — светлой чёрточкой
            c.set(1 + hx, top - 3, po.eyesShut ? cHair : cEye)
            if po.mouth { c.set(hx, top - 2, cMouth) }
            if look.girl {                      // косички
                c.rect(-4 + hx, top - 4, 1, 4, cHair)
                c.rect(3 + hx, top - 4, 1, 4, cHair)
            }
        }
        switch look.hatKind {
        case 1:     // ушанка
            c.rect(-3 + hx, top - 7, 6, 2, cHat)
            c.rect(-3 + hx, top - 5, 6, 1, cHat2)
            c.rect(-4 + hx, top - 5, 1, 3, cHat)
            c.rect(3 + hx, top - 5, 1, 3, cHat)
        case 2:     // капюшон
            c.rect(-3 + hx, top - 7, 6, 2, cJacket)
            c.rect(-4 + hx, top - 6, 1, 5, cJacket)
            c.rect(3 + hx, top - 6, 1, 5, cJacketD)
            c.rect(-3 + hx, top - 5, 6, 1, cJacketD)
            c.set(-3 + hx, top - 7, 0); c.set(2 + hx, top - 7, 0)
        case 3:     // шапка с полоской
            c.rect(-3 + hx, top - 7, 6, 2, cHat)
            c.rect(-3 + hx, top - 6, 6, 1, cScarf)
            c.rect(-3 + hx, top - 5, 6, 1, cHat2)
            c.set(-3 + hx, top - 7, 0); c.set(2 + hx, top - 7, 0)
        default:    // с помпоном
            c.rect(-3 + hx, top - 7, 6, 2, cHat)
            c.rect(-3 + hx, top - 5, 6, 1, cHat2)
            c.set(-3 + hx, top - 7, 0); c.set(2 + hx, top - 7, 0)
            c.rect(-1 + hx, top - 8, 2, 1, cPom)
        }
        if snowHat { c.rect(-2 + hx, top - 8, 4, 1, cSnow) }

        arm(3 + lx, po.handB)                   // ближняя рука — поверх
        if po.shovel != 0 {                     // лопата: черенок от кисти и совок
            let hx0 = 3 + lx + po.handB.0, hy0 = top + po.handB.1
            if po.shovel == 1 {
                c.line(hx0 - 1, hy0 - 3, hx0 + 3, hy0 + 2, cWood)
                c.rect(hx0 + 3, hy0 + 2, 3, 2, cMetal)
            } else {
                c.line(hx0 - 1, hy0 + 3, hx0 + 2, hy0 - 3, cWood)
                c.rect(hx0 + 1, hy0 - 6, 3, 3, cMetal)
                c.rect(hx0 + 1, hy0 - 7, 3, 1, cSnow)
            }
        }
        if po.lump > 0 {
            let w = po.lump, h = max(2, po.lump - 1)
            c.rect(po.lumpX + lx, top + po.lumpY, w, h, cSnow)
            c.rect(po.lumpX + lx, top + po.lumpY + h - 1, w, 1, cSnowD)
        }
    }

    /// Все «пиксели» человечков, снежков и запасённого снега для этого кадра.
    func emit(_ s: Sim, into out: inout [PxInst]) {
        emitHome(s, into: &out)                 // иглу, костры — позади человечков
        emitFun(s, into: &out)                  // ёлки, санки
        emitRescue(s, into: &out)               // палочки на месте завалов
        if folks.isEmpty && shots.isEmpty && ladders.isEmpty { return }
        let white = SIMD4<Float>(0.97, 0.985, 1, 1), shade = SIMD4<Float>(0.80, 0.86, 0.96, 1)
        for L in ladders {                      // приставные лестницы: стойки и перекладины из наста
            let lw = L.c1 - L.c0 + 1
            let bot = bottomRow(L, s)
            let rail: UInt16 = 1 | (UInt16(1) << UInt16(lw - 1))
            for k in L.rows.indices where L.rows[k] != 0 {
                let y = Float(bot - k) * s.cell
                let above = k + 1 < L.rows.count ? L.rows[k + 1] : 0
                let below = k > 0 ? L.rows[k - 1] : 0xFFFF
                for b in 0..<lw where L.rows[k] & (UInt16(1) << UInt16(b)) != 0 {
                    let bit = UInt16(1) << UInt16(b)
                    let x = Float(L.c0 + b) * s.cell
                    let n = Float((k &* 73 &+ b &* 151 &+ L.id &* 31) % 17) / 17        // лёгкая рябь, как у снега в сетке
                    var c = above & bit == 0 ? SIMD3<Float>(0.90, 0.965, 1.0) : SIMD3<Float>(0.62, 0.78, 0.97)
                    if rail & bit != 0 && above & bit != 0 && (k % L.rs) == 0 { c = SIMD3(0.70, 0.84, 0.98) }
                    c *= 0.95 + 0.06 * n
                    out.append(PxInst(rect: SIMD4(x, y, s.cell, s.cell), color: SIMD4(min(c.x, 1), min(c.y, 1), min(c.z, 1), 1)))
                    if L.frost > 0.15 && above & bit == 0 {     // занесло: снежок на перекладине
                        let h = (s.cell * (0.3 + 0.9 * L.frost)).rounded()
                        out.append(PxInst(rect: SIMD4(x, y - h, s.cell, h), color: SIMD4(0.97, 0.985, 1, 1)))
                    }
                    if below & bit == 0 {       // мягкая тень под перекладиной
                        out.append(PxInst(rect: SIMD4(x, y + s.cell, s.cell, s.cell), color: SIMD4(0, 0, 0.004, 0.2)))
                    }
                }
            }
        }
        for L in ladders where L.stock > 0 {    // снег, сложенный у лестницы
            let n = min(4, L.stock / 10 + 1)
            let hx = handX(L, s) + Float(L.out) * 2 * u
            let bx = (hx / u).rounded() * u, by = ((surface(s, x: hx, stand: L.base) ?? platformY(L, s)) / u).rounded() * u
            for k in 0..<n {
                let x = bx + Float(k % 2) * 2 * u - 2 * u, y = by - Float(k / 2 + 1) * 2 * u + u
                out.append(PxInst(rect: SIMD4(x, y, 3 * u, 2 * u), color: white))
                out.append(PxInst(rect: SIMD4(x, y + u, 3 * u, u), color: shade))
            }
        }
        for p in folks {
            if p.x < -40 || p.x > s.wPt + 40 || p.job == .buried || p.mode == .inside { continue }
            canvas.clear()
            let po = pose(p, s.time)
            draw(&canvas, po, p.look, snowHat: p.snowHat > 0)
            let bx = (p.x / u).rounded() * u
            let by = ((p.y + (p.mode == .ground ? u : 0)) / u).rounded() * u - Float(po.jump) * u
            let dir = po.lying && p.anim != .crawl && !p.low ? p.fallDir : p.face
            for cy in 0..<Canvas.h {
                for cx in 0..<Canvas.w {
                    let ci = canvas.px[cy * Canvas.w + cx]
                    if ci == 0 { continue }
                    var lx = cx - Canvas.ox, ly = cy - Canvas.oy
                    if po.lying {               // лежит на спине, головой по ходу падения
                        let h = -ly - 1
                        ly = -(lx + 5)
                        lx = h
                    }
                    let wx = dir > 0 ? bx + Float(lx) * u : bx - Float(lx + 1) * u
                    out.append(PxInst(rect: SIMD4(wx, by + Float(ly) * u, u, u), color: p.look.pal[Int(ci)]))
                }
            }
        }
        for sh in shots {
            let x = (sh.x / u).rounded() * u, y = (sh.y / u).rounded() * u
            out.append(PxInst(rect: SIMD4(x - u, y - u, 2 * u, 2 * u), color: white))
            out.append(PxInst(rect: SIMD4(x, y, u, u), color: shade))
        }
    }
}
