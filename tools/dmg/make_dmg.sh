#!/bin/zsh
# Собирает установочный образ Sugrob.dmg: окно с фоном, значок приложения и папка «Программы».
#
#   tools/dmg/make_dmg.sh                          — из build/dist/Sugrob.app в build/Sugrob.dmg
#   tools/dmg/make_dmg.sh Sugrob.app out.dmg       — из указанного приложения
#   tools/dmg/make_dmg.sh Sugrob.zip out.dmg       — из архива релиза (в нём лежит Sugrob.app)
#
# Окно оформляется без Finder и без AppleScript: расположение значков и фон пишет dmgbuild прямо
# в .DS_Store, поэтому сборка работает и без сеанса пользователя, и не просит прав на управление
# Finder. dmgbuild ставится при первом запуске в .build/dmgbuild-venv (версии — в requirements.txt),
# фон рисует tools/dmg/make_background.swift. Нужны python3 и swiftc.
set -euo pipefail
cd "$(dirname "$0")/../.."
HERE=tools/dmg
SRC=${1:-build/dist/Sugrob.app}
OUT=${2:-build/Sugrob.dmg}
VENV=.build/dmgbuild-venv
die() { print -u2 -- "$*"; exit 1; }

[[ -e $SRC ]] || die "Нет $SRC. Соберите приложение: ./build.sh --dist"
mkdir -p .build build "$(dirname "$OUT")"
# рабочая папка постоянная и в .gitignore (build/): ничего не удаляем, файлы просто перезаписываются
TMP=build/dmg-work
mkdir -p "$TMP/mnt"
trap 'hdiutil detach -quiet "$TMP/mnt" 2>/dev/null || true' EXIT

# приложение: из архива или как есть
if [[ $SRC == *.zip ]]; then
    ditto -x -k "$SRC" "$TMP/app"
    APP=$TMP/app/Sugrob.app
else
    APP=$SRC
fi
[[ -d $APP/Contents/MacOS ]] || die "$APP не похоже на приложение"
codesign --verify --deep --strict "$APP" 2>/dev/null || die "Подпись $APP не проходит проверку"
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")

# dmgbuild в своём venv
if [[ ! -x $VENV/bin/dmgbuild ]]; then
    command -v python3 >/dev/null || die "Нужен python3"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q --disable-pip-version-check -r $HERE/requirements.txt
fi

# фон: пересобираем рисовалку, только если исходник новее
if [[ ! -x .build/dmg-background || $HERE/make_background.swift -nt .build/dmg-background ]]; then
    swiftc -O $HERE/make_background.swift -o .build/dmg-background
fi
.build/dmg-background "$TMP/bg" >/dev/null

ICON=Resources/AppIcon.icns
[[ -f $ICON ]] || ICON=$APP/Contents/Resources/AppIcon.icns
"$VENV/bin/dmgbuild" -s $HERE/settings.py -D app="$APP" -D bg="$TMP/bg" -D icon="$ICON" Sugrob "$OUT" >/dev/null

# проверяем собранное: образ целый, внутри приложение той же версии и ссылка на /Applications
hdiutil verify -quiet "$OUT" || die "Образ не проходит проверку"
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$TMP/mnt" "$OUT" >/dev/null
[[ $(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$TMP/mnt/Sugrob.app/Contents/Info.plist") == $VER ]] || die "В образе не та версия"
codesign --verify --deep --strict "$TMP/mnt/Sugrob.app" || die "Подпись приложения в образе не проходит проверку"
[[ $(readlink "$TMP/mnt/Applications") == /Applications ]] || die "В образе нет ссылки на /Applications"
[[ -f $TMP/mnt/.DS_Store && -e $TMP/mnt/.background.tiff ]] || die "В образе нет оформления окна"
hdiutil detach -quiet "$TMP/mnt"

echo "Готово: $OUT (Сугроб $VER, $(du -h "$OUT" | cut -f1), sha256 $(shasum -a 256 "$OUT" | cut -c1-16)…)"
