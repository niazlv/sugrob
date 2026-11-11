import Foundation

/// Надписи интерфейса. Единственная точка входа — `tr("ключ", аргументы…)`.
///
/// Строки лежат в Resources/<язык>.lproj/Localizable.strings (build.sh кладёт их в Contents/Resources).
/// Ключ — стабильный английский идентификатор вроде `menu.pause`; текст по-английски лежит в en.lproj.
/// Язык выбирает система по CFBundleLocalizations из Info.plist, для незнакомого языка берётся английский.
/// Если в выбранном языке ключа нет, показывается английский текст, а не ключ: новая надпись, которую
/// ещё не успели перевести, ничего не ломает. Ключ выводится только если его нет и в en.lproj.
/// Подстановки — как в String(format:); при двух и более аргументах порядок пишется `%1$@`, `%2$@`,
/// чтобы в языке с другим порядком слов его можно было переставить. Числа в подстановки передаём
/// готовой строкой (`%@`), а не `%d`.
/// Новая надпись: `tr("ключ")` в коде + строка `"ключ" = "текст";` в Localizable.strings каждого языка
/// (сверка — tools/l10n_check.sh).
enum L10n {
    /// Откуда брать строки. Приложение — Bundle.main; проверки подменяют (папка <язык>.lproj тоже годится).
    static var bundle: Bundle = .main

    /// Язык, который выбрала система среди доступных (например "de", "zh-Hans"), для дат и т. п.
    static var language: String = Bundle.main.preferredLocalizations.first ?? "en"

    static var locale: Locale { Locale(identifier: language) }

    /// Английские строки — запасной вариант на случай, когда в выбранном языке ключа нет.
    static var fallback: [String: String] = {
        guard let url = bundle.url(forResource: "Localizable", withExtension: "strings",
                                   subdirectory: nil, localization: "en"),
              let d = NSDictionary(contentsOf: url) as? [String: String] else { return [:] }
        return d
    }()

    private static let missing = "\u{1}missing\u{1}"

    static func string(_ key: String) -> String {
        let s = bundle.localizedString(forKey: key, value: missing, table: nil)
        if s != missing && !s.isEmpty { return s }
        return fallback[key] ?? key
    }
}

/// Локализованная надпись по ключу, с подстановками (`%@`, `%1$@`…), если они есть.
func tr(_ key: String, _ args: CVarArg...) -> String {
    let format = L10n.string(key)
    return args.isEmpty ? format : String(format: format, arguments: args)
}
