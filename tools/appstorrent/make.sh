#!/bin/zsh
# Собирает пакет заявки для каталога приложений appstorrent: один архив со всем, что они просят
# (описание, поля карточки, иконка 1024×1024, фон 742×360 в двойном размере, скриншоты).
#
#   tools/appstorrent/make.sh              — рисует кадры заново и собирает архив
#   tools/appstorrent/make.sh --no-render  — берёт кадры из прошлого запуска (build/appstorrent/raw)
#
# Результат: build/appstorrent/Sugrob-appstorrent-<версия>.zip
#
# Кадры снимает та же симуляция без экрана, что рисует анимации для README (tools/readme-media):
# сцены на нарисованном рабочем столе, а не снимки живого экрана. Исходники берутся из HEAD
# (git archive), так что чужие незакоммиченные правки в сборку не попадают. Папки .build-appstorrent
# нет в git (.build*/ в .gitignore), для каждого коммита своя, ничего не удаляется.
# Скриншоты — одного размера (1350×840) и без альфа-канала, как просит каталог.
set -euo pipefail
HERE=${0:A:h}
ROOT=${HERE:h:h}
cd "$ROOT"
OUT=build/appstorrent
RAW=$OUT/raw
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
PKG=$OUT/Sugrob-appstorrent-$VER
die() { print -u2 -- "$*"; exit 1; }
mkdir -p "$RAW" "$PKG/screenshots"

if [[ ${1:-} != --no-render ]]; then
    REV=$(git rev-parse --short HEAD)
    WORK=$ROOT/.build-appstorrent/$REV
    if [[ ! -x $WORK/.build/release/Sugrob ]]; then
        mkdir -p "$WORK"
        git archive HEAD Package.swift Sources | tar -x -C "$WORK"
        cp tools/readme-media/Demo.swift "$WORK/Sources/Sugrob/Demo.swift"
        cp "$HERE/Shots.swift" "$WORK/Sources/Sugrob/Shots.swift"
        D=$WORK/Sources/Sugrob/Demo.swift
        perl -0pi -e 's/\("hero", hero\),/("shot-hero", shotHero), ("shot-snowman", shotSnowman), ("shot-people", shotPeople), ("shot-storm", shotStorm), ("shot-village", shotVillage), ("shot-tree", shotTree), ("shot-cover", shotCover), ("hero", hero),/' "$D"
        grep -q shotCover "$D" || die "Demo.swift изменился: не нашёл список сцен"
        M=$WORK/Sources/Sugrob/main.swift
        perl -0pi -e 's/(let args = CommandLine\.arguments\n)/$1if let i = args.firstIndex(of: "--demo") {\n    let dir = i + 1 < args.count ? args[i + 1] : "."\n    exit(Demo.run(outDir: dir, args: Array(args.dropFirst(i + 2))))\n}\n/' "$M"
        grep -q -- '--demo' "$M" || die "main.swift изменился: не нашёл, куда вставить --demo"
        (cd "$WORK" && swift build -c release 2>&1 | tail -3)
    fi
    BIN=$WORK/.build/release/Sugrob
    [[ -x $BIN ]] || die "Сборка не удалась"
    for s in shot-hero shot-snowman shot-people shot-storm shot-village shot-tree shot-cover; do
        "$BIN" --demo "$RAW" $s >/dev/null || die "Сцена $s не снялась"
    done
fi

# иконка: из .icns приложения берём вариант 1024×1024
iconutil -c iconset Resources/AppIcon.icns -o "$RAW/icon.iconset"
cp "$RAW/icon.iconset/icon_512x512@2x.png" "$PKG/icon.png"

python3 -I - "$RAW" "$PKG" <<'EOF'
import sys
from PIL import Image
raw, pkg = sys.argv[1], sys.argv[2]

def flat(im):
    """Без альфа-канала: кадры и так непрозрачные, проверяем это, а не молча выбрасываем."""
    if im.mode == "RGBA":
        assert im.getchannel("A").getextrema() == (255, 255), "в кадре есть прозрачность"
    return im.convert("RGB")

# обложка: 1760×856 → 1484×720 (742×360 в двойном размере)
cover = flat(Image.open(f"{raw}/cover-wide.png"))
cover = cover.crop((0, 2, cover.width, 2 + 854)).resize((1484, 720), Image.LANCZOS)
cover.save(f"{pkg}/background.png", optimize=True)

shots = [
    ("01-brush",   "hero-brush",   None),                     # весь экран → 1350×840
    ("02-scatter", "hero-scatter", None),
    ("03-storm",   "storm",        None),
    ("04-snowman", "snowman",      (450, 280, 1800, 1120)),   # врезка 1350×840 из экрана 1800×1120
    ("05-ladder",  "people-climb", (450, 280, 1800, 1120)),
    ("06-tree",    "tree",         (450, 280, 1800, 1120)),
    ("07-village", "village",      None),
]
for name, src, box in shots:
    im = flat(Image.open(f"{raw}/{src}.png"))
    im = im.crop(box) if box else im.resize((1350, 840), Image.LANCZOS)
    assert im.size == (1350, 840), (name, im.size)
    im.save(f"{pkg}/screenshots/{name}.png", optimize=True)
print("кадры готовы:", len(shots), "скриншотов, обложка", cover.size)
EOF

cp "$HERE/description.ru.txt" "$PKG/description.txt"
cat > "$PKG/info.txt" <<INFO
Название: Сугроб (Sugrob)
Версия: $VER
Разработчик: niazlv (Niiaz Leushkin)
Языки интерфейса: русский, английский, немецкий, испанский, французский, португальский, китайский (упрощённый), японский; выбирается язык системы, для остальных английский. Переводы кроме русского сделаны с помощью ИИ
Системные требования: macOS 13 Ventura и новее
Архитектурная совместимость: ARM (Apple Silicon) и x86_64 (Intel), универсальная сборка
Лицензия: MIT, открытый исходный код
Цена: бесплатно, без рекламы, подписок и скрытых платежей

Репозиторий: https://github.com/niazlv/sugrob
Changelog: https://github.com/niazlv/sugrob/releases
Ссылка на скачивание: https://github.com/niazlv/sugrob/releases/latest/download/Sugrob.dmg
Сайт с демо в браузере: https://niazlv.github.io/sugrob/

Файлы:
  description.txt   полное описание (чистый текст, без эмодзи и ссылок)
  icon.png          иконка 1024x1024
  background.png    изображение для фона 1484x720 (742x360 в двойном размере)
  screenshots/      7 снимков 1350x840, без альфа-канала
INFO

ZIP=$OUT/Sugrob-appstorrent-$VER.zip
ditto -c -k --norsrc --noextattr --noacl --keepParent "$PKG" "$ZIP.tmp"
mv -f "$ZIP.tmp" "$ZIP"
echo "Готово: $ROOT/$ZIP ($(du -h "$ZIP" | cut -f1))"
