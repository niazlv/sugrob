import AppKit
import MetalKit
import ServiceManagement

/// Короткий журнал событий со слоями снега: ~/Library/Logs/Sugrob.log (обрезается при запуске).
enum EventLog {
    private static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Sugrob.log")
    private static let start = CACurrentMediaTime()
    private static var lines = 0
    static func reset() { try? "".write(to: url, atomically: true, encoding: .utf8) }
    static func add(_ text: String) {
        guard lines < 2000 else { return }
        lines += 1
        let line = String(format: "%8.2f  %@\n", CACurrentMediaTime() - start, text)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
            try? h.close()
        }
    }
}

final class Settings {
    private let d = UserDefaults.standard
    var weather: Int { get { d.object(forKey: "weather") as? Int ?? 1 } set { d.set(newValue, forKey: "weather") } }
    var wind: Int { get { d.object(forKey: "wind") as? Int ?? 0 } set { d.set(newValue, forKey: "wind") } }
    var depth: Int { get { d.object(forKey: "depth") as? Int ?? 1 } set { d.set(newValue, forKey: "depth") } }
    var voxel: Int { get { d.object(forKey: "voxel") as? Int ?? 3 } set { d.set(newValue, forKey: "voxel") } }
    var openOnly: Bool { get { d.object(forKey: "openOnly") as? Bool ?? false } set { d.set(newValue, forKey: "openOnly") } }
    func flag(_ key: String, _ def: Bool = true) -> Bool { d.object(forKey: key) as? Bool ?? def }
    func toggle(_ key: String, _ def: Bool = true) { d.set(!flag(key, def), forKey: key) }
    var rules: SnowRules {
        SnowRules(windows: flag("onWindows"), menuWindows: flag("onMenuWindows"), narrow: flag("onNarrow"),
                  widgets: flag("onWidgets"), dock: flag("onDock"), radius: CGFloat(cornerRadius))
    }
    /// Радиус углов окон. В macOS 26 окна скруглены сильнее, чем раньше.
    var cornerRadius: Int {
        get { d.object(forKey: "cornerRadius") as? Int ?? (ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 18 : 10) }
        set { d.set(newValue, forKey: "cornerRadius") }
    }
    var autoFill: Bool { get { d.object(forKey: "autoFill") as? Bool ?? true } set { d.set(newValue, forKey: "autoFill") } }

    func simConfig() -> SimConfig {
        var c = SimConfig()
        var windK: Float = 1
        switch weather {
        case 0: c.flakeRate = 5; c.fallMin = 20; c.fallMax = 52; c.gust = 4; c.intensity = 0.5
        case 2: c.flakeRate = 110; c.fallMin = 60; c.fallMax = 130; c.gust = 60; c.intensity = 2.2; windK = 2.2
        default: c.flakeRate = 14; c.fallMin = 22; c.fallMax = 64; c.gust = 6; c.intensity = 1
        }
        c.wind = Float(wind) * 45 * windK
        c.capScale = depth == 0 ? 0.6 : (depth == 2 ? 1.8 : 1)
        if !autoFill { c.intensity = 0 }
        c.openOnly = openOnly
        c.floor = flag("onFloor")
        c.sweep = flag("sweep")
        c.aging = flag("aging")
        return c
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private var overlays: [Overlay] = []
    private var statusItem: NSStatusItem!
    private var device: MTLDevice?
    private var paused = false
    private var pollTimer: Timer?
    private var pollTick = 0
    private let updater = Updater()
    private let launchedAt = CACurrentMediaTime()
    private var spaceSince = CACurrentMediaTime()
    private var lastCleanup = CACurrentMediaTime()
    private var pending: [Int: (key: UInt64, since: CFTimeInterval)] = [:]
    private var lastKey: [Int: UInt64] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        EventLog.reset()
        device = MTLCreateSystemDefaultDevice()
        guard device != nil else {
            let a = NSAlert()
            a.messageText = "Сугроб не может запуститься"
            a.informativeText = "На этом Mac недоступен Metal."
            a.runModal()
            NSApp.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Сугроб") {
            img.isTemplate = true
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "❄"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        buildOverlays()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
        updater.start()
    }

    private func buildOverlays() {
        overlays.forEach { $0.close() }
        overlays = []
        ensureOverlays()
        pollWindows()
    }

    /// У каждого рабочего стола свой слой снега. Здесь заводится слой для стола, на который
    /// пришли впервые, включается слой текущего стола и замирают слои остальных.
    private func ensureOverlays() {
        guard let device else { return }
        let now = CACurrentMediaTime()
        for (si, s) in NSScreen.screens.enumerated() {
            let info = spaceInfo(of: s)
            // обычный стол — свой слой; полноэкранные приложения — один общий на экран
            let key: UInt64 = info.id == 0 ? 0 : (info.fullscreen ? Overlay.fullscreenKey : info.id)
            let mine = overlays.filter { $0.screen === s }
            if lastKey[si] != key {
                EventLog.add("screen \(si): space \(info.id) fullscreen=\(info.fullscreen) -> layer key \(key == Overlay.fullscreenKey ? "FS" : String(key)); layers: \(mine.map { ($0.spaceId == Overlay.fullscreenKey ? "FS" : String($0.spaceId)) + ($0.panel.isOnActiveSpace ? "*" : "") })")
                lastKey[si] = key
            }
            if let cur = mine.first(where: { $0.spaceId == key }) {
                for o in mine where o !== cur { o.suspend() }
                cur.resume(hidden: paused)
                pending[si] = nil
            } else {
                for o in mine { o.suspend() }
                if key != 0 && key != Overlay.fullscreenKey {
                    // Слой обычного стола заводим, только когда перелистывание закончилось:
                    // окно, созданное на ходу, система может отнести не к тому столу.
                    if pending[si]?.key != key { pending[si] = (key, now); continue }
                    if now - pending[si]!.since < 0.45 { continue }
                }
                pending[si] = nil
                guard let o = Overlay(screen: s, device: device, cell: Float(settings.voxel),
                                      cfg: settings.simConfig(), spaceId: key) else { continue }
                o.rules = settings.rules
                o.freshFill = now - launchedAt > 30          // на столах, открытых позже, снег уже лежит
                overlays.append(o)
                o.show()
                if paused { o.setHidden(true) }
                spaceSince = now
                EventLog.add("screen \(si): created layer \(key == Overlay.fullscreenKey ? "FS" : String(key)), on active space: \(o.panel.isOnActiveSpace)")
            }
            // Уборка, когда стол уже какое-то время не менялся: слой чужого стола, оказавшийся здесь
            // (его стол закрыли, и система перенесла окно), убираем; лишние старые — тоже.
            if now - spaceSince > 2, now - lastCleanup > 1 {
                lastCleanup = now
                let own = mine.filter { !$0.isShared && !$0.active }
                var stale = own.filter { $0.panel.isOnActiveSpace }
                let idle = own.filter { !$0.panel.isOnActiveSpace }.sorted { $0.leftAt < $1.leftAt }
                if idle.count > 8 { stale += idle.prefix(idle.count - 8) }
                for o in stale {
                    EventLog.add("screen \(si): closing stray layer \(o.spaceId)")
                    o.close()
                    overlays.removeAll { $0 === o }
                }
            }
        }
    }

    @objc private func screensChanged() { buildOverlays() }
    @objc private func spaceChanged() {
        EventLog.add("system: active space changed")
        spaceSince = CACurrentMediaTime(); ensureOverlays(); pollWindows()
    }

    /// Окна опрашиваются редко, а пока зажата кнопка мыши (перетаскивание) — часто.
    private func poll() {
        ensureOverlays()
        if paused { return }
        pollTick += 1
        let dragging = NSEvent.pressedMouseButtons & 1 != 0
        // у нижнего края может выезжать Dock — там тоже следим часто
        let m = NSEvent.mouseLocation
        let nearDock = overlays.contains { $0.active && $0.screen.frame.contains(m) && m.y < $0.screen.frame.minY + 170 }
        if dragging || nearDock || pollTick % 5 == 0 { pollWindows() }
    }

    private func pollWindows() {
        if paused || overlays.isEmpty { return }
        let (wins, dock, own) = currentWindows()
        for o in overlays where o.active { o.updateWindows(wins, dockOnscreen: dock, own: own) }
    }

    private func applyConfig() {
        let cfg = settings.simConfig()
        for o in overlays { o.sim.cfg = cfg; o.rules = settings.rules }
    }

    // MARK: - Меню

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func item(_ title: String, _ sel: Selector?, tag: Int = 0, on: Bool = false, key: String = "") -> NSMenuItem {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            i.target = self
            i.tag = tag
            i.state = on ? .on : .off
            return i
        }
        func sub(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu()
            items.forEach { m.addItem($0) }
            i.submenu = m
            return i
        }
        menu.addItem(item(paused ? "Вернуть зиму" : "Поставить снег на паузу", #selector(togglePause)))
        menu.addItem(.separator())
        menu.addItem(sub("Погода", [
            item("Лёгкий снег", #selector(setWeather(_:)), tag: 0, on: settings.weather == 0),
            item("Снегопад", #selector(setWeather(_:)), tag: 1, on: settings.weather == 1),
            item("Метель", #selector(setWeather(_:)), tag: 2, on: settings.weather == 2),
        ]))
        menu.addItem(sub("Ветер", [
            item("⇐ Сильный влево", #selector(setWind(_:)), tag: -2, on: settings.wind == -2),
            item("← Влево", #selector(setWind(_:)), tag: -1, on: settings.wind == -1),
            item("Штиль", #selector(setWind(_:)), tag: 0, on: settings.wind == 0),
            item("→ Вправо", #selector(setWind(_:)), tag: 1, on: settings.wind == 1),
            item("⇒ Сильный вправо", #selector(setWind(_:)), tag: 2, on: settings.wind == 2),
        ]))
        menu.addItem(sub("Сугробы", [
            item("Низкие", #selector(setDepth(_:)), tag: 0, on: settings.depth == 0),
            item("Средние", #selector(setDepth(_:)), tag: 1, on: settings.depth == 1),
            item("Высокие", #selector(setDepth(_:)), tag: 2, on: settings.depth == 2),
        ]))
        menu.addItem(sub("Размер вокселя", [
            item("Мелкий", #selector(setVoxel(_:)), tag: 2, on: settings.voxel == 2),
            item("Средний", #selector(setVoxel(_:)), tag: 3, on: settings.voxel == 3),
            item("Крупный", #selector(setVoxel(_:)), tag: 4, on: settings.voxel == 4),
            item("Очень крупный", #selector(setVoxel(_:)), tag: 6, on: settings.voxel == 6),
        ]))
        menu.addItem(.separator())
        menu.addItem(item("Сугробы растут сами", #selector(toggleAutoFill), on: settings.autoFill))
        func rule(_ title: String, _ key: String, _ def: Bool = true) -> NSMenuItem {
            let i = item(title, #selector(toggleRule(_:)), on: settings.flag(key, def))
            i.representedObject = key
            return i
        }
        menu.addItem(sub("Где лежит снег", [
            rule("На окнах", "onWindows"),
            rule("На окнах вплотную к строке меню", "onMenuWindows"),
            rule("На узких окнах", "onNarrow"),
            rule("На виджетах рабочего стола", "onWidgets"),
            rule("Внизу экрана", "onFloor"),
            rule("На Dock", "onDock"),
            .separator(),
            rule("Не ложиться поверх других окон", "openOnly", false),
        ]))
        menu.addItem(sub("Скругление углов окон", [
            item("Нет (прямой край)", #selector(setRadius(_:)), tag: 0, on: settings.cornerRadius == 0),
            item("Малое", #selector(setRadius(_:)), tag: 10, on: settings.cornerRadius == 10),
            item("Среднее", #selector(setRadius(_:)), tag: 18, on: settings.cornerRadius == 18),
            item("Большое", #selector(setRadius(_:)), tag: 26, on: settings.cornerRadius == 26),
        ]))
        menu.addItem(rule("Курсор смахивает снег", "sweep"))
        menu.addItem(rule("Снег слёживается и подмерзает", "aging"))
        menu.addItem(item("Насыпать снег сейчас", #selector(fillNow)))
        menu.addItem(item("Убрать весь снег (лопата)", #selector(shovel)))
        menu.addItem(.separator())
        for hint in ["Ведите курсором по снегу — он смахивается",
                     "⌃⌥ + зажать мышь — слепить и катать снежок",
                     "Отпустить на ходу — бросить",
                     "Опустить шар на шар — снеговик",
                     "Наст (голубой) колется резким взмахом или снежком"] {
            let h = NSMenuItem(title: hint, action: nil, keyEquivalent: "")
            h.isEnabled = false
            menu.addItem(h)
        }
        menu.addItem(.separator())
        menu.addItem(item("Запускать при входе", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        menu.addItem(updater.menuItem())
        menu.addItem(item("Выйти из Сугроба", #selector(quit), key: "q"))
    }

    @objc private func togglePause() {
        paused.toggle()
        for o in overlays { o.setHidden(paused) }
        if !paused { pollWindows() }
    }

    @objc private func setWeather(_ s: NSMenuItem) { settings.weather = s.tag; applyConfig() }
    @objc private func setWind(_ s: NSMenuItem) { settings.wind = s.tag; applyConfig() }
    @objc private func setDepth(_ s: NSMenuItem) { settings.depth = s.tag; applyConfig() }

    @objc private func setVoxel(_ s: NSMenuItem) {
        guard settings.voxel != s.tag else { return }
        settings.voxel = s.tag
        let cfg = settings.simConfig()
        for o in overlays { o.rebuild(cell: Float(settings.voxel), cfg: cfg); o.rules = settings.rules }
        pollWindows()
    }

    @objc private func toggleAutoFill() { settings.autoFill.toggle(); applyConfig() }
    @objc private func toggleRule(_ s: NSMenuItem) {
        guard let key = s.representedObject as? String else { return }
        settings.toggle(key, key != "openOnly")
        if key == "onFloor" && !settings.flag(key) {        // выключили низ экрана — снег оттуда убираем
            for o in overlays { _ = o.sim.extractFloor(x0: 0, x1: o.sim.wPt) }
        }
        if key == "aging" && !settings.flag(key) {          // выключили — весь снег снова рыхлый
            for o in overlays { o.sim.resetHardness() }
        }
        applyConfig()
        pollWindows()
    }

    @objc private func setRadius(_ s: NSMenuItem) {
        settings.cornerRadius = s.tag
        applyConfig()
        pollWindows()
    }

    @objc private func fillNow() {
        for o in overlays { o.sim.forceFill = true; o.sim.fillSurfaces(); o.sim.forceFill = false }
    }

    @objc private func shovel() { for o in overlays { o.sim.clearAll() } }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let a = NSAlert()
            a.messageText = "Не получилось изменить автозапуск"
            a.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
