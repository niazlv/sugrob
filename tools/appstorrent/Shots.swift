import AppKit

// Кадры для каталога приложений: целые экраны 1800×1120 (900×560 pt, 2x) и обложка.
// Это те же сцены, что в README (tools/readme-media/Demo.swift), но снятые стоп-кадром.
extension Demo {
    static func still(_ st: DemoStage, _ out: String, _ name: String) {
        st.save("\(out)/\(name).png")
        print("saved \(name)")
    }

    static func shotHero(_ out: String, _ args: [String]) -> Bool {
        guard let st = DemoStage(w: 900, h: 560, scale: 2, wins: desk, dock: deskDock) else { return false }
        st.arrow = true
        st.run(8)
        st.curOn = true
        st.cur = SIMD2(470, 330)
        st.run(1.0, to: SIMD2(66, 136), ease: true)
        st.run(1.5, to: SIMD2(240, 139))
        still(st, out, "hero-brush")
        st.run(1.1, to: SIMD2(420, 139))
        st.run(0.7, to: SIMD2(560, 330), ease: true)
        st.run(1.7)
        still(st, out, "hero-dock")
        st.run(0.7, to: SIMD2(360, 488), ease: true)
        st.run(0.16, to: SIMD2(560, 476))
        st.run(0.35, to: SIMD2(640, 400), ease: true)
        still(st, out, "hero-scatter")
        return true
    }

    static func shotSnowman(_ out: String, _ args: [String]) -> Bool {
        let wins = [DemoWin(rect: CGRect(x: 560, y: 392, width: 280, height: 200), dark: false)]
        guard let st = DemoStage(w: 900, h: 560, scale: 2, wins: wins, dock: nil, seed: 21) else { return false }
        let sim = st.sim
        st.arrow = true
        st.run(8)
        var placed: [Int32] = []
        func top() -> SIMD2<Float>? {
            guard let id = placed.last, let b = sim.balls.first(where: { $0.id == id }) else { return nil }
            return SIMD2(b.x, b.y - b.r)
        }
        func roll(from a: SIMD2<Float>, to b: SIMD2<Float>, secs: Float, x: Float) {
            st.curOn = true
            st.run(0.55, to: a, ease: true)
            sim.handsMode = true
            st.run(0.15)
            let before = Set(sim.balls.map { $0.id })
            sim.grabBegin()
            st.run(secs, to: b)
            let mine = sim.balls.first { !before.contains($0.id) }
            let r = mine?.r ?? 12
            if let t = top() {
                st.run(0.9, to: SIMD2(t.x, t.y - r - 16), ease: true)
                st.run(0.5, to: SIMD2(t.x, t.y - r - 1.5))
            } else {
                st.run(0.9, to: SIMD2(x, 392 - 44 - r), ease: true)
                st.run(0.5, to: SIMD2(x, 392 - 22 - r))
            }
            st.run(0.2)
            sim.grabEnd()
            sim.handsMode = false
            if let m = mine { placed.append(m.id) }
            st.run(0.25)
            st.run(0.5, to: SIMD2(st.cur.x - 46, st.cur.y + 30), ease: true)
            st.run(0.3)
        }
        st.cur = SIMD2(470, 420)
        st.curOn = true
        st.run(0.5)
        roll(from: SIMD2(300, 546), to: SIMD2(545, 546), secs: 1.7, x: 640)
        roll(from: SIMD2(545, 546), to: SIMD2(405, 546), secs: 1.1, x: 640)
        roll(from: SIMD2(400, 546), to: SIMD2(470, 546), secs: 0.7, x: 640)
        st.run(0.7, to: SIMD2(520, 330), ease: true)
        st.run(2.0)
        still(st, out, "snowman")
        return true
    }

    static func shotPeople(_ out: String, _ args: [String]) -> Bool {
        let wins = [DemoWin(rect: CGRect(x: 520, y: 340, width: 300, height: 260), dark: true)]
        guard let st = DemoStage(w: 900, h: 560, scale: 2, wins: wins, dock: nil, seed: 7) else { return false }
        let pp = st.sim.people
        st.sim.cfg.people = 2
        st.sim.cfg.peopleLadders = true
        st.sim.cfg.peopleStay = false
        st.run(6)
        pp.summon()
        guard st.wait(200, { pp.ladders.contains { $0.active && $0.rows.count > 0 && $0.front >= $0.rows.count - 14 } }) else {
            print("people: no ladder"); return false
        }
        st.run(1.0)
        still(st, out, "people-ladder")
        _ = st.wait(30, { pp.ladders.contains { $0.done } })
        st.run(2.5)
        still(st, out, "people-climb")
        return true
    }

    static func shotStorm(_ out: String, _ args: [String]) -> Bool {
        guard let st = DemoStage(w: 900, h: 560, scale: 2, wins: desk, dock: deskDock, seed: 11) else { return false }
        st.sim.cfg.storms = true
        st.run(8)
        st.sim.wind.startStorm(strength: 1, dir: 1, seconds: 60)
        st.run(11)
        still(st, out, "storm")
        return true
    }

    static func shotVillage(_ out: String, _ args: [String]) -> Bool {
        let wins = [DemoWin(rect: CGRect(x: 40, y: 190, width: 250, height: 420), dark: true)]
        guard let st = DemoStage(w: 900, h: 560, scale: 2, wins: wins, dock: nil, seed: 5) else { return false }
        let sim = st.sim, pp = sim.people
        sim.cfg.people = 2
        sim.cfg.peopleLadders = false
        pp.u = 2
        pp.visitEnd = sim.time + 100000
        HomeTune.evening = true
        st.run(6)
        for i in 0..<3 { _ = pp.debugHouse(sim, x: 440 + Float(i) * 138, door: i == 2 ? -1 : 1) }
        st.run(60)
        guard st.wait(900, { pp.fires.contains { $0.big } && pp.folks.filter { $0.job == .fire }.count >= 5 }) else {
            print("village: no gathering"); return false
        }
        st.run(5)
        still(st, out, "village")
        return true
    }

    static func shotTree(_ out: String, _ args: [String]) -> Bool {
        let wins = [DemoWin(rect: CGRect(x: 560, y: 392, width: 280, height: 200), dark: false)]
        guard let st = DemoStage(w: 900, h: 560, scale: 2, wins: wins, dock: nil, seed: 9) else { return false }
        let sim = st.sim, pp = sim.people
        sim.cfg.people = 2
        sim.cfg.peopleLadders = false
        sim.cfg.peopleStay = false
        sim.cfg.peopleEvents = true
        st.run(6)
        pp.summon()
        st.run(14)
        guard pp.startTree(sim) else { print("tree: refused"); return false }
        guard st.wait(120, { !pp.trees.isEmpty }) else { print("tree: not planted"); return false }
        st.run(4)
        still(st, out, "tree")
        return true
    }

    /// Обложка 742×360 в двойном размере: вечерний костёр, срез сцены «поселение» в масштабе 4x.
    static func shotCover(_ out: String, _ args: [String]) -> Bool {
        let wins = [DemoWin(rect: CGRect(x: 40, y: 190, width: 250, height: 420), dark: true)]
        guard let st = DemoStage(w: 900, h: 560, scale: 4, wins: wins, dock: nil, seed: 5) else { return false }
        let sim = st.sim, pp = sim.people
        sim.cfg.people = 2
        sim.cfg.peopleLadders = false
        pp.u = 2
        pp.visitEnd = sim.time + 100000
        HomeTune.evening = true
        st.run(6)
        for i in 0..<3 { _ = pp.debugHouse(sim, x: 440 + Float(i) * 138, door: i == 2 ? -1 : 1) }
        st.run(60)
        guard st.wait(900, { pp.fires.contains { $0.big } && pp.folks.filter { $0.job == .fire }.count >= 5 }) else {
            print("cover: no gathering"); return false
        }
        st.run(5)
        // 440×214 pt = 1760×856 px: чуть шире обложки, чтобы все три иглу влезли; до 1484×720 доведёт make
        st.crop = CGRect(x: 370, y: 346, width: 440, height: 214)
        still(st, out, "cover-wide")
        return true
    }
}
