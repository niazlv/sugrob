import Foundation

// Снег живёт в двух состояниях:
//  - лежащий: воксельная сетка `snow` (ячейка = cell пунктов), неподвижна, пока есть опора;
//  - летящий: частицы `parts` (снежинки и комья), у них есть скорость, ветер и гравитация.
// Ячейка, потерявшая опору, превращается в ком и падает; ком, упавший на опору, снова
// становится ячейкой и скатывается по склону. Снежные шары — отдельные твёрдые тела.

struct Rng {
    var s: UInt64
    init(seed: UInt64) { s = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17
        return s
    }
    mutating func f() -> Float { Float(next() >> 40) * (1.0 / 16777216.0) }
    mutating func range(_ a: Float, _ b: Float) -> Float { a + (b - a) * f() }
    mutating func shade() -> UInt8 { UInt8(1 + next() % 255) }
}

struct Particle {
    var x: Float, y: Float, vx: Float, vy: Float
    var fall: Float      // установившаяся скорость падения снежинки
    var phase: Float
    var size: Float
    var alpha: Float
    var kind: UInt8      // 0 — снежинка, 1 — ком
    var shade: UInt8
    var passer: Bool     // снежинка «перед окнами»: пролетает мимо оконных карнизов
    var ghost: Float = 0 // секунды, пока ком пролетает сквозь лежащий снег (его только что выбили)
    var drift: Float = 0 // собственный боковой снос снежинки
    var fresh = true     // только что появилась: в этом же кадре не двигается (см. stepParticles)
    var hard: UInt8 = 0  // слежалость снега, из которого ком (см. Sim.hard)
}

/// Горизонтальная опора: верх окна (kind 1), Dock (kind 2) или значок рабочего стола (kind 3).
/// Координаты в пунктах экрана.
struct Ledge {
    var y: Float
    var x0: Float
    var x1: Float
    var kind: UInt8
    var win: Int
    var ox: Float = 0      // левый край окна: от него отсчитывается рисунок бугров, чтобы он ехал с окном
    var wr: Float = .infinity   // правый край окна
    var r: Float = 0       // радиус скругления углов окна: у краёв опора идёт по дуге, а не по прямой
    var cap: Float = 0     // предел высоты шапки, pt; 0 — обычный для такой опоры (окно 20, Dock 14)
}

/// Всё, что лежит на одном рабочем столе: при переключении столов снег у каждого свой.
struct SimState {
    var snow: [UInt8]
    var hard: [UInt8]
    var balls: [Ball]
    var segs: [Ledge]
    var blockers: [WinBox]
}

/// Рамка окна в пунктах экрана: по ним решается, где над опорой свободно и снег может копиться сам.
struct WinBox {
    var x0: Float, x1: Float, y0: Float, y1: Float
    var win: Int
}

/// Сугроб и шары, убранные вместе с окном (другой рабочий стол, свёрнуто, скрыто).
struct PileStash {
    var cells: [(dx: Int32, dy: Int32, sh: UInt8, hd: UInt8)] = []
    var balls: [Ball] = []
}

struct Ball {
    var id: Int32
    var x: Float, y: Float
    var vx: Float = 0, vy: Float = 0
    var r: Float
    var angle: Float = 0
    var parent: Int32 = -1     // шар, к которому прилип (снеговик)
    var offX: Float = 0, offY: Float = 0
    var held = false
    var grounded = false
    var hasChild = false
    var seed: Float
    var pick: Float = 0        // сколько ячеек шар «должен» намотать за пройденный путь
    var rest: Float = 0        // сколько секунд шар стоит неподвижно
    var cover: Float = 0       // 0…1: насколько его замело (шапка сверху, намёт по бокам)
    var squash: Float = 0      // 0…1: насколько осел, прежде чем стать сугробом
    var pressAcc: Float = 0    // запас «продавливания» снега под тяжёлым шаром
    var bury: Float = 0        // 0…1: насколько шар уже занесён сугробом по бокам
    var cutA: Float = 0        // скол: направление среза в осях самого шара
    var cutD: Float = 0        // скол: глубина среза в долях радиуса (0 — шар целый)
    var brittle = false        // слежавшийся шар, сорвавшийся со снеговика: бьётся от слабого удара
    var loose: Float = 0       // секунды, пока только что отлепившийся шар не может прилипнуть снова
    // обозначения снеговика — свойство самого шара: 0 нет, 1 лицо (голова), 2 пуговицы и ветки (туловище)
    var decor: UInt8 = 0
    var decorA: Float = 0      // при каком повороте шара обозначения стоят прямо
    var wear: Float = 0        // насколько обозначения закатаны новым снегом (1 — пропали)
    // стоящий шар — опора для снега (Sim.mask): номер его места и где он был, когда маску ставили
    var slot: UInt8 = 0
    var mx: Float = 0, my: Float = 0, mr: Float = 0
    var stillT: Float = 0      // сколько секунд шар не двигается
}

struct SimConfig {
    var flakeRate: Float = 14      // снежинок в секунду на 1000 pt ширины
    var fallMin: Float = 22
    var fallMax: Float = 64
    var wind: Float = 0            // pt/с, плюс — вправо
    var gust: Float = 6
    var intensity: Float = 1       // скорость нарастания сугробов
    var capScale: Float = 1        // множитель предельной высоты (20 pt окно, 14 Dock, 30 низ экрана)
    var sweepRadius: Float = 16
    var openOnly = false           // true — снег сам копится только там, где над опорой нет другого окна
    var floor = true               // снег копится внизу экрана
    var sweep = true               // курсор смахивает снег
    var aging = true               // снег со временем слёживается и подмерзает
    var agingRate: Float = 1       // ускорение старения (для тестов)
    var people = 0                 // человечки (People.swift): 0 — не приходят, 1 — редко, 2 — иногда, 3 — часто
    var peopleLadders = true       // строят лестницы к окнам
    var peopleSize: Float = 2      // размер «пикселя» человечка, pt
    var peopleStay = true          // кто-то из гостей может остаться жить: построить иглу
    var peopleEvents = true        // зимние происшествия: снег с карниза, санки, ёлка
    var storms = true              // время от времени налетает буран (Wind.swift)
}

/// Поверхность, на которой копится снег: карниз окна, Dock или низ экрана.
private struct Surface {
    var row: Int          // строка верхнего края опоры
    var rows: [Int32]     // строка опоры в каждом столбце (у скруглённых углов ниже); снег лежит выше неё
    var c0: Int
    var caps: [UInt8]     // предел высоты по столбцам, в ячейках
    var win: Int          // чьё это: номер окна, -1 Dock, -2 низ экрана
    var top: Float        // выше этой линии шапка не растёт (строка меню)
    var rate: [Float]     // скорость нарастания по столбцам, pt/с
}

final class Sim {
    let cell: Float
    let inv: Float
    let W: Int
    let H: Int
    let wPt: Float
    let hPt: Float

    var cfg = SimConfig() { didSet { rebuildSurfaces() } }
    private var surfaces: [Surface] = []
    private var blockers: [WinBox] = []
    var forceFill = false
    // счётчики за последний шаг — для стресс-теста
    private(set) var statDeposits = 0
    private(set) var statSpawns = 0
    private var accumAcc: Float = 0
    private var hbuf: [UInt8] = []
    private var ceff: [Int] = []
    private var capFixed: [Bool] = []
    var snow: [UInt8]
    /// Слежалость каждой ячейки снега, 0…255. Свежий снег рыхлый; полежав, становится плотным
    /// (от `Sim.dense`): хуже сдвигается, держит склон круче. Давний подмерзает в наст (от `Sim.frozen`):
    /// курсором не смахнуть, только расколоть резким ударом или снежком.
    var hard: [UInt8]
    /// Ячейки, занятые стоящим шаром (номер его места 1…250, 0 — свободно). Стоящий шар — твёрдая опора:
    /// снег ложится на него сверху, комья о него останавливаются, а в ячейках самого шара может лежать
    /// налипший снег. Шар сдвинулся или исчез — маска снимается, и снег с него осыпается.
    var mask: [UInt8]
    private var slotUsed = [Bool](repeating: false, count: 256)
    private var slotBox = [(x0: Int, y0: Int, x1: Int, y1: Int)](repeating: (0, 0, -1, -1), count: 256)
    static let dense: UInt8 = 80
    static let frozen: UInt8 = 200
    var hardDirty = true
    private var ageAcc: Float = 0
    private var ageSlice = 0
    var ledge: [UInt8]
    private var queued: [UInt8]
    private var wakeQ: [Int32] = []
    private var sweepBuf: [Int32] = []
    private var sweepShade: [UInt8] = []
    /// Пустоты внутри сугробов (под настом): 1 — пустая ячейка под сводом. Только для отрисовки.
    var cave: [UInt8]
    var caveDirty = true
    private var caveCols: [UInt8]       // столбцы, где пустоты могли появиться или исчезнуть
    /// Сколько столбец сугроба «должен» осесть, в ячейках, — отдельно для каждого сугроба
    /// (индекс — строка его опоры и столбец). Копится плавно, поэтому соседние столбцы
    /// оседают почти одновременно и поверхность не рябит.
    private var sinkAcc: [Float]
    private var caveAny = false
    private var caveTick = 0
    private var frameNo = 0
    /// Сколько пустоты может быть внутри сугроба, ячеек: выше — это уже не пустота, а просто воздух.
    let gapMax: Int
    // счётчики жизни старого снега — для самотеста
    private(set) var statSettled = 0     // ячеек ушло на уплотнение и испарение снизу
    private(set) var statHollowed = 0    // ячеек свода испарилось над пустотой
    private(set) var statCollapsed = 0   // ячеек слежавшегося снега обрушилось
    private(set) var statMelted = 0      // ячеек подтаяло снизу у сугробов выше предела

    var parts = ContiguousArray<Particle>()
    var balls: [Ball] = []
    var segs: [Ledge] = []

    var gridDirty = true
    var time: Float = 0
    var windNow: Float = 0
    var handsMode = false
    var topLimit: Float = 0    // выше этой линии (строка меню) падающий снег не копится
    var minRoom: Float = 0     // но окну вплотную к строке меню оставляем хотя бы столько места под шапку
    private(set) var heldId: Int32 = -1

    private var rng: Rng
    private var spawnAcc: Float = 0
    private var nextBallId: Int32 = 1

    // курсор
    private(set) var cx: Float = -1000
    private(set) var cy: Float = -1000
    private var prevX: Float = -1000
    private var prevY: Float = -1000
    private(set) var cvx: Float = 0
    private(set) var cvy: Float = 0
    private(set) var cursorOn = false

    let maxParts = 60000
    let maxBallR: Float = 64
    let breakSpeed: Float = 1000
    let gravity: Float = 1500
    // через сколько секунд покоя шар примерзает к месту
    static let stuckAfter: Float = 20
    static let heavyR: Float = 10          // шары крупнее продавливают снег и гонят перед собой вал

    init(widthPt: Float, heightPt: Float, cell: Float, seed: UInt64 = 0) {
        self.cell = cell
        self.inv = 1 / cell
        self.wPt = widthPt
        self.hPt = heightPt
        self.W = max(1, Int((widthPt / cell).rounded(.up)))
        self.H = max(1, Int((heightPt / cell).rounded(.up)))
        snow = [UInt8](repeating: 0, count: W * H)
        hard = [UInt8](repeating: 0, count: W * H)
        mask = [UInt8](repeating: 0, count: W * H)
        cave = [UInt8](repeating: 0, count: W * H)
        caveCols = [UInt8](repeating: 0, count: W)
        let w = W
        sinkAcc = (0..<(w * (H + 1))).map { 0.5 + 0.45 * sinf(Float($0 % w) * 0.07) }    // плавный сдвиг фазы вдоль экрана
        gapMax = max(3, Int((40 / cell).rounded(.up)))
        ledge = [UInt8](repeating: 0, count: W * H)
        queued = [UInt8](repeating: 0, count: W * H)
        rng = Rng(seed: seed == 0 ? UInt64(Date().timeIntervalSince1970 * 1000) | 1 : seed)
        parts.reserveCapacity(8192)
        rebuildSurfaces()
    }

    // MARK: - Сетка

    @inline(__always) private func isFree(_ x: Int, _ y: Int) -> Bool {
        if x < 0 || x >= W || y >= H { return false }
        if y < 0 { return true }
        let i = y * W + x
        return snow[i] == 0 && ledge[i] == 0 && mask[i] == 0
    }

    @inline(__always) private func wake(_ x: Int, _ y: Int) {
        if x < 0 || x >= W || y < 0 || y >= H { return }
        let i = y * W + x
        if snow[i] != 0 && queued[i] == 0 {
            queued[i] = 1
            wakeQ.append(Int32(i))
        }
    }

    private func wakeRegion(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
        let ax = max(0, x0), bx = min(W - 1, x1), ay = max(0, y0), by = min(H - 1, y1)
        if ax > bx || ay > by { return }
        for y in ay...by { for x in ax...bx { wake(x, y) } }
    }

    private func ledgeCells(_ s: Ledge) -> (row: Int, c0: Int, c1: Int)? {
        let row = Int((s.y * inv).rounded())
        let c0 = max(0, Int((s.x0 * inv).rounded(.up)))
        let c1 = min(W - 1, Int((s.x1 * inv).rounded(.down)) - 1)
        if row < 1 || row >= H || c0 > c1 { return nil }
        return (row, c0, c1)
    }

    /// Строка опоры в столбце c. У скруглённого угла окна опора идёт по дуге — ниже верхнего края.
    private func colRow(_ s: Ledge, _ c: Int) -> Int {
        var y = s.y
        if s.r > 0 {
            let x = (Float(c) + 0.5) * cell
            let d = max(0, min(x - s.ox, s.wr - x))
            if d < s.r {
                let k = s.r - d
                y += s.r - sqrtf(max(0, s.r * s.r - k * k))
            }
        }
        return max(1, min(H - 1, Int((y * inv).rounded())))
    }

    /// Новая раскладка опор. Снег над исчезнувшими опорами теряет поддержку и осыпается.
    func setLedges(_ new: [Ledge], windows: [WinBox] = []) {
        let old = segs
        blockers = windows
        for s in old {
            guard let (_, c0, c1) = ledgeCells(s) else { continue }
            for x in c0...c1 { ledge[colRow(s, x) * W + x] = 0 }
        }
        var snapped: [Ledge] = []
        snapped.reserveCapacity(new.count)
        for s in new {
            guard let (row, c0, c1) = ledgeCells(s) else { continue }
            var t = s
            t.y = Float(row) * cell
            for x in c0...c1 { ledge[colRow(t, x) * W + x] = s.kind }
            snapped.append(t)
        }
        for s in old {
            guard let (_, c0, c1) = ledgeCells(s) else { continue }
            for x in c0...c1 {
                let r = colRow(s, x)
                if ledge[r * W + x] == 0 { wake(x, r - 1) }
            }
        }
        segs = snapped
        rebuildSurfaces()
    }

    /// Окно сдвинулось: сугроб над его карнизом переезжает вместе с ним целиком, ячейка в ячейку.
    /// При резком рывке верхний слой срывается и отстаёт.
    func shiftPile(_ s: Ledge, cols: Int, rows: Int, vx: Float, vy: Float) {
        guard cols != 0 || rows != 0, let (_, c0, c1) = ledgeCells(s) else { return }
        let speed = sqrtf(vx * vx + vy * vy)
        let shed = max(0, min(0.6, (speed - 700) / 2500))
        var moved: [(x: Int, y: Int, sh: UInt8, hd: UInt8, top: Bool, bottom: Bool)] = []
        for x in c0...c1 {
            let row = colRow(s, x)
            ledge[row * W + x] = 0
            let h = pileHeight(x, row)
            var under = true            // под ячейкой опора (карниз) или пустота — её надо будет проверить
            var y = row - 1
            while y >= row - h {
                let i = y * W + x
                if snow[i] != 0 {
                    moved.append((x, y, snow[i], hard[i], y == 0 || snow[i - W] == 0, under))
                    snow[i] = 0
                    under = false
                } else {
                    under = true
                }
                y -= 1
            }
        }
        markCaves(c0 + min(0, cols), c1 + max(0, cols))
        for m in moved {
            let nx = m.x + cols, ny = m.y + rows
            let px = (Float(nx) + 0.5) * cell, py = (Float(ny) + 0.5) * cell
            if nx < 0 || nx >= W || ny < 0 || ny >= H { continue }
            let i = ny * W + nx
            if m.top && shed > 0 && m.hd < Sim.frozen && rng.f() < shed {
                spawnChunk(px, py, vx * 0.35 + rng.range(-30, 30), min(vy, 0) * 0.3 - rng.range(20, 90), m.sh, hard: m.hd)
            } else if snow[i] == 0 && ledge[i] == 0 {
                snow[i] = m.sh
                hard[i] = m.hd
                if m.bottom { wake(nx, ny) }     // нижний ряд сам проверит, есть ли под ним опора
            } else {
                spawnChunk(px, py, vx * 0.3, 0, m.sh, hard: m.hd)
            }
        }
        hardDirty = true
        let dx = Float(cols) * cell, dy = Float(rows) * cell
        people.pileShifted(self, s, dx: dx, dy: dy)
        for i in balls.indices where balls[i].grounded && balls[i].parent == -1 {
            let b = balls[i]
            if b.y + b.r < s.y + 2.5 && b.y + b.r > s.y - 90 && b.x > s.x0 - b.r && b.x < s.x1 + b.r {
                balls[i].x += dx
                balls[i].y += dy
            }
        }
        gridDirty = true
    }

    // MARK: - Накопление

    /// Рисунок бугров вдоль поверхности: 0.32…1.
    private func lobe(_ a: Float, _ phase: Float) -> Float {
        0.66 + sinf(a * 0.031 + phase) * 0.2 + sinf(a * 0.083 + phase * 1.9 + 0.7) * 0.1 + sinf(a * 0.171 + phase * 0.6) * 0.04
    }

    /// Плавный шум 0…1 вдоль поверхности.
    private func vnoise(_ x: Float) -> Float {
        func h(_ n: Float) -> Float { let v = sinf(n * 127.1 + 311.7) * 43758.5453; return v - v.rounded(.down) }
        let i = x.rounded(.down), f = x - i
        let u = f * f * (3 - 2 * f)
        return h(i) * (1 - u) + h(i + 1) * u
    }

    private func rebuildSurfaces() {
        surfaces.removeAll(keepingCapacity: true)
        func make(row: Int, rows: [Int32], c0: Int, c1: Int, base: Float, phase: Float, ox: Float, x0: Float, x1: Float,
                  taper: Bool, own: Int) {
            // Снег сам копится только там, где над опорой свободно: если в полосе над ней
            // лежит другое окно (спереди или сзади), шапка закрыла бы его содержимое.
            let y = Float(row) * cell
            let band = base * cfg.capScale + 2
            let slope: Float = 26
            // сколько места над опорой до строки меню; если мало — вся шапка пропорционально ниже
            let top = min(topLimit, y - minRoom)
            let fit = min(1, max(0, y - top) / (base * cfg.capScale * 1.45))
            var blocked: [(Float, Float)] = []
            // низ экрана открыт всегда: снег там лежит и поверх окон, доходящих до края
            for b in blockers where cfg.openOnly && own != -2 && b.win != own && b.y0 < y - 0.5 && b.y1 > y - band && b.x1 > x0 && b.x0 < x1 {
                blocked.append((b.x0 - 2, b.x1 + 2))
            }
            var caps: [UInt8] = [], rate: [Float] = []
            caps.reserveCapacity(c1 - c0 + 1); rate.reserveCapacity(c1 - c0 + 1)
            for c in c0...c1 {
                let x = (Float(c) + 0.5) * cell
                // Расстояние до ближайшего места, где снегу лежать нельзя: край опоры или чужое окно.
                // К такому месту шапка плавно сходит на нет, а не обрывается стенкой.
                var dist: Float = taper ? min(x - x0, x1 - x) : .infinity
                for b in blocked {
                    if x < b.0 { dist = min(dist, b.0 - x) }
                    else if x > b.1 { dist = min(dist, x - b.1) }
                    else { dist = 0 }
                }
                if dist <= 0 {
                    caps.append(0); rate.append(0)
                    continue
                }
                var t: Float = 1
                if dist < slope {
                    let e = dist / slope
                    t = e * e * (3 - 2 * e)
                }
                // крупные бугры плюс мелкая неровность, чтобы верх не был как по линейке
                let a = x - ox
                let l = lobe(a, phase)
                let rough = 1 + (vnoise(a * 0.065 + phase) - 0.5) * 0.55 + (vnoise(a * 0.17 + phase * 1.7) - 0.5) * 0.3
                caps.append(UInt8(max(0, min(250, (base * cfg.capScale * l * rough * t * fit / cell).rounded()))))
                rate.append((0.16 + 0.2 * l) * t)
            }
            surfaces.append(Surface(row: row, rows: rows, c0: c0, caps: caps, win: own, top: top, rate: rate))
        }
        var dock: [(Int, Int)] = []
        for s in segs {
            guard let (row, c0, c1) = ledgeCells(s) else { continue }
            if s.kind == 2 { dock.append((c0, c1)) }
            make(row: row, rows: (c0...c1).map { Int32(colRow(s, $0)) }, c0: c0, c1: c1, base: s.cap > 0 ? s.cap : (s.kind == 2 ? 14 : 20), phase: Float(abs(s.win) % 997) * 0.17,
                 ox: s.ox, x0: s.x0, x1: s.x1, taper: true, own: s.win)
        }
        make(row: H, rows: [Int32](repeating: Int32(H), count: W), c0: 0, c1: W - 1, base: 30, phase: 1.3, ox: 0, x0: 0, x1: wPt, taper: false, own: -2)
        if !cfg.floor {
            for c in 0..<W { surfaces[surfaces.count - 1].caps[c] = 0 }
        }
        for (c0, c1) in dock {      // под Dock снег не копится
            for c in max(0, c0 - 2)...min(W - 1, c1 + 2) { surfaces[surfaces.count - 1].caps[c] = 0 }
        }
    }

    /// Высота сугроба над строкой опоры row в столбце c — до самой верхней ячейки. Пустоты внутри
    /// (под настом) сугроб не обрывают: свод лежит над ними, и новый снег ложится на свод, а не в пустоту.
    private func pileHeight(_ c: Int, _ row: Int) -> Int {
        var y = row - 1
        var h = 0, gap = 0
        while y >= 0 && row - y <= 250 {
            let i = y * W + c
            if mask[i] != 0 { break }               // выше — стоящий шар, это уже не сугроб
            if snow[i] != 0 {
                h = row - y
                gap = 0
            } else if ledge[i] != 0 {
                break
            } else {
                gap += 1
                if gap > gapMax { break }
            }
            y -= 1
        }
        return h
    }

    /// Снежинка упала в столбец px около строки py: кладём ячейку на шапку под ней,
    /// если та ещё не доросла до своего предела (те же волнистые пределы и то же правило
    /// «не поверх чужого окна», что и при самонарастании).
    private func flakeLands(_ px: Int, _ py: Int) {
        var yy = max(0, py)
        var n = 0
        while yy < H && ledge[yy * W + px] == 0 && n < 260 { yy += 1; n += 1 }   // строка опоры под снежинкой
        let row = yy
        guard let s = surfaces.first(where: {
            px >= $0.c0 && px < $0.c0 + $0.caps.count && Int($0.rows[px - $0.c0]) == row
        }) else { return }
        let j = px - s.c0
        var best = j
        var bh = pileHeight(px, row)
        var bd = Int(s.caps[j]) - bh
        for k in [j - 1, j + 1] where k >= 0 && k < s.caps.count {
            let h = pileHeight(s.c0 + k, Int(s.rows[k]))
            let d = Int(s.caps[k]) - h
            if d > bd { bd = d; best = k; bh = h }
        }
        if bd <= 0 && rng.f() >= intake(bh, Int(s.caps[best])) { return }
        let c = s.c0 + best
        let y = Int(s.rows[best]) - 1 - bh
        if y < 0 || Float(y) * cell < s.top { return }
        let i = y * W + c
        if snow[i] != 0 || ledge[i] != 0 || mask[i] != 0 { return }
        snow[i] = rng.shade()
        hard[i] = 0
        gridDirty = true
    }

    /// Насыпать снег разом до предела на всех открытых поверхностях.
    func fillSurfaces(only win: Int? = nil) {
        guard cfg.intensity > 0 || forceFill else { return }
        for s in surfaces where win == nil || s.win == win {
            for j in 0..<s.caps.count {
                let c = s.c0 + j
                var h = pileHeight(c, Int(s.rows[j]))
                var y = Int(s.rows[j]) - 1 - h
                while h < Int(s.caps[j]) && y >= 0 && Float(y) * cell >= s.top
                        && snow[y * W + c] == 0 && ledge[y * W + c] == 0 {
                    snow[y * W + c] = rng.shade()
                    hard[y * W + c] = 0
                    h += 1; y -= 1
                }
            }
        }
        gridDirty = true
    }

    /// Сугробы растут равномерно по всей поверхности до своего волнистого предела:
    /// новая ячейка ложится туда, где до предела дальше всего, поэтому верх получается гладким.
    private func accumulate(_ dt: Float) {
        accumAcc += dt
        guard accumAcc >= 0.1 else { return }
        if cfg.intensity > 0 { grow(accumAcc) }
        relieve(accumAcc)
        accumAcc = 0
    }

    /// Какая доля нового снега ещё ложится на сугроб высотой h при пределе cap. До предела — весь.
    /// Предел не обрывает снегопад: выше него ложится малая доля (и всё меньше, но не выше полутора
    /// пределов), а лишнее съедают уплотнение под весом и подтаивание снизу (см. relieve).
    private func intake(_ h: Int, _ cap: Int) -> Float {
        if cap <= 0 { return 0 }
        if h < cap { return 1 }
        return max(0, 0.03 * (1 - (Float(h) / Float(cap) - 1) / 0.5))
    }

    /// Сугроб выше предела сам себя укорачивает: лишний вес сильнее трамбует снег, а под толстым
    /// слоем снег у тёплого окна и у земли подтаивает снизу. Убыль копится плавно (тем же счётчиком,
    /// что и обычное оседание), и проседает самый высокий из соседних столбцов — поверхность остаётся
    /// ровной. Поэтому у предела сугроб не застывает, а медленно обновляется: сверху свежий снег, снизу уходит старый.
    private func relieve(_ step: Float) {
        let r = step * max(cfg.agingRate, 0.01)
        for s in surfaces {
            let n = s.caps.count
            for j in 0..<n where s.caps[j] > 0 {
                let c = s.c0 + j, row = Int(s.rows[j])
                let over = Float(pileHeight(c, row)) / Float(s.caps[j]) - 1
                if over <= 0 { continue }
                let a = row * W + c
                sinkAcc[a] += 0.032 * over * r
                guard sinkAcc[a] >= 1 else { continue }
                sinkAcc[a] -= 1
                var best = j, bestH = -1
                for k in max(0, j - 1)...min(n - 1, j + 1) where Int(s.rows[k]) == row && s.caps[k] > 0 {
                    let h = pileHeight(s.c0 + k, row)
                    if h > bestH || (h == bestH && k == j) { bestH = h; best = k }
                }
                let x = s.c0 + best
                // Убывает верхний пласт — тот, что лежит на поверхности. Стоит он на опоре — подтаивает
                // снизу, и столбец оседает целиком. Лежит сводом над пустотой — уплотняется над ней, а сама
                // пустота не меняется: если бы свод таял снизу в одном столбце, в сугробе прорезались бы
                // узкие щели. Тонкий свод не трогаем, чтобы не проесть его насквозь.
                var y = row - bestH
                guard y >= 0, y < row, snow[y * W + x] != 0 else { continue }
                let top = y
                while y + 1 < row && snow[(y + 1) * W + x] != 0 { y += 1 }
                if y < row - 1 && y - top < 3 { continue }
                statMelted += 1
                settleAway(x, y, fromBase: false)
            }
        }
    }

    /// Снег, который «нападал», пока этот рабочий стол был не на экране.
    func catchUp(_ seconds: Float) {
        if cfg.aging {          // пока стола не было на экране, снег на нём тоже слёживался
            let add = min(255, seconds * 0.44 * cfg.agingRate)
            for i in snow.indices where snow[i] != 0 {
                let covered = i >= W && snow[i - W] != 0
                hard[i] = UInt8(min(255, Float(hard[i]) + add * (covered ? 2 : 1)))
            }
            hardDirty = true
        }
        guard cfg.intensity > 0 else { return }
        var t = min(seconds, 240)
        while t > 0 { grow(min(t, 1)); relieve(min(t, 1)); t -= 1 }
    }

    private func grow(_ step: Float) {
        let k = step * cfg.intensity / cell
        // Стоящий шар заметает: снег набивается в угол под его нависающим боком и растёт
        // намётом рядом, со временем — до самой макушки. Внутрь шара снег не кладётся.
        var resting: [(x: Float, r: Float, row: Int, cover: Float, bury: Float, pile: Int)] = []
        for b in balls where b.parent == -1 && b.grounded && !b.held {
            if let sup = support(x: b.x, centerY: b.y, r: b.r, ledges: true) {
                let pile = Int(((Float(sup.row) * cell - (b.y + bottomExt(b))) * inv).rounded())
                resting.append((b.x, b.r, sup.row, b.cover, b.bury, pile))
            }
        }
        for s in surfaces {
            let n = s.caps.count
            ceff.removeAll(keepingCapacity: true)
            capFixed.removeAll(keepingCapacity: true)
            for j in 0..<n {
                var c = Int(s.caps[j])
                var fixed = false               // рядом шар: предел задаёт его бок, сверх него снег не ляжет
                if !resting.isEmpty {
                    let x = (Float(s.c0 + j) + 0.5) * cell
                    for b in resting where b.row == s.row {
                        let dn = abs(x - b.x) / b.r
                        if dn < 1 {
                            let under = b.r * (1 - sqrtf(1 - dn * dn))          // зазор между снегом и боком шара
                            c = b.pile + Int(under * min(1, b.cover * 1.3) * inv)
                            fixed = true
                        } else if dn < 2.2 {
                            let hgt = (b.cover * 0.35 + b.bury * 1.5) * b.r * (1 - (dn - 1) / 1.2)
                            c = max(c, b.pile + Int(hgt * inv))
                            fixed = true
                        }
                    }
                }
                ceff.append(c)
                capFixed.append(fixed)
            }
            hbuf.removeAll(keepingCapacity: true)
            for j in 0..<n {
                hbuf.append(UInt8(min(250, pileHeight(s.c0 + j, Int(s.rows[j])))))
            }
            for j in 0..<n {
                if rng.f() >= s.rate[j] * k { continue }
                var best = j
                var bd = ceff[j] - Int(hbuf[j])
                if j > 0 { let d = ceff[j - 1] - Int(hbuf[j - 1]); if d > bd { bd = d; best = j - 1 } }
                if j + 1 < n { let d = ceff[j + 1] - Int(hbuf[j + 1]); if d > bd { bd = d; best = j + 1 } }
                if bd <= 0 {
                    // Сугроб уже у предела: свежий снег ещё ложится, но редко и сразу тонкой полоской
                    // на несколько соседних столбцов (не выше них) — без одиночных зубцов на поверхности.
                    if capFixed[best] || rng.f() * 5 >= intake(Int(hbuf[best]), ceff[best]) { continue }
                    let h0 = Int(hbuf[best])
                    for k in max(0, best - 2)...min(n - 1, best + 2) where !capFixed[k] && ceff[k] > 0 && Int(hbuf[k]) <= h0
                        && s.rows[k] == s.rows[best] {
                        let c = s.c0 + k
                        let y = Int(s.rows[k]) - 1 - Int(hbuf[k])
                        if y < 0 || Float(y) * cell < s.top { continue }
                        let i = y * W + c
                        if snow[i] != 0 || ledge[i] != 0 { continue }
                        snow[i] = rng.shade()
                        hard[i] = 0
                        hbuf[k] += 1
                        gridDirty = true
                    }
                    continue
                }
                let c = s.c0 + best
                let y = Int(s.rows[best]) - 1 - Int(hbuf[best])
                if y < 0 || Float(y) * cell < s.top { continue }
                let i = y * W + c
                if snow[i] != 0 || ledge[i] != 0 { continue }
                snow[i] = rng.shade()
                hard[i] = 0
                hbuf[best] += 1
                gridDirty = true
            }
        }
        accreteOnBalls(step)
    }

    // MARK: - Рабочие столы

    func saveState() -> SimState {
        SimState(snow: snow, hard: hard, balls: balls.filter { !$0.held }, segs: segs, blockers: blockers)
    }

    /// Загрузить снег другого рабочего стола (nil — на этом столе ещё не были).
    /// Снежинки в воздухе остаются, комья старого стола исчезают.
    func loadState(_ st: SimState?) {
        for i in queued.indices { queued[i] = 0 }
        wakeQ.removeAll(keepingCapacity: true)
        parts.removeAll { $0.kind == 1 }
        heldId = -1
        for i in ledge.indices { ledge[i] = 0 }
        segs = []
        if let st, st.snow.count == snow.count {
            snow = st.snow
            hard = st.hard
            resetMasks()
            balls = st.balls
            for i in balls.indices { balls[i].slot = 0 }
            setLedges(st.segs, windows: st.blockers)
        } else {
            for i in snow.indices { snow[i] = 0 }
            resetMasks()
            balls = []
            setLedges([], windows: [])
        }
        markCaves(0, W - 1)
        gridDirty = true
        hardDirty = true
    }

    // MARK: - Окно ушло с экрана и вернулось

    /// Забрать сугроб и шары с карнизов окна (окно ушло на другой рабочий стол, свёрнуто или скрыто).
    func extractPile(win: Int) -> PileStash {
        var st = PileStash()
        for s in segs where s.win == win {
            guard let (row, c0, c1) = ledgeCells(s) else { continue }
            let oc = Int((s.ox * inv).rounded())
            for x in c0...c1 {
                let cr = colRow(s, x)
                for y in stride(from: cr - 1, through: cr - pileHeight(x, cr), by: -1) where snow[y * W + x] != 0 {
                    st.cells.append((Int32(x - oc), Int32(y - row), snow[y * W + x], hard[y * W + x]))
                    snow[y * W + x] = 0
                }
            }
            markCaves(c0, c1)
            var ids = Set<Int32>()
            for b in balls where b.parent == -1 && !b.held && b.grounded
                && b.y + b.r < s.y + 2.5 && b.y + b.r > s.y - 90 && b.x > s.x0 - b.r && b.x < s.x1 + b.r { ids.insert(b.id) }
            var grew = true
            while grew {
                grew = false
                for b in balls where b.parent != -1 && ids.contains(b.parent) && !ids.contains(b.id) {
                    ids.insert(b.id); grew = true
                }
            }
            for b in balls where ids.contains(b.id) {
                var c = b
                c.x -= s.ox; c.y -= s.y
                st.balls.append(c)
            }
            balls.removeAll { ids.contains($0.id) }
        }
        gridDirty = true
        return st
    }

    /// Убрать снег с низа экрана на участке (для выключателя «Внизу экрана»).
    func extractFloor(x0: Float, x1: Float) -> PileStash {
        var st = PileStash()
        let c0 = max(0, Int(x0 * inv)), c1 = min(W - 1, Int(x1 * inv))
        guard c0 <= c1 else { return st }
        for x in c0...c1 {
            for y in stride(from: H - 1, through: H - pileHeight(x, H), by: -1) where snow[y * W + x] != 0 {
                st.cells.append((Int32(x), Int32(y), snow[y * W + x], hard[y * W + x]))
                snow[y * W + x] = 0
            }
        }
        markCaves(c0, c1)
        gridDirty = true
        return st
    }

    /// Dock выезжает из-под низа экрана и поднимает на себе снег, который там лежал.
    func liftFloor(x0: Float, x1: Float, toY y: Float) {
        let c0 = max(0, Int(x0 * inv)), c1 = min(W - 1, Int(x1 * inv))
        let row = Int((y * inv).rounded())
        guard c0 <= c1, row >= 1, row < H else { return }
        let up = H - row
        for x in c0...c1 {
            var col: [(UInt8, UInt8)] = []
            for yy in stride(from: H - 1, through: H - pileHeight(x, H), by: -1) {     // вместе с пустотами
                col.append((snow[yy * W + x], hard[yy * W + x]))
                snow[yy * W + x] = 0
            }
            for (k, c) in col.enumerated() where c.0 != 0 {
                let ny = H - 1 - k - up
                if ny < 0 || snow[ny * W + x] != 0 { continue }
                snow[ny * W + x] = c.0
                hard[ny * W + x] = c.1
                wake(x, ny)         // у скруглённых краёв Dock опора ниже — там снег досыплется сам
            }
        }
        for i in balls.indices where balls[i].parent == -1 && balls[i].grounded && !balls[i].held {
            let b = balls[i]
            if b.x > x0 && b.x < x1 && b.y + b.r > hPt - 90 { balls[i].y -= Float(up) * cell }
        }
        people.floorShifted(self, x0: x0, x1: x1, dy: -Float(up) * cell)     // человечки и их постройки едут вместе со снегом
        markCaves(c0, c1)
        gridDirty = true
        hardDirty = true
    }

    /// Dock уезжает вниз: снег с него опускается обратно на низ экрана.
    func dropDock() {
        for s in segs where s.win == -1 {
            guard let (row, c0, c1) = ledgeCells(s) else { continue }
            for x in c0...c1 {
                var col: [(UInt8, UInt8)] = []
                let cr = colRow(s, x)
                for yy in stride(from: cr - 1, through: cr - pileHeight(x, cr), by: -1) {    // вместе с пустотами
                    col.append((snow[yy * W + x], hard[yy * W + x]))
                    snow[yy * W + x] = 0
                }
                var ny = H - 1 - pileHeight(x, H)
                for c in col {
                    if ny < 0 { break }
                    if c.0 != 0 && snow[ny * W + x] == 0 && ledge[ny * W + x] == 0 {
                        snow[ny * W + x] = c.0
                        hard[ny * W + x] = c.1
                        wake(x, ny)
                    }
                    ny -= 1
                }
            }
            markCaves(c0, c1)
            let down = Float(H - row) * cell
            for i in balls.indices where balls[i].parent == -1 && balls[i].grounded && !balls[i].held {
                let b = balls[i]
                if b.x > s.x0 && b.x < s.x1 && b.y + b.r < s.y + 2.5 && b.y + b.r > s.y - 90 { balls[i].y += down }
            }
            people.floorShifted(self, x0: s.x0, x1: s.x1, dy: down)
        }
        gridDirty = true
        hardDirty = true
    }

    /// Вернуть сугроб на окно, которое снова на экране (ox, y — левый верхний угол окна).
    func insertPile(_ st: PileStash, ox: Float, y: Float) {
        let oc = Int((ox * inv).rounded()), row = Int((y * inv).rounded())
        for c in st.cells {
            let x = oc + Int(c.dx), yy = row + Int(c.dy)
            if x < 0 || x >= W || yy < 0 || yy >= H { continue }
            markCave(x)
            let i = yy * W + x
            if snow[i] == 0 && ledge[i] == 0 {
                snow[i] = c.sh
                hard[i] = c.hd
                wake(x, yy)
            }
        }
        for var b in st.balls {
            b.x += ox; b.y += Float(row) * cell
            b.vx = 0; b.vy = 0
            balls.append(b)
        }
        gridDirty = true
        hardDirty = true
    }

    /// Снять со всего снега слежалость (выключили «снег слёживается»).
    func resetHardness() {
        for i in hard.indices { hard[i] = 0 }
        hardDirty = true
        for y in 0..<max(0, H - 1) {           // рыхлый снег над пустотами больше не держится
            for x in 0..<W where snow[y * W + x] != 0 && isFree(x, y + 1) { wake(x, y) }
        }
    }

    /// Снег слёживается: поверхность медленнее, под слоем — вдвое быстрее.
    /// Плотным становится примерно за 3 минуты (под слоем за 1,5), настом — за 7,5 (под слоем за 4).
    private func age(_ dt: Float) {
        guard cfg.aging else { return }
        ageAcc += dt
        var passes = 0
        var changed = false
        while ageAcc >= 0.1 && passes < 10 {
            ageAcc -= 0.1
            passes += 1
            var y = ageSlice
            ageSlice = (ageSlice + 1) % 10
            let p = 0.44 * cfg.agingRate
            let rate = cfg.agingRate
            while y < H {
                let base = y * W
                for x in 0..<W where snow[base + x] != 0 {
                    let i = base + x
                    let covered = y > 0 && snow[i - W] != 0
                    if hard[i] < 255 {
                        let q = covered ? p * 2 : p
                        var add = Int(q)                       // при ускорении — больше единицы за проход
                        if rng.f() < q - Float(add) { add += 1 }
                        if add > 0 {
                            hard[i] = UInt8(min(255, Int(hard[i]) + add))
                            changed = true
                        }
                    }
                    // Каждая ячейка проходится раз в секунду. Что со временем делается со старым снегом:
                    // 0 — под ячейкой пустота, 1 — снег, 2 — сама опора (окно, Dock, низ экрана)
                    let below = y + 1 >= H ? 2 : (snow[i + W] != 0 ? 1 : (ledge[i + W] != 0 ? 2 : 0))
                    if below == 0 {
                        // Свод над пустотой понемногу испаряется снизу — там, где пустота уже широкая:
                        // она растёт вверх куполом, плита над ней становится тоньше.
                        if hard[i] >= Sim.dense && x > 0 && x < W - 1 && snow[i - 1] != 0 && snow[i + 1] != 0
                            && isFree(x - 1, y + 1) && isFree(x + 1, y + 1) && rng.f() < 0.0015 * rate
                            && hollowBelow(x, y) < gapMax - 4 {
                            hollowOut(x, y)
                        }
                    } else if covered {
                        // Слои в сугробе лежат ровно: ячейка, которая осела глубже соседей и оказалась мягче
                        // их с обеих сторон (свежий снег, затянутый в старый), смерзается с ними за десяток
                        // секунд. Иначе на границе свежего и старого снега тянулись бы вертикальные «потёки».
                        if x >= 2 && x < W - 2 {
                            let hl = max(snow[i - 1] != 0 ? hard[i - 1] : 0, snow[i - 2] != 0 ? hard[i - 2] : 0)
                            let hr = max(snow[i + 1] != 0 ? hard[i + 1] : 0, snow[i + 2] != 0 ? hard[i + 2] : 0)
                            let up = Int(min(hl, hr)), hd = Int(hard[i])
                            if up > hd + 6 {
                                hard[i] = UInt8(min(255, hd + max(1, Int(Float(up - hd) * 0.25 * min(rate, 4)))))
                                changed = true
                            }
                        }
                        // У самой опоры старый снег испаряется и перекристаллизуется (глубинная изморозь;
                        // окно к тому же тёплое), а наст над ним остаётся плитой — под ним пустота.
                        // Новая пустота зарождается редко, а у края уже существующей снег уходит быстрее:
                        // пустоты получаются цельными и широкими, а не дырявыми.
                        if below == 2 && hard[i] >= Sim.dense && y > 0 {
                            let edge = (x > 0 && snow[i - 1] == 0 && ledge[i - 1] == 0 && snow[i - W - 1] != 0)
                                || (x < W - 1 && snow[i + 1] == 0 && ledge[i + 1] == 0 && snow[i - W + 1] != 0)
                            if rng.f() < (edge ? 0.01 : 0.00008) * rate { settleAway(x, y, fromBase: true); continue }
                        }
                        // Уплотнение под весом: свежий снег оседает быстро, фирн почти не сжимается.
                        // Сколько давит — по числу ячеек сверху (до трёх).
                        var load: Float = 1
                        if y >= 2 && snow[i - 2 * W] != 0 { load += 1; if y >= 3 && snow[i - 3 * W] != 0 { load += 1 } }
                        var b = y + 1
                        while b < H && snow[b * W + x] != 0 { b += 1 }
                        let a = b * W + x
                        sinkAcc[a] += 0.003 * max(0, 1 - Float(hard[i]) / 280) * load / 3 * rate
                        if sinkAcc[a] >= 1 {
                            sinkAcc[a] -= 1
                            // Оседает самый высокий из соседних столбцов, а из равных — тот, что у края уступа:
                            // уступ отступает ровно, поверхность сглаживается и не покрывается зубцами.
                            var tops = [Int](repeating: y + 1, count: 5)       // верх столбцов x-2…x+2 (меньше — выше)
                            for d in -2...2 {
                                let c = x + d
                                guard c >= 0 && c < W && snow[y * W + c] != 0 else { continue }
                                var t = y
                                while t > 0 && snow[(t - 1) * W + c] != 0 { t -= 1 }
                                tops[d + 2] = t
                            }
                            var sx = x, best = (tops[2], -(tops[1] + tops[3]))
                            for d in [-1, 1] where tops[d + 2] <= y {
                                let key = (tops[d + 2], -(tops[d + 1] + tops[d + 3]))
                                if key < best { best = key; sx = x + d }
                            }
                            // Дно пустоты под настом не проседает, если пустота и так почти предельной высоты:
                            // выше gapMax её уже не считают частью сугроба (ни на рисунке, ни при снегопаде).
                            let t = best.0
                            if t > 0 && hollowAbove(sx, t) >= gapMax - 4 {
                                continue
                            }
                            settleAway(sx, y, fromBase: false)
                        }
                    }
                }
                y += 10
            }
        }
        if ageAcc > 1 { ageAcc = 0 }
        if changed { hardDirty = true }
    }

    // MARK: - Старый снег: плиты, оседание, пустоты

    /// Держится ли слежавшаяся ячейка, под которой пусто. Плотный снег и наст ведут себя как плита:
    /// опираются на соседей по горизонтали — мостом между двумя опорами или козырьком от одной.
    /// Пролёт тем больше, чем твёрже снег и толще плита; тяжёлый шар сверху его укорачивает.
    private func holds(_ x: Int, _ y: Int) -> Bool {
        let hd = hard[y * W + x]
        if hd < Sim.dense { return false }
        let t = Float(Int(hd) - Int(Sim.dense)) / Float(255 - Int(Sim.dense))
        var th = 1
        while th < 6 && y - th >= 0 && snow[(y - th) * W + x] != 0 { th += 1 }
        var span = (8 + 34 * t) * min(1.6, max(0.45, Float(th) * cell / 7)) * inv      // ячеек
        let px = (Float(x) + 0.5) * cell, py = Float(y) * cell
        for b in balls where b.grounded && b.parent == -1 && !b.held && b.r >= Sim.heavyR
            && abs(b.x - px) < b.r && b.y < py && py - b.y < b.r + 60 {
            span *= max(0.3, 1 - (b.r - 6) / 45)         // тяжёлый шар давит на плиту
        }
        let cant = span * 0.32
        let reach = Int(span) + 1
        func anchor(_ dir: Int) -> Int {
            var d = 1
            while d <= reach {
                let sx = x + dir * d
                if sx < 0 || sx >= W { return -1 }
                let j = y * W + sx
                if ledge[j] != 0 { return d }
                if snow[j] == 0 { return -1 }
                if !isFree(sx, y + 1) { return d }
                d += 1
            }
            return -1
        }
        let dl = anchor(-1), dr = anchor(1)
        if (dl > 0 && Float(dl) <= cant) || (dr > 0 && Float(dr) <= cant) { return true }
        return dl > 0 && dr > 0 && Float(dl + dr) <= span
    }

    /// Средняя высота сугробов в долях их предела: низ экрана и окна (для самотеста).
    func fillLevel() -> (floor: Float, windows: Float) {
        var fs: Float = 0, fn: Float = 0, ws: Float = 0, wn: Float = 0
        for s in surfaces {
            for j in 0..<s.caps.count where s.caps[j] >= 3 {
                let u = Float(pileHeight(s.c0 + j, Int(s.rows[j]))) / Float(s.caps[j])
                if s.win == -2 { fs += u; fn += 1 } else if s.win >= 0 { ws += u; wn += 1 }
            }
        }
        return (fn > 0 ? fs / fn : 0, wn > 0 ? ws / wn : 0)
    }

    /// Перепроверить все висящие ячейки (для самотеста, когда снег расставлен вручную).
    func recheckHanging() { wakeHanging(0, 0, W - 1, H - 2) }

    /// Самый широкий пролёт плиты (твёрдый наст, толстая плита), ячеек: дальше опору не ищем.
    private var reachMax: Int { Int(42 * 1.6 * inv) + 2 }

    /// Разбудить висящие ячейки в прямоугольнике: у них могла смениться опора.
    private func wakeHanging(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
        let ax = max(0, x0), bx = min(W - 1, x1), ay = max(0, y0), by = min(H - 2, y1)
        if ax > bx || ay > by { return }
        for y in ay...by {
            for x in ax...bx where snow[y * W + x] != 0 && snow[(y + 1) * W + x] == 0 && ledge[(y + 1) * W + x] == 0 {
                wake(x, y)
            }
        }
    }

    @inline(__always) private func markCave(_ x: Int) {
        if x >= 0 && x < W { caveCols[x] = 1; caveAny = true }
    }

    private func markCaves(_ x0: Int, _ x1: Int) {
        let a = max(0, x0), b = min(W - 1, x1)
        if a > b { return }
        for x in a...b { caveCols[x] = 1 }
        caveAny = true
    }

    /// Ячейка (x, y) ушла: снег под весом уплотнился или испарился у опоры. То, что лежит над ней,
    /// оседает на ячейку вниз; наст, который держится плитой, остаётся — под ним пустота.
    private func settleAway(_ x: Int, _ y: Int, fromBase: Bool) {
        let i = y * W + x
        if fromBase {
            // У опоры снег уходит, только если наст над ним держится плитой сам: тогда под настом
            // остаётся пустота. Где плиты нет, снег сверху тут же сел бы на это место.
            guard y > 0, snow[i - W] != 0, hard[i - W] >= Sim.frozen else { return }
            let sh = snow[i]
            snow[i] = 0
            let carried = holds(x, y - 1)
            snow[i] = sh
            if !carried { return }
        }
        snow[i] = 0
        statSettled += 1
        var k = y - 1
        while k >= 0 {
            let j = k * W + x
            if snow[j] == 0 { break }
            // медленное уплотнение проседает вместе со всем, что сверху, даже с настом
            if fromBase && hard[j] >= Sim.frozen && holds(x, k) { markCave(x); break }
            snow[j + W] = snow[j]
            hard[j + W] = hard[j]
            snow[j] = 0
            k -= 1
        }
        if k < y - 1 {
            // столбец осел: верх стал ниже, а снег, что сел на место ушедшего, плотнее
            hard[i] = UInt8(min(255, Int(hard[i]) + 8))
            slump(x, k, depth: 4)
            wake(x - 1, k + 1); wake(x + 1, k + 1); wake(x - 1, k); wake(x + 1, k)
        } else {
            markCave(x)
        }
        wakeHanging(x - reachMax, max(0, k), x + reachMax, y)
        gridDirty = true
        hardDirty = true
    }

    /// Старый снег не стоит столбиками: если сосед оказался выше на две ячейки, его верх
    /// сползает сюда (снег медленно течёт). Поверхность остаётся плавной, объём не меняется.
    /// (x, k) — пустое место прямо над верхом столбца x.
    private func slump(_ x: Int, _ k: Int, depth: Int) {
        guard depth > 0, k >= 1, snow[k * W + x] == 0, ledge[k * W + x] == 0 else { return }
        var best = -1, bestTop = Int.max
        for nx in [x - 1, x + 1] where nx >= 0 && nx < W {
            guard snow[k * W + nx] != 0, snow[(k - 1) * W + nx] != 0 else { continue }
            var t = k - 1
            while t > 0 && snow[(t - 1) * W + nx] != 0 { t -= 1 }
            if t < bestTop || (t == bestTop && rng.next() & 1 == 0) { bestTop = t; best = nx }
        }
        guard best >= 0 else { return }
        let from = bestTop * W + best, to = k * W + x
        snow[to] = snow[from]
        hard[to] = hard[from]
        snow[from] = 0
        slump(best, bestTop, depth: depth - 1)
    }

    /// Высота пустоты над ячейкой (x, y), если сверху её закрывает снег (иначе 0 — над ней открыто).
    private func hollowAbove(_ x: Int, _ y: Int) -> Int {
        var d = 0, k = y - 1
        while k >= 0 && d <= gapMax && snow[k * W + x] == 0 && ledge[k * W + x] == 0 { d += 1; k -= 1 }
        return k >= 0 && d <= gapMax && snow[k * W + x] != 0 ? d : 0
    }

    /// Высота пустоты под ячейкой (x, y), ячеек (не больше gapMax).
    private func hollowBelow(_ x: Int, _ y: Int) -> Int {
        var d = 0, k = y + 1
        while k < H && d < gapMax && snow[k * W + x] == 0 && ledge[k * W + x] == 0 { d += 1; k += 1 }
        return d
    }

    /// Нижняя ячейка свода над пустотой испарилась: пустота выросла вверх, плита стала тоньше.
    private func hollowOut(_ x: Int, _ y: Int) {
        snow[y * W + x] = 0
        statHollowed += 1
        markCave(x)
        wake(x, y - 1)
        wakeHanging(x - reachMax, y - 1, x + reachMax, y)
        gridDirty = true
    }

    /// Пустоты внутри сугробов для отрисовки: пустые ячейки, над которыми свод, а снизу снег или опора.
    /// Пересчитываются только столбцы, где что-то могло измениться, и не чаще 15 раз в секунду.
    private func updateCaves() {
        guard caveAny else { return }
        caveTick += 1
        if caveTick < 4 { return }
        caveTick = 0
        caveAny = false
        for x in 0..<W where caveCols[x] != 0 {
            var found = false
            var run = -1
            for y in 0..<H {
                let i = y * W + x
                cave[i] = 0
                if snow[i] != 0 || ledge[i] != 0 {
                    if run >= 0 && y - run <= gapMax {
                        for k in run..<y { cave[k * W + x] = 1 }
                        found = true
                    }
                    run = -1
                } else if run < 0 && y > 0 && snow[i - W] != 0 {
                    run = y
                }
            }
            if run >= 0 && H - run <= gapMax {
                for k in run..<H { cave[k * W + x] = 1 }
                found = true
            }
            if found { caveAny = true } else { caveCols[x] = 0 }
        }
        caveDirty = true
    }

    /// Удар снежка раскалывает слежавшийся снег и наст вокруг места удара и выбивает из него комья.
    private func shatter(x: Float, y: Float, r: Float) {
        let x0 = max(0, Int(((x - r) * inv).rounded(.down))), x1 = min(W - 1, Int(((x + r) * inv).rounded(.down)))
        let y0 = max(0, Int(((y - r) * inv).rounded(.down))), y1 = min(H - 1, Int(((y + r) * inv).rounded(.down)))
        if x0 > x1 || y0 > y1 { return }
        for gy in y0...y1 {
            for gx in x0...x1 {
                let i = gy * W + gx
                let sh = snow[i]
                if sh == 0 { continue }
                let px = (Float(gx) + 0.5) * cell, py = (Float(gy) + 0.5) * cell
                let dx = px - x, dy = py - y
                let d2 = dx * dx + dy * dy
                if d2 > r * r { continue }
                let hd = hard[i]
                hard[i] = hd >= Sim.frozen ? 110 : (hd > 50 ? hd - 50 : 0)
                if d2 < r * r * 0.4 {
                    let d = sqrtf(d2) + 0.01
                    snow[i] = 0
                    spawnChunk(px, py, dx / d * rng.range(60, 300) + rng.range(-40, 40), -rng.range(120, 380), sh, hard: hard[i])
                }
            }
        }
        wakeRegion(x0 - 1, y0 - 1, x1 + 1, y1 + 1)
        gridDirty = true
        hardDirty = true
    }

    func clearAll() {
        for i in snow.indices { snow[i] = 0; cave[i] = 0 }
        for x in caveCols.indices { caveCols[x] = 0 }
        caveAny = false
        caveDirty = true
        for i in queued.indices { queued[i] = 0 }
        wakeQ.removeAll(keepingCapacity: true)
        parts.removeAll(keepingCapacity: true)
        balls.removeAll()
        resetMasks()
        heldId = -1
        gridDirty = true
    }

    private func processWake() {
        var i = 0
        let budget = 40000
        while i < wakeQ.count && i < budget {
            let idx = Int(wakeQ[i])
            i += 1
            queued[idx] = 0
            let sh = snow[idx]
            if sh == 0 { continue }
            if mask[idx] != 0 { continue }          // снег, налипший на стоящий шар, держится на нём
            let hd = hard[idx]
            let x = idx % W, y = idx / W
            var dir = 0
            var fall = false
            if isFree(x, y + 1) {
                if hd >= Sim.dense && holds(x, y) {      // слежавшийся снег держится плитой — под ним пустота
                    markCave(x)
                    continue
                }
                fall = true
                if hd >= Sim.dense { statCollapsed += 1; markCave(x) }
            } else if hd < Sim.frozen {      // наст по склону не осыпается — только падает, оставшись без опоры
                let l = isFree(x - 1, y) && isFree(x - 1, y + 1)
                let r = isFree(x + 1, y) && isFree(x + 1, y + 1)
                let l2 = l && isFree(x - 1, y + 2)
                let r2 = r && isFree(x + 1, y + 2)
                if l2 || r2 {
                    dir = (l2 && r2) ? (rng.next() & 1 == 0 ? -1 : 1) : (l2 ? -1 : 1)
                } else if hd < Sim.dense && (l || r) && rng.f() < 0.6 {      // плотный держит склон круче
                    dir = (l && r) ? (rng.next() & 1 == 0 ? -1 : 1) : (l ? -1 : 1)
                }
            }
            if !fall && dir == 0 { continue }
            snow[idx] = 0
            markCave(x)
            gridDirty = true
            let px = (Float(x) + 0.5) * cell, py = (Float(y) + 0.5) * cell
            if fall {
                spawnChunk(px, py, rng.range(-6, 6), rng.range(0, 25), sh, hard: hd)
            } else {
                spawnChunk(px, py, Float(dir) * rng.range(35, 70), -rng.range(0, 15), sh, hard: hd)
            }
            wake(x, y - 1); wake(x - 1, y - 1); wake(x + 1, y - 1); wake(x - 1, y); wake(x + 1, y)
        }
        if i >= wakeQ.count {
            wakeQ.removeAll(keepingCapacity: true)
        } else {
            wakeQ.removeFirst(i)
        }
    }

    /// Высота сугроба под ячейкой и тип опоры под ним (1 — окно, 2 — земля/Dock).
    private func pileInfo(_ x: Int, _ y: Int) -> (h: Int, base: UInt8) {
        var yy = y + 1
        var h = 0
        while yy < H && snow[yy * W + x] != 0 && h < 96 { h += 1; yy += 1 }
        if yy >= H { return (h, 2) }
        let k = ledge[yy * W + x]
        return (h, k == 0 ? 2 : k)
    }

    /// Положить ячейку снега: она проваливается и скатывается, пока склон слишком крут.
    /// (vx, vy) — скорость того, что её принесло: скатываться она предпочитает в ту же сторону,
    /// а сорвавшись с края, летит с этой скоростью, а не падает отвесно.
    private func settle(_ sx: Int, _ sy: Int, _ shade: UInt8, hard hd: UInt8 = 0, vx: Float = 0, vy: Float = 0) {
        var x = sx, y = sy
        var lastDir = 0
        let pref = vx > 20 ? 1 : (vx < -20 ? -1 : 0)
        func pick(_ l: Bool, _ r: Bool) -> Int {
            if l && r { return pref != 0 ? pref : (rng.next() & 1 == 0 ? -1 : 1) }
            return l ? -1 : 1
        }
        for _ in 0..<14 {
            var dropped = 0
            while isFree(x, y + 1) {
                y += 1
                dropped += 1
                if dropped > 2 {
                    spawnChunk((Float(x) + 0.5) * cell, (Float(y) - 1.5) * cell,
                               vx + Float(lastDir) * rng.range(15, 70) + rng.range(-12, 12),
                               vy + rng.range(0, 45), shade, hard: hd)
                    return
                }
            }
            let l = isFree(x - 1, y) && isFree(x - 1, y + 1)
            let r = isFree(x + 1, y) && isFree(x + 1, y + 1)
            if !l && !r { break }
            let l2 = l && isFree(x - 1, y + 2)
            let r2 = r && isFree(x + 1, y + 2)
            let dir = (l2 || r2) ? pick(l2, r2) : pick(l, r)
            x += dir
            y += 1
            lastDir = dir
        }
        if y < 0 || !isFree(x, y) { return }
        snow[y * W + x] = shade
        hard[y * W + x] = hd
        gridDirty = true
        if hd != 0 { hardDirty = true }
    }

    private func deposit(_ p: Particle, _ px: Int, _ py: Int) {
        statDeposits += 1
        if px < 0 || px >= W { return }
        if p.kind == 0 {
            // Когда сугробы растут сами, снежинка просто тает. Когда нет — шапку строят
            // сами упавшие снежинки: где упала, там и легла.
            if cfg.intensity <= 0 {
                flakeLands(px, min(py, H - 1))
                if p.alpha > 0.575 { flakeLands(px, min(py, H - 1)) }   // крупная снежинка — две ячейки
            }
            return
        }
        var y = min(py, H - 1)
        if y < 0 { return }
        var tries = 0
        while !isFree(px, y) && tries < 16 { y -= 1; tries += 1 }
        if y < 0 || !isFree(px, y) { return }
        settle(px, y, p.shade, hard: p.hard > 12 ? p.hard - 12 : 0, vx: p.vx * 0.3)      // от удара снег чуть разрыхляется
    }

    // MARK: - Частицы

    private func spawnChunk(_ x: Float, _ y: Float, _ vx: Float, _ vy: Float, _ shade: UInt8, hard: UInt8 = 0, ghost: Float = 0) {
        statSpawns += 1
        if parts.count >= maxParts { return }
        parts.append(Particle(x: x, y: y, vx: vx, vy: vy, fall: 0, phase: 0, size: cell, alpha: 1,
                              kind: 1, shade: shade, passer: false, ghost: ghost, hard: hard))
    }

    private func makeFlake(x: Float, y: Float) -> Particle {
        let e = rng.f()
        let fall = cfg.fallMin + (cfg.fallMax - cfg.fallMin) * e
        return Particle(x: x, y: y, vx: windNow, vy: fall, fall: fall, phase: rng.range(0, 6.283),
                        size: 2.4 + 3.4 * e * e, alpha: 0.28 + e * 0.6, kind: 0, shade: 1,
                        passer: rng.f() < 0.4, ghost: 0, drift: rng.range(-7, 7))
    }

    private var spawnMargin: Float {
        min(500, abs(windNow) * hPt / max(20, (cfg.fallMin + cfg.fallMax) * 0.5))
    }

    /// Заполнить небо сразу, чтобы снег не «начинался сверху» при запуске.
    func prefill() {
        let avg = max(20, (cfg.fallMin + cfg.fallMax) * 0.5)
        let n = Int(cfg.flakeRate * wPt / 1000 * hPt / avg)
        for _ in 0..<min(n, maxParts / 2) {
            parts.append(makeFlake(x: rng.range(0, wPt), y: rng.range(0, hPt)))
        }
    }

    private func spawnFlakes(_ dt: Float) {
        let m = spawnMargin
        spawnAcc += cfg.flakeRate * dt * (wPt + 2 * m) / 1000
        while spawnAcc >= 1 {
            spawnAcc -= 1
            if parts.count < maxParts {
                parts.append(makeFlake(x: rng.range(-m, wPt + m), y: -rng.range(2, 14)))
            }
        }
    }

    private func pileOnWindow(_ x: Int, _ y: Int) -> Bool {
        var yy = y
        var n = 0
        while yy < H && snow[yy * W + x] != 0 && n < 96 { yy += 1; n += 1 }
        if yy >= H { return false }
        return ledge[yy * W + x] == 1 || ledge[yy * W + x] == 3
    }

    private func stepParticles(_ dt: Float) {
        let kf = min(1, dt * 3)
        let drag = max(0, 1 - 1.4 * dt)
        let g = 1400 * dt
        let cursorPush = cursorOn && (cvx * cvx + cvy * cvy) > 1600
        let pr: Float = 24
        // Твёрдым для комьев курсор бывает только в движении: стоячий курсор в ямке сугроба
        // иначе вечно выталкивал бы комья, которые скатываются под него.
        let solidCursor = cfg.sweep && cursorOn && heldId == -1 && !handsMode && cursorPush
        var budget = parts.count * 2 + 4096
        let cr = cfg.sweepRadius + 1.5
        var i = 0
        while i < parts.count {
            var p = parts[i]
            // Частица, появившаяся в этом кадре (в том числе ком, сорвавшийся при укладке другого),
            // ждёт следующего кадра. Иначе цепочка «упал → сорвался → упал» может крутиться
            // внутри одного кадра бесконечно и подвесить приложение.
            budget -= 1
            if p.fresh || budget < 0 {
                parts[i].fresh = false
                i += 1
                continue
            }
            if p.ghost > 0 { p.ghost -= dt }
            if p.kind == 0 {
                let sway = sinf(p.phase + time * 0.6) * 10
                let tvx = windNow * (0.6 + 0.4 * p.alpha) + p.drift + sway
                p.vx += (tvx - p.vx) * kf
                p.vy += (p.fall - p.vy) * kf
            } else {
                p.vy += g
                p.vx = (p.vx - windNow * 0.3) * drag + windNow * 0.3
                p.vy *= drag
            }
            if solidCursor && p.kind == 1 {
                // Для комьев курсор — твёрдый кружок: они не проваливаются сквозь него,
                // а едут на нём и скатываются по бокам. Иначе сдвинутый снег сыпался бы за курсор.
                let dx = p.x - cx, dy = p.y - cy
                if abs(dx) < cr && abs(dy) < cr {
                    let d2 = dx * dx + dy * dy
                    if d2 < cr * cr {
                        let d = sqrtf(d2)
                        let nx = d > 0.01 ? dx / d : 0, ny = d > 0.01 ? dy / d : -1
                        p.x = cx + nx * cr
                        p.y = cy + ny * cr
                        let vn = (p.vx - cvx) * nx + (p.vy - cvy) * ny
                        if vn < 0 { p.vx -= vn * nx; p.vy -= vn * ny }
                        // трение о руку: ком едет чуть быстрее курсора и скатывается вперёд, а не назад
                        if cursorPush { p.vx += (cvx * 1.2 - p.vx) * 0.35; p.vy += (cvy * 1.2 - p.vy) * 0.2 }
                    }
                }
            }
            if cursorPush && p.kind == 0 {
                let dx = p.x - cx, dy = p.y - cy
                if abs(dx) < pr && abs(dy) < pr && dx * dx + dy * dy < pr * pr {
                    p.vx += (cvx - p.vx) * 0.35
                    p.vy += (cvy - p.vy) * 0.35
                }
            }
            let nx = p.x + p.vx * dt, ny = p.y + p.vy * dt
            let dist = max(abs(nx - p.x), abs(ny - p.y))
            let steps = max(1, min(32, Int(dist * inv) + 1))
            var pcx = Int((p.x * inv).rounded(.down)), pcy = Int((p.y * inv).rounded(.down))
            var dead = false
            for s in 1...steps {
                let t = Float(s) / Float(steps)
                let ccx = Int(((p.x + (nx - p.x) * t) * inv).rounded(.down))
                let ccy = Int(((p.y + (ny - p.y) * t) * inv).rounded(.down))
                if ccx == pcx && ccy == pcy { continue }
                if ccy >= H {
                    deposit(p, pcx, H - 1)
                    dead = true
                    break
                }
                if ccy >= 0 && ccx >= 0 && ccx < W {
                    let idx = ccy * W + ccx
                    var hit = false
                    if snow[idx] != 0 {
                        hit = p.ghost <= 0 && !(p.passer && pileOnWindow(ccx, ccy))
                    } else if ledge[idx] != 0 && ccy > pcy {
                        hit = !(p.passer && (ledge[idx] == 1 || ledge[idx] == 3))
                    } else if mask[idx] != 0 {
                        hit = p.ghost <= 0          // стоящий шар
                        if hit && p.kind == 0 {
                            // снежинка легла на шар: когда сугробы не растут сами, именно такие снежинки
                            // его и заносят; в сугроб под шаром она при этом не попадает
                            if cfg.intensity <= 0 && rng.f() < 0.5 && isFree(pcx, pcy) { settle(pcx, pcy, rng.shade()) }
                            dead = true
                            break
                        }
                    }
                    if hit {
                        deposit(p, pcx, pcy)
                        dead = true
                        break
                    }
                }
                pcx = ccx; pcy = ccy
            }
            if !dead {
                p.x = nx; p.y = ny
                if p.x < -620 || p.x > wPt + 620 || p.y > hPt + 20 || p.y < -4000 { dead = true }
            }
            if dead {
                parts[i] = parts[parts.count - 1]
                parts.removeLast()
            } else {
                parts[i] = p
                i += 1
            }
        }
    }

    // MARK: - Курсор

    func setCursor(x: Float, y: Float, dt: Float, on: Bool) {
        if on && cursorOn && dt > 0 {
            prevX = cx; prevY = cy
            cvx += ((x - cx) / dt - cvx) * 0.6
            cvy += ((y - cy) / dt - cvy) * 0.6
        } else {
            prevX = x; prevY = y
            cvx = 0; cvy = 0
        }
        cx = x; cy = y
        cursorOn = on
    }

    /// Курсор — твёрдый кружок, который вытесняет лежащий снег. Объём сохраняется в каждом кадре:
    /// ячейка сразу переезжает на ближайшее свободное место по ходу движения (перед курсором
    /// растёт вал, который осыпается сам), а при быстром взмахе срывается с поверхности комом.
    private func cursorSweep() {
        guard cfg.sweep, cursorOn, heldId == -1 else { return }
        let dx = cx - prevX, dy = cy - prevY
        let d2 = dx * dx + dy * dy
        guard d2 > 0.09, d2 < 500 * 500 else { return }
        let R = cfg.sweepRadius
        let x0 = max(0, Int(((min(cx, prevX) - R) * inv).rounded(.down)))
        let x1 = min(W - 1, Int(((max(cx, prevX) + R) * inv).rounded(.down)))
        let y0 = max(0, Int(((min(cy, prevY) - R) * inv).rounded(.down)))
        let y1 = min(H - 1, Int(((max(cy, prevY) + R) * inv).rounded(.down)))
        if x0 > x1 || y0 > y1 { return }

        // расстояние от центра ячейки до пути курсора за кадр
        func pathDist2(_ gx: Int, _ gy: Int) -> Float {
            let px = (Float(gx) + 0.5) * cell, py = (Float(gy) + 0.5) * cell
            let t = max(0, min(1, ((px - prevX) * dx + (py - prevY) * dy) / d2))
            let ox = px - (prevX + dx * t), oy = py - (prevY + dy * t)
            return ox * ox + oy * oy
        }

        let speed = sqrtf(cvx * cvx + cvy * cvy)
        let densePick = min(0.6, 0.12 + speed / 2500)       // плотный снег поддаётся не сразу
        sweepBuf.removeAll(keepingCapacity: true)
        for gy in y0...y1 {
            for gx in x0...x1 where snow[gy * W + gx] != 0 {
                if pathDist2(gx, gy) > R * R { continue }
                let i = gy * W + gx
                let hd = hard[i]
                if hd >= Sim.frozen {
                    // наст курсор не берёт; резкий удар раскалывает его в плотные комья
                    if speed > 1100 && rng.f() < 0.5 { hard[i] = 130; hardDirty = true } else { continue }
                } else if hd >= Sim.dense {
                    if rng.f() > densePick { continue }
                    hard[i] = hd - 25           // от толчков разрыхляется
                    hardDirty = true
                }
                sweepBuf.append(Int32(i))
            }
        }
        if sweepBuf.isEmpty { return }
        sweepShade.removeAll(keepingCapacity: true)
        for i in sweepBuf { sweepShade.append(snow[Int(i)]); snow[Int(i)] = 0 }

        let flyP = max(0, min(1, (speed - 150) / 650))
        let dl = sqrtf(d2)
        let mx = dx / dl, my = dy / dl
        let clear = (R + cell * 0.6) * (R + cell * 0.6)

        // идти от ячейки по лучу до первой свободной ячейки вне кружка
        func march(_ gx: Int, _ gy: Int, _ ux: Float, _ uy: Float, _ steps: Int) -> (Int, Int)? {
            var fx = (Float(gx) + 0.5) * cell, fy = (Float(gy) + 0.5) * cell
            for _ in 0..<steps {
                fx += ux * cell; fy += uy * cell
                let qx = Int((fx * inv).rounded(.down)), qy = Int((fy * inv).rounded(.down))
                if qx < 0 || qx >= W || qy < 0 || qy >= H { return nil }
                let q = qy * W + qx
                if ledge[q] != 0 { return nil }
                if snow[q] == 0 && mask[q] == 0 && pathDist2(qx, qy) > clear { return (qx, qy) }
            }
            return nil
        }

        for (k, i) in sweepBuf.enumerated() {
            let idx = Int(i)
            let sh = sweepShade[k]
            let hd = hard[idx]
            let gx = idx % W, gy = idx / W
            let px = (Float(gx) + 0.5) * cell, py = (Float(gy) + 0.5) * cell
            var ox = px - cx, oy = py - cy
            let ol = sqrtf(ox * ox + oy * oy) + 0.001
            ox /= ol; oy /= ol
            // в основном по ходу движения (иначе снег перелетает через курсор и ложится позади),
            // чуть наружу и чуть вверх
            var ux = ox * 0.25 + mx + rng.range(-0.15, 0.15)
            var uy = oy * 0.25 + my - 0.35
            let ul = sqrtf(ux * ux + uy * uy) + 0.001
            ux /= ul; uy /= ul
            let side: Float = (ox + mx * 0.5) >= 0 ? 0.8 : -0.8
            let target = march(gx, gy, ux, uy, 28) ?? march(gx, gy, side, -0.6, 28) ?? march(gx, gy, 0, -1, 48)
            guard let (tx, ty) = target else {
                snow[idx] = sh      // деваться некуда — снег остаётся под курсором
                continue
            }
            if rng.f() < flyP {
                let kk = rng.range(0.45, 1.0)
                var vx = cvx * kk + ox * rng.range(10, 60) + rng.range(-25, 25)
                var vy = cvy * kk + oy * rng.range(10, 60) - rng.range(0, 0.22) * speed - rng.range(0, 40)
                let v = sqrtf(vx * vx + vy * vy)
                if v > 1500 { vx *= 1500 / v; vy *= 1500 / v }
                spawnChunk((Float(tx) + 0.5) * cell, (Float(ty) + 0.5) * cell, vx, vy, sh, hard: hd)
            } else {
                // если под новым местом пусто (столкнули с края) — полетит по ходу руки
                settle(tx, ty, sh, hard: hd, vx: max(-900, min(900, cvx)) * rng.range(0.45, 0.9),
                       vy: max(-400, min(0, cvy)) * 0.5)
            }
        }
        gridDirty = true
        wakeRegion(x0 - 1, y0 - 1, x1 + 1, y1 + 1)
    }

    // MARK: - Снежные шары

    private func ballIndex(_ id: Int32) -> Int? {
        if id == -1 { return nil }
        for i in balls.indices where balls[i].id == id { return i }
        return nil
    }

    private func rootId(_ i: Int) -> Int32 {
        var k = i
        var n = 0
        while balls[k].parent != -1, n < 16, let j = ballIndex(balls[k].parent) { k = j; n += 1 }
        return balls[k].id
    }

    private func grow(_ i: Int, cells n: Int) {
        if n <= 0 { return }
        let area = Float.pi * balls[i].r * balls[i].r + Float(n) * cell * cell * 0.7
        let nr = min(maxBallR, sqrtf(area / .pi))
        let dr = nr - balls[i].r
        balls[i].r = nr
        if !balls[i].held { balls[i].y -= dr }
    }

    /// Шар забирает снег, которого касается (растёт), либо разбрасывает его на лету.
    private func ballEatsSnow(_ i: Int, spray: Bool) {
        let b = balls[i]
        let rr = b.r + cell * 0.5
        let x0 = max(0, Int(((b.x - rr) * inv).rounded(.down)))
        let x1 = min(W - 1, Int(((b.x + rr) * inv).rounded(.down)))
        let y0 = max(0, Int(((b.y - rr) * inv).rounded(.down)))
        let y1 = min(H - 1, Int(((b.y + rr) * inv).rounded(.down)))
        if x0 > x1 || y0 > y1 { return }
        let full = b.r >= maxBallR - 0.01
        var eaten = 0
        var any = false
        for gy in y0...y1 {
            for gx in x0...x1 {
                let idx = gy * W + gx
                let sh = snow[idx]
                if sh == 0 { continue }
                let px = (Float(gx) + 0.5) * cell, py = (Float(gy) + 0.5) * cell
                let dx = px - b.x, dy = py - b.y
                if dx * dx + dy * dy > rr * rr { continue }
                snow[idx] = 0
                any = true
                if spray || full {
                    let hd = hard[idx]
                    spawnChunk(px, py, b.vx * 0.5 + rng.range(-90, 90), b.vy * 0.4 - rng.range(0, 140), sh,
                               hard: hd > 60 ? hd - 60 : 0, ghost: 0.12)
                } else {
                    eaten += 1
                }
            }
        }
        if any {
            gridDirty = true
            wakeRegion(x0 - 1, y0 - 1, x1 + 1, y1 + 1)
            grow(i, cells: eaten)
        }
    }

    /// На что обопрётся шар в точке x, если его центр на высоте centerY: поверхность снега
    /// над ближайшей опорой снизу (карниз окна — только если центр выше его линии — или низ экрана).
    private func support(x: Float, centerY: Float, r: Float, ledges: Bool) -> (surf: Float, row: Int)? {
        var base = hPt
        var row = H
        if ledges {
            for s in segs where x > s.x0 - r * 0.3 && x < s.x1 + r * 0.3 && centerY < s.y - 1 && s.y < base {
                base = s.y
                row = Int((s.y * inv).rounded())
            }
        }
        let c = max(0, min(W - 1, Int(x * inv)))
        var sum = 0, n = 0
        for k in max(0, c - 1)...min(W - 1, c + 1) { sum += pileHeight(k, row); n += 1 }
        return (base - Float(sum) / Float(n) * cell, row)
    }

    /// Шар катится по снегу и наматывает на себя верхний слой: за пройденный путь он забирает
    /// полоску толщиной в долю радиуса, снимая верхушки самых высоких столбцов под собой.
    private func pickSurface(_ i: Int, travelled: Float) {
        let b = balls[i]
        guard b.r < maxBallR - 0.01, travelled > 0,
              let sup = support(x: b.x, centerY: b.y, r: b.r, ledges: true) else { return }
        let layer = max(cell, min(cell * 3, b.r * 0.3))
        balls[i].pick += min(travelled, 40) * layer / (cell * cell)
        let c = max(0, min(W - 1, Int(b.x * inv)))
        let half = max(1, Int(b.r * 0.6 * inv))
        let reach = (b.r + cell * 1.5) * (b.r + cell * 1.5)
        var eaten = 0
        while balls[i].pick >= 1 {
            var bestC = -1, bestH = 0
            for k in max(0, c - half)...min(W - 1, c + half) {
                let h = pileHeight(k, sup.row)
                if h == 0 || h < bestH || (h == bestH && abs(k - c) >= abs(bestC - c)) { continue }
                if hard[(sup.row - h) * W + k] >= Sim.frozen { continue }     // наст на шар не наматывается
                let dx = (Float(k) + 0.5) * cell - b.x, dy = (Float(sup.row - h) + 0.5) * cell - b.y
                if dx * dx + dy * dy > reach { continue }       // до этой верхушки шар не достаёт
                bestC = k; bestH = h
            }
            if bestC < 0 { balls[i].pick = min(balls[i].pick, 1); break }
            let y = sup.row - bestH
            snow[y * W + bestC] = 0
            wakeRegion(bestC - 1, y - 3, bestC + 1, y)
            eaten += 1
            balls[i].pick -= hard[y * W + bestC] >= Sim.dense ? 2 : 1      // плотный наматывается вдвое медленнее
        }
        if eaten > 0 {
            gridDirty = true
            var add = eaten
            if balls[i].cutD > 0 {              // намотанный снег сначала заращивает скол
                let per = cell * cell / (3.2 * b.r * b.r)      // на скол уходит примерно столько снега, сколько откололось
                let used = min(add, Int((balls[i].cutD / per).rounded(.up)))
                balls[i].cutD -= Float(used) * per
                if balls[i].cutD < 0.03 { balls[i].cutD = 0 }
                add -= used
            }
            if balls[i].decor != 0 {            // новый слой снега закатывает обозначения
                balls[i].wear += Float(eaten) * cell * cell / (.pi * b.r * b.r * 0.3)
                if balls[i].wear >= 1 { balls[i].decor = 0; balls[i].wear = 0 }
            }
            grow(i, cells: add)
        }
    }

    /// Насколько тяжёлый шар проваливается в снег: в рыхлый — глубже, в плотный — чуть, в наст — нет.
    private func sinkDepth(_ r: Float, x: Float, row: Int) -> Float {
        if r < Sim.heavyR { return 0 }
        let c = max(0, min(W - 1, Int(x * inv)))
        let h = pileHeight(c, row)
        if h < 2 { return 0 }
        let hd = hard[(row - h) * W + c]
        let soft: Float = hd < Sim.dense ? 1 : (hd < Sim.frozen ? 0.35 : 0)
        return min(soft * min(0.22 * r, 2.2 * cell), Float(h - 1) * cell)
    }

    /// Какую слежалость снега (`Sim.hard`) должна набрать опора, чтобы держать шар: чем шар тяжелее,
    /// тем плотнее должен стать снег под ним. Наст (от `Sim.frozen`) держит любой шар.
    private func bearHard(_ r: Float) -> UInt8 { UInt8(max(40, min(195, 20 + 5.5 * r))) }

    /// Шар уплотняет снег под собой, а не стирает его. Снег в столбике под шаром сминается: самая
    /// рыхлая ячейка в слое под нагрузкой вминается в нижнюю (их снег складывается, нижняя становится
    /// плотнее), всё, что лежало выше неё, опускается на ячейку — и шар оседает вместе с поверхностью.
    /// Мнёт только тяжёлый шар (от `heavyR`), нагрузка доходит на ~0,4 радиуса вглубь; когда весь этот
    /// слой плотнее `bearHard`, шар стоит. В свежий снег большой шар уходит глубоко, в слежавшийся — чуть,
    /// наст не мнётся. Вес держит пятно опоры; перед катящимся шаром снег не мнётся, а сгребается валом.
    /// Под стоящим шаром снег ещё и спекается: подушка под ним слёживается быстрее, чем снег вокруг.
    private func ballPress(_ i: Int, _ dt: Float) {
        let b = balls[i]
        guard let sup = support(x: b.x, centerY: b.y, r: b.r, ledges: true) else { return }
        let bear = bearHard(b.r)
        // лёгкий снежок снег не мнёт — у него только спекание под собой (ниже); тяжёлому к запасу добавляет удар при падении
        balls[i].pressAcc = b.r >= Sim.heavyR ? min(16, b.pressAcc + dt * 60) : 0
        let c = max(0, min(W - 1, Int(b.x * inv)))
        let half = max(1, Int(b.r * 0.85 * inv))
        let depth = max(1, Int(b.r * 0.4 * inv))
        let low = b.y + bottomExt(b)
        let rolling = abs(b.vx) > 15, dir: Float = b.vx > 0 ? 1 : -1
        var changed = false
        while balls[i].pressAcc >= 1 {
            var bestK = -1, bestY = -1, bestTop = 0
            var bestGap = -Float.infinity
            for k in max(0, c - half)...min(W - 1, c + half) {
                let dx = (Float(k) + 0.5) * cell - b.x
                if abs(dx) >= b.r { continue }
                if rolling && dx * dir > cell * 0.5 { continue }       // перед катящимся шаром снег не мнётся, а сгребается валом (ballPlow)
                let h = pileHeight(k, sup.row)
                if h == 0 { continue }
                let top = sup.row - h
                let gap = min(low, b.y + sqrtf(b.r * b.r - dx * dx)) - Float(top) * cell    // > 0 — снег упёрся в шар
                // вес держит пятно опоры (до половины радиуса от центра); под боками мнётся только врезавшийся в шар снег
                if gap < -cell * 0.4 || (abs(dx) > b.r * 0.5 && gap < cell * 0.5) || gap <= bestGap { continue }
                var y = top, soft = -1
                while y <= top + depth && y < sup.row {
                    let j = y * W + k
                    if snow[j] == 0 { break }                       // под сводом пустота — её продавливает punchThrough
                    if hard[j] < bear { soft = y; break }
                    y += 1
                }
                if soft < 0 { continue }
                bestK = k; bestY = soft; bestTop = top; bestGap = gap
            }
            if bestK < 0 { balls[i].pressAcc = min(balls[i].pressAcc, 1); break }
            let j = bestY * W + bestK
            if bestY + 1 < sup.row && snow[j + W] != 0 {
                hard[j + W] = UInt8(min(255, Int(hard[j + W]) + Int(hard[j]) + 64))
                var y = bestY
                while y > bestTop {
                    snow[y * W + bestK] = snow[(y - 1) * W + bestK]
                    hard[y * W + bestK] = hard[(y - 1) * W + bestK]
                    y -= 1
                }
                snow[bestTop * W + bestK] = 0
                hard[bestTop * W + bestK] = 0
            } else {
                hard[j] = bear      // последний слой на опоре вминать некуда — только уплотняется
            }
            balls[i].pressAcc -= 1
            changed = true
        }
        if cfg.aging && b.rest > 1 {
            // спекание под нагрузкой: примерно вдвое быстрее, чем слёживается снег вокруг
            let p = dt * cfg.agingRate * 0.9
            for k in max(0, c - half / 2)...min(W - 1, c + half / 2) {
                let h = pileHeight(k, sup.row)
                if h == 0 { continue }
                for y in (sup.row - h)...min(sup.row - 1, sup.row - h + depth) {
                    let j = y * W + k
                    if snow[j] != 0 && hard[j] < 250 && rng.f() < p { hard[j] += 1; changed = true }
                }
            }
        }
        if changed { gridDirty = true; hardDirty = true }
        // Плита под тяжёлым шаром может не выдержать: висящие ячейки под ним время от времени перепроверяются.
        if frameNo % 8 == 0 && b.r >= Sim.heavyR {
            wakeHanging(c - half - 1, sup.row - gapMax - 8, c + half + 1, sup.row - 1)
            punchThrough(i, sup.row)
        }
    }

    /// Тяжёлый шар продавливает тонкую корку над пустотой: столбики под ним проваливаются внутрь.
    private func punchThrough(_ i: Int, _ row: Int) {
        let b = balls[i]
        let c = max(0, min(W - 1, Int(b.x * inv)))
        let half = Int(b.r * 0.45 * inv)
        let limit = (b.r - 6) * 0.7          // какую толщину наста шар ещё продавит, pt
        var any = false
        for k in max(0, c - half)...min(W - 1, c + half) {
            let h = pileHeight(k, row)
            if h == 0 { continue }
            let top = row - h
            var y = top
            while y < row && snow[y * W + k] != 0 { y += 1 }
            if y >= row { continue }                     // под шаром сплошной снег
            let hd = hard[top * W + k]
            let weak: Float = hd >= Sim.frozen ? 1 : (hd >= Sim.dense ? 0.6 : 0.3)     // рыхлую корку продавить легче
            if Float(y - top) * cell * weak > limit { continue }
            for yy in top..<y {
                let j = yy * W + k
                let sh = snow[j]
                snow[j] = 0
                spawnChunk((Float(k) + 0.5) * cell, (Float(yy) + 0.5) * cell, rng.range(-25, 25), rng.range(20, 90), sh,
                           hard: hard[j] > 60 ? hard[j] - 60 : 0)
                statCollapsed += 1
            }
            markCave(k)
            wakeRegion(k - 1, top - 1, k + 1, y)
            wakeHanging(k - reachMax, top, k + reachMax, y)
            any = true
        }
        if any { gridDirty = true }
    }

    /// Катящийся тяжёлый шар гонит снег перед собой: то, что попало в его переднюю часть,
    /// сдвигается вперёд валом. Вал отнимает у шара скорость.
    private func ballPlow(_ i: Int, dir: Float, brake: Bool) {
        let b = balls[i]
        let inside = (b.r - cell * 0.3) * (b.r - cell * 0.3)
        let xa = b.x + dir * b.r * 0.2, xb = b.x + dir * b.r
        let x0 = max(0, Int((min(xa, xb) * inv).rounded(.down))), x1 = min(W - 1, Int((max(xa, xb) * inv).rounded(.down)))
        let y0 = max(0, Int(((b.y - b.r) * inv).rounded(.down))), y1 = min(H - 1, Int(((b.y + b.r) * inv).rounded(.down)))
        if x0 > x1 || y0 > y1 { return }
        let out = (b.r + cell * 0.6) * (b.r + cell * 0.6)
        var n = 0
        for gy in y0...y1 {
            for gx in x0...x1 {
                let idx = gy * W + gx
                let sh = snow[idx]
                if sh == 0 || hard[idx] >= Sim.frozen { continue }
                let px = (Float(gx) + 0.5) * cell, py = (Float(gy) + 0.5) * cell
                let dx = px - b.x, dy = py - b.y
                if dx * dir < b.r * 0.2 || dx * dx + dy * dy > inside { continue }
                var fx = px, fy = py
                var tx = -1, ty = -1
                for _ in 0..<40 {
                    fx += dir * cell * 0.94; fy -= cell * 0.34
                    let qx = Int((fx * inv).rounded(.down)), qy = Int((fy * inv).rounded(.down))
                    if qx < 0 || qx >= W || qy < 0 || qy >= H || ledge[qy * W + qx] != 0 { break }
                    let ex = fx - b.x, ey = fy - b.y
                    if snow[qy * W + qx] == 0 && ex * ex + ey * ey > out { tx = qx; ty = qy; break }
                }
                if tx < 0 { continue }
                let hd = hard[idx]
                snow[idx] = 0
                settle(tx, ty, sh, hard: hd, vx: dir * max(40, abs(b.vx)) * 0.6)
                n += 1
            }
        }
        if n > 0 {
            gridDirty = true
            wakeRegion(x0 - 1, y0 - 1, x1 + 1, y1 + 1)
            if brake { balls[i].vx *= max(0, 1 - 0.6 * Float(n) * cell * cell / (.pi * b.r * b.r)) }
        }
    }

    /// Насколько шар выступает вниз от центра. У сколотого шара, стоящего на срезе, — меньше радиуса:
    /// он лежит плашмя, а покатившись, переваливается через край скола.
    private func bottomExt(_ b: Ball) -> Float {
        if b.cutD <= 0.01 { return b.r }
        return b.r * (1 - b.cutD * max(0, sinf(b.cutA + b.angle)))
    }

    /// Примёрзший шар пытаются сдвинуть: низ остаётся примёрзшим к месту (становится настом),
    /// а сам шар выходит сколотым.
    private func breakLoose(_ i: Int) {
        let b = balls[i]
        guard cfg.aging, b.rest > Sim.stuckAfter else { return }
        let k = min(0.75, 0.3 + (b.rest - Sim.stuckAfter) / 500 + b.bury * 0.3)
        let lineY = b.y + b.r * (1 - k)
        let x0 = max(0, Int(((b.x - b.r) * inv).rounded(.down))), x1 = min(W - 1, Int(((b.x + b.r) * inv).rounded(.down)))
        let y0 = max(0, Int((lineY * inv).rounded(.down))), y1 = min(H - 1, Int(((b.y + b.r) * inv).rounded(.down)))
        if x0 <= x1 && y0 <= y1 {
            for gy in y0...y1 {
                for gx in x0...x1 {
                    let px = (Float(gx) + 0.5) * cell, py = (Float(gy) + 0.5) * cell
                    let dx = px - b.x, dy = py - b.y
                    if py <= lineY || dx * dx + dy * dy > b.r * b.r { continue }
                    let idx = gy * W + gx
                    if snow[idx] != 0 || ledge[idx] != 0 { continue }
                    snow[idx] = rng.shade()
                    hard[idx] = 215
                    wake(gx, gy)
                }
            }
        }
        balls[i].cutD = max(b.cutD, k)
        balls[i].cutA = .pi / 2 - b.angle
        balls[i].rest = 0
        balls[i].bury = 0
        gridDirty = true
        hardDirty = true
    }

    /// Шар, которого занесло, перестаёт быть шаром: его снег остаётся на месте слежавшимся комом,
    /// нависающие бока осыпаются — получается сугроб.
    private func meltIntoSnow(_ b: Ball) {
        let hd: UInt8 = b.rest > 180 ? 205 : (b.rest > Sim.stuckAfter ? 130 : 70)
        let rx = b.r * (1 + 0.3 * b.squash), ry = b.r * (1 - 0.35 * b.squash)
        let cyc = b.y + b.r * 0.35 * b.squash
        let wa = b.cutA + b.angle
        let x0 = max(0, Int(((b.x - rx) * inv).rounded(.down))), x1 = min(W - 1, Int(((b.x + rx) * inv).rounded(.down)))
        let y0 = max(0, Int(((cyc - ry) * inv).rounded(.down))), y1 = min(H - 1, Int(((cyc + ry) * inv).rounded(.down)))
        if x0 > x1 || y0 > y1 { return }
        for gy in y0...y1 {
            for gx in x0...x1 {
                let dx = (Float(gx) + 0.5) * cell - b.x, dy = (Float(gy) + 0.5) * cell - cyc
                if (dx / rx) * (dx / rx) + (dy / ry) * (dy / ry) > 1 { continue }
                if b.cutD > 0.01 && dx * cosf(wa) + dy * sinf(wa) > b.r * (1 - b.cutD) { continue }
                let idx = gy * W + gx
                if snow[idx] != 0 || ledge[idx] != 0 { continue }
                snow[idx] = rng.shade()
                hard[idx] = hd
                wake(gx, gy)
            }
        }
        gridDirty = true
        hardDirty = true
    }

    /// Снеговик рассыпается: шар, который толкнули, и всё, что на нём стоит, отлепляются и летят порознь.
    /// Слежавшиеся шары при этом хрупкие — бьются, упав.
    private func crumble(_ i: Int, _ ivx: Float, _ ivy: Float) {
        let id = balls[i].id
        var ids: Set<Int32> = [id]
        var grew = true
        while grew {
            grew = false
            for b in balls where b.parent != -1 && ids.contains(b.parent) && !ids.contains(b.id) {
                ids.insert(b.id); grew = true
            }
        }
        for j in balls.indices where ids.contains(balls[j].id) && balls[j].rest > Sim.stuckAfter {
            balls[j].brittle = true
        }
        if balls[i].parent == -1 { breakLoose(i) }          // основание могло примёрзнуть
        for j in balls.indices where ids.contains(balls[j].id) {
            let hit = balls[j].id == id
            balls[j].parent = -1
            balls[j].grounded = false
            balls[j].loose = 1.5
            balls[j].vx = ivx * (hit ? 0.8 : 0.3) + rng.range(-70, 70)
            balls[j].vy = ivy * (hit ? 0.8 : 0.2) - rng.range(0, 90)
        }
    }

    // MARK: - Шар как опора для снега

    private func resetMasks() {
        for i in mask.indices { mask[i] = 0 }
        for k in slotUsed.indices { slotUsed[k] = false; slotBox[k] = (0, 0, -1, -1) }
        for i in balls.indices { balls[i].slot = 0 }
    }

    /// Ветки туловища снеговика в осях его обозначений (те же отрезки, что рисует шейдер).
    private func onArm(_ x: Float, _ y: Float, _ r: Float) -> Bool {
        func dist(_ ax: Float, _ ay: Float, _ bx: Float, _ by: Float) -> Float {
            let ex = bx - ax, ey = by - ay
            let t = max(0, min(1, ((x - ax) * ex + (y - ay) * ey) / (ex * ex + ey * ey)))
            return hypotf(x - (ax + ex * t), y - (ay + ey * t))
        }
        for sg in [Float(-1), 1] {
            let ax = sg * 0.8 * r, ay = -0.05 * r, bx = sg * 1.75 * r, by = -0.6 * r
            let mx = ax + (bx - ax) * 0.62, my = ay + (by - ay) * 0.62
            if dist(ax, ay, bx, by) < cell * 0.62 || dist(mx, my, mx + sg * 0.12 * r, my - 0.36 * r) < cell * 0.55 { return true }
        }
        return false
    }

    /// Шар встал — занять под него ячейки в маске (с учётом скола и веток).
    private func maskBall(_ i: Int) {
        guard let slot = (1...250).first(where: { !slotUsed[$0] }) else { return }
        let b = balls[i]
        let arms = b.decor == 2 && b.r > 9
        let ext = arms ? b.r * 1.85 : b.r
        let x0 = max(0, Int(((b.x - ext) * inv).rounded(.down))), x1 = min(W - 1, Int(((b.x + ext) * inv).rounded(.down)))
        let y0 = max(0, Int(((b.y - b.r) * inv).rounded(.down))), y1 = min(H - 1, Int(((b.y + b.r) * inv).rounded(.down)))
        guard x0 <= x1, y0 <= y1 else { return }
        let wa = b.cutA + b.angle
        let da = b.angle - b.decorA
        let ca = cosf(-da), sa = sinf(-da)
        for gy in y0...y1 {
            for gx in x0...x1 {
                let idx = gy * W + gx
                // ячейки, где уже лежит снег, — это сугроб, в который шар просел, а не шар: их не занимаем
                if mask[idx] != 0 || ledge[idx] != 0 || snow[idx] != 0 { continue }
                let dx = (Float(gx) + 0.5) * cell - b.x, dy = (Float(gy) + 0.5) * cell - b.y
                var inside = dx * dx + dy * dy <= b.r * b.r
                if inside && b.cutD > 0.01 && dx * cosf(wa) + dy * sinf(wa) > b.r * (1 - b.cutD) { inside = false }
                if !inside && arms { inside = onArm(dx * ca - dy * sa, dx * sa + dy * ca, b.r) }
                if inside { mask[idx] = UInt8(slot) }
            }
        }
        slotUsed[slot] = true
        slotBox[slot] = (x0, y0, x1, y1)
        balls[i].slot = UInt8(slot)
        balls[i].mx = b.x; balls[i].my = b.y; balls[i].mr = b.r
    }

    /// Шар сдвинулся или исчез: его ячейки свободны, а снег, который на нём лежал и к нему лип, теряет опору.
    private func clearSlot(_ slot: Int) {
        let bx = slotBox[slot]
        if bx.x0 <= bx.x1 && bx.y0 <= bx.y1 {
            for gy in bx.y0...bx.y1 {
                for gx in bx.x0...bx.x1 where mask[gy * W + gx] == UInt8(slot) {
                    mask[gy * W + gx] = 0
                    wake(gx, gy)
                    wake(gx, gy - 1)
                }
            }
        }
        slotUsed[slot] = false
        slotBox[slot] = (0, 0, -1, -1)
    }

    /// Следит, чтобы маска была ровно у стоящих шаров. Снимает её и у шаров, которые убрали из `balls` напрямую.
    private func updateMasks(_ dt: Float) {
        var alive = [Bool](repeating: false, count: 256)
        for i in balls.indices {
            let b = balls[i]
            let still = !b.held && (b.grounded || b.parent != -1) && b.vx * b.vx + b.vy * b.vy < 25
            balls[i].stillT = still ? b.stillT + dt : 0
            if b.slot != 0 {
                let moved = abs(b.x - b.mx) > 0.6 || abs(b.y - b.my) > 0.6 || abs(b.r - b.mr) > 0.6
                if !still || moved || !slotUsed[Int(b.slot)] {
                    if slotUsed[Int(b.slot)] { clearSlot(Int(b.slot)) }
                    balls[i].slot = 0
                }
            }
            if balls[i].slot == 0 && balls[i].stillT > 0.35 { maskBall(i) }
            if balls[i].slot != 0 { alive[Int(balls[i].slot)] = true }
        }
        for k in 1...250 where slotUsed[k] && !alive[k] { clearSlot(k) }
    }

    /// Снег на стоящих шарах — тот же снег, что и везде. Он ложится на шар (и на ветки) сверху и скатывается
    /// с крутых боков по общим правилам; а к тому, что уже лежит, липнет дальше — так шар постепенно
    /// затягивает снегом, и обозначения снеговика пропадают под ним. Шар, покрытый почти целиком,
    /// перестаёт быть шаром и остаётся в сугробе слежавшимся комом.
    private func accreteOnBalls(_ step: Float) {
        let k = step * cfg.intensity / cell
        var melts: [Int32] = []
        for b in balls where b.slot != 0 && slotUsed[Int(b.slot)] {
            let slot = b.slot
            let bx = slotBox[Int(slot)]
            if bx.x0 > bx.x1 || bx.y0 > bx.y1 { continue }
            let limit = Int((0.3 * b.cover + 1.3 * b.bury) * b.mr * inv) + 1       // со временем слой толще
            // 1. снег ложится сверху
            for c in bx.x0...bx.x1 {
                if rng.f() >= 0.28 * k { continue }
                var y = bx.y0
                while y <= bx.y1 && mask[y * W + c] != slot { y += 1 }
                if y > bx.y1 { continue }                     // в этом столбце шара нет
                var thick = 0
                var blocked = false
                y -= 1
                while y >= 0 {
                    let i = y * W + c
                    if mask[i] != 0 { blocked = true; break }      // выше стоит другой шар — снег ляжет на него
                    if snow[i] == 0 { break }
                    thick += 1
                    y -= 1
                }
                if blocked || y < 0 || thick >= limit || Float(y) * cell < topLimit || ledge[y * W + c] != 0 { continue }
                settle(c, y, rng.shade())
            }
            // 2. Снег липнет к снегу. Сверху он сползает по шару тем ниже, чем толще лежит на макушке;
            //    снизу шар тонет в сугробе — до той высоты, до которой сугроб поднялся рядом с ним.
            let cl = Int(((b.mx - b.mr) * inv).rounded(.down)) - 1, cr = Int(((b.mx + b.mr) * inv).rounded(.down)) + 1
            // Уровень сугроба рядом с шаром — сплошной снег от опоры, на которой всё стоит (то, что
            // лежит на ветках или на шаре ниже, сугробом не считается). Берём меньший из двух боков.
            var level = H
            if let sup = support(x: b.mx, centerY: b.my, r: b.mr, ledges: true) {
                let hl = cl >= 0 ? pileHeight(cl, sup.row) : 0
                let hr = cr < W ? pileHeight(cr, sup.row) : 0
                level = sup.row - min(hl, hr)
            }
            for c in bx.x0...bx.x1 {
                var yt = bx.y0
                while yt <= bx.y1 && mask[yt * W + c] != slot { yt += 1 }
                if yt > bx.y1 { continue }
                var thick = 0
                var y = yt - 1
                while y >= 0 && snow[y * W + c] != 0 && mask[y * W + c] == 0 { thick += 1; y -= 1 }
                // сверху вниз: первая непокрытая ячейка шара в пределах досягаемости слоя
                if thick > 0 && rng.f() < 0.25 * cfg.intensity * step * 10 {
                    let reach = yt + Int(Float(thick) * 1.6)
                    var g = yt
                    while g <= bx.y1 && g < reach && mask[g * W + c] == slot && snow[g * W + c] != 0 { g += 1 }
                    if g <= bx.y1 && g < reach && mask[g * W + c] == slot {
                        snow[g * W + c] = rng.shade(); hard[g * W + c] = 0; gridDirty = true
                    }
                }
                // снизу вверх: всё, что ниже уровня сугроба рядом
                if level <= bx.y1 && rng.f() < 0.25 * cfg.intensity * step * 10 {
                    var g = bx.y1
                    while g >= level && (mask[g * W + c] != slot || snow[g * W + c] != 0) { g -= 1 }
                    if g >= level && g >= bx.y0 {
                        snow[g * W + c] = rng.shade(); hard[g * W + c] = 0; gridDirty = true
                    }
                }
            }
            // 3. занесло почти целиком?
            var total = 0, covered = 0
            for gy in bx.y0...bx.y1 {
                for gx in bx.x0...bx.x1 where mask[gy * W + gx] == slot {
                    total += 1
                    if snow[gy * W + gx] != 0 { covered += 1 }
                }
            }
            if total > 0 && covered * 100 >= total * 82 { melts.append(b.id) }
        }
        for id in melts {
            guard let i = ballIndex(id) else { continue }
            let slot = Int(balls[i].slot)
            meltIntoSnow(balls[i])
            if slotUsed[slot] { clearSlot(slot) }
            balls.remove(at: i)
        }
    }

    private func burstBall(_ b: Ball, floorY: Float) {
        let n = min(600, max(6, Int(Float.pi * b.r * b.r / (cell * cell) * 0.9)))
        for _ in 0..<n {
            let a = rng.range(0, 6.2832)
            let rad = b.r * sqrtf(rng.f())
            let px = min(max(b.x + cosf(a) * rad, 1), wPt - 1)
            let py = min(b.y + sinf(a) * rad, floorY - 1)
            let sp = rng.range(60, 420)
            spawnChunk(px, py, cosf(a) * sp + b.vx * 0.3, sinf(a) * sp * 0.8 - abs(b.vy) * 0.18 - 60, rng.shade(), ghost: 0.12)
        }
    }

    /// Варежка: взять шар под курсором или слепить новый из снега вокруг.
    func grabBegin() {
        guard heldId == -1 else { return }
        var best = -1
        var bestD = Float.infinity
        for i in balls.indices {
            let d = hypotf(balls[i].x - cx, balls[i].y - cy) - balls[i].r
            if d < 8 && d < bestD { best = i; bestD = d }
        }
        if best >= 0 {
            if balls[best].parent == -1 { breakLoose(best) }       // примёрзший отламывается от основания
            balls[best].held = true
            balls[best].parent = -1
            balls[best].grounded = false
            heldId = balls[best].id
            return
        }
        // горсть с поверхности: по две верхние ячейки из столбцов под рукой
        var n = 0
        if let sup = support(x: cx, centerY: min(cy, hPt - 1) - 12, r: 6, ledges: true), abs(cy - sup.surf) < 30 {
            let c = max(0, min(W - 1, Int(cx * inv))), half = Int(12 * inv)
            for k in max(0, c - half)...min(W - 1, c + half) {
                for _ in 0..<2 {
                    let h = pileHeight(k, sup.row)
                    if h == 0 || hard[(sup.row - h) * W + k] >= Sim.frozen { break }
                    snow[(sup.row - h) * W + k] = 0
                    n += 1
                }
            }
            if n > 0 { gridDirty = true }
        }
        let area = max(Float(n) * cell * cell * 0.7, Float.pi * 36)
        var b = Ball(id: nextBallId, x: cx, y: cy, r: sqrtf(area / .pi), seed: rng.range(0, 100))
        nextBallId += 1
        b.held = true
        balls.append(b)
        heldId = b.id
        if balls.count > 40, let old = balls.firstIndex(where: { !$0.held && $0.parent == -1 && !$0.hasChild }) {
            burstBall(balls[old], floorY: .infinity)
            balls.remove(at: old)
        }
    }

    /// Отпустить шар: он летит со скоростью руки.
    func grabEnd() {
        guard let i = ballIndex(heldId) else { heldId = -1; return }
        var vx = cvx, vy = cvy
        let v = sqrtf(vx * vx + vy * vy)
        if v > 2600 { vx *= 2600 / v; vy *= 2600 / v }
        balls[i].held = false
        balls[i].vx = vx
        balls[i].vy = vy
        heldId = -1
    }

    private func stepBalls(_ dt: Float) {
        if balls.isEmpty { return }
        var burst: [(id: Int32, floorY: Float)] = []

        if let i = ballIndex(heldId) {
            // Шар в руке нельзя вдавить в снег: он катится по поверхности и наматывает верхний слой.
            let ox = balls[i].x, oy = balls[i].y
            var ny = cy
            var touching = false
            if let sup = support(x: cx, centerY: min(cy, hPt - 1) - 12, r: balls[i].r, ledges: true) {
                touching = ny + balls[i].r >= sup.surf - cell
                ny = min(ny, sup.surf - balls[i].r)
            }
            balls[i].vx = cvx; balls[i].vy = cvy
            balls[i].x = cx; balls[i].y = ny
            balls[i].angle += (cx - ox) / max(balls[i].r, 4)
            if touching {
                pickSurface(i, travelled: hypotf(cx - ox, ny - oy))
                if balls[i].r >= Sim.heavyR && abs(cx - ox) > 0.3 { ballPlow(i, dir: cx > ox ? 1 : -1, brake: false) }
            }
        } else if heldId != -1 {
            heldId = -1
        }

        // Курсор толкает шары. Одиночный катится; примёрзший от толчка отламывается от основания;
        // снеговик лёгкого касания не замечает, а от толчка рассыпается.
        if cfg.sweep && cursorOn && heldId == -1 && !handsMode {
            for i in balls.indices where !balls[i].held {
                let b = balls[i]
                let dx = b.x - cx, dy = b.y - cy
                let rr = b.r + 7
                let d = sqrtf(dx * dx + dy * dy)
                if d >= rr || d < 0.01 { continue }
                let nx = dx / d, ny = dy / d
                let vn = min(1400, cvx * nx + cvy * ny)
                let frozen = b.rest > Sim.stuckAfter
                if b.parent != -1 || b.hasChild {
                    if vn < (frozen ? 380 : 220) { continue }
                    crumble(i, nx * vn, ny * vn)
                    if vn > 900 { burst.append((b.id, .infinity)) }     // от сильного удара шар разлетается сразу
                    continue
                }
                if frozen {
                    if vn < 250 { continue }
                    breakLoose(i)
                }
                balls[i].rest = 0
                balls[i].x += nx * (rr - d)
                balls[i].y += ny * (rr - d)
                let cur = balls[i].vx * nx + balls[i].vy * ny
                if vn > cur {
                    balls[i].vx += nx * (vn - cur) * 0.9
                    balls[i].vy += ny * (vn - cur) * 0.9
                }
            }
        }

        var crumbles: [(id: Int32, vx: Float, vy: Float)] = []
        for i in balls.indices {
            if balls[i].held || balls[i].parent != -1 { continue }
            var b = balls[i]
            let creeping = abs(b.vx) < 15 && b.vy < 200        // стоит, оседает или едва ползёт
            b.grounded = false
            b.vy += gravity * dt
            b.vx *= 1 - min(1, 0.15 * dt)
            let sp = sqrtf(b.vx * b.vx + b.vy * b.vy)
            let n = max(1, min(12, Int(sp * dt / max(2, b.r * 0.4)) + 1))
            let h = dt / Float(n)
            var dead = false
            var deadFloor = Float.infinity
            sub: for _ in 0..<n {
                let prevY = b.y
                b.x += b.vx * h
                b.y += b.vy * h
                if b.x < b.r {
                    b.x = b.r
                    if b.vx < 0 {
                        if -b.vx > breakSpeed { dead = true; break sub }
                        b.vx = -b.vx * 0.3
                    }
                }
                if b.x > wPt - b.r {
                    b.x = wPt - b.r
                    if b.vx > 0 {
                        if b.vx > breakSpeed { dead = true; break sub }
                        b.vx = -b.vx * 0.3
                    }
                }
                var floorY = Float.infinity
                var supRow = -1
                var supSurf = Float.infinity
                // Тяжёлый шар чуть проваливается в рыхлый снег, а дальше уходит в него, только сминая снег
                // под собой (ballPress). Снег снизу шар, который стоит или едва ползёт, не поднимает: что
                // подсыпалось ему под низ или под бок, упирается в шар и вминается в подушку под ним.
                // Поднимается на снег только катящийся шар — он на него накатывается.
                if let sup = support(x: b.x, centerY: prevY, r: b.r, ledges: b.vy >= 0) {
                    let sink = sinkDepth(b.r, x: b.x, row: sup.row)
                    if b.y + bottomExt(b) >= sup.surf + sink {
                        floorY = creeping ? max(sup.surf + sink, prevY + bottomExt(b)) : sup.surf + sink
                        supRow = sup.row
                        supSurf = floorY - sink         // на чём шар стоит на деле: если снег подсыпался под него, то ниже снега
                    }
                }
                if floorY.isFinite {
                    if b.vy > (b.brittle ? 260 : breakSpeed) { dead = true; deadFloor = floorY; b.y = floorY - b.r; break sub }
                    b.y = floorY - bottomExt(b)
                    let flat = b.cutD * max(0, sinf(b.cutA + b.angle))     // стоит на сколе — катиться не хочет
                    // Снег удар не возвращает: шар не отскакивает, а вминается — энергия уходит в уплотнение
                    // (ballPress). Чуть отскакивает он только от голой опоры.
                    if b.vy > 140 {
                        if pileHeight(max(0, min(W - 1, Int(b.x * inv))), supRow) == 0 {
                            b.vy = -b.vy * 0.18
                        } else {
                            if b.r >= Sim.heavyR { b.pressAcc += min(12, b.vy / 60) }
                            b.vy = 0
                        }
                    } else {
                        b.vy = 0
                    }
                    b.grounded = true
                    // Шар на склоне катится вниз сам. Наклон берётся по высоте снега слева и справа
                    // от точки опоры; на пологом (меньше ~10°) рыхлый снег шар держит.
                    // Снеговик (шар, на котором стоят другие) не катится.
                    var downhill = false
                    if !b.hasChild {
                        let d = max(cell * 2, b.r * 0.5)
                        let l = support(x: b.x - d, centerY: prevY, r: b.r, ledges: true)
                        let rr = support(x: b.x + d, centerY: prevY, r: b.r, ledges: true)
                        // за краем опоры высоту не считаем: с края шар падает, только когда выкатится сам
                        let hl = (l != nil && l!.row == supRow) ? l!.surf : floorY
                        let hr = (rr != nil && rr!.row == supRow) ? rr!.surf : floorY
                        let slope = max(-1.2, min(1.2, (hr - hl) / (2 * d)))        // > 0 — правая сторона ниже
                        // В ямке — своей вмятине или между буграми — шар не катится: склон тянет его, только если
                        // под гору снег и правда ниже того, на чём он стоит. Иначе он «выкапывается» сам рывком вверх.
                        let below = (slope > 0 ? hr : hl) - supSurf
                        if abs(slope) > (b.rest > Sim.stuckAfter ? 0.6 : 0.18) + flat * 0.5 && below > 0 {     // примёрзший держится и на крутом
                            b.vx += gravity * 0.66 * slope / (1 + slope * slope) * h   // 2/3 — катящийся диск
                            downhill = true
                        }
                    }
                    b.vx *= 1 - min(1, (2.2 + 7 * flat) * h)
                    if abs(b.vx) < 4 && !downhill { b.vx = 0 }
                }
                for j in balls.indices where j != i {
                    let o = balls[j]
                    if o.held { continue }
                    let dx = b.x - o.x, dy = b.y - o.y
                    let minD = b.r + o.r
                    let d2 = dx * dx + dy * dy
                    if d2 >= minD * minD || d2 < 1e-6 { continue }
                    if rootId(j) == b.id { continue }
                    let d = sqrtf(d2)
                    let nx = dx / d, ny = dy / d
                    let oStatic = o.parent != -1 || o.grounded || o.hasChild
                    let rvx = b.vx - (oStatic ? 0 : o.vx), rvy = b.vy - (oStatic ? 0 : o.vy)
                    let vn = rvx * nx + rvy * ny
                    if -vn > (b.brittle ? 300 : breakSpeed) {
                        dead = true
                        if -vn > breakSpeed * 1.35 || o.r < b.r * 0.9 {
                            burst.append((o.id, .infinity))
                        } else if !oStatic {
                            balls[j].vx += -nx * (-vn) * 0.35
                            balls[j].vy += -ny * (-vn) * 0.35
                        }
                        break sub
                    }
                    if ny < -0.8 && -vn < 520 && oStatic && !o.hasChild && b.loose <= 0 {
                        // Мягко опустился сверху — прилип: получился снеговик.
                        b.parent = o.id
                        b.offX = nx * minD * 0.95
                        b.offY = ny * minD * 0.95
                        b.x = o.x + b.offX
                        b.y = o.y + b.offY
                        b.vx = 0; b.vy = 0
                        b.grounded = false
                        break sub
                    }
                    // ощутимый удар по снеговику — и он рассыпается
                    if oStatic && (o.parent != -1 || o.hasChild) && -vn > 320 {
                        crumbles.append((o.id, -nx * (-vn) * 0.6, -ny * (-vn) * 0.6))
                    }
                    let pen = minD - d
                    if oStatic {
                        b.x += nx * pen
                        b.y += ny * pen
                        if vn < 0 {
                            b.vx -= 1.12 * vn * nx
                            b.vy -= 1.12 * vn * ny
                        }
                    } else {
                        let mb = b.r * b.r, mo = o.r * o.r, tot = mb + mo
                        b.x += nx * pen * mo / tot
                        b.y += ny * pen * mo / tot
                        balls[j].x -= nx * pen * mb / tot
                        balls[j].y -= ny * pen * mb / tot
                        if vn < 0 {
                            let jimp = -1.12 * vn / (1 / mb + 1 / mo)
                            b.vx += nx * jimp / mb
                            b.vy += ny * jimp / mb
                            balls[j].vx -= nx * jimp / mo
                            balls[j].vy -= ny * jimp / mo
                        }
                    }
                }
            }
            b.angle += b.vx * dt / max(b.r, 4)
            balls[i] = b
            if dead {
                burst.append((b.id, deadFloor))
                continue
            }
            if b.parent != -1 { continue }
            if b.grounded {
                if abs(b.vx) > 8 { pickSurface(i, travelled: abs(b.vx) * dt) }
                ballPress(i, dt)            // снег под шаром сминается под любым шаром, под лёгким — чуть
                if b.r >= Sim.heavyR {
                    if abs(balls[i].vx) > 15 { ballPlow(i, dir: balls[i].vx > 0 ? 1 : -1, brake: true) }
                }
            } else if b.vx * b.vx + b.vy * b.vy > 350 * 350 {
                ballEatsSnow(i, spray: true)
            }
        }

        for c in crumbles {
            if let j = ballIndex(c.id) { crumble(j, c.vx, c.vy) }
        }
        for (id, floorY) in burst {
            guard let i = ballIndex(id) else { continue }
            if floorY.isFinite { shatter(x: balls[i].x, y: floorY, r: balls[i].r * 1.4 + 8) }
            burstBall(balls[i], floorY: floorY)
            if heldId == id { heldId = -1 }
            balls.remove(at: i)
        }

        // Прилипшие шары едут за своим основанием.
        for _ in 0..<4 {
            for i in balls.indices where balls[i].parent != -1 && !balls[i].held {
                if let p = ballIndex(balls[i].parent) {
                    balls[i].x = balls[p].x + balls[i].offX
                    balls[i].y = balls[p].y + balls[i].offY
                    balls[i].vx = balls[p].vx
                    balls[i].vy = balls[p].vy
                } else {
                    balls[i].parent = -1
                    balls[i].vx = 0; balls[i].vy = 0
                }
            }
        }
        for i in balls.indices { balls[i].hasChild = false }
        for i in balls.indices where balls[i].parent != -1 {
            if let p = ballIndex(balls[i].parent) { balls[p].hasChild = true }
        }

        // Обозначения снеговика — свойство самого шара, а не его места в стопке. Шар, который поставили
        // на другой, становится головой (лицо); голова, на которую поставили ещё шар, — туловищем
        // (пуговицы и ветки). Сбили шар — обозначения остаются при нём, остальные не «перестраиваются».
        for i in balls.indices {
            if balls[i].parent != -1 && balls[i].decor == 0 {
                balls[i].decor = 1
                balls[i].decorA = balls[i].angle
                balls[i].wear = 0
            }
            if balls[i].hasChild && balls[i].decor == 1 { balls[i].decor = 2 }
        }

        // Шар, который давно стоит: примерзает и слёживается. `cover` и `bury` задают, каким толстым
        // слоем снег может лечь на него и рядом; сам снег кладут grow и accreteOnBalls.
        var melts: [Int32] = []
        for i in balls.indices {
            let b = balls[i]
            if b.loose > 0 { balls[i].loose = max(0, b.loose - dt) }
            // шар, под которым оседает снег, опускается вместе с ним — это не сдвиг, он продолжает стоять
            let settling = !b.held && b.parent == -1 && b.rest > 0 && abs(b.vx) < 5 && b.vy >= 0 && b.vy < 160
            let still = !b.held && (b.grounded || b.parent != -1 || settling) && (b.vx * b.vx + b.vy * b.vy < 25 || settling)
            if still && cfg.aging {
                let step = dt * cfg.agingRate
                balls[i].rest += step
                if balls[i].rest > 1 { balls[i].brittle = false }
                let snowing = max(cfg.intensity, cfg.flakeRate > 0 ? 0.3 : 0)     // в метель заметает быстрее
                if snowing > 0 {
                    balls[i].cover = min(1, b.cover + step * snowing / 70)
                    if balls[i].cover >= 1 { balls[i].bury = min(1, b.bury + step * snowing / 200) }
                }
            } else if b.rest > 0 || b.cover > 0 {
                balls[i].rest = 0
                balls[i].cover = 0
                balls[i].squash = 0
                balls[i].bury = 0
            }
        }
        for id in melts {
            guard let i = ballIndex(id) else { continue }
            meltIntoSnow(balls[i])
            balls.remove(at: i)
        }
        updateMasks(dt)
    }

    // MARK: - Шаг

    func step(_ dt: Float) {
        statDeposits = 0
        statSpawns = 0
        time += dt
        windNow = cfg.wind * (1 + 0.35 * sinf(time * 0.17 + 0.5))
            + cfg.gust * (sinf(time * 0.31) * 0.6 + sinf(time * 0.83 + 1.7) * 0.4)
        windNow += wind.boost(self, dt)         // буран добавляет ветра
        spawnFlakes(dt)
        accumulate(dt)
        age(dt)
        cursorSweep()
        processWake()
        stepParticles(dt)
        stepBalls(dt)
        wind.step(self, dt)
        people.step(self, dt)
        updateCaves()
        frameNo &+= 1
    }

    // MARK: - Человечки (People.swift)

    let people = People()
    /// Ветер над лежачим снегом и бураны (Wind.swift).
    let wind = Wind()

    /// Рамки окон от переднего к заднему — как их передали в setLedges.
    var windowBoxes: [WinBox] { blockers }

    /// Высота сугроба над строкой опоры row в столбце c (то же, что видят шары).
    func snowHeight(_ c: Int, _ row: Int) -> Int {
        c >= 0 && c < W && row >= 1 && row <= H ? pileHeight(c, row) : 0
    }

    /// Снег в прямоугольнике тронули (сняли ячейки): соседние перепроверят свою опору.
    func snowDisturbed(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
        wakeRegion(x0, y0, x1, y1)
        markCaves(x0, x1)           // ход под сводом рисуется пустотой, как и пустоты под настом
    }

    /// Новый шар (для снеговика, которого катают человечки). held — шар ведут сами, физика его не трогает.
    func addBall(x: Float, y: Float, r: Float, held: Bool) -> Int32 {
        var b = Ball(id: nextBallId, x: x, y: y, r: r, seed: rng.range(0, 100))
        nextBallId += 1
        b.held = held
        balls.append(b)
        return b.id
    }
}
