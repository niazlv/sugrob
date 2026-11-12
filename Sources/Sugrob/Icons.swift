import AppKit
import UniformTypeIdentifiers

/// Значки рабочего стола: папки, программы и файлы, на которые тоже может лечь снег.
///
/// Все значки рисует одно окно Finder во весь экран, поэтому по списку окон их не найти. Где они,
/// знает только сам Finder и сообщает это через «Универсальный доступ» — разрешение, без которого
/// остальное приложение обходится. Поэтому снег на значках выключен, пока его не включат в меню,
/// а без разрешения просто ничего не делает.
///
/// Спрашивает Finder не сам Сугроб, а его помощник — маленькая вложенная программа
/// (Sources/SugrobIcons, готовый файл в Contents/Helpers). Разрешение macOS привязывает к подписи,
/// а подпись Сугроба меняется с каждой сборкой; помощник же от версии к версии не меняется ни на
/// байт, поэтому разрешение, выданное ему, переживает обновления. Помощник отдаёт только рамку
/// значка и его тип: расширение, папка ли это, диск ли, размер кадра картинки. Имена наружу
/// не выходят, сами файлы не открываются.
///
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
    var enabled = false {
        didSet {
            guard !enabled else { return }
            helper?.stop()
            helper = nil
            icons = []; kept = [:]; logged = ""; waiting = false; wantPrompt = false
            startedAt = -100
        }
    }
    /// Что нашлось при последнем чтении. Меняется только в главном потоке.
    private(set) var icons: [Icon] = []
    /// Разрешение «Универсальный доступ» у помощника есть (по его последнему ответу).
    private(set) var trusted = false

    private var helper: IconHelper?
    private var startedAt: CFTimeInterval = -100
    private var askedAt: CFTimeInterval = -100
    private var waiting = false                     // вопрос задан, ответа ещё нет
    private var wantPrompt = false                  // если доступа нет — показать системный запрос
    private var logged = ""
    private var roofs: [String: Roof?] = [:]        // «крыша» иконки каждого типа, в долях её размера
    private var kept: [Int: (icon: Icon, missed: Int)] = [:]

    /// Попросить помощника показать системный запрос «разрешить управление компьютером»;
    /// сам переключатель включает человек. `onlyIfNeeded` — спросить, только если доступа нет.
    func requestAccess(onlyIfNeeded: Bool = false) {
        if onlyIfNeeded { wantPrompt = true; return }
        running(CACurrentMediaTime(), force: true)?.send("prompt")
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Зовётся при каждом опросе окон. Помощник опрашивается не чаще раза в секунду; он работает
    /// отдельным процессом, так что занятый Finder снег не задерживает.
    func refresh(now: CFTimeInterval) {
        guard enabled, let h = running(now) else { return }
        guard waiting ? now - askedAt > 20 : now - askedAt >= 1 else { return }
        waiting = h.send("read")
        askedAt = now
    }

    private func note(_ line: String) {
        guard line != logged else { return }
        logged = line
        EventLog.add("icons: " + line)
    }

    /// Помощник, запущенный и живой. Упавшего перезапускаем, но не чаще раза в десять секунд.
    @discardableResult
    private func running(_ now: CFTimeInterval, force: Bool = false) -> IconHelper? {
        if let h = helper, h.alive { return h }
        guard force || now - startedAt > 10 else { return nil }
        startedAt = now
        waiting = false
        helper = nil
        guard let h = IconHelper() else {
            note("the helper is missing or would not start")
            return nil
        }
        h.onReply = { [weak self] lines in self?.reply(lines) }
        helper = h
        EventLog.add("icons: helper started, pid \(h.pid)\(h.disclaimed ? "" : " (not on its own: permission will be asked for Sugrob itself)")")
        return h
    }

    private func reply(_ lines: [String]) {
        guard enabled, let head = lines.first?.split(separator: " "), head.first == "icons", head.count >= 2 else { return }
        waiting = false
        trusted = head[1] == "1"
        let items = DesktopIcons.hiddenBySystem() ? [] : DesktopIcons.parse(lines.dropFirst())
        icons = steady(place(items))
        note(trusted ? "\(items.count) on the desktop, snow on \(icons.count)" : "no Accessibility access for the helper")
        if wantPrompt {
            wantPrompt = false
            if !trusted { helper?.send("prompt") }
        }
    }

    // MARK: - Что рассказал помощник

    /// Значок, как его описал Finder: рамка и то, чем он нарисован — иконкой типа (type) или миниатюрой
    /// содержимого (aspect — её ширина к высоте). Ни того, ни другого — форма неизвестна, снег не кладём.
    struct Item {
        var frame: CGRect
        var type = ""
        var aspect: CGFloat = 0
    }

    /// Строки ответа помощника: «x y w h роль расширение папка диск ширина высота ориентация».
    static func parse<S: Sequence>(_ lines: S) -> [Item] where S.Element == String {
        let previews = showsPreviews()
        return lines.compactMap { line in
            let f = line.split(separator: " ")
            guard f.count >= 11, let x = Double(f[0]), let y = Double(f[1]), let w = Double(f[2]), let h = Double(f[3]) else { return nil }
            var item = Item(frame: CGRect(x: x, y: y, width: w, height: h))
            let ext = f[5] == "-" ? "" : String(f[5])
            if let t = iconType(ext: ext, directory: f[6] == "1", volume: f[7] == "1", previews: previews) {
                item.type = t
            } else if var mw = Double(f[8]), var mh = Double(f[9]), mw > 0, mh > 0 {
                // снимок, повёрнутый пометкой камеры: размеры записаны лёжа, а показывается он стоя (и наоборот)
                if let o = Int(f[10]), o >= 0, (o == 1) != (mh > mw) { swap(&mw, &mh) }
                item.aspect = CGFloat(mw / mh)
            }
            return item
        }
    }

    /// Значки на столе выключены в настройках системы («Показывать объекты: на рабочем столе») —
    /// Finder всё равно назвал бы их места, и снег лёг бы на пустоту.
    private static func hiddenBySystem() -> Bool {
        if let f = UserDefaults(suiteName: "com.apple.finder"), let show = f.object(forKey: "CreateDesktop") as? Bool, !show { return true }
        guard let d = UserDefaults(suiteName: "com.apple.WindowManager") else { return false }
        let stage = d.object(forKey: "GloballyEnabled") as? Bool ?? false
        return d.object(forKey: stage ? "HideDesktop" : "StandardHideDesktopIcons") as? Bool ?? false
    }

    /// Показывает ли Finder на столе миниатюры содержимого («Показать параметры вида»).
    private static func showsPreviews() -> Bool {
        let view = UserDefaults(suiteName: "com.apple.finder")?.dictionary(forKey: "DesktopViewSettings")
        let icon = view?["IconViewSettings"] as? [String: Any]
        return (icon?["showIconPreview"] as? NSNumber)?.boolValue ?? true
    }

    /// Чьей иконкой Finder рисует этот объект. nil — вместо иконки там миниатюра содержимого
    /// (или что-то, чью форму не угадать).
    static func iconType(ext: String, directory: Bool, volume: Bool, previews: Bool) -> String? {
        if directory {
            if volume { return UTType.volume.identifier }
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

    /// `Sugrob --ax-dump <файл>`: что помощник рассказывает о рабочем столе — роли, рамки и типы, без
    /// имён. Если доступа ещё нет, показывает системный запрос и ждёт до трёх минут.
    static func dump(to path: String) -> Int32 {
        var out = ""
        func flush() { try? out.write(toFile: path, atomically: true, encoding: .utf8) }
        let answers = DispatchQueue(label: "sugrob.icons.dump")
        guard let h = IconHelper(queue: answers) else {
            out = "the helper is missing: \(IconHelper.executable)\n"
            flush()
            return 1
        }
        let got = DispatchSemaphore(value: 0)
        var last: [String] = []
        h.onReply = { lines in last = lines; got.signal() }
        func ask(_ cmd: String, timeout: Double = 30) -> [String] {
            guard h.send(cmd), got.wait(timeout: .now() + timeout) == .success else { return [] }
            return answers.sync { last }
        }
        var pong = ask("ping")
        out += "helper pid \(h.pid), responsible for itself: \(h.disclaimed), says: \(pong.first ?? "nothing")\n"
        if pong.first?.hasSuffix(" 0") == true {
            _ = ask("prompt")
            flush()
            for _ in 0..<180 where pong.first?.hasSuffix(" 1") != true {
                Thread.sleep(forTimeInterval: 1)
                pong = ask("ping")
            }
            out += "after waiting: \(pong.first ?? "nothing")\n"
        }
        out += ask("tree limit=40").joined(separator: "\n") + "\n"
        let t = CACurrentMediaTime()
        let answer = ask("read", timeout: 240)      // первый раз может ждать ответа на запрос доступа к папке
        let items = parse(answer.dropFirst())
        out += "read: \(answer.first ?? "nothing") in \(Int((CACurrentMediaTime() - t) * 1000)) ms, "
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
        h.stop()
        flush()
        return answer.first?.hasPrefix("icons 1") == true ? 0 : 1
    }
}

/// Помощник (Sources/SugrobIcons): запуск и разговор строками через его стандартный ввод и вывод.
///
/// Запускается он так, чтобы отвечать за себя сам: иначе macOS записала бы его запросы на счёт
/// Сугроба, и разрешение снова зависело бы от подписи основной программы.
final class IconHelper {
    static var executable: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/SugrobIcons.app/Contents/MacOS/SugrobIcons").path
    }

    private(set) var pid: pid_t = 0
    private(set) var alive = false
    /// Система согласилась считать помощника отдельной программой (а не частью Сугроба).
    private(set) var disclaimed = false
    /// Ответ целиком: одна строка или блок от заголовка до `end` (без самого `end`).
    var onReply: (([String]) -> Void)?

    private var toChild: FileHandle?
    private var fromChild: FileHandle?
    private var watcher: DispatchSourceProcess?
    private let io = DispatchQueue(label: "sugrob.icon-helper")
    private let answers: DispatchQueue
    private var pending = Data()
    private var block: [String]?

    /// «Отвечает за себя сам» — недокументированная, но давняя настройка запуска процесса; ею
    /// пользуются браузеры и терминалы. Нет её — помощник всё равно работает, но разрешение
    /// система спросит на имя Сугроба.
    private static let disclaim: (@convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32)? = {
        guard let s = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim") else { return nil }
        return unsafeBitCast(s, to: (@convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32).self)
    }()

    init?(queue: DispatchQueue = .main) {
        answers = queue
        let path = IconHelper.executable
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        // Скачанное из сети приложение помечено «карантином», и пометка стоит на каждом его файле.
        // Сам Сугроб человек уже разрешил запускать; помощник — его часть (он под той же подписью),
        // так что отдельного вопроса про него быть не должно. Не вышло снять — запускаем как есть.
        var dir = URL(fileURLWithPath: path)
        for _ in 0..<4 {
            removexattr(dir.path, "com.apple.quarantine", 0)
            dir.deleteLastPathComponent()           // …/MacOS, …/Contents, …/SugrobIcons.app
        }
        signal(SIGPIPE, SIG_IGN)            // помощник мог выйти: запись в его ввод не должна убивать Сугроб
        var toPipe: [Int32] = [0, 0], fromPipe: [Int32] = [0, 0]
        guard pipe(&toPipe) == 0 else { return nil }
        guard pipe(&fromPipe) == 0 else { close(toPipe[0]); close(toPipe[1]); return nil }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_adddup2(&actions, toPipe[0], 0)
        posix_spawn_file_actions_adddup2(&actions, fromPipe[1], 1)
        posix_spawn_file_actions_addinherit_np(&actions, 2)
        var attrs: posix_spawnattr_t?
        posix_spawnattr_init(&attrs)
        posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))     // остальные наши файлы ему не достаются
        disclaimed = IconHelper.disclaim.map { $0(&attrs, 1) == 0 } ?? false
        var child: pid_t = 0
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup(path), nil]
        let env: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        let rc = posix_spawn(&child, path, &actions, &attrs, argv, env)
        free(argv[0])
        env.forEach { free($0) }
        posix_spawn_file_actions_destroy(&actions)
        posix_spawnattr_destroy(&attrs)
        close(toPipe[0])
        close(fromPipe[1])
        guard rc == 0 else { close(toPipe[1]); close(fromPipe[0]); return nil }

        pid = child
        alive = true
        toChild = FileHandle(fileDescriptor: toPipe[1], closeOnDealloc: true)
        let from = FileHandle(fileDescriptor: fromPipe[0], closeOnDealloc: true)
        fromChild = from
        from.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil }
            self?.io.async { self?.feed(data) }
        }
        let w = DispatchSource.makeProcessSource(identifier: child, eventMask: .exit, queue: io)
        w.setEventHandler { [weak self] in
            var status: Int32 = 0
            waitpid(child, &status, 0)
            self?.alive = false
            self?.watcher?.cancel()
        }
        w.resume()
        watcher = w
    }

    @discardableResult
    func send(_ line: String) -> Bool {
        guard alive, let h = toChild else { return false }
        do { try h.write(contentsOf: Data((line + "\n").utf8)); return true } catch { alive = false; return false }
    }

    /// Закрыть помощнику ввод — он выходит сам. То же случится, если Сугроб просто завершится.
    func stop() {
        guard alive else { return }
        alive = false
        try? toChild?.close()
        toChild = nil
        kill(pid, SIGTERM)
    }

    private func feed(_ data: Data) {
        if data.isEmpty { alive = false; return }
        pending.append(data)
        while let nl = pending.firstIndex(of: 0x0A) {
            let line = String(decoding: pending[pending.startIndex..<nl], as: UTF8.self)
            pending.removeSubrange(pending.startIndex...nl)
            if block != nil {
                if line == "end" { deliver(block!); block = nil }
                else if block!.count < 5000 { block!.append(line) }
            } else if line.hasPrefix("icons ") || line.hasPrefix("tree ") {
                block = [line]
            } else {
                deliver([line])
            }
        }
        if pending.count > 1 << 20 { pending.removeAll() }
    }

    private func deliver(_ lines: [String]) {
        answers.async { [weak self] in self?.onReply?(lines) }
    }
}
