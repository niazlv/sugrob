import WASILibc

// Ядро симуляции (Sim, People*, Wind) в приложении импортирует Foundation, но берёт оттуда
// только часы, час суток и форматирование строк для журналов. В браузерной сборке Foundation
// не подключается (он на порядок увеличил бы файл) — здесь лежат замены ровно под эти вызовы.

struct Date {
    var timeIntervalSince1970: Double
    init() {
        var tv = timeval()
        gettimeofday(&tv, nil)
        timeIntervalSince1970 = Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6
    }
}

/// Час суток по часам посетителя: его сообщает страница (см. sg_hour).
var webLocalHour = 12

struct Calendar {
    enum Component { case hour }
    static let current = Calendar()
    func component(_ c: Component, from d: Date) -> Int { webLocalHour }
}

struct ProcessInfo {
    static let processInfo = ProcessInfo()
    var environment: [String: String] { [:] }
}

extension String {
    /// Только для отладочных журналов ядра: в браузере они не нужны, подстановки не делаются.
    init(format: String, _ args: Any...) { self = format }
}

// Замер времени шага ветра (только для профилирования в тестах приложения).
let CLOCK_THREAD_CPUTIME_ID = 0
func clock_gettime_nsec_np(_ id: Int) -> UInt64 { 0 }
