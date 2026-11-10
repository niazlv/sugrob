import AppKit
import CoreServices
import CryptoKit
import Foundation

// Автообновление.
// Последний релиз на GitHub отдаёт update.json и Sugrob.zip (их выкладывает release.sh).
// Хранилищу не доверяем: манифест подписан Ed25519 (ключ у автора, см. tools/ota_sign.swift),
// архив привязан к нему через sha256, а ставится только более новая сборка
// с тем же идентификатором и целой подписью кода.

enum UpdateConfig {
    static let feed = URL(string: "https://github.com/niazlv/sugrob/releases/latest/download/update.json")!
    /// Публичный ключ подписи обновлений (ota-sign pub).
    static let publicKey = "gAFzsgllnxV2qC5JGkhCq5ZIIlrKQdvgHwRnqaoKZRw="
    static let checkEvery: TimeInterval = 4 * 3600
    static let retryAfterError: TimeInterval = 30 * 60
    /// Сколько секунд без мыши и клавиатуры, чтобы перезапуск не помешал.
    static var idleBeforeInstall: TimeInterval { env("SUGROB_UPDATE_IDLE").flatMap(Double.init) ?? 60 }
    static var firstCheckDelay: TimeInterval { env("SUGROB_UPDATE_DELAY").flatMap(Double.init) ?? 20 }
    static func env(_ k: String) -> String? { ProcessInfo.processInfo.environment[k] }
}

struct UpdateManifest: Codable, Sendable {
    var version: String
    var build: Int
    var url: String
    var size: Int
    var sha256: String
    var minimumSystemVersion: String
    var notes: String
    var signature: String

    /// Что подписано: всё, кроме адреса (архив привязан через sha256).
    /// Должно совпадать с message() в tools/ota_sign.swift.
    var signedMessage: Data {
        Data("sugrob-ota-1\n\(build)\n\(version)\n\(sha256)\n\(size)\n\(minimumSystemVersion)\n\(notes)".utf8)
    }
}

enum UpdateError: LocalizedError {
    case http(Int), badManifest, badSignature, corrupt, wrongBundle, codesign, notWritable(String), tool(String, Int32)

    var errorDescription: String? {
        switch self {
        case .http(let c): return "сервер обновлений ответил \(c)"
        case .badManifest: return "сервер обновлений прислал непонятный ответ"
        case .badSignature: return "подпись обновления не сошлась — ставить не буду"
        case .corrupt: return "архив обновления повреждён"
        case .wrongBundle: return "в архиве не та программа или не та сборка"
        case .codesign: return "подпись кода в архиве нарушена"
        case .notWritable(let p): return "нет прав на запись в «\(p)» — перенесите Сугроб в Программы"
        case .tool(let n, let c): return "\(n) завершился с кодом \(c)"
        }
    }
}

struct UpdateEngine: Sendable {
    let feed: URL
    let publicKey: Data
    let bundleID: String
    let currentVersion: String
    let currentBuild: Int

    /// nil, если запущено не из .app (например, .build/release/Sugrob) — тогда обновлять нечего.
    static func standard() -> UpdateEngine? {
        let b = Bundle.main
        guard b.bundleURL.pathExtension == "app", let id = b.bundleIdentifier,
              let key = Data(base64Encoded: UpdateConfig.publicKey) else { return nil }
        let feed = UpdateConfig.env("SUGROB_UPDATE_URL").flatMap(URL.init(string:)) ?? UpdateConfig.feed
        return UpdateEngine(feed: feed, publicKey: key, bundleID: id,
                            currentVersion: b.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
                            currentBuild: Int(b.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0)
    }

    private var session: URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 600
        c.httpAdditionalHeaders = ["User-Agent": "Sugrob/\(currentVersion) (\(currentBuild))"]
        return URLSession(configuration: c)
    }

    func fetchManifest() async throws -> UpdateManifest {
        let (data, resp) = try await session.data(from: feed)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw UpdateError.http(code) }
        guard data.count < 64 << 10, let m = try? JSONDecoder().decode(UpdateManifest.self, from: data)
        else { throw UpdateError.badManifest }
        guard let sig = Data(base64Encoded: m.signature),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(sig, for: m.signedMessage)
        else { throw UpdateError.badSignature }
        return m
    }

    func isNewer(_ m: UpdateManifest) -> Bool { m.build > currentBuild }

    func systemFits(_ m: UpdateManifest) -> Bool {
        let p = m.minimumSystemVersion.split(separator: ".").map { Int($0) ?? 0 } + [0, 0, 0]
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: p[0], minorVersion: p[1], patchVersion: p[2]))
    }

    /// Качает архив, сверяет с манифестом, распаковывает и проверяет приложение внутри.
    /// Возвращает путь к готовому Sugrob.app в кэше.
    func downloadAndStage(_ m: UpdateManifest) async throws -> URL {
        guard m.size > 0, m.size < 200 << 20, let url = URL(string: m.url, relativeTo: feed)?.absoluteURL
        else { throw UpdateError.badManifest }
        let (tmp, resp) = try await session.download(from: url)
        let fm = FileManager.default
        defer { try? fm.removeItem(at: tmp) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw UpdateError.http(code) }
        let data = try Data(contentsOf: tmp)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == m.size, sha == m.sha256.lowercased() else { throw UpdateError.corrupt }

        let dir = Self.cacheDir.appendingPathComponent("\(m.build)-\(UUID().uuidString.prefix(8))")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let zip = dir.appendingPathComponent("update.zip")
        try data.write(to: zip)
        let out = dir.appendingPathComponent("app")
        try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path])
        let apps = try fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
        guard apps.count == 1, let app = apps.first,
              let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == bundleID,
              Int(info["CFBundleVersion"] as? String ?? "") == m.build, m.build > currentBuild
        else { throw UpdateError.wrongBundle }
        do { try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) }
        catch { throw UpdateError.codesign }
        return app
    }

    static var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "local.sugrob.app")
            .appendingPathComponent("Updates")
    }

    /// Где лежит само приложение. Запущенное из «Загрузок» без переноса macOS
    /// подменяет копией в AppTranslocation — менять нужно оригинал.
    static func installedBundleURL() -> URL {
        let url = Bundle.main.bundleURL
        guard url.path.contains("/AppTranslocation/") else { return url }
        typealias Fn = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        if let h = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
           let sym = dlsym(h, "SecTranslocateCreateOriginalPathForURL"),
           let r = unsafeBitCast(sym, to: Fn.self)(url as CFURL, nil) {
            return r.takeRetainedValue() as URL
        }
        return url
    }

    /// Меняет приложение на новое двумя переименованиями в той же папке.
    /// Работающий процесс держит старые файлы и спокойно доживает до перезапуска.
    static func install(staged: URL, over target: URL) throws {
        let fm = FileManager.default
        let dir = target.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: dir.path) else { throw UpdateError.notWritable(dir.path) }
        let tag = UUID().uuidString.prefix(8)
        let incoming = dir.appendingPathComponent(".\(target.lastPathComponent).new-\(tag)")
        let old = dir.appendingPathComponent(".\(target.lastPathComponent).old-\(tag)")
        try run("/usr/bin/ditto", [staged.path, incoming.path])      // ditto — и между дисками
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", incoming.path])
        do { try fm.moveItem(at: target, to: old) } catch {
            try? fm.removeItem(at: incoming)
            throw UpdateError.notWritable(dir.path)
        }
        do { try fm.moveItem(at: incoming, to: target) } catch {
            try? fm.moveItem(at: old, to: target)
            try? fm.removeItem(at: incoming)
            throw error
        }
        try? fm.removeItem(at: old)
        LSRegisterURL(target as CFURL, true)
        try? fm.removeItem(at: cacheDir)
    }

    /// Хвосты от прерванной установки и старые загрузки.
    static func cleanupLeftovers() {
        let fm = FileManager.default
        try? fm.removeItem(at: cacheDir)
        let target = installedBundleURL()
        let dir = target.deletingLastPathComponent()
        let prefixes = [".\(target.lastPathComponent).new-", ".\(target.lastPathComponent).old-"]
        for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where prefixes.contains(where: name.hasPrefix) {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// Открывает приложение заново, как только этот процесс завершится.
    static func relaunchAfterExit(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while /bin/kill -0 \"$0\" 2>/dev/null; do /bin/sleep 0.2; done; exec /usr/bin/open -n \"$1\"",
                       String(getpid()), app.path]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError.tool((tool as NSString).lastPathComponent, p.terminationStatus) }
        return 0
    }
}

/// Проверка, загрузка и установка в работающем приложении + подменю «Обновления».
@MainActor
final class Updater: NSObject {
    enum State {
        case idle, checking, downloading(String), ready(UpdateManifest, URL), installing, upToDate, failed(String)
    }

    private(set) var state: State = .idle
    private let engine = UpdateEngine.standard()
    private let d = UserDefaults.standard
    private var timer: Timer?
    private var nextCheck = Date.distantFuture

    nonisolated override init() { super.init() }

    var auto: Bool {
        get { d.object(forKey: "autoUpdate") as? Bool ?? true }
        set { d.set(newValue, forKey: "autoUpdate") }
    }
    private var lastCheck: Date? {
        get { d.object(forKey: "updateLastCheck") as? Date }
        set { d.set(newValue, forKey: "updateLastCheck") }
    }

    func start() {
        guard engine != nil else { return }
        UpdateEngine.cleanupLeftovers()
        nextCheck = Date() + UpdateConfig.firstCheckDelay
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        switch state {
        case .checking, .downloading, .installing:
            return
        case .ready(let m, let app):
            if auto && Self.idleSeconds() >= UpdateConfig.idleBeforeInstall { install(m, app, user: false) }
        default:
            if Date() >= nextCheck { check(user: false) }
        }
    }

    /// Сколько секунд не трогали мышь и клавиатуру (разрешений не требует).
    static func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    func check(user: Bool) {
        guard let engine else { return }
        switch state {
        case .checking, .downloading, .installing: return
        case .ready(let m, let app):
            if user { offer(m, app) }
            return
        default: break
        }
        state = .checking
        Task {
            do {
                let m = try await engine.fetchManifest()
                lastCheck = Date()
                nextCheck = Date() + UpdateConfig.checkEvery
                guard engine.isNewer(m) else {
                    state = .upToDate
                    if user { alert("У вас последняя версия", "Сугроб \(engine.currentVersion) (\(engine.currentBuild)).") }
                    return
                }
                guard engine.systemFits(m) else {
                    state = .failed("версии \(m.version) нужна macOS \(m.minimumSystemVersion)")
                    if user { alert("Есть Сугроб \(m.version)", "Ему нужна macOS \(m.minimumSystemVersion) или новее.") }
                    return
                }
                state = .downloading(m.version)
                let app = try await engine.downloadAndStage(m)
                state = .ready(m, app)
                if user { offer(m, app) } else { tick() }
            } catch {
                nextCheck = Date() + UpdateConfig.retryAfterError
                state = .failed(error.localizedDescription)
                if user { alert("Не удалось проверить обновления", error.localizedDescription) }
            }
        }
    }

    private func install(_ m: UpdateManifest, _ app: URL, user: Bool) {
        state = .installing
        let target = UpdateEngine.installedBundleURL()
        do {
            try UpdateEngine.install(staged: app, over: target)
            UpdateEngine.relaunchAfterExit(target)
            NSApp.terminate(nil)
        } catch {
            // Не вышло (обычно нет прав на папку) — не повторять каждые 5 секунд.
            nextCheck = Date() + UpdateConfig.checkEvery
            state = .failed(error.localizedDescription)
            if user { alert("Не удалось установить Сугроб \(m.version)", error.localizedDescription) }
        }
    }

    private func offer(_ m: UpdateManifest, _ app: URL) {
        let a = NSAlert()
        a.messageText = "Доступен Сугроб \(m.version)"
        a.informativeText = (m.notes.isEmpty ? "" : m.notes + "\n\n") + "Сейчас у вас \(engine?.currentVersion ?? "?"). Снег после перезапуска начнётся заново."
        a.addButton(withTitle: "Установить и перезапустить")
        a.addButton(withTitle: "Позже")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { install(m, app, user: true) }
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    // MARK: - Меню

    func menuItem() -> NSMenuItem {
        let root = NSMenuItem(title: "Обновления", action: nil, keyEquivalent: "")
        let m = NSMenu()
        func info(_ s: String) {
            let i = NSMenuItem(title: s, action: nil, keyEquivalent: "")
            i.isEnabled = false
            m.addItem(i)
        }
        func act(_ s: String, _ sel: Selector, on: Bool = false, enabled: Bool = true) {
            let i = NSMenuItem(title: s, action: enabled ? sel : nil, keyEquivalent: "")
            i.target = self
            i.state = on ? .on : .off
            i.isEnabled = enabled
            m.addItem(i)
        }
        guard let engine else {
            info("Недоступны: запущено не из Sugrob.app")
            root.submenu = m
            return root
        }
        info("Версия \(engine.currentVersion) (\(engine.currentBuild))")
        info(statusText)
        var busy = false
        switch state {
        case .ready(let mf, _):
            root.title = "Обновления — готова \(mf.version)"
            act("Установить \(mf.version) и перезапустить", #selector(installAction))
        case .checking, .downloading, .installing:
            busy = true
        default: break
        }
        act("Проверить сейчас", #selector(checkAction), enabled: !busy)
        m.addItem(.separator())
        act("Обновлять автоматически", #selector(toggleAuto), on: auto)
        root.submenu = m
        return root
    }

    private var statusText: String {
        switch state {
        case .idle: return lastCheck.map { "Проверено \(Self.when($0))" } ?? "Ещё не проверялось"
        case .checking: return "Проверяю…"
        case .downloading(let v): return "Скачиваю \(v)…"
        case .ready(let m, _): return auto ? "Готова \(m.version): поставлю, когда отойдёте от компьютера" : "Готова \(m.version)"
        case .installing: return "Устанавливаю…"
        case .upToDate: return "Последняя версия, проверено \(lastCheck.map(Self.when) ?? "")"
        case .failed(let e): return "Ошибка: " + (e.count > 70 ? String(e.prefix(70)) + "…" : e)
        }
    }

    private static func when(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = Calendar.current.isDateInToday(d) ? "'в' HH:mm" : "d MMM 'в' HH:mm"
        return f.string(from: d)
    }

    @objc private func checkAction() { check(user: true) }
    @objc private func installAction() {
        if case .ready(let m, let app) = state { install(m, app, user: true) }
    }
    @objc private func toggleAuto() { auto.toggle() }
}

/// `Sugrob --update-now [--relaunch]` — проверить и поставить обновление из командной строки.
/// Коды выхода: 0 — обновлено, 3 — обновлений нет, 1 — ошибка.
enum UpdateCLI {
    final class Box: @unchecked Sendable { var code: Int32 = 1 }

    static func run(relaunch: Bool) -> Int32 {
        guard let engine = UpdateEngine.standard() else {
            print("Обновление: запущено не из Sugrob.app")
            return 1
        }
        print("Сугроб \(engine.currentVersion) (\(engine.currentBuild)), источник \(engine.feed.absoluteString)")
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            defer { done.signal() }
            do {
                let m = try await engine.fetchManifest()
                guard engine.isNewer(m) else {
                    print("Обновлений нет: на сервере \(m.version) (\(m.build))")
                    box.code = 3
                    return
                }
                guard engine.systemFits(m) else {
                    print("Версии \(m.version) нужна macOS \(m.minimumSystemVersion)")
                    box.code = 3
                    return
                }
                print("Найдена \(m.version) (\(m.build)), качаю и проверяю…")
                let app = try await engine.downloadAndStage(m)
                let target = UpdateEngine.installedBundleURL()
                try UpdateEngine.install(staged: app, over: target)
                print("Установлено: \(target.path)")
                if relaunch { UpdateEngine.relaunchAfterExit(target) }
                box.code = 0
            } catch {
                print("Ошибка: \(error.localizedDescription)")
                box.code = 1
            }
        }
        done.wait()
        return box.code
    }
}
