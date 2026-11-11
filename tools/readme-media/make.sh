#!/bin/zsh
# Снимает анимации для README и кладёт их в docs/*.webp.
#   tools/readme-media/make.sh             — все сцены
#   tools/readme-media/make.sh hero tree   — только названные
# Сцены: hero, snowman, people, tree, storm, village (описаны в Demo.swift рядом).
#
# В приложение съёмка не входит. Скрипт копирует исходники в .build-readme/ (папка в .gitignore),
# добавляет туда Demo.swift и ключ --demo, собирает копию и гоняет симуляцию без экрана.
# Нужен img2webp: brew install webp.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${SUGROB_ROOT:-$(cd "$HERE/../.." && pwd)}"
OUT="${SUGROB_MEDIA_OUT:-$ROOT/docs}"
WORK="$ROOT/.build-readme"
command -v img2webp >/dev/null || { echo "нужен img2webp: brew install webp"; exit 1; }

mkdir -p "$WORK/pkg" "$WORK/frames" "$OUT"
rsync -a --delete --exclude .build "$ROOT/Package.swift" "$ROOT/Sources" "$WORK/pkg/"
cp "$HERE/Demo.swift" "$WORK/pkg/Sources/Sugrob/Demo.swift"
MAIN="$WORK/pkg/Sources/Sugrob/main.swift"
perl -0pi -e 's/(let args = CommandLine\.arguments\n)/$1if let i = args.firstIndex(of: "--demo") {\n    let dir = i + 1 < args.count ? args[i + 1] : "."\n    exit(Demo.run(outDir: dir, args: Array(args.dropFirst(i + 2))))\n}\n/' "$MAIN"
grep -q -- '--demo' "$MAIN" || { echo "main.swift изменился: не нашёл, куда вставить --demo"; exit 1; }
(cd "$WORK/pkg" && swift build -c release 2>&1 | grep -E "error|warning: unre|Compiling|Build" || true)
BIN="$WORK/pkg/.build/release/Sugrob"
[[ -x "$BIN" ]] || { echo "сборка не удалась"; exit 1; }

if (( $# )); then scenes=("$@"); else scenes=(hero snowman people tree storm village); fi
for s in $scenes; do
    "$BIN" --demo "$WORK/frames" "$s"
    # 20 кадров в секунду. -kmax 1 делает каждый кадр независимым: по умолчанию ключевой кадр один,
    # и на длинной анимации Chromium на каждом кадре пересчитывает цепочку от начала — клип идёт
    # в разы медленнее, чем записан. С потерями: без них снегопад раздувает файл в разы.
    img2webp -loop 0 -kmax 1 -lossy -q 75 -m 4 -d 50 "$WORK/frames/$s"/f*.png -o "$OUT/$s.webp" | tail -1
done
ls -lh "$OUT"/*.webp
