#!/bin/zsh
# Собирает помощника для значков рабочего стола и «замораживает» его в Resources/SugrobIcons.app.
#
#   tools/icons-helper/freeze.sh --yes
#
# Запускать ТОЛЬКО когда помощника действительно нужно изменить.
#
# macOS привязывает разрешение «Универсальный доступ» к подписи программы. У Сугроба нет сертификата
# разработчика, его подпись — это отпечаток самого файла, и он меняется с каждой сборкой. Поэтому
# помощник не пересобирается вместе с приложением: build.sh кладёт в каждую сборку один и тот же
# готовый файл из Resources/SugrobIcons.app, байт в байт. Пока он не менялся, система узнаёт его
# после обновления и разрешение остаётся. Этот скрипт файл меняет — значит, у всех, кто включил снег
# на значках, разрешение сбросится, и им придётся выдать его заново.
#
# Исходник помощника — Sources/SugrobIcons/main.swift. Всё, что может понадобиться менять (какие
# значки считать, как понимать их форму), живёт в самом Сугробе, а не в нём.
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT=Resources/SugrobIcons.app
WORK=build/icons-helper
if [[ "${1:-}" != "--yes" ]]; then
    print -u2 -- "Пересборка помощника сбросит «Универсальный доступ» у всех, кто включил снег на значках."
    print -u2 -- "Если это действительно нужно: tools/icons-helper/freeze.sh --yes"
    exit 1
fi

swift build -c release --arch arm64 --arch x86_64 --product SugrobIcons
BIN=.build/apple/Products/Release/SugrobIcons

APP=$WORK/SugrobIcons.app
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources $WORK/full.iconset $WORK/small.iconset
cp -f $BIN $APP/Contents/MacOS/SugrobIcons
strip -x $APP/Contents/MacOS/SugrobIcons
cp -f tools/icons-helper/Info.plist $APP/Contents/Info.plist
# Значок — чтобы в списке «Универсального доступа» помощник выглядел как Сугроб. Только мелкие размеры.
iconutil -c iconset Resources/AppIcon.icns -o $WORK/full.iconset
for f in icon_16x16.png icon_16x16@2x.png icon_32x32.png icon_32x32@2x.png icon_128x128.png; do
    cp -f $WORK/full.iconset/$f $WORK/small.iconset/$f
done
iconutil -c icns $WORK/small.iconset -o $APP/Contents/Resources/AppIcon.icns

xattr -cr $APP
codesign --force --sign - --identifier local.sugrob.icons $APP
codesign --verify --strict $APP

# Раскладываем поверх прежнего: набор файлов тот же, так что удалять ничего не нужно.
ditto $APP $OUT
codesign --verify --strict $OUT
echo "Заморожен: $OUT"
codesign -dvvv $OUT 2>&1 | grep -E "^(Identifier|CDHash|Signature)="
codesign -d -r- $OUT 2>&1 | grep designated
echo "Закоммитьте Resources/SugrobIcons.app. Дальше в каждую сборку пойдёт именно этот файл."
