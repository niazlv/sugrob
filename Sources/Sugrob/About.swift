import AppKit

/// Окно «О Сугробе»: стандартная панель macOS — значок, название и версию она берёт из Info.plist.
/// От себя добавляем подпись и ссылки: исходники, сайт и поддержка. Адресов для переводов здесь нет:
/// они живут на сайте, чтобы их можно было менять без выпуска новой версии.
enum AboutPanel {
    /// Как подписан разработчик: латиницей во всех языках, не переводится.
    static let developer = "niazlv (Niiaz Leushkin)"
    static let author = URL(string: "https://github.com/niazlv")!
    static let source = URL(string: "https://github.com/niazlv/sugrob")!
    static let site = URL(string: "https://niazlv.github.io/sugrob/")!
    static let support = URL(string: "https://niazlv.github.io/sugrob/#support")!

    /// Окно «О программе» отводит под подпись фиксированное место (по высоте около 140 pt при ширине около 268 pt).
    /// Если текст не влез, оно превращает подпись в прокручиваемое поле и обрезает конец. Переводы разной длины,
    /// поэтому берём первый стиль, при котором подпись помещается: её раскладывает тот же NSLayoutManager,
    /// что и в панели. Русский и английский помещаются в самом первом (прежнем) стиле.
    static func credits() -> NSAttributedString {
        let styles: [(size: CGFloat, para: CGFloat, line: CGFloat)] =
            [(11, 7, 1), (11, 5, 1), (11, 3, 0), (10, 3, 0), (10, 2, 0), (9, 2, 0)]
        var out = build(styles[0])
        for st in styles {
            out = build(st)
            if fits(out) { break }
        }
        return out
    }

    private static func fits(_ s: NSAttributedString) -> Bool {
        let storage = NSTextStorage(attributedString: s)
        let layout = NSLayoutManager()
        let box = NSTextContainer(size: NSSize(width: 264, height: 1_000_000))
        layout.addTextContainer(box)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: box)
        return layout.usedRect(for: box).height <= 140
    }

    private static func build(_ style: (size: CGFloat, para: CGFloat, line: CGFloat)) -> NSAttributedString {
        let par = NSMutableParagraphStyle()
        par.alignment = .center
        par.paragraphSpacing = style.para
        par.lineSpacing = style.line
        let font = NSFont.systemFont(ofSize: style.size)
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
        // \u{2028} — перенос строки внутри абзаца: между такими строками нет абзацного отступа.
        // В строках перевода такой перенос записан как \n, чтобы переводчик сам решал, где разорвать.
        func soft(_ key: String) -> String { tr(key).replacingOccurrences(of: "\n", with: "\u{2028}") }
        text(soft("about.tagline") + "\n")
        text(soft("about.free") + "\n", dim: true)
        // «Разработчик: niazlv (Niiaz Leushkin)»: ссылка стоит на месте %@, чтобы в любом языке слова шли
        // в своём порядке. Ник и имя не переводятся.
        let by = tr("about.author").components(separatedBy: "%@")
        text(by[0], dim: true)
        link(developer, author)
        text(by.count > 1 ? by[1] : "", dim: true)
        text("\n")
        link(tr("about.source"), source)
        text("  ·  ", dim: true)
        link(tr("about.site"), site)
        text("\n")
        text(tr("about.support.lead") + "\u{2028}", dim: true)
        link(tr("about.support.link"), support)
        return out
    }

    static func show() {
        // приложение живёт в строке меню и не бывает активным само — без этого окно осталось бы позади
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits()])
    }
}
