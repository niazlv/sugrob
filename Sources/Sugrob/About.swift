import AppKit

/// Окно «О Сугробе»: стандартная панель macOS — значок, название и версию она берёт из Info.plist.
/// От себя добавляем подпись и ссылки: исходники, сайт и поддержка. Адресов для переводов здесь нет:
/// они живут на сайте, чтобы их можно было менять без выпуска новой версии.
enum AboutPanel {
    static let author = URL(string: "https://github.com/niazlv")!
    static let source = URL(string: "https://github.com/niazlv/sugrob")!
    static let site = URL(string: "https://niazlv.github.io/sugrob/")!
    static let support = URL(string: "https://niazlv.github.io/sugrob/#support")!

    static func credits() -> NSAttributedString {
        let par = NSMutableParagraphStyle()
        par.alignment = .center
        par.paragraphSpacing = 7
        par.lineSpacing = 1
        let font = NSFont.systemFont(ofSize: 11)
        let out = NSMutableAttributedString()
        func text(_ s: String, dim: Bool = false) {
            out.append(NSAttributedString(string: s, attributes: [
                .font: font, .paragraphStyle: par,
                .foregroundColor: dim ? NSColor.secondaryLabelColor : NSColor.labelColor,
            ]))
        }
        func link(_ s: String, _ url: URL) {
            out.append(NSAttributedString(string: s, attributes: [.font: font, .paragraphStyle: par, .link: url]))
        }
        // \u{2028} — перенос строки внутри абзаца: между такими строками нет абзацного отступа
        text("Снег с настоящей физикой\u{2028}на рабочем столе Mac.\n")
        text("Бесплатно, без рекламы и подписок.\u{2028}Открытый код, лицензия MIT.\n", dim: true)
        text("Автор — ", dim: true)
        link("@niazlv", author)
        text("\n")
        link("Исходный код", source)
        text("  ·  ", dim: true)
        link("Сайт и демо в браузере", site)
        text("\n")
        text("Если Сугроб вас порадовал и не жалко —\u{2028}", dim: true)
        link("поддержите автора копейкой", support)
        return out
    }

    static func show() {
        // приложение живёт в строке меню и не бывает активным само — без этого окно осталось бы позади
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits()])
    }
}
