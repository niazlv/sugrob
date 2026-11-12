import AppKit
import MetalKit

/// Где снегу разрешено лежать — переключается галочками в меню.
struct SnowRules {
    var windows = true        // на окнах
    var menuWindows = true    // на окнах вплотную к строке меню (тонкая шапка заходит на меню)
    var narrow = true         // на узких окнах (от 60 pt, иначе от 120)
    var widgets = true        // на виджетах рабочего стола
    var dock = true           // на Dock
    var radius: CGFloat = 18  // радиус скругления углов окон: опора под снегом идёт по дуге угла
    var offVideo = true       // поверх окон, где идёт видео, снег не рисуется
    var icons = false         // на значках рабочего стола (нужен «Универсальный доступ», см. DesktopIcons)
}

struct WinInfo {
    var id: Int
    var widget = false
    var video = false     // окно приложения, которое сейчас показывает видео (см. VideoWatch)
    var icon = false      // не окно, а значок рабочего стола: рамка — от его «крыши» до низа
    var iconSize: CGFloat = 0
    /// У виджета системное окно шире видимой плитки на прозрачную кайму; снег должен лежать на плитке.
    var inset: CGFloat { widget ? 8 : 0 }
    var left: CGFloat { rect.minX + inset }
    var right: CGFloat { rect.maxX - inset }
    var top: CGFloat { rect.minY + inset }
    var rect: CGRect      // глобальные координаты CG (начало — левый верх главного экрана)
}

/// Что сейчас на экране, кроме самого снега.
struct WindowSnapshot {
    var wins: [WinInfo] = []            // обычные окна и виджеты, от переднего к заднему
    var dock = false                    // полоса Dock на экране (в том числе выехала из автоскрытия)
    var own: [Int: CGRect] = [:]        // где сейчас наши собственные слои снега
    var floating: [CGRect] = []         // видео поверх всех окон («картинка в картинке»)
    var widgets = 0                     // сколько виджетов нашлось (для журнала)
    var videoApps: Set<String> = []     // кто показывает видео (для журнала)
}

/// Чьё окно. Имя владельца (kCGWindowOwnerName) для этого не годится: система отдаёт его в переводе —
/// «Центр уведомлений», «Mitteilungszentrale», «程序坞», — поэтому процесс узнаём по bundle id.
private var bundleCache: [Int: String] = [:]
private var bundleCacheAt: CFTimeInterval = 0
func bundleID(ofPID pid: Int) -> String {
    let now = CACurrentMediaTime()
    if now - bundleCacheAt > 30 {           // номера процессов со временем переиспользуются
        bundleCache.removeAll(keepingCapacity: true)
        bundleCacheAt = now
    }
    if let b = bundleCache[pid] { return b }
    let b = NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier ?? ""
    bundleCache[pid] = b
    return b
}

/// Системные процессы, чьи окна ниже обычных — не виджеты: значки стола, обои, сам Dock.
private let notWidgets: Set<String> = ["com.apple.finder", "com.apple.dock", "com.apple.wallpaper.agent",
                                       "com.apple.controlcenter", "com.apple.Spotlight", "com.apple.systemuiserver",
                                       "com.apple.WindowManager"]

/// Виджет рабочего стола: окно ниже обычных, которое держит «Центр уведомлений». Если в новой системе
/// виджеты переедут к другому системному процессу, они всё равно найдутся: подойдёт любое небольшое
/// окно процесса Apple на этом уровне.
func isWidgetWindow(layer: Int, bundle: String, size: CGSize) -> Bool {
    guard layer < 0 else { return false }
    if bundle == "com.apple.notificationcenterui" { return true }
    return bundle.hasPrefix("com.apple.") && !notWidgets.contains(bundle) && size.width <= 1000 && size.height <= 1000
}

/// Окна текущего рабочего стола, от переднего к заднему. Имена окон не читаются —
/// только рамки, поэтому разрешение «Запись экрана» не нужно.
func currentWindows(video: Bool = true) -> WindowSnapshot {
    var snap = WindowSnapshot()
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return snap }
    let me = Int(ProcessInfo.processInfo.processIdentifier)
    let playing = video ? VideoWatch.pids() : []
    for w in list {
        guard let layer = w[kCGWindowLayer as String] as? Int,
              let bd = w[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bd as CFDictionary) else { continue }
        let pid = w[kCGWindowOwnerPID as String] as? Int ?? 0
        if pid == me {
            if let n = w[kCGWindowNumber as String] as? Int { snap.own[n] = rect }
            continue
        }
        if let a = w[kCGWindowAlpha as String] as? Double, a < 0.05 { continue }
        let bundle = layer == 0 && !playing.contains(pid) ? "" : bundleID(ofPID: pid)
        if layer == 20 && bundle == "com.apple.dock" { snap.dock = true }
        if rect.width < 40 || rect.height < 40 { continue }
        if layer > 0 {
            // «картинка в картинке» и подобные окна с видео поверх остальных
            if video, layer < 1000, rect.width >= 120, rect.height >= 68,
               bundle == "com.apple.PIPAgent" || playing.contains(pid) { snap.floating.append(rect) }
            continue
        }
        // обычные окна и виджеты рабочего стола
        let widget = isWidgetWindow(layer: layer, bundle: bundle, size: rect.size)
        guard layer == 0 || widget else { continue }
        let isVideo = !widget && playing.contains(pid)
        if widget { snap.widgets += 1 }
        if isVideo { snap.videoApps.insert(bundle.isEmpty ? "pid \(pid)" : bundle) }
        snap.wins.append(WinInfo(id: (w[kCGWindowNumber as String] as? Int) ?? 0, widget: widget, video: isVideo, rect: rect))
    }
    return snap
}

/// Кому принадлежат окна не из обычного слоя — одной строкой, для журнала. Имена и содержимое окон
/// не читаются: только процесс, уровень и число окон.
func windowCensus() -> String {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return "?" }
    var count: [String: Int] = [:]
    for w in list {
        guard let layer = w[kCGWindowLayer as String] as? Int, layer != 0 else { continue }
        let pid = w[kCGWindowOwnerPID as String] as? Int ?? 0
        let b = bundleID(ofPID: pid)
        count["\(b.isEmpty ? "-" : b)@\(layer)", default: 0] += 1
    }
    return count.sorted { $0.key < $1.key }.map { "\($0.key)x\($0.value)" }.joined(separator: " ")
}

/// Номера всех существующих окон, включая окна на других рабочих столах, свёрнутые и скрытые.
func allWindowIDs() -> Set<Int> {
    guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
    var out = Set<Int>()
    for w in list { if let n = w[kCGWindowNumber as String] as? Int { out.insert(n) } }
    return out
}

/// Номер текущего рабочего стола на дисплее. Публичного API для этого нет, поэтому функция берётся
/// из системной библиотеки по имени; если её не окажется, вернётся 0 и снег будет общим для всех столов.
private let spaceLookup: (conn: Int32, fn: (@convention(c) (Int32, CFString) -> UInt64)?) = {
    guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
          let c = dlsym(h, "SLSMainConnectionID"), let f = dlsym(h, "SLSManagedDisplayGetCurrentSpace") else {
        return (0, nil)
    }
    let conn = unsafeBitCast(c, to: (@convention(c) () -> Int32).self)()
    return (conn, unsafeBitCast(f, to: (@convention(c) (Int32, CFString) -> UInt64).self))
}()

/// Точная рамка Dock от системы (в координатах CG). nil — функция недоступна; пустая рамка — Dock скрыт.
private let dockRectLookup: (conn: Int32, fn: (@convention(c) (Int32, UnsafeMutablePointer<CGRect>, UnsafeMutablePointer<Int32>) -> Int32)?) = {
    guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
          let c = dlsym(h, "SLSMainConnectionID"), let f = dlsym(h, "SLSGetDockRectWithReason") else { return (0, nil) }
    let conn = unsafeBitCast(c, to: (@convention(c) () -> Int32).self)()
    return (conn, unsafeBitCast(f, to: (@convention(c) (Int32, UnsafeMutablePointer<CGRect>, UnsafeMutablePointer<Int32>) -> Int32).self))
}()

func systemDockRect() -> CGRect? {
    guard let fn = dockRectLookup.fn else { return nil }
    var r = CGRect.zero
    var reason: Int32 = 0
    return fn(dockRectLookup.conn, &r, &reason) == 0 ? r : nil
}

func currentSpace(of screen: NSScreen) -> UInt64 {
    guard let fn = spaceLookup.fn,
          let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
          let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
          let str = CFUUIDCreateString(nil, uuid) else { return 0 }
    return fn(spaceLookup.conn, str)
}

/// Текущий рабочий стол дисплея и его вид: обычный стол или полноэкранное приложение.
private let spaceListLookup: (conn: Int32, fn: (@convention(c) (Int32) -> Unmanaged<CFArray>?)?) = {
    guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
          let c = dlsym(h, "SLSMainConnectionID"), let f = dlsym(h, "SLSCopyManagedDisplaySpaces") else { return (0, nil) }
    let conn = unsafeBitCast(c, to: (@convention(c) () -> Int32).self)()
    return (conn, unsafeBitCast(f, to: (@convention(c) (Int32) -> Unmanaged<CFArray>?).self))
}()

func spaceInfo(of screen: NSScreen) -> (id: UInt64, fullscreen: Bool) {
    let id = currentSpace(of: screen)
    guard id != 0, let fn = spaceListLookup.fn,
          let displays = fn(spaceListLookup.conn)?.takeRetainedValue() as? [[String: Any]] else { return (id, false) }
    for d in displays {
        guard let cur = d["Current Space"] as? [String: Any],
              (cur["id64"] as? NSNumber)?.uint64Value == id else { continue }
        return (id, (cur["type"] as? NSNumber)?.intValue == 4)        // 4 — полноэкранное приложение
    }
    return (id, false)
}

/// Номера всех рабочих столов, какие сейчас есть (обычных и полноэкранных). nil — узнать нельзя.
func allSpaces() -> Set<UInt64>? {
    guard let fn = spaceListLookup.fn,
          let displays = fn(spaceListLookup.conn)?.takeRetainedValue() as? [[String: Any]] else { return nil }
    var out = Set<UInt64>()
    for d in displays {
        for s in d["Spaces"] as? [[String: Any]] ?? [] {
            if let id = (s["id64"] as? NSNumber)?.uint64Value { out.insert(id) }
        }
    }
    return out.isEmpty ? nil : out
}

final class SnowView: MTKView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
}

/// Прозрачное окно во весь экран со своей симуляцией снега — по одному на каждый рабочий стол,
/// обычный или полноэкранный. Окно принадлежит своему столу, поэтому при перелистывании столов
/// система везёт его вместе с окнами этого стола, и снег не отрывается от них и не пропадает.
final class Overlay: NSObject, MTKViewDelegate {
    let screen: NSScreen
    let panel: NSPanel
    let view: SnowView
    private(set) var sim: Sim
    private let renderer: Renderer
    private let queue: MTLCommandQueue

    private var last = CACurrentMediaTime()
    private var wasPressed = false
    private var holding = false
    private var hands = false
    private var prevWins: [Int: CGRect] = [:]
    private var stashes: [Int: PileStash] = [:]
    var rules = SnowRules()

    /// Рабочий стол, которому принадлежит это окно. Общие слои (isShared) видны на всех столах сразу:
    /// 0 — номер стола узнать нельзя; Overlay.fullscreenKey — один слой на все полноэкранные приложения
    /// (запасной вариант, если система не пустила слой в сам полноэкранный стол).
    let spaceId: UInt64
    static let fullscreenKey = UInt64.max
    var isShared: Bool { spaceId == 0 || spaceId == Overlay.fullscreenKey }
    /// Слой полноэкранного приложения (свой у стола или общий).
    let fullscreen: Bool
    let createdAt = CACurrentMediaTime()
    /// Слой прижился на своём столе (проверяется вскоре после создания).
    var settled = false
    var misses = 0
    /// Стол этого слоя пропал из списка системы (приложение вышло из полноэкранного режима, стол закрыли):
    /// слой сразу прячется, а если стол не вернулся — закрывается.
    private(set) var orphanedAt: CFTimeInterval?
    private var pausedByUser = false
    /// На новом столе снег «уже лежит», а не начинается с нуля.
    var freshFill = false
    private(set) var active = true              // этот стол сейчас на экране
    private(set) var leftAt = CACurrentMediaTime()
    private var dockShown = false
    private var maxOffset: CGFloat = 0          // насколько слой уезжал вместе со столом (для журнала)
    private var lastPoll = CACurrentMediaTime()
    /// Где сейчас идёт видео (в пунктах слоя): там снег не рисуется, будто идёт позади окна.
    private var hideRects: [CGRect] = []
    private var hideShown: [CGRect] = []        // что закрыто на экране: при исчезновении видео снег проявляется плавно
    private var hideK: Float = 0
    private var hideSnap = true                 // слой только что появился или вернулся: видео закрыто сразу, без проявления

    init?(screen: NSScreen, device: MTLDevice, cell: Float, cfg: SimConfig, spaceId: UInt64, fullscreen: Bool = false) {
        guard let renderer = Renderer(device: device, pixelFormat: .bgra8Unorm),
              let queue = device.makeCommandQueue() else { return nil }
        self.screen = screen
        self.spaceId = spaceId
        self.fullscreen = fullscreen || spaceId == Overlay.fullscreenKey
        self.renderer = renderer
        self.queue = queue
        let f = screen.frame
        sim = Sim(widthPt: Float(f.width), heightPt: Float(f.height), cell: cell)
        sim.cfg = cfg
        sim.prefill()

        panel = NSPanel(contentRect: f, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.setFrame(f, display: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        // Слой принадлежит только своему столу и едет вместе с ним при перелистывании. В стол чужого
        // полноэкранного приложения система пускает только «вспомогательные» окна (fullScreenAuxiliary):
        // окно, показанное, пока такой стол на экране, остаётся в нём. Общий слой виден на всех столах.
        let shared = spaceId == 0 || spaceId == Overlay.fullscreenKey
        panel.collectionBehavior = shared ? [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
                                          : (self.fullscreen ? [.fullScreenAuxiliary, .stationary, .ignoresCycle]
                                                             : [.stationary, .ignoresCycle])

        view = SnowView(frame: NSRect(origin: .zero, size: f.size), device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.autoresizingMask = [.width, .height]
        // Рисуем точка в точку, без удвоения под Retina: воксели всё равно крупнее пикселя,
        // а памяти и работы видеокарты нужно вчетверо меньше (окон теперь по одному на стол).
        view.autoResizeDrawable = false
        view.drawableSize = f.size
        super.init()
        view.delegate = self
        panel.contentView = view
        view.layer?.isOpaque = false
        if let ml = view.layer as? CAMetalLayer {
            ml.isOpaque = false
            ml.magnificationFilter = .nearest
            ml.maximumDrawableCount = 2
        }
    }

    func show() {
        last = CACurrentMediaTime()
        view.isPaused = false
        panel.orderFrontRegardless()
    }

    /// Пауза из меню: окно остаётся на своём столе, просто становится невидимым.
    func setHidden(_ hidden: Bool) {
        pausedByUser = hidden
        panel.alphaValue = hidden || (isShared && !active) || orphanedAt != nil ? 0 : 1
        view.isPaused = hidden || !active
        if !view.isPaused { last = CACurrentMediaTime() }
    }

    /// Стол слоя есть в списке системы или пропал. Слой пропавшего стола система переносит на соседний —
    /// там он лёг бы застывшим кадром поверх чужого снега, поэтому сразу становится невидимым.
    func setOrphaned(_ gone: Bool, now: CFTimeInterval) {
        if gone == (orphanedAt != nil) { return }
        orphanedAt = gone ? now : nil
        panel.alphaValue = gone || pausedByUser || (isShared && !active) ? 0 : 1
    }

    /// Стол ушёл с экрана: симуляция замирает, последний кадр остаётся (он виден, пока стол уезжает).
    func suspend() {
        guard active else { return }
        active = false
        leftAt = CACurrentMediaTime()
        if holding { sim.grabEnd(); holding = false; hands = false; panel.ignoresMouseEvents = true }
        if dockShown { sim.dropDock(); dockShown = false }
        view.isPaused = true
        if isShared { panel.alphaValue = 0 }        // общий слой иначе лёг бы поверх чужого стола
    }

    /// Стол вернулся: досыпаем снег за время отсутствия и продолжаем.
    func resume(hidden: Bool) {
        guard !active else { return }
        active = true
        hideSnap = true
        sim.catchUp(Float(CACurrentMediaTime() - leftAt))
        last = CACurrentMediaTime()
        view.isPaused = hidden
        pausedByUser = hidden
        if isShared { panel.alphaValue = hidden ? 0 : 1 }
    }

    func close() {
        view.isPaused = true
        view.delegate = nil
        panel.orderOut(nil)
        panel.close()
    }

    func rebuild(cell: Float, cfg: SimConfig) {
        let f = screen.frame
        sim = Sim(widthPt: Float(f.width), heightPt: Float(f.height), cell: cell)
        sim.cfg = cfg
        sim.prefill()
        prevWins = [:]
        stashes = [:]
        dockShown = false
        hideRects = []; hideShown = []; hideK = 0
    }

    /// Рамка экрана в координатах CG (ось Y вниз от верха главного экрана).
    private var cgFrame: CGRect {
        let primaryH = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let f = screen.frame
        return CGRect(x: f.minX, y: primaryH - f.maxY, width: f.width, height: f.height)
    }

    // MARK: - Опоры: верхние края окон и Dock

    func updateWindows(_ wins: [WinInfo], dockOnscreen: Bool = false, own: [Int: CGRect] = [:], floating: [CGRect] = []) {
        let now = CACurrentMediaTime()
        let dt = Float(max(0.01, now - lastPoll))
        lastPoll = now
        // Положение окон считаем от самого слоя снега, а не от экрана. При перелистывании столов
        // система сдвигает координаты и окон, и нашего слоя (он принадлежит тому же столу) —
        // относительно слоя окна остаются на месте, и сугробы не нужно двигать второй раз.
        let sf = own[panel.windowNumber] ?? cgFrame
        let off = sf.minX - cgFrame.minX
        if abs(off) > 1 {
            if abs(off) > abs(maxOffset) { maxOffset = off }
        } else if maxOffset != 0 {
            EventLog.add("layer \(spaceId): rode the desktop during a switch, up to \(Int(maxOffset)) pt off-screen")
            maxOffset = 0
        }

        // Значки — исключение: их рамки называет Finder, а для него значки при перелистывании стоят
        // на месте. Приводим их к тем же «едущим» координатам, что у окон и у слоя, — иначе, пока стол
        // листают, снег съезжал бы со значков в сторону.
        let ride = CGPoint(x: sf.minX - cgFrame.minX, y: sf.minY - cgFrame.minY)
        let wins = ride == .zero ? wins : wins.map { w -> WinInfo in
            guard w.icon else { return w }
            var moved = w
            moved.rect = w.rect.offsetBy(dx: ride.x, dy: ride.y)
            return moved
        }

        var cur: [Int: CGRect] = [:]        // рамки окон относительно слоя
        for w in wins {
            let rel = w.rect.offsetBy(dx: -sf.minX, dy: -sf.minY)
            cur[w.id] = rel
            if let old = prevWins[w.id], old.origin != rel.origin {
                let dx = Float(rel.minX - old.minX), dy = Float(rel.minY - old.minY)
                // сдвиг в целых ячейках — так же, как округляется положение карниза
                func cellOf(_ v: CGFloat) -> Int { Int((Float(v) / sim.cell).rounded()) }
                let cols = cellOf(w.left - sf.minX) - cellOf(old.minX + w.inset)
                let rows = cellOf(w.top - sf.minY) - cellOf(old.minY + w.inset)
                for s in sim.segs where s.win == w.id {
                    sim.shiftPile(s, cols: cols, rows: rows, vx: dx / dt, vy: dy / dt)
                }
            }
        }
        prevWins = cur

        // Окно пропало с экрана, но существует (другой рабочий стол, свёрнуто, скрыто) —
        // его сугроб не осыпается, а уходит вместе с ним и вернётся, когда окно появится снова.
        let gone = Set(sim.segs.lazy.filter { $0.win >= 0 && cur[$0.win] == nil }.map { $0.win })
        if !gone.isEmpty {
            let alive = allWindowIDs()
            for id in gone where alive.contains(id) { stashes[id] = sim.extractPile(win: id) }
            stashes = stashes.filter { alive.contains($0.key) }
        }

        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let open = sim.cfg.openOnly
        sim.topLimit = Float(menuBar) + 1
        sim.minRoom = rules.menuWindows ? 9 : 0     // окно вплотную к меню получает тонкую шапку, чуть заходящую на меню
        var out: [Ledge] = []
        for (i, w) in wins.enumerated() {
            let y = w.top
            let rad = w.icon ? 0 : (w.widget ? min(rules.radius, 1) * 22 : rules.radius)
            let edge = w.icon ? 1 : max(3, rad * 0.3)       // у самого края дуга слишком крутая — снег там не держится
            // значки есть только на обычном столе: в полноэкранном приложении их не видно
            guard w.icon ? rules.icons && !fullscreen : (w.widget ? rules.widgets : rules.windows) else { continue }
            guard w.icon || (w.rect.width >= (rules.narrow ? 60 : 120) && w.rect.height >= 40) else { continue }
            guard y > sf.minY + menuBar + (rules.menuWindows ? -1 : 12), y > sf.minY + 6, y < sf.maxY - 12 else { continue }
            // Полноэкранное приложение упирается в верх экрана (на экране с вырезом — в чёрную полосу под ним):
            // «тонкая шапка у строки меню» там превратилась бы в полоску снега в одну ячейку по самому верху.
            if fullscreen && y <= sf.minY + max(menuBar, screen.safeAreaInsets.top) + 2 { continue }
            var ivs: [(CGFloat, CGFloat)] = [(max(w.left + edge, sf.minX), min(w.right - edge, sf.maxX))]
            // вычесть то, что закрыто окнами спереди (и то, над чем нет свободного места)
            for j in 0..<i {
                let f = wins[j].rect
                guard f.minY <= y + 3, f.maxY > y - (open ? 14 : 3) else { continue }
                let a = f.minX - 3, b = f.maxX + 3
                var next: [(CGFloat, CGFloat)] = []
                for iv in ivs {
                    if b <= iv.0 || a >= iv.1 { next.append(iv); continue }
                    if a > iv.0 { next.append((iv.0, a)) }
                    if b < iv.1 { next.append((b, iv.1)) }
                }
                ivs = next
                if ivs.isEmpty { break }
            }
            for iv in ivs where iv.1 - iv.0 >= (w.icon ? 12 : 18) {
                // на значке шапка маленькая, под стать ему: около шестой части его размера
                out.append(Ledge(y: Float(y - sf.minY), x0: Float(iv.0 - sf.minX), x1: Float(iv.1 - sf.minX),
                                 kind: w.icon ? 3 : 1, win: w.id, ox: Float(w.left - sf.minX), wr: Float(w.right - sf.minX),
                                 r: Float(rad), cap: w.icon ? Float(min(12, max(5, w.iconSize * 0.16))) : 0))
            }
        }
        let dl = rules.dock ? dockLedge(onscreen: dockOnscreen) : nil
        if let dl, !dockShown {
            sim.liftFloor(x0: dl.x0, x1: dl.x1, toY: dl.y)      // Dock выезжает и поднимает снег на себе
        } else if dl == nil, dockShown {
            sim.dropDock()                                       // прячется — снег опускается обратно
        } else if let dl, let old = sim.segs.first(where: { $0.win == -1 }) {
            let rows = Int((dl.y / sim.cell).rounded()) - Int((old.y / sim.cell).rounded())
            if rows != 0 { sim.shiftPile(old, cols: 0, rows: rows, vx: 0, vy: 0) }
        }
        if let dl { out.append(dl) }
        let boxes = wins.filter { !$0.icon }.map {
            WinBox(x0: Float($0.rect.minX - sf.minX), x1: Float($0.rect.maxX - sf.minX),
                   y0: Float($0.rect.minY - sf.minY), y1: Float($0.rect.maxY - sf.minY), win: $0.id)
        }
        sim.setLedges(out, windows: boxes)
        dockShown = dl != nil
        if !stashes.isEmpty {
            for id in Set(out.map { $0.win }) {
                guard let st = stashes[id], let r = cur[id] else { continue }
                let inset = wins.first(where: { $0.id == id })?.inset ?? 0
                sim.insertPile(st, ox: Float(r.minX + inset), y: Float(r.minY + inset))
                stashes[id] = nil
            }
        }
        if freshFill {
            sim.fillSurfaces()
            freshFill = false
        }
        hideRects = rules.offVideo
            ? videoZones(wins, floating: floating, capped: Set(out.map { $0.win }),
                         dock: dl.map { CGRect(x: sf.minX + CGFloat($0.ox), y: sf.minY + CGFloat($0.y), width: CGFloat($0.wr - $0.ox), height: sf.height) },
                         frame: sf, dip: rules.radius * 0.3 + CGFloat(sim.cell) + 1)
            : []
        if hideSnap {
            hideSnap = false
            hideShown = hideRects
            hideK = hideRects.isEmpty ? 0 : 1
        }
    }

    /// Dock внизу экрана.
    /// - Видим ли он: если не скрывается — всегда; автоскрытый — пока на экране его окно (dockOnscreen).
    /// - Ширина: точная, от системы (она известна и для скрытого Dock).
    /// - Высота: у нескрываемого — из рамки системы; у автоскрытого система её не сообщает,
    ///   поэтому считается по размеру плитки. Когда значков много, Dock занимает всю ширину
    ///   и плитки ужимаются — это учитывается через число значков.
    private func dockLedge(onscreen: Bool) -> Ledge? {
        let f = screen.frame, v = screen.visibleFrame
        let sf = cgFrame
        guard let d = UserDefaults(suiteName: "com.apple.dock") else { return nil }
        if let o = d.string(forKey: "orientation"), o != "bottom" { return nil }
        let apps = (d.array(forKey: "persistent-apps") ?? [])
        let others = (d.array(forKey: "persistent-others") ?? []).count
        var pinned = Set<String>()
        for a in apps {
            if let dict = a as? [String: Any], let td = dict["tile-data"] as? [String: Any],
               let b = td["bundle-identifier"] as? String { pinned.insert(b) }
        }
        var extra = 0
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let b = app.bundleIdentifier, b != "com.apple.finder", !pinned.contains(b) { extra += 1 }
        }
        let tiles = CGFloat(apps.count + others + extra + 2)
        var tile = CGFloat(d.object(forKey: "tilesize") as? Double ?? 48)

        // горизонтальные границы
        var x0: CGFloat, x1: CGFloat
        let sys = systemDockRect()
        if let r = sys, r.width > 40, r.maxX > sf.minX, r.minX < sf.maxX, r.minY > sf.minY, r.minY <= sf.maxY + 1 {
            x0 = r.minX - sf.minX
            x1 = r.maxX - sf.minX
            tile = min(tile, (r.width - 40) / max(1, tiles) - 4.5)      // плитки ужаты, если Dock во всю ширину
        } else if sys != nil && sys!.width > 40 {
            return nil                                                  // Dock на другом экране
        } else {
            let width = min(f.width - 16, tiles * (tile + 4.5) + 40)
            x0 = f.width / 2 - width / 2
            x1 = x0 + width
        }

        // верхний край
        let inset = v.minY - f.minY
        var top: CGFloat
        if let r = sys, r.height > 8 {
            top = r.minY - sf.minY + 2
        } else if inset > 20 {
            top = f.height - inset + 3
        } else {
            // автоскрытый Dock выезжает на том экране, где курсор упёрся в нижний край
            guard onscreen, dockShown || f.contains(NSEvent.mouseLocation) else { return nil }
            top = f.height - (tile + 23.5)
        }
        let rad = Float(min(24, (f.height - top) * 0.28))
        let edge = CGFloat(max(3, rad * 0.3))
        return Ledge(y: Float(top), x0: Float(x0 + edge), x1: Float(x1 - edge), kind: 2, win: -1,
                     ox: Float(x0), wr: Float(x1), r: rad)
    }

    // MARK: - Кадр

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(min(max(now - last, 0.001), 1.0 / 20))
        last = now

        // Курсор и кнопки читаются опросом: окно прозрачно для кликов.
        let f = screen.frame
        let m = NSEvent.mouseLocation
        let inside = f.contains(m)
        let mx = Float(m.x - f.minX) + 3
        let my = Float(f.maxY - m.y) + 5
        sim.setCursor(x: mx, y: my, dt: dt, on: inside)

        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = flags.contains(.control) && flags.contains(.option)
            && !flags.contains(.command) && !flags.contains(.shift)
        let pressed = NSEvent.pressedMouseButtons & 1 != 0
        let wantHands = (key && inside) || holding
        if wantHands != hands {
            hands = wantHands
            panel.ignoresMouseEvents = !hands
        }
        sim.handsMode = hands
        if hands && pressed && !wasPressed && !holding && inside {
            sim.grabBegin()
            holding = sim.heldId != -1
        }
        if holding && !pressed {
            sim.grabEnd()
            holding = false
        }
        wasPressed = pressed

        sim.step(dt)

        // видео началось — снег поверх него гаснет за треть секунды, кончилось — так же проявляется
        if !hideRects.isEmpty {
            hideShown = hideRects
            hideK = min(1, hideK + dt / 0.3)
        } else if hideK > 0 {
            hideK = max(0, hideK - dt / 0.3)
            if hideK == 0 { hideShown = [] }
        }

        guard let rpd = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cmd = queue.makeCommandBuffer() else { return }
        // лёгкое затемнение в режиме варежки: видно, что режим включён, и окно ловит клики
        let dim = hands ? 0.05 : 0.0
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: dim)
        renderer.encode(sim: sim, cmd: cmd, rpd: rpd, scale: 1, hide: hideShown, hideK: hideK)
        cmd.present(drawable)
        cmd.commit()
    }
}
