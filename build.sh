#!/bin/zsh
# Собирает Сугроб.
#   ./build.sh         — build/Sugrob.app под этот Mac, для проверки
#   ./build.sh --dist  — универсальная (arm64 + x86_64) build/dist/Sugrob.app и build/Sugrob.zip для раздачи
# Выпуск обновления — ./release.sh (он сам вызывает --dist).
set -e
cd "$(dirname "$0")"
if [[ "$1" == "--dist" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN=.build/apple/Products/Release/Sugrob
    APP=build/dist/Sugrob.app
else
    swift build -c release
    BIN=.build/release/Sugrob
    APP=build/Sugrob.app
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ ! -f Resources/AppIcon.icns ]]; then
    swift tools/make_icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
# Через временный файл и mv: запущенный Сугроб держит старый файл и не падает.
put() { cp -f "$1" "$2.tmp" && mv -f "$2.tmp" "$2"; }
put "$BIN" "$APP/Contents/MacOS/Sugrob"
put Resources/Info.plist "$APP/Contents/Info.plist"
put Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Переводы: Resources/<язык>.lproj/{Localizable,InfoPlist}.strings → Contents/Resources/<язык>.lproj
# (обязательно до codesign; автообновление ставит приложение целиком, так что они доезжают вместе с ним).
for f in Resources/*.lproj/*.strings(N); do
    mkdir -p "$APP/Contents/Resources/${f:h:t}"
    put "$f" "$APP/Contents/Resources/${f:h:t}/${f:t}"
done
if [[ "$1" == "--dist" ]]; then
    # Только предупреждение: нехватка перевода не мешает сборке, приложение покажет английский текст.
    tools/l10n_check.sh || echo "Предупреждение: переводы расходятся с en (см. выше). Сборка продолжается."
fi
xattr -cr "$APP"
codesign --force --sign - "$APP" 2>/dev/null || { xattr -lr "$APP"; echo "подпись не удалась"; exit 1; }
if [[ "$1" == "--dist" ]]; then
    ditto -c -k --norsrc --noextattr --noacl --keepParent "$APP" build/Sugrob.zip.tmp
    mv -f build/Sugrob.zip.tmp build/Sugrob.zip
    echo "Готово: $PWD/$APP и $PWD/build/Sugrob.zip"
else
    echo "Готово: $PWD/$APP"
fi
