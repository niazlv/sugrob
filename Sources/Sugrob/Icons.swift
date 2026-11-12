import AppKit
import ApplicationServices
import UniformTypeIdentifiers

/// Значки рабочего стола: папки, программы и файлы, на которые тоже может лечь снег.
///
/// Все значки рисует одно окно Finder во весь экран, поэтому по списку окон их не найти. Где они,
/// знает только сам Finder и сообщает это через «Универсальный доступ» — разрешение, без которого
/// остальное приложение обходится. Поэтому снег на значках выключен, пока его не включат в меню,
/// а без разрешения просто ничего не делает.
///
/// У Finder берутся только рамка значка и его тип: папка это, программа, диск или файл с таким-то
/// расширением. Имена не запоминаются и не пишутся в журнал, сами файлы не открываются.
/// Форма значка — где у него «крыша», на которую ложится снег, — снимается с системной иконки
/// этого типа. У картинок, видео и PDF Finder рисует вместо иконки миниатюру со своими пропорциями;
/// их сообщает Spotlight (размер кадра — метаданные, не содержимое). За это macOS один раз спросит
/// доступ к папке «Рабочий стол»; отказали — снег ляжет на всё, кроме миниатюр: лучше никак,
/// чем в воздухе над картинкой.
final class DesktopIcons {
    static let shared = DesktopIcons()

    struct Icon {
        var id: Int
        var rect: CGRect        // от «крыши» значка до его низа, глобальные координаты CG (как у окон)
        var size: CGFloat       // размер самого значка, от него зависит высота шапки
    }

    /// Снег на значках включён в меню.
    var enabled = false { didSet { if !enabled { icons = []; kept = [:]; lastRead = -100; logged = "" } } }
    /// Что нашлось при последнем чтении. Меняется только в главном потоке.
    private(set) var icons: [Icon] = []
    /// Разрешение «Универсальный доступ» выдано (по последней проверке).
    private(set) var trusted = AXIsProcessTrusted()

    private let queue = DispatchQueue(label: "sugrob.desktop-icons", qos: .utility)
    private var busy = false
    private var lastRead: CFTimeInterval = -100
    private var logged = ""
    private var roofs: [String: Roof?] = [:]        // «крыша» иконки каждого типа, в долях её размера
    private var kept: [Int: (icon: Icon, missed: Int)] = [:]

    /// Системный запрос «разрешить управление компьютером»; сам переключатель включает человек.
    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Зовётся при каждом опросе окон. Сам Finder опрашивается не чаще раза в секунду и в фоне:
    /// если он занят и молчит, снег от этого не замирает.
    func refresh(now: CFTimeInterval) {
        guard enabled, !busy, now - lastRead >= 1 else { return }
        lastRead = now
        busy = true
        queue.async {
            let (items, ok) = DesktopIcons.hiddenBySystem() ? ([], AXIsProcessTrusted()) : DesktopIcons.read()
            DispatchQueue.main.async {
                self.busy = false
                self.trusted = ok
                self.icons = self.enabled ? self.steady(self.place(items)) : []
                let line = ok ? "\(items.count) on the desktop, snow on \(self.icons.count)" : "no Accessibility access"
                if self.enabled, line != self.logged {
                    self.logged = line
                    EventLog.add("icons: " + line)
                }
            }
        }
    }

    // MARK: - Чтение у Finder

    /// Значок, как его описал Finder: рамка и то, чем он нарисован — иконкой типа (type) или миниатюрой
    /// содержимого (aspect — её ширина к высоте). Ни того, ни другого — форма неизвестна, снег не кладём.
    struct Item {
        var frame: CGRect
        var type = ""
        var aspect: CGFloat = 0
    }

    /// Значки на столе выключены в настройках системы («Показывать объекты: на рабочем столе») —
    /// Finder всё равно назвал бы их места, и снег лёг бы на пустоту.
    private static func hiddenBySystem() -> Bool {
        if let f = UserDefaults(suiteName: "com.apple.finder"), let show = f.object(forKey: "CreateDesktop") as? Bool, !show { return true }
        guard let d = UserDefaults(suiteName: "com.apple.WindowManager") else { return false }
        let stage = d.object(forKey: "GloballyEnabled") as? Bool ?? false
        return d.object(forKey: stage ? "HideDesktop" : "StandardHideDesktopIcons") as? Bool ?? false
    }

    private static func attr(_ e: AXUIElement, _ name: String) -> (value: AnyObject?, error: AXError) {
        var v: AnyObject?
        let err = AXUIElementCopyAttributeValue(e, name as CFString, &v)
        return (err == .success ? v : nil, err)
    }

    private static func frame(_ e: AXUIElement) -> CGRect? {
        guard let pv = attr(e, kAXPositionAttribute).value, let sv = attr(e, kAXSizeAttribute).value,
              CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    private static func finder() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return nil }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)      // занятый Finder не ждём дольше
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    /// Что Finder показывает на столе и разрешено ли нам спрашивать. Разрешение проверяется самим
    /// запросом: отметка `AXIsProcessTrusted()` в уже запущенном процессе обновляется не сразу.
    ///
    /// Рабочий стол у Finder — не окно, а отдельная область прямо в приложении (AXScrollArea → AXGroup),
    /// значки в ней — картинки (AXImage) с рамкой ровно по размеру значка. Обычные окна не трогаем.
    private static func read() -> (items: [Item], trusted: Bool) {
        guard let app = finder() else { return ([], AXIsProcessTrusted()) }
        let top = attr(app, kAXChildrenAttribute)
        if top.error == .apiDisabled { return ([], false) }
        let preview = showsPreviews()
        // точки монтирования: диск на столе Finder рисует значком диска, где бы тот ни был подключён
        let mounts = Set((FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? [])
            .map { $0.standardizedFileURL.path })
        var out: [Item] = []
        func collect(_ e: AXUIElement, _ depth: Int) {
            if depth > 4 || out.count > 600 { return }
            if (attr(e, kAXRoleAttribute).value as? String) == kAXImageRole {
                guard let f = frame(e), f.width >= 12, f.height >= 12, f.width <= 300, f.height <= 300 else { return }
                var item = Item(frame: f)
                if let url = attr(e, kAXURLAttribute).value as? URL {
                    if let t = iconType(of: url, previews: preview, mounts: mounts) { item.type = t }
                    else { item.aspect = thumbnailAspect(url) }
                }
                out.append(item)
                return
            }
            for c in attr(e, kAXChildrenAttribute).value as? [AXUIElement] ?? [] { collect(c, depth + 1) }
        }
        for area in top.value as? [AXUIElement] ?? [] {
            let role = attr(area, kAXRoleAttribute).value as? String ?? ""
            if role != kAXWindowRole && role != kAXMenuBarRole { collect(area, 0) }
        }
        return (out, top.error == .success || AXIsProcessTrusted())
    }

    /// Настройки вида рабочего стола в Finder («Показать параметры вида»).
    private static func viewSettings() -> [String: Any] {
        let view = UserDefaults(suiteName: "com.apple.finder")?.dictionary(forKey: "DesktopViewSettings")
        return view?["IconViewSettings"] as? [String: Any] ?? [:]
    }

    private static func showsPreviews() -> Bool { (viewSettings()["showIconPreview"] as? NSNumber)?.boolValue ?? true }

    /// Чьей иконкой Finder рисует этот объект. Из адреса берутся только расширение и то, папка ли это.
    /// nil — вместо иконки там миниатюра содержимого (или что-то, чью форму не угадать).
    static func iconType(of url: URL, previews: Bool, mounts: Set<String> = []) -> String? {
        let ext = url.pathExtension.lowercased()
        if url.hasDirectoryPath {
            let parts = url.standardizedFileURL.pathComponents
            if parts.count <= 1 || (parts.count == 3 && parts[1] == "Volumes") || mounts.contains(url.standardizedFileURL.path) {
                return UTType.volume.identifier
            }
            if ext == "app" { return UTType.applicationBundle.identifier }
            // папка с точкой в имени — всё ещё папка; пакет (проект, библиотека) рисуется иконкой своего типа
            if !ext.isEmpty, let t = UTType(filenameExtension: ext), !t.isDynamic, t.conforms(to: .package) { return t.identifier }
            return UTType.folder.identifier
        }
        guard !ext.isEmpty, let t = UTType(filenameExtension: ext) else { return UTType.data.identifier }
        let drawn: [UTType] = [.image, .audiovisualContent, .pdf, .presentation, .spreadsheet, .threeDContent,
                               .html, .webArchive, .font, .diskImage, .aliasFile, .symbolicLink]
        if previews && drawn.contains(where: { t.conforms(to: $0) }) { return nil }
        return t.identifier
    }

    /// Пропорции миниатюры (ширина к высоте) по сведениям Spotlight: размер кадра у картинки и видео,
    /// размер страницы у PDF. 0 — неизвестно (файл не проиндексирован, доступ к папке не дали, тип не тот).
    /// Ответы помнятся несколько минут — по хешу пути, сам путь не хранится.
    private static var aspects: [Int: CGFloat] = [:]
    private static var aspectsAt: CFTimeInterval = 0
    private static func thumbnailAspect(_ url: URL) -> CGFloat {
        let now = CACurrentMediaTime()
        if now - aspectsAt > 300 || aspects.count > 2000 { aspects.removeAll(); aspectsAt = now }
        let key = url.path.hashValue
        if let known = aspects[key] { return known }
        var aspect: CGFloat = 0
        if let t = UTType(filenameExtension: url.pathExtension.lowercased()),
           t.conforms(to: .image) || t.conforms(to: .audiovisualContent) || t.conforms(to: .pdf),
           let item = MDItemCreateWithURL(nil, url as CFURL) {
            func num(_ k: String) -> CGFloat { CGFloat((MDItemCopyAttribute(item, k as CFString) as? NSNumber)?.doubleValue ?? 0) }
            var w = num("kMDItemPixelWidth"), h = num("kMDItemPixelHeight")
            if w <= 0 || h <= 0 { w = num("kMDItemPageWidth"); h = num("kMDItemPageHeight") }
            if w > 0 && h > 0 {
                // снимок, повёрнутый пометкой камеры: размеры записаны лёжа, а показывается он стоя (и наоборот)
                if let o = MDItemCopyAttribute(item, "kMDItemOrientation" as CFString) as? NSNumber, (o.intValue == 1) != (h > w) { swap(&w, &h) }
                aspect = w / h
            }
        }
        aspects[key] = aspect
        return aspect
    }

    // MARK: - Форма значка

    /// Ровная часть верхнего края иконки, в долях её размера (0 — левый/верхний край рамки).
    struct Roof { var x0: CGFloat, x1: CGFloat, y: CGFloat }

    /// Самый широкий ровный участок верхнего края: столбцы, чей верх лежит в пределах одной полосы.
    /// У папки это корпус вместе с язычком, у документа — лист до загнутого уголка, у программы —
    /// верх скруглённого квадрата между углами.
    static func roof(of icon: NSImage) -> Roof? {
        let n = 128
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: n * 4, bitsPerPixel: 32),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        icon.draw(in: NSRect(x: 0, y: 0, width: n, height: n), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return nil }
        // верх непрозрачной части в каждом столбце (тень вокруг иконки полупрозрачная — не в счёт)
        var top = [Int](repeating: n, count: n)
        for x in 0..<n {
            for y in 0..<n where data[(y * n + x) * 4 + 3] > 140 { top[x] = y; break }
        }
        let band = n / 12                       // полоса, в которой верх считается ровным (~8 % размера)
        var best: (a: Int, b: Int, y: Int)?
        for level in Set(top) where level < n * 3 / 4 {
            var a = -1
            for x in 0...n {
                let inside = x < n && top[x] >= level && top[x] <= level + band
                if inside { if a < 0 { a = x } }
                else if a >= 0 {
                    let len = x - a
                    if len > (best.map { $0.b - $0.a } ?? 0) + 2 || (best != nil && len >= best!.b - best!.a - 2 && level < best!.y) {
                        best = (a, x, level)
                    }
                    a = -1
                }
            }
        }
        guard let r = best, r.b - r.a >= n / 4 else { return nil }
        let mean = top[r.a..<r.b].reduce(0, +) / (r.b - r.a)
        return Roof(x0: CGFloat(r.a) / CGFloat(n), x1: CGFloat(r.b) / CGFloat(n), y: CGFloat(mean) / CGFloat(n))
    }

    private func roof(forType id: String) -> Roof? {
        if let known = roofs[id] { return known }
        // Значок диска зависит от самого диска (внутренний, внешний, карта памяти), а чтобы его получить,
        // пришлось бы лезть на диск. У всех них верх — узкая грань почти у края рамки; берём её по замеру.
        if id == UTType.volume.identifier { roofs[id] = Roof(x0: 0.16, x1: 0.84, y: 0.05); return roofs[id]! }
        let r = UTType(id).flatMap { DesktopIcons.roof(of: NSWorkspace.shared.icon(for: $0)) }
        roofs[id] = r
        return r
    }

    /// Рамки значков → места для снега. Главный поток: иконки типов рисуются здесь (и только по разу).
    private func place(_ items: [Item]) -> [Icon] {
        items.compactMap { it in
            let f = it.frame
            var rect: CGRect
            if it.aspect > 0 {
                // Миниатюру Finder вписывает в квадрат 7/8 размера значка и ставит по центру рамки.
                let box = f.width * 0.875
                let w = it.aspect >= 1 ? box : box * it.aspect, h = it.aspect >= 1 ? box / it.aspect : box
                guard w >= 14, h >= 3 else { return nil }
                rect = CGRect(x: f.midX - w / 2 + 1, y: f.midY - h / 2, width: w - 2, height: h)
            } else {
                guard !it.type.isEmpty, let r = roof(forType: it.type) else { return nil }
                rect = CGRect(x: f.minX + r.x0 * f.width, y: f.minY + r.y * f.height,
                              width: (r.x1 - r.x0) * f.width, height: (1 - r.y) * f.height)
            }
            // Номер — по месту: значок передвинули, значит, старая опора пропала (снег с неё осыпается),
            // а на новом месте шапка вырастет заново.
            let id = 0x4000_0000 + ((Int(f.midX.rounded()) & 0x7FFF) << 15 | (Int(f.midY.rounded()) & 0x7FFF))
            return Icon(id: id, rect: rect, size: f.width)
        }
    }

    /// Finder иногда не отвечает вовремя (занят, перезапускается), и значок на одно чтение «пропадает».
    /// Опора при этом исчезать не должна — снег с неё осыпался бы зря, — поэтому значок считается
    /// убранным, только если его не было три чтения подряд.
    private func steady(_ found: [Icon]) -> [Icon] {
        for i in found { kept[i.id] = (i, 0) }
        let now = Set(found.map { $0.id })
        for (id, k) in kept where !now.contains(id) {
            kept[id] = k.missed >= 2 ? nil : (k.icon, k.missed + 1)
        }
        return kept.values.map { $0.icon }.sorted { $0.id < $1.id }
    }

    // MARK: - Отладка

    /// `Sugrob --ax-dump <файл>`: что Finder рассказывает о рабочем столе — роли, рамки и типы, без имён.
    /// Запускать через `open -n Sugrob.app --args --ax-dump <файл>`: разрешение выдаётся приложению,
    /// а не тому, кто запустил его из терминала.
    static func dump(to path: String) -> Int32 {
        var out = "trusted: \(AXIsProcessTrusted())\n"
        func flush() { try? out.write(toFile: path, atomically: true, encoding: .utf8) }
        if !AXIsProcessTrusted() {
            requestAccess()
            flush()
            for _ in 0..<180 where !read().trusted { Thread.sleep(forTimeInterval: 1) }
        }
        let t = CACurrentMediaTime()
        let (items, ok) = read()
        out += "read(): trusted \(ok), \(items.count) icons in \(Int((CACurrentMediaTime() - t) * 1000)) ms, "
            + "previews \(showsPreviews()), hidden by system \(hiddenBySystem())\n"
        let placed = shared.place(items)
        out += "snow on \(placed.count)\n"
        for (id, r) in shared.roofs.sorted(by: { $0.key < $1.key }) {
            out += "roof \(id): " + (r.map { String(format: "x %.3f…%.3f y %.3f", $0.x0, $0.x1, $0.y) } ?? "none") + "\n"
        }
        for it in items {
            out += "icon [\(Int(it.frame.minX)),\(Int(it.frame.minY)) \(Int(it.frame.width))x\(Int(it.frame.height))] "
                + (it.aspect > 0 ? String(format: "thumbnail %.2f", it.aspect) : (it.type.isEmpty ? "-" : it.type)) + "\n"
        }
        for i in placed {
            out += String(format: "ledge %.1f %.1f %.1f %.1f\n", i.rect.minX, i.rect.minY, i.rect.width, i.rect.height)
        }
        flush()
        return ok ? 0 : 1
    }
}
