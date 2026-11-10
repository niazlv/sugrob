#!/bin/zsh
# Выпускает новую версию Сугроба на GitHub Releases, откуда её берёт автообновление.
#
#   ./release.sh 1.2 "Что нового"
#
# Что делает:
#   1. поднимает CFBundleVersion (приложения ставят только сборку новее своей)
#      и ставит версию в Resources/Info.plist;
#   2. собирает универсальную сборку (./build.sh --dist);
#   3. подписывает update.json ключом ~/.config/sugrob/ota-ed25519.key (tools/ota_sign.swift);
#   4. коммитит Info.plist, ставит тег v<версия>, пушит;
#   5. создаёт релиз с Sugrob.zip и update.json и проверяет, что GitHub отдаёт именно их.
#
# Нужны: gh (gh auth login), чистое рабочее дерево, ключ подписи. Установленные копии
# принимают только подпись этим ключом — без него выпустить обновление нельзя.
set -euo pipefail
cd "$(dirname "$0")"

PLIST=Resources/Info.plist
OUT=build/release
pb() { /usr/libexec/PlistBuddy -c "$1" "${2:-$PLIST}"; }
die() { print -u2 -- "$*"; exit 1; }

VERSION=${1:-}
NOTES=${2:-Исправления и улучшения}
[[ $VERSION =~ '^[0-9]+(\.[0-9]+)*$' ]] || die "Укажите версию: ./release.sh 1.2 \"Что нового\""
TAG=v$VERSION

# Репозиторий — тот, откуда приложение берёт обновления.
REPO=$(grep -o 'github\.com/[^/"]*/[^/"]*/releases/latest/download/update\.json' Sources/Sugrob/Updater.swift \
       | cut -d/ -f2-3 | head -1)
[[ -n $REPO ]] || die "В Updater.swift не найден адрес github.com/<владелец>/<репо>/releases/latest/download/update.json"
ZIP_URL=https://github.com/$REPO/releases/download/$TAG/Sugrob.zip
FEED=https://github.com/$REPO/releases/latest/download/update.json

# Ключ подписи должен совпадать с ключом, вшитым в приложение.
mkdir -p .build
if [[ ! -x .build/ota-sign || tools/ota_sign.swift -nt .build/ota-sign ]]; then
    swiftc -O tools/ota_sign.swift -o .build/ota-sign
fi
PUB=$(.build/ota-sign pub)
grep -qF "\"$PUB\"" Sources/Sugrob/Updater.swift || die "Публичный ключ в Updater.swift не совпадает с ключом подписи"

command -v gh >/dev/null || die "Нужен gh: brew install gh && gh auth login"
gh auth status >/dev/null 2>&1 || die "gh не залогинен: gh auth login"
[[ -z $(git status --porcelain) ]] || die "Есть незакоммиченные изменения — сначала закоммитьте их"
git fetch -q origin
[[ $(git rev-list --count HEAD..@{u}) == 0 ]] || die "Ветка отстаёт от origin — сначала git pull"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "Тег $TAG уже есть — выберите другую версию"
[[ -z $(git ls-remote --tags origin "refs/tags/$TAG") ]] || die "Тег $TAG уже есть на GitHub"

BUILD=$(( $(pb "Print :CFBundleVersion") + 1 ))
MINOS=$(pb "Print :LSMinimumSystemVersion")
pb "Set :CFBundleShortVersionString $VERSION"
pb "Set :CFBundleVersion $BUILD"
undo() { git checkout -q -- $PLIST; }
echo "== Сугроб $VERSION ($BUILD) → $REPO"

./build.sh --dist || { undo; die "Сборка не удалась, Info.plist возвращён"; }
[[ $(pb "Print :CFBundleVersion" build/dist/Sugrob.app/Contents/Info.plist) == $BUILD ]] || { undo; die "В сборке не тот номер"; }

mkdir -p $OUT
cp -f build/Sugrob.zip $OUT/Sugrob.zip
.build/ota-sign manifest $OUT/Sugrob.zip "$VERSION" $BUILD "$MINOS" "$NOTES" "$ZIP_URL" > $OUT/update.json
.build/ota-sign verify $OUT/update.json $OUT/Sugrob.zip || { undo; die "Манифест не проходит проверку"; }

git commit -q -m "Сугроб $VERSION ($BUILD)" -- $PLIST
git tag "$TAG"
git push -q origin HEAD "$TAG"
gh release create "$TAG" --repo "$REPO" --verify-tag --title "Сугроб $VERSION" --notes "$NOTES" \
    $OUT/Sugrob.zip $OUT/update.json

curl -fsSL --max-time 30 "$FEED" | cmp -s - $OUT/update.json || die "GitHub отдаёт не тот update.json"
[[ $(curl -fsSL --max-time 120 "$ZIP_URL" | shasum -a 256 | cut -c1-64) == $(shasum -a 256 $OUT/Sugrob.zip | cut -c1-64) ]] \
    || die "GitHub отдаёт не тот архив"
echo "Опубликовано: https://github.com/$REPO/releases/tag/$TAG"

# Необязательный шаг на этой машине (не в git), например зеркало манифеста.
if [[ -x ./release.local.sh ]]; then ./release.local.sh $OUT/update.json $OUT/Sugrob.zip; fi
