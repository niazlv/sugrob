#!/usr/bin/env python3
"""Карточки с QR-кодами для блока «Поддержать» в README: docs/donate-*.png.

    python3 tools/readme-media/donate_cards.py

Нужны opencv-python и Pillow. QR-коды строятся локально (адреса никуда не отправляются),
а готовая картинка тут же читается обратно: если из неё не получился ровно тот же адрес,
скрипт падает и ничего не оставляет.

Адреса заданы здесь; в README.md и README.ru.md они продублированы текстом — меняйте вместе.
"""
import random
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "docs"

CARDS = [
    # файл, название, подпись, цвет метки, адрес
    ("btc", "Bitcoin", "BTC", (247, 147, 26), "bc1qyt9hzvtd69t5jkk7h39fqd4pz7tg9jl9pq4arf"),
    ("eth", "Ethereum", "ETH · ERC-20", (98, 126, 234), "0xBA10A984A88AeE82A2D3b30EA6d91BC554D46A25"),
    ("bnb", "BNB Chain", "BNB · BEP-20", (243, 186, 47), "0xBA10A984A88AeE82A2D3b30EA6d91BC554D46A25"),
    ("sol", "Solana", "SOL", (20, 241, 149), "9GhoGBorb8xvkUjFgGfrcFun1m6ad9K9chDUhvagXYwX"),
    ("trx", "Tron", "TRX · TRC-20", (235, 0, 41), "TKyahQhTeLdMraKDbedLz17jorRTfER8xX"),
]

S = 2                       # картинка вдвое крупнее, чем показывается
W, H = 176 * S, 226 * S     # карточка
CAP = 16 * S                # место над карточкой под снежную шапку
VOX = 3 * S                 # «воксель» снега
NAVY = (27, 40, 94)
PLATE = (244, 247, 255)
INK = (14, 22, 58)


def font(size, bold=False):
    for path, index in (("/System/Library/Fonts/HelveticaNeue.ttc", 1 if bold else 0),
                        ("/System/Library/Fonts/Helvetica.ttc", 1 if bold else 0)):
        try:
            return ImageFont.truetype(path, size, index=index)
        except OSError:
            continue
    return ImageFont.load_default()


def qr_matrix(text):
    enc = cv2.QRCodeEncoder.create()            # коррекция ошибок по умолчанию, версия подбирается сама
    img = enc.encode(text)
    # encode отдаёт картинку с полями; сводим её к матрице модулей
    ys, xs = np.where(img < 128)
    img = img[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    run = 1
    while img[0, run] < 128:                    # верхний левый угол — сплошная полоса в 7 модулей
        run += 1
    m = run // 7
    return img[m // 2::m, m // 2::m] < 128


def snow_cap(d, rng, x0, x1, base):
    """Шапка из кубиков по верхнему краю карточки — как на окнах в приложении."""
    cols = (x1 - x0) // VOX
    h, heights = 3.0, []
    for c in range(cols):
        h += rng.uniform(-0.9, 0.9)
        h = max(1.6, min(5.0, h))
        edge = min(c, cols - 1 - c)
        heights.append(max(0, min(round(h), edge)))     # к краям шапка сходит на нет
    for c, n in enumerate(heights):
        for k in range(n):
            # голубоватый, а не чисто белый: на светлой теме GitHub шапка тоже должна читаться
            shade = rng.choice([(236, 242, 255), (224, 233, 252)]) if k == n - 1 \
                else rng.choice([(205, 219, 247), (190, 207, 242), (178, 197, 238)])
            x, y = x0 + c * VOX, base + VOX - (k + 1) * VOX     # нижний ряд лежит на самой карточке
            d.rectangle([x, y, x + VOX - 1, y + VOX - 1], fill=shade)


def card(name, sub, dot, addr, seed):
    rng = random.Random(seed)
    img = Image.new("RGBA", (W, H + CAP), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    top = CAP
    d.rounded_rectangle([0, top, W - 1, top + H - 1], radius=14 * S, fill=NAVY)
    # заголовок: цветная метка и название сети
    f1, f2 = font(15 * S, bold=True), font(11 * S)
    tw = d.textlength(name, font=f1)
    x = (W - (tw + 16 * S)) / 2
    cy = top + 22 * S
    d.ellipse([x, cy - 4 * S, x + 8 * S, cy + 4 * S], fill=dot)
    d.text((x + 16 * S, cy), name, font=f1, fill=(255, 255, 255), anchor="lm")
    # QR на светлой плашке
    q = qr_matrix(addr)
    n = q.shape[0]
    side = 144 * S
    quiet = 3
    mod = side // (n + 2 * quiet)
    code = mod * n
    px, py = (W - side) // 2, top + 40 * S
    d.rounded_rectangle([px, py, px + side - 1, py + side - 1], radius=8 * S, fill=PLATE)
    ox, oy = px + (side - code) // 2, py + (side - code) // 2
    for r in range(n):
        for c in range(n):
            if q[r, c]:
                d.rectangle([ox + c * mod, oy + r * mod, ox + (c + 1) * mod - 1, oy + (r + 1) * mod - 1], fill=INK)
    d.text((W / 2, top + H - 20 * S), sub, font=f2, fill=(175, 192, 238), anchor="mm")
    snow_cap(d, rng, 10 * S, W - 10 * S, top + S)
    return img


def decode(img):
    flat = Image.new("RGB", img.size, (255, 255, 255))
    flat.paste(img, mask=img.split()[3])
    text, _, _ = cv2.QRCodeDetector().detectAndDecode(cv2.cvtColor(np.array(flat), cv2.COLOR_RGB2GRAY))
    return text


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    done = []
    for i, (slug, name, sub, dot, addr) in enumerate(CARDS):
        img = card(name, sub, dot, addr, seed=20261111 + i)
        got = decode(img)
        if got != addr:
            sys.exit(f"{slug}: QR читается как {got!r}, а должен быть {addr!r} — ничего не записано")
        done.append((OUT / f"donate-{slug}.png", img))
    for path, img in done:
        img.save(path, optimize=True)
        print(f"{path.name}: {img.size[0]}x{img.size[1]}, QR проверен")


if __name__ == "__main__":
    main()
