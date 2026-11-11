#!/bin/zsh
# Проверка локализации интерфейса (Resources/<язык>.lproj/*.strings).
#
#   tools/l10n_check.sh
#
# Что проверяет (эталон — en.lproj):
#   1. plutil -lint для каждого .strings;
#   2. во всех языках тот же набор ключей, что в en (нет недостающих и лишних), значения не пустые;
#   3. у одного ключа во всех языках те же подстановки (%@, %d, %1$@, %2$@… — позиционная и обычная
#      запись считаются одинаковыми, если порядок тот же);
#   4. папки .lproj совпадают с CFBundleLocalizations в Resources/Info.plist;
#   5. каждый ключ из tr("…") в Sources/Sugrob/*.swift есть в en (иначе на экране будет сам ключ).
# Ещё сообщает (не ошибка), какие ключи en нигде в коде не встречаются.
# Код возврата: 0 — всё сошлось, 1 — есть расхождения. build.sh --dist вызывает скрипт как
# предупреждение и не останавливается: нехватка перевода безопасна, приложение покажет английский текст.
cd "$(dirname "$0")/.." || exit 2

RES=Resources
bad=0
note() { print -u2 -- "l10n: $*"; }

dirs=($RES/*.lproj(N))
[[ ${#dirs} -gt 0 ]] || { note "нет папок $RES/*.lproj"; exit 1; }
[[ -d $RES/en.lproj ]] || { note "нет эталона $RES/en.lproj"; exit 1; }

# 1. синтаксис
for f in $RES/*.lproj/*.strings(N); do
    out=$(plutil -lint "$f" 2>&1) || { note "plutil: $out"; bad=1; }
done

# 2–5. содержимое
command -v python3 >/dev/null || { note "нет python3, содержимое не проверено"; exit $bad; }
python3 -I - "$RES" "$bad" <<'PY' || bad=1
import glob, json, os, plistlib, re, subprocess, sys

res, bad = sys.argv[1], int(sys.argv[2])
problems = []

def load(path):
    out = subprocess.run(["plutil", "-convert", "json", "-o", "-", "--", path], capture_output=True, text=True)
    if out.returncode != 0:
        return None
    return json.loads(out.stdout)

PH = re.compile(r"%(?:(\d+)\$)?[-+ 0#]*\d*(?:\.\d+)?(?:hh|h|ll|l|z|q)?([@dDuUxXoOfeEgGcCsSaAp])")

def placeholders(s):
    s = s.replace("%%", "")
    seq, out = 0, []
    for m in PH.finditer(s):
        if m.group(1):
            idx = int(m.group(1))
        else:
            seq += 1
            idx = seq
        out.append((idx, m.group(2)))
    return sorted(out)

langs = sorted(os.path.basename(d)[:-6] for d in glob.glob(os.path.join(res, "*.lproj")))
tables = sorted(os.path.basename(f)[:-8] for f in glob.glob(os.path.join(res, "en.lproj", "*.strings")))
data = {}
for lang in langs:
    for t in tables:
        p = os.path.join(res, lang + ".lproj", t + ".strings")
        if not os.path.exists(p):
            problems.append("%s: нет файла %s.strings" % (lang, t))
            continue
        d = load(p)
        if d is None:
            continue                         # синтаксис уже ругался в plutil -lint
        data[(lang, t)] = d

for t in tables:
    ref = data.get(("en", t))
    if ref is None:
        continue
    for lang in langs:
        if lang == "en" or (lang, t) not in data:
            continue
        d = data[(lang, t)]
        for k in sorted(set(ref) - set(d)):
            problems.append("%s/%s: нет ключа %s" % (lang, t, k))
        for k in sorted(set(d) - set(ref)):
            problems.append("%s/%s: лишний ключ %s (нет в en)" % (lang, t, k))
        for k in sorted(set(ref) & set(d)):
            if not d[k].strip():
                problems.append("%s/%s: пустое значение %s" % (lang, t, k))
            elif placeholders(d[k]) != placeholders(ref[k]):
                problems.append("%s/%s: подстановки %s не совпадают с en: %r и %r" % (lang, t, k, d[k], ref[k]))

# CFBundleLocalizations <-> папки
try:
    plist = plistlib.load(open(os.path.join(res, "Info.plist"), "rb"))
    declared = sorted(plist.get("CFBundleLocalizations", []))
    if declared != langs:
        problems.append("CFBundleLocalizations %s не совпадает с папками %s" % (declared, langs))
    if plist.get("CFBundleDevelopmentRegion") != "en":
        problems.append("CFBundleDevelopmentRegion должен быть en")
except Exception as e:
    problems.append("Info.plist: %s" % e)

# ключи из кода
src = ""
for f in glob.glob("Sources/Sugrob/*.swift"):
    src += "".join(l for l in open(f, encoding="utf8") if not l.lstrip().startswith("//")) + "\n"
en = data.get(("en", "Localizable"), {})
used = set(re.findall(r'\btr\(\s*"([^"]+)"', src))
for k in sorted(used - set(en)):
    problems.append("в коде tr(\"%s\"), а в en.lproj/Localizable.strings ключа нет" % k)
unused = [k for k in sorted(en) if '"%s"' % k not in src]
if unused:
    print("l10n: ключи есть в en, но в коде не встречаются: " + ", ".join(unused), file=sys.stderr)

for p in problems:
    print("l10n: " + p, file=sys.stderr)
if not problems:
    print("l10n: порядок — %d язык(ов), ключей: %d" % (len(langs), len(en)), file=sys.stderr)
sys.exit(1 if problems else 0)
PY
exit $bad
