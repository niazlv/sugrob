import AppKit
import IOKit.pwr_mgt

/// Кто сейчас показывает видео.
///
/// Содержимое чужих окон приложению не видно (и разрешение «Запись экрана» ради этого просить не хочется),
/// поэтому признак косвенный: пока идёт видео, проигрыватель просит систему не гасить экран.
/// Так делают браузеры (только для видео на видимой вкладке — музыка в фоне экран не держит), плееры,
/// видеозвонки, презентации. Список таких просьб система отдаёт без всяких разрешений.
enum VideoWatch {
    private static var cached: Set<Int> = []
    private static var readAt: CFTimeInterval = -100

    /// Процессы, по чьей просьбе экран сейчас не гаснет. Обновляется не чаще раза в секунду.
    static func pids() -> Set<Int> {
        let now = CACurrentMediaTime()
        if now - readAt < 1 { return cached }
        readAt = now
        cached = read()
        return cached
    }

    private static func read() -> Set<Int> {
        var ref: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&ref) == kIOReturnSuccess,
              let all = ref?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        var out = Set<Int>()
        for (owner, list) in all {
            for a in list {
                let type = a["AssertionTrueType"] as? String ?? a["AssertType"] as? String ?? ""
                guard type == "PreventUserIdleDisplaySleep" || type == "NoDisplaySleepAssertion" else { continue }
                if let level = a["AssertLevel"] as? NSNumber, level.intValue == 0 { continue }
                // просьбу мог подать системный посредник от имени приложения
                let pid = (a["AssertionOnBehalfOfPID"] as? NSNumber)?.intValue ?? owner.intValue
                out.insert(pid)
                if let app = hostApp(of: pid) { out.insert(app) }
            }
        }
        return out
    }

    /// Вспомогательный процесс (отрисовка страницы, декодер) окон не имеет — окна у приложения,
    /// внутри которого он лежит. Возвращает это приложение; nil — процесс сам себе хозяин.
    private static let responsible: (@convention(c) (pid_t) -> pid_t)? = {
        guard let s = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(s, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    private static func hostApp(of pid: Int) -> Int? {
        guard let responsible else { return nil }
        let host = Int(responsible(pid_t(pid)))
        guard host > 0, host != pid else { return nil }
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid_t(pid), &buf, UInt32(buf.count)) > 0 else { return nil }
        let path = String(cString: buf)
        // Только то, что лежит внутри самого приложения или служит ему: `caffeinate -d` в терминале
        // не должен объявлять «видео» все окна терминала.
        if path.contains(".xpc/") { return host }
        if let bundle = NSRunningApplication(processIdentifier: pid_t(host))?.bundleURL?.path,
           path.hasPrefix(bundle + "/") { return host }
        return nil
    }
}

/// Рамка минус вырез: до четырёх прямоугольников вокруг него.
func subtractRect(_ r: CGRect, _ cut: CGRect) -> [CGRect] {
    let c = r.intersection(cut)
    if c.isNull || c.width <= 0 || c.height <= 0 { return [r] }
    var out: [CGRect] = []
    if c.minY > r.minY { out.append(CGRect(x: r.minX, y: r.minY, width: r.width, height: c.minY - r.minY)) }
    if c.maxY < r.maxY { out.append(CGRect(x: r.minX, y: c.maxY, width: r.width, height: r.maxY - c.maxY)) }
    if c.minX > r.minX { out.append(CGRect(x: r.minX, y: c.minY, width: c.minX - r.minX, height: c.height)) }
    if c.maxX < r.maxX { out.append(CGRect(x: c.maxX, y: c.minY, width: r.maxX - c.maxX, height: c.height)) }
    return out
}

/// Где снег не рисуется: видимые части окон, в которых идёт видео (в координатах слоя `frame`).
/// Снег как будто идёт позади такого окна: снежинки за ним пропадают и появляются снизу, сугроб
/// у нижнего края экрана за ним не виден. Шапка на самом окне и всё, что лежит на окнах перед ним
/// и на Dock, остаётся.
/// - wins: окна от переднего к заднему; capped: номера окон, на которых лежит снег;
/// - dock: полоса Dock (от её верха и ниже), если она на экране; floating: видео поверх всех окон;
/// - dip: насколько шапка у скруглённых углов заходит на само окно.
func videoZones(_ wins: [WinInfo], floating: [CGRect] = [], capped: Set<Int>, dock: CGRect? = nil,
                frame: CGRect, dip: CGFloat) -> [CGRect] {
    guard !floating.isEmpty || wins.contains(where: { $0.video }) else { return [] }
    let capH: CGFloat = 64                              // сколько оставить над окном под его шапку
    var zones: [CGRect] = []
    for (i, w) in wins.enumerated() where w.video {
        let top = w.top + (capped.contains(w.id) ? dip : 0)
        var parts = [CGRect(x: w.left, y: top, width: w.right - w.left, height: w.rect.maxY - top)]
        for j in 0..<i {
            let f = wins[j]
            let cap = capped.contains(f.id)
            if f.video && !cap { continue }             // переднее окно с видео закрыто своей зоной
            let cut = f.video ? CGRect(x: f.left - 4, y: f.top - capH, width: f.right - f.left + 8, height: capH + dip)
                              : CGRect(x: f.rect.minX - (cap ? 4 : 0), y: f.rect.minY - (cap ? capH : 0),
                                       width: f.rect.width + (cap ? 8 : 0), height: f.rect.height + (cap ? capH : 0))
            parts = parts.flatMap { subtractRect($0, cut) }
            if parts.isEmpty { break }
        }
        if let d = dock {                               // Dock и снег на нём — перед окнами
            let cut = CGRect(x: d.minX - 4, y: d.minY - capH, width: d.width + 8, height: d.height + capH)
            parts = parts.flatMap { subtractRect($0, cut) }
        }
        zones += parts
    }
    zones += floating
    return zones.compactMap {
        let r = $0.intersection(frame)
        return r.isNull || r.width < 2 || r.height < 2 ? nil : r.offsetBy(dx: -frame.minX, dy: -frame.minY)
    }
}
