import Foundation

// Завалы. На человечка высыпался снег (смахнули с карниза, обвалилась лестница, съехал сугроб) —
// его завалило, под снегом его не видно. Кто был рядом — мечутся, бегут и откапывают руками.
// Неглубоко заваленный выбирается сам. Копают слишком долго или завалило глубоко — на этом месте
// втыкают палочку с его шарфом, стоят вокруг, взявшись за руки, и расходятся. Палочку заметает снегом.
//
// Чужих человечков этот файл не меняет: каждый сам замечает, что случилось рядом (см. rescueGuard), —
// кого завалило, не поставили ли уже палочку, не летит ли сверху снег.

/// Палочка на месте, где кого-то не откопали (kind 0). Тем же списком ведётся снег, который
/// прямо сейчас летит с карниза (kind 1): по нему те, кто внизу, решают — отскочить или задрать голову.
struct Grave {
    var id: Int
    var x: Float
    var stand: Int              // -2 — низ экрана, иначе номер окна
    var topY: Float             // верх палочки
    var scarf: SIMD4<Float>     // цвет шарфа того, кто там остался
    var born: Float
    var planted = false         // воткнута (до этого не рисуется)
    var acc: Float = 0          // запас «заметания», ячеек
    var sunk: Float = 0         // на сколько палочку уже занесло, pt
    var kind = 0                // 0 — палочка, 1 — снег летит с карниза
    var victim: Int32 = -1      // кто под ней остался
    var planter: Int32 = -1     // кто её втыкает
    // kind 1: снег сыплется с края карниза струёй — из точки (x0, topY) со скоростью vx вбок
    var until: Float = 0        // когда долетит последний ком
    var dir: Float = 1          // в какую сторону от окна он падает
    var x0: Float = 0
    var vx: Float = 0
    var left = 0                // сколько ячеек ещё не слетело
    var rate: Float = 0         // ячеек в секунду
}

/// Счётчики для самотестов (и журнал завалов: `SUGROB_RESCUE_LOG=1`).
enum RescueStats {
    static var buried = 0, selfOut = 0, dugOut = 0, graves = 0, covered = 0, avalanches = 0
    static let log = ProcessInfo.processInfo.environment["SUGROB_RESCUE_LOG"] != nil
    static var line: String {
        "buried \(buried) (self out \(selfOut), dug out \(dugOut)), graves \(graves) (covered \(covered)), avalanches \(avalanches)"
    }
}

extension People {
    // MARK: - Завалило?

    /// Доля коробки тела, занятая снегом. Нижняя ячейка не в счёт: ноги и так стоят в снегу.
    /// Снег на карнизе или на шаре над головой — не завал: выше них столбец не считается.
    func snowFill(_ p: Person, _ s: Sim, height: Float) -> Float {
        func cl(_ v: Float, _ hi: Int) -> Int { Int(max(-2, min(Float(hi) + 2, v.rounded(.down)))) }
        let c0 = max(0, cl((p.x - 1.5 * u) * s.inv, s.W)), c1 = min(s.W - 1, cl((p.x + 1.5 * u) * s.inv, s.W))
        let r0 = max(0, cl((p.y - height) * s.inv, s.H))
        let r1 = min(s.H - 1, cl((p.y * s.inv).rounded(.up), s.H) - 2)
        guard c0 <= c1, r0 <= r1 else { return 0 }
        var n = 0
        for c in c0...c1 {
            var r = r1
            while r >= r0 {
                let i = r * s.W + c
                if s.ledge[i] != 0 || s.mask[i] != 0 { break }
                if s.snow[i] != 0 { n += 1 }
                r -= 1
            }
        }
        return Float(n) / Float((c1 - c0 + 1) * (r1 - r0 + 1))
    }

    /// Откуда взялся снег вокруг человечка: сыплется сверху комьями или его сгребают курсором.
    func snowCame(_ p: Person, _ s: Sim) -> Bool {
        if s.cursorOn && cursorStill < 1.5 && abs(s.cx - p.x) < 30 * u && abs(s.cy - (p.y - 8 * u)) < 40 * u { return true }
        var n = 0
        for q in s.parts where q.kind == 1 && abs(q.x - p.x) < 14 * u && q.y < p.y + 2 * u && q.y > p.y - 70 * u {
            n += 1
            if n >= 2 { return true }
        }
        return false
    }

    /// Вызывается для каждого человечка каждый кадр до его дел. true — состояние сменилось, кадр закончен.
    func rescueGuard(_ p: inout Person, _ s: Sim, _ dt: Float) -> Bool {
        guard !p.gone, p.job != .buried, p.mode == .ground || p.mode == .crawl, p.x.isFinite, p.y.isFinite else { return false }
        // встающий (hit, фаза 3) считается стоящим — иначе только что откопанного тут же «заваливало» бы снова
        let low = (p.job == .hit && p.phase == 2) || p.mode == .crawl
        let fill = snowFill(p, s, height: (low ? 7 : p.tall - 2) * u)
        // Сбитого с ног должно накрыть с головой (облачко снега от падения — не завал); того, кто роет траншею
        // для тоннеля и сам стоит в снегу по пояс, — тем более.
        let trench = p.job == .tunnel && p.mode == .ground
        // Житель, занятый у своего дома (чистит, чинит, идёт домой), стоит на утоптанной площадке ниже
        // соседнего снега, и вокруг летят его же комья — это не завал, пока не накрыло по-настоящему.
        let atHome = p.home != -1 && p.mode == .ground && (p.job == .shovel || p.job == .igloo || p.job == .home)
            && igloos.contains(where: { $0.id == p.home && abs($0.x - p.x) < 26 * u })
        let strict = trench || atHome
        let deep = (strict ? 10 : (p.mode == .ground && low ? 8 : 5.5)) * u
        if fill >= (strict ? 0.85 : 0.55), let sy = surface(s, x: p.x, stand: p.stand), p.y - sy >= deep {
            // Снег не падал — значит, не завал (сугроб вырос сам, растаял снеговик, в котором стоял): просто
            // вылезает наверх. Так же и тот, кто только что выбрался: стенки ямы ещё сыплются ему под ноги.
            // У незаваленного depth0 — счётчик: меньше нуля — «выбрался, до такого-то времени не заваливает»,
            // больше — сколько секунд подряд он под снегом (кадр-другой — ещё не завал: сугроб осыпается).
            guard p.mode == .crawl || (snowCame(p, s) && !(p.depth0 < 0 && s.time < -p.depth0)) else {
                p.y -= min(p.y - sy, 40 * u * dt)
                return false
            }
            p.depth0 = max(0, p.depth0) + dt
            if p.depth0 < 0.04 && p.mode != .crawl { return false }
            if RescueStats.log {
                print(String(format: "rescue: t=%.1f #%d buried at %.0f,%.0f (job %@, mode %@, fill %.0f%%, depth %.1fu)",
                             s.time, p.id, p.x, p.y, "\(p.job)", "\(p.mode)", fill * 100, (p.y - sy) / u))
            }
            RescueStats.buried += 1
            release(&p, s)
            p.job = .buried
            p.mode = .ground
            next(&p, 0)
            p.depth0 = p.y - sy
            p.wait = rng.range(1.5, 3)          // через сколько начнёт выбираться сам, если неглубоко
            p.acc = 0
            p.aux = 0
            p.aux2 = 0
            return true
        }
        if p.depth0 > 0 { p.depth0 = 0 }
        guard p.mode == .ground, !p.away, !(p.job == .hit && p.phase >= 2),
              p.job != .panic, p.job != .rescue, p.job != .mourn else { return false }
        return lookUp(&p, s) || alarm(&p, s)
    }

    /// Может ли q броситься на помощь заваленному v.
    func canHelp(_ q: Person, _ v: Person) -> Bool {
        !q.gone && q.id != v.id && q.mode == .ground && q.stand == v.stand && !q.away && !(q.job == .hit && q.phase >= 2)
            && q.job != .panic && q.job != .rescue && q.job != .mourn && abs(q.x - v.x) < 180 * u
    }

    func helpers(of id: Int32) -> [Person] {
        folks.filter { ($0.job == .panic || $0.job == .rescue) && $0.target == id && !$0.gone }
    }

    /// Рядом кого-то только что завалило (или из сугроба летит снег — кто-то выкапывается сам):
    /// до четырёх ближайших бросают всё и паникуют.
    func alarm(_ p: inout Person, _ s: Sim) -> Bool {
        var found: Person? = nil
        for v in folks where v.job == .buried && !v.gone && (v.t < 0.7 || s.time < v.aux) && canHelp(p, v) {
            if found == nil || abs(v.x - p.x) < abs(found!.x - p.x) { found = v }
        }
        guard let v = found else { return false }
        let crew = helpers(of: v.id)
        let d = abs(p.x - v.x)
        var ahead = crew.count
        for q in folks where q.id != p.id && canHelp(q, v) {
            let dq = abs(q.x - v.x)
            if dq < d || (dq == d && q.id < p.id) { ahead += 1 }
        }
        guard ahead < 4 else { return false }
        // встать со своей стороны, а если там уже больше народу, чем напротив, — обойти завал
        var side: Float = p.x >= v.x ? 1 : -1
        var same = 0, other = 0
        for q in crew { if (q.aux2 >= 0) == (side > 0) { same += 1 } else { other += 1 } }
        if same > other { side = -side; same = other }
        release(&p, s)
        p.job = .panic
        p.target = v.id
        next(&p, 0)
        p.wait = rng.range(0.6, 1.3)
        p.aux = 0
        p.aux2 = side * (6.5 + 7.5 * Float(same) + rng.range(-1, 1)) * u
        p.anim = .panic
        return true
    }

    /// Сверху летит снег с карниза: кто-то успевает отскочить, кто-то замирает, задрав голову.
    func lookUp(_ p: inout Person, _ s: Sim) -> Bool {
        guard p.stand == -2 else { return false }
        for g in graves where g.kind == 1 && s.time - g.born < 0.35 && p.obj != g.id && abs(p.x - g.x) < 16 * u {
            let h = (UInt32(truncatingIfNeeded: Int(p.id) &* 7919 &+ g.id &* 104729) &* 2654435761) >> 16
            if h % 100 < 40 {
                release(&p, s)
                p.job = .arrive                 // бегом в сторону
                let away: Float = abs(p.x - g.x) < 2 * u ? g.dir : (p.x > g.x ? 1 : -1)
                p.goalX = clampX(p.x + away * rng.range(36, 46) * u, s)
                if abs(p.goalX - p.x) < 20 * u { p.goalX = clampX(p.x - away * 42 * u, s) }     // упёрся в край экрана
            } else if p.job == .idle || p.job == .wander || p.job == .gaze || p.job == .wave || p.job == .cheer {
                p.job = .gaze
                p.wait = max(0.4, g.until - s.time)
                p.face = -g.dir
            } else {
                continue
            }
            p.obj = g.id
            next(&p, 0)
            return true
        }
        return false
    }

    /// Стенки ямы шириной ±half столбцов вокруг x осыпаются: в рыхлом снегу отвесный колодец не вырыть,
    /// поэтому глубокий завал раскапывать намного дольше мелкого.
    func cave(_ s: Sim, x: Float, top: Float, half: Int) {
        guard x.isFinite, top.isFinite else { return }
        let c = Int(max(0, min(Float(s.W - 1), x * s.inv))), r = Int(max(0, min(Float(s.H), top * s.inv)))
        s.snowDisturbed(c - half - 2, r - Int(40 * u * s.inv), c + half + 2, r + 1)
    }

    /// Сколько ячеек в «пригоршне» снега площадью k квадратных «пикселей» человечка.
    func handful(_ s: Sim, _ k: Float) -> Int { max(1, Int((k * u * u / (s.cell * s.cell)).rounded())) }

    // MARK: - Под снегом

    func runBuried(_ p: inout Person, _ s: Sim, _ dt: Float) {
        if graves.contains(where: { $0.kind == 0 && $0.victim == p.id }) { p.gone = true; return }      // не откопали
        guard let sy = surface(s, x: p.x, stand: p.stand) else {        // опоры больше нет — падает вместе со снегом
            idle(&p, 0.3)
            drop(&p, s)
            return
        }
        let depth = p.y - sy
        // Первые полторы секунды снег ещё сыплется и оседает (сначала ложится столбом): глубина — какая есть;
        // дальше — наибольшая (если досыпало ещё)
        p.depth0 = p.t < 1.5 ? depth : max(p.depth0, depth)
        let crew = folks.contains { ($0.job == .panic || $0.job == .rescue) && $0.target == p.id && !$0.gone }
        let k = sqrtf(u / 2)
        /// Выбросить n ячеек наружу — больше туда, где ниже, чтобы не скатывались обратно.
        func toss(_ n: Int, far: Float) {
            let l = surface(s, x: p.x - 8 * u, stand: p.stand) ?? sy, r = surface(s, x: p.x + 8 * u, stand: p.stand) ?? sy
            let down: Float = r >= l ? 1 : -1
            for _ in 0..<n {
                let dir = rng.f() < 0.8 ? down : -down
                chunk(s, p.x + rng.range(-2, 2) * u, sy - rng.range(1, 4), dir * rng.range(60, 130) * k * far, -rng.range(120, 200) * k)
            }
        }
        // слишком долго один под снегом (или всех разогнали, ждать некого) — выбирается рывком
        let limit: Float = s.cfg.people == 0 && !forced ? 4 : 60
        if !crew && depth >= 5 * u && p.t > limit {
            toss(scoop(s, x: p.x, stand: p.stand, want: handful(s, 90), half: Int(3 * u * s.inv) + 1, per: 40), far: 1.6)
        }
        // выбрался. Снег над головой должен разойтись не на миг (сугроб ещё осыпается), а хотя бы на несколько кадров
        p.aux2 = depth < 5 * u ? p.aux2 + dt : 0
        if p.aux2 > 0.1 || (!crew && p.t > limit) {
            if crew { RescueStats.dugOut += 1 } else { RescueStats.selfOut += 1 }
            if RescueStats.log { print(String(format: "rescue: t=%.1f #%d is out after %.1f s (max depth %.1fu, helpers: %@)", s.time, p.id, p.t, p.depth0 / u, crew ? "yes" : "no")) }
            p.y = min(p.y, (surface(s, x: p.x, stand: p.stand) ?? sy) + 2 * u)
            puff(s, p.x, p.y - 2 * u, n: 6, stand: p.stand)
            for _ in 0..<3 { dust(s, p.x + rng.range(-3, 3) * u, p.y - rng.range(4, 12) * u) }
            p.snowHat = 6
            p.depth0 = -(s.time + 3)
            p.fallDir = p.face
            p.job = .hit
            next(&p, 3)
            p.anim = .getup
            return
        }
        // сам: неглубоко — быстро, а если на помощь никто не пришёл — понемногу, но чем дальше, тем отчаяннее
        let shallow = p.depth0 < 9 * u
        guard shallow ? p.t > p.wait : (!crew && p.t > 2.5) else { return }
        p.acc += dt
        guard p.acc >= (shallow ? 0.22 : 0.5) else { return }
        p.acc = 0
        let n = scoop(s, x: p.x, stand: p.stand, want: handful(s, shallow ? 6 : 4 + min(20, p.t * 0.3)), half: Int(2 * u * s.inv) + 1, per: 2)
        cave(s, x: p.x, top: sy, half: Int(2 * u * s.inv) + 1)
        toss(n, far: shallow ? 1 : 1 + min(0.6, p.t * 0.02))
        if n > 0 && !shallow { p.aux = s.time + 0.6 }       // из сугроба летит снег — это могут заметить (см. alarm)
    }

    // MARK: - Паника и раскопки

    /// Заваленный, к которому бежит или которого откапывает p. nil — спасать больше некого (p уже занят другим).
    func victim(_ p: inout Person, _ s: Sim) -> Person? {
        if let g = graves.first(where: { $0.kind == 0 && $0.victim == p.target }) { mourn(&p, s, g); return nil }
        guard let v = folks.first(where: { $0.id == p.target }), !v.gone else { idle(&p, rng.range(0.3, 1)); return nil }
        if v.job != .buried {                   // выбрался
            p.face = v.x >= p.x ? 1 : -1
            p.job = .cheer
            p.wait = 1.5
            next(&p, 0)
            return nil
        }
        return v
    }

    func runPanic(_ p: inout Person, _ s: Sim, _ dt: Float) {
        guard let v = victim(&p, s) else { return }
        if p.phase == 0 {                       // мечется туда-сюда
            p.anim = .panic
            if p.t >= p.aux {
                p.face = -p.face
                p.aux = p.t + rng.range(0.14, 0.3)
            }
            let step = 30 * u * dt
            p.x = clampX(p.x + p.face * step, s)
            if p.stand != -2, let seg = segFor(s, win: p.stand, x: p.x) { p.x = max(seg.x0 + 3, min(seg.x1 - 3, p.x)) }
            p.walkPhase += step / (4.5 * u)
            settle(&p, s, dt, fast: true)
            if p.mode == .ground && p.t > p.wait { next(&p, 1) }
            return
        }
        var gx = clampX(v.x + p.aux2, s)        // бежит к завалу, каждый — на своё место
        if p.stand != -2, let seg = segFor(s, win: p.stand, x: v.x) { gx = max(seg.x0 + 3, min(seg.x1 - 3, gx)) }
        let there = walk(&p, s, to: gx, speed: 46 * u, dt)
        if p.mode != .ground { return }
        if p.anim == .run { p.anim = .panic }
        if there || p.t > 10 {
            p.face = v.x >= p.x ? 1 : -1
            p.job = .rescue
            next(&p, 0)
            p.acc = rng.range(0, 0.3)
        }
    }

    func runRescue(_ p: inout Person, _ s: Sim, _ dt: Float) {
        guard let v = victim(&p, s) else { return }
        p.face = v.x >= p.x ? 1 : -1
        settle(&p, s, dt, fast: true)           // копает, а не стоит: снег, летящий из ямы, его не заваливает
        if p.mode != .ground { return }
        p.anim = .dig
        p.acc += dt
        let top = surface(s, x: v.x, stand: v.stand) ?? p.y
        // чем глубже яма, тем дольше выгребать из неё каждую пригоршню
        if p.acc >= 0.4 * (1 + max(0, v.y - top - 8 * u) / (12 * u)) {
            p.acc = rng.range(-0.05, 0.05)
            let out: Float = p.x >= v.x ? 1 : -1, k = sqrtf(u / 2)
            // к самому заваленному дотягиваются двое ближних; дальние отгребают то, что сползает в яму с их стороны
            let near = abs(p.x - v.x) < 9 * u
            let half = Int((near ? 4 : 3) * u * s.inv) + 1
            let n = scoop(s, x: near ? v.x : v.x + out * 6.5 * u, stand: v.stand, want: handful(s, rng.range(7, 11)), half: half, per: 2)
            cave(s, x: v.x, top: top, half: Int(4 * u * s.inv) + 1)
            for _ in 0..<n {                    // комья летят за спину, подальше от ямы
                chunk(s, p.x + out * rng.range(0, 2) * u, min(p.y - 9 * u, top - 2) - rng.range(0, 4),
                      out * rng.range(70, 150) * k, -rng.range(110, 190) * k)
            }
        }
        if p.t > (v.depth0 > 26 * u ? 9 : 25) {         // не откопать
            var g = Grave(id: nextObjId, x: v.x, stand: v.stand, topY: (surface(s, x: v.x, stand: v.stand) ?? v.y) - 9 * u,
                          scarf: v.look.pal[Int(cScarf)], born: s.time)
            nextObjId += 1
            g.victim = v.id
            graves.append(g)
            if let old = graves.firstIndex(where: { $0.kind == 0 }), graves.filter({ $0.kind == 0 }).count > 8 { graves.remove(at: old) }
            RescueStats.graves += 1
            if RescueStats.log { print(String(format: "rescue: t=%.1f #%d is given up after %.1f s (max depth %.1fu)", s.time, v.id, v.t, v.depth0 / u)) }
            mourn(&p, s, g)
        }
    }

    // MARK: - Палочка

    /// Идти оплакивать: место у палочки — со своей стороны, на расстоянии вытянутых рук друг от друга.
    func mourn(_ p: inout Person, _ s: Sim, _ g: Grave) {
        let side: Float = p.x >= g.x ? 1 : -1
        let d = abs(p.x - g.x)
        var idx = 0
        for q in folks where q.id != p.id && !q.gone {
            let mine = (q.job == .mourn && q.obj == g.id) || ((q.job == .panic || q.job == .rescue) && q.target == g.victim)
            guard mine, (q.x >= g.x) == (side > 0) else { continue }
            let dq = abs(q.x - g.x)
            if dq < d || (dq == d && q.id < p.id) { idx += 1 }
        }
        release(&p, s)
        p.job = .mourn
        p.obj = g.id
        next(&p, 0)
        p.aux2 = side * (8 + 9 * Float(idx)) * u        // соседи дотягиваются друг до друга руками
        p.wait = rng.range(7, 10)
    }

    func runMourn(_ p: inout Person, _ s: Sim, _ dt: Float) {
        guard let gi = graves.firstIndex(where: { $0.id == p.obj && $0.kind == 0 }) else { idle(&p, rng.range(0.3, 1.5)); return }
        let g = graves[gi]
        switch p.phase {
        case 0:     // подойти
            var gx = clampX(g.x + p.aux2, s)
            if p.stand != -2, let seg = segFor(s, win: p.stand, x: g.x) { gx = max(seg.x0 + 3, min(seg.x1 - 3, gx)) }
            if walk(&p, s, to: gx, speed: 15 * u, dt) || p.t > 8 {
                if p.mode != .ground { return }
                p.face = g.x >= p.x ? 1 : -1
                if !g.planted && g.planter == -1 {
                    graves[gi].planter = p.id
                    next(&p, 1)
                } else {
                    next(&p, 2)
                }
            }
        case 1:     // первый дошедший втыкает палочку
            p.face = g.x >= p.x ? 1 : -1
            p.anim = .pat
            settle(&p, s, dt)
            if p.mode != .ground { graves[gi].planter = -1; return }
            if p.t > 0.25, let sy = surface(s, x: g.x, stand: g.stand) {
                graves[gi].planted = true       // входит в снег: сначала торчит повыше
                graves[gi].topY = sy - (12 - 3 * min(1, (p.t - 0.25) / 0.45)) * u
            }
            if p.t > 0.9 { next(&p, 2) }
        default:    // стоят вокруг, опустив головы
            p.face = g.x >= p.x ? 1 : -1
            p.anim = .mourn
            settle(&p, s, dt)
            if !g.planted && !folks.contains(where: { $0.id == g.planter && $0.job == .mourn && $0.obj == g.id && $0.phase == 1 && !$0.gone }) {
                graves[gi].planter = p.id       // того, кто втыкал, сбили с ног
                next(&p, 1)
            } else if p.t > p.wait {
                idle(&p, rng.range(0.4, 2.5))
            }
        }
    }

    /// Раз в кадр: палочки заметает снегом.
    func stepRescue(_ s: Sim, _ dt: Float) {
        guard !graves.isEmpty else { return }
        let fall = min(8, max(s.cfg.intensity, s.cfg.flakeRate / 30))      // идёт ли снег и насколько сильно
        var i = 0
        while i < graves.count {
            var g = graves[i]
            if g.kind == 1 {                    // снег съезжает с карниза
                g.acc += g.rate * dt
                while g.acc >= 1 && g.left > 0 {
                    g.acc -= 1
                    g.left -= 1
                    chunk(s, g.x0 + g.dir * rng.range(0, 2) * u, g.topY - rng.range(0, 6) * u,
                          g.vx * rng.range(0.88, 1.12) + rng.range(-3, 3), rng.range(-30, 70))
                }
                if g.left > 0 && rng.f() < 0.35 { dust(s, g.x0 + rng.range(-6, 6), g.topY - rng.range(0, 12)) }
                if s.time > g.until || s.time < g.born { graves.remove(at: i) } else { graves[i] = g; i += 1 }
                continue
            }
            // окно ушло или его только что сдвинули (сугроб уехал вместе с ним) — палочки больше нет
            let moved = g.stand != -2 && g.stand != -1 && boxes[g.stand].map { $0.still == 0 } ?? false
            guard !moved, let sy = surface(s, x: g.x, stand: g.stand) else {
                if g.planted { for _ in 0..<3 { dust(s, g.x + rng.range(-2, 2), g.topY + rng.range(0, 6) * u) } }
                graves.remove(at: i)
                continue
            }
            if !g.planted {
                // воткнуть некому (всех сбили с ног или прогнали) — палочка всё равно остаётся
                if s.time - g.born > 8 && !folks.contains(where: { $0.job == .mourn && $0.obj == g.id && !$0.gone }) {
                    g.planted = true
                    g.topY = sy - 9 * u
                }
                graves[i] = g
                i += 1
                continue
            }
            // снег под палочкой осел или его смахнули — она опускается вместе с ним
            if g.planter == -1 || !folks.contains(where: { $0.id == g.planter && $0.job == .mourn && $0.phase == 1 }) {
                g.planter = -1
                // воткнута с запасом: пару пригоршней снега рядом можно взять. Чем дольше идёт снег, тем
                // глубже она сидит, — даже если сугроб под ней оседает так же быстро, как растёт
                g.topY = max(g.topY, sy - max(0, 13 * u - g.sunk))
            }
            if sy - g.topY <= u {               // замело
                RescueStats.covered += 1
                graves.remove(at: i)
                continue
            }
            if fall > 0 {
                g.sunk += dt * fall * 9 * u / 280
                g.acc += dt * fall * 0.24 * u * u / (s.cell * s.cell)
                while g.acc >= 1 {
                    g.acc -= 1
                    drift(s, g)
                }
            }
            graves[i] = g
            i += 1
        }
    }

    /// Ячейка снега ложится у палочки — так, чтобы вокруг неё рос пологий бугорок.
    func drift(_ s: Sim, _ g: Grave) {
        let c = Int(max(0, min(Float(s.W - 1), g.x * s.inv)))
        var seg: Ledge? = nil
        if g.stand != -2 {
            seg = segFor(s, win: g.stand, x: g.x)
            if seg == nil { return }
        }
        let half = Int(4 * u * s.inv) + 1
        var best = -1, bestRow = 0, bestScore = Int.max
        for col in (c - half)...(c + half) where col >= 0 && col < s.W {
            if let sg = seg, Float(col) * s.cell < sg.x0 || Float(col + 1) * s.cell > sg.x1 { continue }
            let base = seg != nil ? ledgeRow(s, seg!, col) : s.H
            let h = pile(s, col, base)
            let r = base - h - 1
            guard r >= 0, r < s.H else { continue }
            let j = r * s.W + col
            guard s.snow[j] == 0, s.ledge[j] == 0, s.mask[j] == 0 else { continue }
            let score = (h + abs(col - c)) * 4 + Int(rng.next() & 3)
            if score < bestScore { bestScore = score; best = col; bestRow = r }
        }
        guard best >= 0 else { return }
        let j = bestRow * s.W + best
        s.snow[j] = rng.shade()
        s.hard[j] = 0
        s.gridDirty = true
        s.hardDirty = true
    }

    func emitRescue(_ s: Sim, into out: inout [PxInst]) {
        for g in graves where g.kind == 0 && g.planted {
            guard let sy = surface(s, x: g.x, stand: g.stand) else { continue }
            let bx = (g.x / u).rounded() * u
            let top = (g.topY / u).rounded() * u
            let bot = (sy / u).rounded() * u + u        // на «пиксель» уходит в снег
            guard bot - top >= u else { continue }
            out.append(PxInst(rect: SIMD4(bx + u, top + u, u, bot - top - u), color: SIMD4(0, 0, 0.02, 0.22)))     // тень — чтобы читалась на светлом
            out.append(PxInst(rect: SIMD4(bx, top, u, bot - top), color: SIMD4(0.52, 0.35, 0.20, 1)))
            out.append(PxInst(rect: SIMD4(bx, top, u, u), color: SIMD4(0.74, 0.55, 0.34, 1)))
            // шарф: узел в три «пикселя» и хвост, который полощется по ветру
            let ky = top + 2 * u
            guard ky + u <= bot - u else { continue }
            let dark = SIMD4<Float>(g.scarf.x * 0.74, g.scarf.y * 0.74, g.scarf.z * 0.74, 1)
            let dir: Float = s.windNow < -2 ? -1 : 1
            let windy = abs(s.windNow) > 25
            let f = Int(s.time * (windy ? 5 : 2.2) + Float(g.id) * 1.7) & 1
            out.append(PxInst(rect: SIMD4(bx - u, ky, 3 * u, u), color: g.scarf))
            out.append(PxInst(rect: SIMD4(bx, ky, u, u), color: dark))
            let a: (Float, Float) = windy ? (2, 0) : (2, 1)
            let b: (Float, Float) = windy ? (3, Float(f)) : (2 + Float(f), 2)
            for (k, t) in [a, b].enumerated() {
                let x = dir > 0 ? bx + t.0 * u : bx - t.0 * u
                if ky + t.1 * u + u <= bot { out.append(PxInst(rect: SIMD4(x, ky + t.1 * u, u, u), color: k == 0 ? g.scarf : dark)) }
            }
        }
    }

    // MARK: - Снег с карниза

    /// Происшествие: снег съезжает с карниза окна на тех, кто стоит внизу. false — сейчас не на кого.
    func avalanche(_ s: Sim) -> Bool {
        // 80–120 ячеек при вокселе 3 и «пикселе» 2; иногда съезжает вдвое больше — из-под такого откопают не всегда
        let big = rng.f() < 0.25
        let want = Int(Float(handful(s, big ? rng.range(360, 520) : rng.range(180, 270))) * max(1, sqrtf(s.cell / 3)))  // крупные воксели ложатся грубее
        let span = Int((big ? 70 : 40) * u * s.inv) + 2 // с какой ширины карниза съезжает
        var cands: [(seg: Ledge, dir: Float, x0: Float, tx: Float, floor: Float)] = []
        for seg in s.segs where seg.kind == 1 && seg.x1 - seg.x0 > 40 {
            for dir in [Float(-1), 1] {
                let edge = dir < 0 ? seg.x0 : seg.x1
                let x0 = edge + dir * 6                 // сразу за боком окна
                guard x0 > 12, x0 < s.wPt - 12 else { continue }
                var have = 0                            // есть ли чему съезжать
                let ce = Int(edge * s.inv)
                for k in 0...span {
                    let col = ce - Int(dir) * k
                    if col >= 0 && col < s.W && Float(col) * s.cell >= seg.x0 - s.cell && Float(col) * s.cell <= seg.x1 {
                        have += pile(s, col, ledgeRow(s, seg, col))
                    }
                }
                guard have * 10 >= (big ? handful(s, 270) : want) * 7 else { continue }
                for q in folks where !q.gone && q.mode == .ground && q.stand == -2 && !q.away && !(q.job == .hit && q.phase >= 2)
                    && q.job != .panic && q.job != .rescue && q.job != .mourn {
                    let d = dir * (q.x - x0)
                    guard d > -3 * u, d < 14 * u, q.y - seg.y >= 30 * u else { continue }
                    let tx = x0 + dir * max(2 * u, d)
                    // по дороге вниз нет другого карниза
                    let lo = min(x0, tx) - 8, hi = max(x0, tx) + 8
                    if s.segs.contains(where: { $0.y > seg.y + 2 && $0.y < q.y && $0.x1 > lo && $0.x0 < hi }) { continue }
                    cands.append((seg, dir, x0, tx, q.y))
                }
            }
        }
        guard !cands.isEmpty else { return false }
        let c = cands[Int(rng.next() % UInt64(cands.count))]
        let edge = c.dir < 0 ? c.seg.x0 : c.seg.x1
        let got = scoop(s, x: edge - c.dir * s.cell * 0.5, stand: c.seg.win, want: want, half: span, per: 60)
        guard got > 0 else { return false }
        // сколько лететь и с какой скоростью вбок, чтобы упало куда надо (то же сопротивление, что у комьев)
        var y = c.seg.y, vy: Float = 20, T: Float = 0, reach: Float = 0, k: Float = 1
        let h: Float = 1.0 / 60
        while y < c.floor && T < 4 {
            vy = (vy + 1400 * h) * (1 - 1.4 * h)
            y += vy * h
            k *= 1 - 1.4 * h
            reach += k * h
            T += h
        }
        // сами комья сыплются с края струёй ещё четверть секунды (см. stepRescue)
        let pour: Float = 0.28
        var g = Grave(id: nextObjId, x: c.tx, stand: -2, topY: c.seg.y, scarf: .zero, born: s.time)
        nextObjId += 1
        g.kind = 1
        g.dir = c.dir
        g.x0 = c.x0
        g.vx = (c.tx - c.x0 - s.windNow * 0.3 * (T - reach)) / max(0.05, reach)      // с поправкой на ветер
        g.left = got
        g.rate = Float(got) / pour
        g.until = s.time + pour + T + 0.25
        graves.append(g)
        RescueStats.avalanches += 1
        if RescueStats.log { print(String(format: "rescue: t=%.1f avalanche: %d cells off window %d at x=%.0f, lands in %.2f s", s.time, got, c.seg.win, c.tx, T)) }
        return true
    }
}
