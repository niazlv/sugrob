import Foundation
import ApplicationServices
import CoreServices
import UniformTypeIdentifiers

// Помощник Сугроба: сообщает, где на рабочем столе лежат значки.
//
// Зачем он отдельный. Места значков знает только Finder и отдаёт их через «Универсальный доступ».
// macOS привязывает это разрешение к подписи программы, а Сугроб выходит без сертификата
// разработчика — его подпись меняется с каждой сборкой, и после каждого обновления разрешение
// пришлось бы выдавать заново. Помощник решает это тем, что НЕ МЕНЯЕТСЯ: в каждую сборку кладётся
// один и тот же готовый файл, байт в байт (Resources/SugrobIcons.app), поэтому система узнаёт его
// и после обновления. Отсюда правило: всё, что может понадобиться менять, живёт в самом Сугробе,
// а здесь — только чтение и ничего лишнего. Пересборка помощника сбрасывает разрешение у всех.
//
// Что он умеет: назвать рамку каждого значка рабочего стола, его расширение, папка ли это, диск ли,
// и размер кадра картинки или видео по сведениям Spotlight. Имена файлов наружу не выдаются,
// сами файлы не открываются, другие программы, кроме Finder, не опрашиваются.
//
// Разговор — строками через стандартный ввод и вывод (запускает и слушает его только Сугроб):
//   ping                          → pong <версия> <доступ 0|1>
//   prompt                        → ok          (показать системный запрос «Универсального доступа»)
//   read [roles=AXImage] [depth=4] [min=12] [max=300] [limit=600]
//                                 → icons <доступ> <n>, затем n строк, затем end
//        строка значка: x y w h роль расширение папка диск ширина высота ориентация
//        (расширение «-», если его нет; размеры кадра 0, если неизвестны; ориентация −1, если нет)
//   tree [depth=5] [limit=400]    → tree <доступ> <n>, затем n строк «глубина роль подроль x y w h детей», end
//   quit или конец ввода          → выход

let protocolVersion = 1

signal(SIGPIPE, SIG_IGN)
AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)      // занятый Finder не ждём дольше

func say(_ line: String) { print(line) }
func done() { fflush(stdout) }

// MARK: - Finder

/// Номер процесса Finder. Ищется по пути исполняемого файла, без AppKit: список программ от AppKit
/// обновляется только при работающем цикле событий, а его здесь нет.
var finderPID: pid_t = 0
func findFinder() -> pid_t {
    func isFinder(_ pid: pid_t) -> Bool {
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return false }
        return String(cString: buf) == "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"
    }
    if finderPID > 0, isFinder(finderPID) { return finderPID }
    finderPID = 0
    var pids = [pid_t](repeating: 0, count: 8192)
    let bytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
    for pid in pids.prefix(max(0, Int(bytes))) where pid > 0 && isFinder(pid) { finderPID = pid; break }
    return finderPID
}

func attr(_ e: AXUIElement, _ name: String) -> (value: AnyObject?, error: AXError) {
    var v: AnyObject?
    let err = AXUIElementCopyAttributeValue(e, name as CFString, &v)
    return (err == .success ? v : nil, err)
}

func frame(_ e: AXUIElement) -> CGRect? {
    guard let pv = attr(e, kAXPositionAttribute).value, let sv = attr(e, kAXSizeAttribute).value,
          CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    guard AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &s) else { return nil }
    return CGRect(origin: p, size: s)
}

/// То, что у Finder лежит не в окнах и не в строке меню: рабочий стол. Заодно — есть ли доступ:
/// он проверяется самим запросом, потому что отметка `AXIsProcessTrusted()` обновляется не сразу.
func desktop() -> (areas: [AXUIElement], trusted: Bool) {
    let pid = findFinder()
    guard pid > 0 else { return ([], AXIsProcessTrusted()) }
    let top = attr(AXUIElementCreateApplication(pid), kAXChildrenAttribute)
    if top.error == .apiDisabled { return ([], false) }
    let areas = (top.value as? [AXUIElement] ?? []).filter {
        let role = attr($0, kAXRoleAttribute).value as? String ?? ""
        return role != kAXWindowRole && role != kAXMenuBarRole
    }
    return (areas, top.error == .success || AXIsProcessTrusted())
}

// MARK: - Сведения о файле (без имён)

/// Слово без пробелов и неожиданных знаков — чтобы строка ответа разбиралась однозначно.
func word(_ s: String, limit: Int = 24) -> String {
    let ok = s.unicodeScalars.filter { ($0.value >= 48 && $0.value <= 57) || ($0.value >= 65 && $0.value <= 90)
        || ($0.value >= 97 && $0.value <= 122) || $0 == "_" || $0 == "+" || $0 == "-" }
    let out = String(String.UnicodeScalarView(ok.prefix(limit)))
    return out.isEmpty ? "-" : out
}

/// Размер кадра по сведениям Spotlight: у картинки и видео — в точках изображения, у PDF — размер
/// страницы; ориентация — как её записала камера. Спрашивается только для таких файлов (иначе macOS
/// зря спросила бы доступ к папке). Ответы помнятся несколько минут по хешу пути, сам путь не хранится.
var frames: [Int: (w: Double, h: Double, o: Int)] = [:]
var framesAt = Date()
func mediaFrame(_ url: URL) -> (w: Double, h: Double, o: Int) {
    if Date().timeIntervalSince(framesAt) > 300 || frames.count > 4000 { frames.removeAll(); framesAt = Date() }
    let key = url.path.hashValue
    if let known = frames[key] { return known }
    var out = (w: 0.0, h: 0.0, o: -1)
    if let t = UTType(filenameExtension: url.pathExtension.lowercased()),
       t.conforms(to: .image) || t.conforms(to: .audiovisualContent) || t.conforms(to: .pdf),
       let item = MDItemCreateWithURL(nil, url as CFURL) {
        func num(_ k: String) -> Double? { (MDItemCopyAttribute(item, k as CFString) as? NSNumber)?.doubleValue }
        out.w = num("kMDItemPixelWidth") ?? 0
        out.h = num("kMDItemPixelHeight") ?? 0
        if out.w <= 0 || out.h <= 0 { out.w = num("kMDItemPageWidth") ?? 0; out.h = num("kMDItemPageHeight") ?? 0 }
        out.o = num("kMDItemOrientation").map { Int($0) } ?? -1
    }
    frames[key] = out
    return out
}

// MARK: - Команды

func options(_ parts: [Substring]) -> [String: String] {
    var out: [String: String] = [:]
    for p in parts {
        let kv = p.split(separator: "=", maxSplits: 1)
        if kv.count == 2 { out[String(kv[0])] = String(kv[1]) }
    }
    return out
}

func read(_ opt: [String: String]) {
    let roles = Set((opt["roles"] ?? kAXImageRole).split(separator: ",").map(String.init))
    let depthMax = min(8, Int(opt["depth"] ?? "") ?? 4)
    let lo = CGFloat(Double(opt["min"] ?? "") ?? 12), hi = CGFloat(Double(opt["max"] ?? "") ?? 300)
    let limit = min(2000, Int(opt["limit"] ?? "") ?? 600)
    let (areas, trusted) = desktop()
    // точки монтирования: диск на столе Finder рисует значком диска, где бы тот ни был подключён
    let mounts = Set((FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? [])
        .map { $0.standardizedFileURL.path })
    var lines: [String] = []
    func collect(_ e: AXUIElement, _ depth: Int) {
        if depth > depthMax || lines.count >= limit { return }
        let role = attr(e, kAXRoleAttribute).value as? String ?? ""
        if roles.contains(role) {
            guard let f = frame(e), f.width >= lo, f.height >= lo, f.width <= hi, f.height <= hi else { return }
            var ext = "-", dir = 0, vol = 0
            var media = (w: 0.0, h: 0.0, o: -1)
            if let url = attr(e, kAXURLAttribute).value as? URL {
                ext = word(url.pathExtension.lowercased())
                let path = url.standardizedFileURL.path
                let parts = url.standardizedFileURL.pathComponents
                if url.hasDirectoryPath {
                    dir = 1
                    if parts.count <= 1 || (parts.count == 3 && parts[1] == "Volumes") || mounts.contains(path) { vol = 1 }
                } else {
                    media = mediaFrame(url)
                }
            }
            lines.append(String(format: "%.1f %.1f %.1f %.1f", f.minX, f.minY, f.width, f.height)
                         + " \(word(role, limit: 40)) \(ext) \(dir) \(vol) "
                         + String(format: "%.0f %.0f", media.w, media.h) + " \(media.o)")
            return
        }
        for c in attr(e, kAXChildrenAttribute).value as? [AXUIElement] ?? [] { collect(c, depth + 1) }
    }
    for a in areas { collect(a, 0) }
    say("icons \(trusted ? 1 : 0) \(lines.count)")
    lines.forEach(say)
    say("end")
}

func tree(_ opt: [String: String]) {
    let depthMax = min(8, Int(opt["depth"] ?? "") ?? 5)
    let limit = min(2000, Int(opt["limit"] ?? "") ?? 400)
    let (areas, trusted) = desktop()
    var lines: [String] = []
    func walk(_ e: AXUIElement, _ depth: Int) {
        if depth > depthMax || lines.count >= limit { return }
        let role = word(attr(e, kAXRoleAttribute).value as? String ?? "", limit: 40)
        let sub = word(attr(e, kAXSubroleAttribute).value as? String ?? "", limit: 40)
        let kids = attr(e, kAXChildrenAttribute).value as? [AXUIElement] ?? []
        let f = frame(e) ?? .zero
        lines.append("\(depth) \(role) \(sub) " + String(format: "%.0f %.0f %.0f %.0f", f.minX, f.minY, f.width, f.height) + " \(kids.count)")
        for c in kids { walk(c, depth + 1) }
    }
    for a in areas { walk(a, 0) }
    say("tree \(trusted ? 1 : 0) \(lines.count)")
    lines.forEach(say)
    say("end")
}

while let line = readLine(strippingNewline: true) {
    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
    guard let cmd = parts.first else { continue }
    switch cmd {
    case "ping":
        say("pong \(protocolVersion) \(desktop().trusted ? 1 : 0)")
    case "prompt":
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        say("ok")
    case "read":
        read(options(Array(parts.dropFirst())))
    case "tree":
        tree(options(Array(parts.dropFirst())))
    case "quit":
        done()
        exit(0)
    default:
        say("err unknown")
    }
    done()
}
