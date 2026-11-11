#!/bin/bash
# Собирает ядро Сугроба в WebAssembly и кладёт его в site/sugrob.wasm.
#
# Нужен тулчейн swift.org (Swift из Xcode в wasm не собирает) и Swift SDK для WebAssembly той же версии:
#   https://www.swift.org/documentation/articles/wasm-getting-started.html
# Пути можно переопределить: SUGROB_SWIFT (исполняемый файл swift), SUGROB_WASM_SDK (имя SDK).
set -euo pipefail
cd "$(dirname "$0")"

VER=6.4.2
SWIFT="${SUGROB_SWIFT:-$HOME/Library/Developer/Toolchains/swift-$VER-RELEASE.xctoolchain/usr/bin/swift}"
SDK="${SUGROB_WASM_SDK:-swift-$VER-RELEASE_wasm}"
[ -x "$SWIFT" ] || SWIFT=swift

# Снимок ядра: те же файлы, что в приложении. Меняется одна строка — вместо Foundation
# подключается libc для wasm, а недостающее (часы, форматирование) даёт Bridge/Shim.swift.
OUT=Sources/SugrobWeb
mkdir -p "$OUT"
for f in Sim People PeopleHome PeopleRescue PeopleFun Wind; do
    sed 's/^import Foundation$/import WASILibc/' "../Sources/Sugrob/$f.swift" > "$OUT/$f.swift"
done
cp Bridge/Bridge.swift Bridge/Shim.swift "$OUT/"
echo "// Точка входа не нужна: модуль собирается как библиотека (reactor), страница зовёт sg_*." > "$OUT/main.swift"

"$SWIFT" build --swift-sdk "$SDK" -c release --product SugrobWeb \
    -Xswiftc -Xclang-linker -Xswiftc -mexec-model=reactor \
    -Xlinker --export-if-defined=__main_argc_argv \
    -Xlinker --strip-all

WASM="$("$SWIFT" build --swift-sdk "$SDK" -c release --show-bin-path)/SugrobWeb.wasm"
cp "$WASM" site/sugrob.wasm
ls -l site/sugrob.wasm
