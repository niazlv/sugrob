// QR-код прямо на странице: байтовый режим, уровень коррекции Q (восстанавливает до четверти кода —
// поэтому в середину можно положить значок сети), версии 1–6, чего хватает на адрес любого кошелька.
// Устройство кода — по стандарту ISO/IEC 18004. После правок здесь код нужно прочитать обратно
// независимым читателем, в том числе с закрытой серединой (см. web/README.md).

// Версия -> коррекция на блок, блоки [сколько, байтов данных], центр выравнивающего узора. Уровень Q.
const VERSIONS = {
  1: { ec: 13, groups: [[1, 13]], align: 0 },
  2: { ec: 22, groups: [[1, 22]], align: 18 },
  3: { ec: 18, groups: [[2, 17]], align: 22 },
  4: { ec: 26, groups: [[2, 24]], align: 26 },
  5: { ec: 18, groups: [[2, 15], [2, 16]], align: 30 },
  6: { ec: 24, groups: [[4, 19]], align: 34 },
};

// умножение в поле GF(2^8) по модулю x^8 + x^4 + x^3 + x^2 + 1
function mul(x, y) {
  let z = 0;
  for (let i = 7; i >= 0; i--) {
    z = (z << 1) ^ ((z >>> 7) * 0x11d);
    z ^= ((y >>> i) & 1) * x;
  }
  return z & 0xff;
}

// байты коррекции Рида — Соломона для одного блока
function reedSolomon(data, degree) {
  const div = new Array(degree).fill(0);
  div[degree - 1] = 1;
  let root = 1;
  for (let i = 0; i < degree; i++) {
    for (let j = 0; j < degree; j++) {
      div[j] = mul(div[j], root);
      if (j + 1 < degree) div[j] ^= div[j + 1];
    }
    root = mul(root, 2);
  }
  const rem = new Array(degree).fill(0);
  for (const b of data) {
    const factor = b ^ rem.shift();
    rem.push(0);
    for (let i = 0; i < degree; i++) rem[i] ^= mul(div[i], factor);
  }
  return rem;
}

/** Матрица кода для строки. Возвращает { size, dark(x, y) }. */
export function qrMatrix(text) {
  const bytes = [...new TextEncoder().encode(text)];
  let version = 0, spec = null, dataLen = 0;
  for (let v = 1; v <= 6; v++) {
    const s = VERSIONS[v];
    const n = s.groups.reduce((a, [count, len]) => a + count * len, 0);
    if (bytes.length + 2 <= n) { version = v; spec = s; dataLen = n; break; }    // 4 бита режима + 8 бит длины
  }
  if (!version) throw new Error('QR: строка слишком длинная');

  // поток битов: режим, длина, данные, конец, добивка
  const bits = [];
  const put = (value, n) => { for (let i = n - 1; i >= 0; i--) bits.push((value >>> i) & 1); };
  put(4, 4);
  put(bytes.length, 8);
  for (const b of bytes) put(b, 8);
  put(0, Math.min(4, dataLen * 8 - bits.length));
  while (bits.length % 8) bits.push(0);
  const data = [];
  for (let i = 0; i < bits.length; i += 8) data.push(bits.slice(i, i + 8).reduce((a, b) => (a << 1) | b, 0));
  for (let pad = 0xec; data.length < dataLen; pad ^= 0xec ^ 0x11) data.push(pad);

  // блоки и их коррекция, затем перемешивание: по байту от каждого блока по очереди
  const blocks = [];
  let at = 0;
  for (const [count, len] of spec.groups) {
    for (let i = 0; i < count; i++) {
      const d = data.slice(at, at + len);
      at += len;
      blocks.push({ d, e: reedSolomon(d, spec.ec) });
    }
  }
  const stream = [];
  const longest = Math.max(...blocks.map(b => b.d.length));
  for (let i = 0; i < longest; i++) for (const b of blocks) if (i < b.d.length) stream.push(b.d[i]);
  for (let i = 0; i < spec.ec; i++) for (const b of blocks) stream.push(b.e[i]);

  const size = version * 4 + 17;
  const mod = Array.from({ length: size }, () => new Array(size).fill(false));
  const fixed = Array.from({ length: size }, () => new Array(size).fill(false));     // служебные модули
  const set = (x, y, dark) => { mod[y][x] = dark; fixed[y][x] = true; };

  // поисковые узоры по трём углам, с белой каймой
  for (const [cx, cy] of [[3, 3], [size - 4, 3], [3, size - 4]]) {
    for (let dy = -4; dy <= 4; dy++) for (let dx = -4; dx <= 4; dx++) {
      const x = cx + dx, y = cy + dy;
      if (x < 0 || y < 0 || x >= size || y >= size) continue;
      const d = Math.max(Math.abs(dx), Math.abs(dy));
      set(x, y, d !== 2 && d !== 4);
    }
  }
  // выравнивающий узор
  if (spec.align) {
    for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) {
      set(spec.align + dx, spec.align + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
    }
  }
  // синхронизация
  for (let i = 8; i < size - 8; i++) {
    if (!fixed[6][i]) set(i, 6, i % 2 === 0);
    if (!fixed[i][6]) set(6, i, i % 2 === 0);
  }

  // сведения о формате: уровень Q (биты 11) и номер маски, с собственной защитой
  function drawFormat(mask) {
    const d = (3 << 3) | mask;
    let rem = d;
    for (let i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
    const f = ((d << 10) | rem) ^ 0x5412;
    const bit = i => ((f >>> i) & 1) === 1;
    for (let i = 0; i <= 5; i++) set(8, i, bit(i));
    set(8, 7, bit(6));
    set(8, 8, bit(7));
    set(7, 8, bit(8));
    for (let i = 9; i < 15; i++) set(14 - i, 8, bit(i));
    for (let i = 0; i < 8; i++) set(size - 1 - i, 8, bit(i));
    for (let i = 8; i < 15; i++) set(8, size - 15 + i, bit(i));
    set(8, size - 8, true);
  }
  drawFormat(0);        // пока только занять место

  // данные: змейкой парами столбцов снизу вверх и обратно, справа налево
  let k = 0;
  for (let right = size - 1; right >= 1; right -= 2) {
    if (right === 6) right = 5;
    for (let vert = 0; vert < size; vert++) {
      for (let j = 0; j < 2; j++) {
        const x = right - j;
        const upward = ((right + 1) & 2) === 0;
        const y = upward ? size - 1 - vert : vert;
        if (!fixed[y][x] && k < stream.length * 8) {
          mod[y][x] = ((stream[k >>> 3] >>> (7 - (k & 7))) & 1) === 1;
          k++;
        }
      }
    }
  }

  const MASKS = [
    (x, y) => (x + y) % 2 === 0,
    (x, y) => y % 2 === 0,
    (x, y) => x % 3 === 0,
    (x, y) => (x + y) % 3 === 0,
    (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0,
    (x, y) => (x * y) % 2 + (x * y) % 3 === 0,
    (x, y) => ((x * y) % 2 + (x * y) % 3) % 2 === 0,
    (x, y) => ((x + y) % 2 + (x * y) % 3) % 2 === 0,
  ];
  const applyMask = m => {
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
      if (!fixed[y][x] && MASKS[m](x, y)) mod[y][x] = !mod[y][x];
    }
  };

  // штраф за рисунок, который трудно читать: длинные полосы, квадраты 2×2, ложные поисковые узоры, перекос цвета
  function penalty() {
    let p = 0;
    const line = get => {
      let run = 1;
      for (let i = 1; i <= size; i++) {
        if (i < size && get(i) === get(i - 1)) { run++; continue; }
        if (run >= 5) p += run - 2;
        run = 1;
      }
      for (let i = 0; i + 10 < size; i++) {
        const s = j => get(i + j);
        const core = j => s(j) && !s(j + 1) && s(j + 2) && s(j + 3) && s(j + 4) && !s(j + 5) && s(j + 6);
        if ((core(0) && !s(7) && !s(8) && !s(9) && !s(10)) || (!s(0) && !s(1) && !s(2) && !s(3) && core(4))) p += 40;
      }
    };
    for (let y = 0; y < size; y++) line(i => mod[y][i]);
    for (let x = 0; x < size; x++) line(i => mod[i][x]);
    let dark = 0;
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
      if (mod[y][x]) dark++;
      if (x + 1 < size && y + 1 < size && mod[y][x] === mod[y][x + 1] && mod[y][x] === mod[y + 1][x] && mod[y][x] === mod[y + 1][x + 1]) p += 3;
    }
    p += Math.floor(Math.abs(dark * 20 - size * size * 10) / (size * size)) * 10;
    return p;
  }

  let best = 0, bestPenalty = Infinity;
  for (let m = 0; m < 8; m++) {
    applyMask(m);
    drawFormat(m);
    const p = penalty();
    if (p < bestPenalty) { bestPenalty = p; best = m; }
    applyMask(m);       // маска обратима: повторное наложение её снимает
  }
  applyMask(best);
  drawFormat(best);

  return { size, version, mask: best, dark: (x, y) => x >= 0 && y >= 0 && x < size && y < size && mod[y][x] };
}

/** Сколько модулей в середине закрывает значок (сторона квадрата). */
export const LOGO_MODULES = 7;

/**
 * Код в виде SVG: модули со скруглёнными наружными углами, сливаются в сплошные «острова».
 * logo — разметка значка 24×24, который ложится в середину на белую плашку.
 */
export function qrSvg(text, { color = '#101737', logo = '', quiet = 2 } = {}) {
  const q = qrMatrix(text);
  const n = q.size, c = n / 2, half = LOGO_MODULES / 2;
  const hidden = (x, y) => logo && Math.abs(x + 0.5 - c) < half && Math.abs(y + 0.5 - c) < half;
  const dark = (x, y) => q.dark(x, y) && !hidden(x, y);
  const r = 0.44;
  let d = '';
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
    if (!dark(x, y)) continue;
    const l = dark(x - 1, y), rt = dark(x + 1, y), u = dark(x, y - 1), dn = dark(x, y + 1);
    const tl = !l && !u ? r : 0, tr = !rt && !u ? r : 0, br = !rt && !dn ? r : 0, bl = !l && !dn ? r : 0;
    const X = x + quiet, Y = y + quiet;
    d += `M${X + tl} ${Y}H${X + 1 - tr}` + (tr ? `a${r} ${r} 0 0 1 ${r} ${r}` : '')
      + `V${Y + 1 - br}` + (br ? `a${r} ${r} 0 0 1 ${-r} ${r}` : '')
      + `H${X + bl}` + (bl ? `a${r} ${r} 0 0 1 ${-r} ${-r}` : '')
      + `V${Y + tl}` + (tl ? `a${r} ${r} 0 0 1 ${r} ${-r}` : '') + 'Z';
  }
  const side = n + quiet * 2;
  let mark = '';
  if (logo) {
    const s = LOGO_MODULES - 1.2, o = side / 2 - s / 2;
    mark = `<g transform="translate(${o} ${o}) scale(${s / 24})">${logo}</g>`;
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${side} ${side}" role="img"><path fill="${color}" d="${d}"/>${mark}</svg>`;
}
