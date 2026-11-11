// Загрузка ядра Сугроба (sugrob.wasm) и тонкая обёртка над его вызовами.
// Модулю нужен минимум WASI: часы, случайные числа и вывод в консоль. Файлов и окружения у него нет.

function wasi(getMem) {
  const dec = new TextDecoder();
  let line = '';
  const view = () => new DataView(getMem().buffer);
  const ok = () => 0, badf = () => 8;
  return {
    args_get: ok,
    args_sizes_get(argc, size) { const v = view(); v.setUint32(argc, 0, true); v.setUint32(size, 0, true); return 0; },
    environ_get: ok,
    environ_sizes_get(n, size) { const v = view(); v.setUint32(n, 0, true); v.setUint32(size, 0, true); return 0; },
    clock_time_get(id, precision, out) {
      const ms = id === 0 ? Date.now() : performance.now();
      view().setBigUint64(out, BigInt(Math.round(ms * 1e6)), true);
      return 0;
    },
    random_get(ptr, len) {
      const b = new Uint8Array(getMem().buffer, ptr, len);
      for (let i = 0; i < len; i += 65536) crypto.getRandomValues(b.subarray(i, Math.min(len, i + 65536)));
      return 0;
    },
    fd_write(fd, iovs, n, written) {
      const v = view();
      let total = 0;
      for (let i = 0; i < n; i++) {
        const p = v.getUint32(iovs + i * 8, true), l = v.getUint32(iovs + i * 8 + 4, true);
        line += dec.decode(new Uint8Array(getMem().buffer, p, l));
        total += l;
      }
      let k;
      while ((k = line.indexOf('\n')) >= 0) { console.log(line.slice(0, k)); line = line.slice(k + 1); }
      v.setUint32(written, total, true);
      return 0;
    },
    fd_close: ok,
    fd_fdstat_get(fd, out) {
      const v = view();
      v.setUint8(out, 2); v.setUint16(out + 2, 0, true);
      v.setBigUint64(out + 8, 0n, true); v.setBigUint64(out + 16, 0n, true);
      return 0;
    },
    fd_prestat_get: badf,
    fd_prestat_dir_name: badf,
    fd_read: badf,
    fd_seek: badf,
    path_open: badf,
    proc_exit(code) { throw new Error('sugrob.wasm exited: ' + code); },
  };
}

export const SET = {
  weather: 0, wind: 1, depth: 2, autoFill: 3, openOnly: 4, floor: 5, sweep: 6, aging: 7,
  people: 8, ladders: 9, stay: 10, storms: 11, events: 12, peopleSize: 13, agingRate: 14,
};
export const ACT = { storm: 0, summon: 1, clearPeople: 2, fill: 3, shovel: 4 };
export const TASK = { ladder: 0, tunnel: 1, igloo: 2, angel: 3, sled: 4, tree: 5, cornice: 6 };

export async function loadEngine(source) {
  let memory;
  const imports = { wasi_snapshot_preview1: wasi(() => memory) };
  let instance;
  if (source instanceof ArrayBuffer || ArrayBuffer.isView(source)) {
    ({ instance } = await WebAssembly.instantiate(source, imports));
  } else {
    const res = fetch(source);
    try {
      ({ instance } = await WebAssembly.instantiateStreaming(res, imports));
    } catch (e) {
      // сервер отдал файл не как application/wasm — собираем из байтов
      ({ instance } = await WebAssembly.instantiate(await (await fetch(source)).arrayBuffer(), imports));
    }
  }
  const x = instance.exports;
  memory = x.memory;
  x._initialize();
  x.sg_hour(new Date().getHours());

  const eng = {
    W: 0, H: 0, flags: 0,
    init(w, h, cell) { x.sg_init(w, h, cell); eng.W = x.sg_dim(0); eng.H = x.sg_dim(1); },
    set(key, v) { x.sg_set(key, +v); },
    action(k) { x.sg_action(k); },
    /** wins: [{id, x, y, w, h, shown}] от переднего к заднему; dock: {x0, x1, top, r} или null */
    windows(wins, menuBar, radius, dock, dt) {
      x.sg_win_begin();
      for (const w of wins) x.sg_win_add(w.id, w.x, w.y, w.w, w.h, w.shown ? 1 : 0);
      if (dock) x.sg_win_end(menuBar, radius, dock.x0, dock.x1, dock.top, dock.r, dt);
      else x.sg_win_end(menuBar, radius, 0, 0, -1, 0, dt);
    },
    cursor(px, py, on) { x.sg_cursor(px, py, on ? 1 : 0); },
    hands(key, down) { x.sg_hands(key ? 1 : 0, down ? 1 : 0); },
    step(dt, steps = 1) { eng.flags = x.sg_step(dt, steps); return eng.flags; },
    /** стартовая сцена: слежавшийся снег на полу и горки в точках x1, x2 (отрицательное — нет) */
    scene(x1, x2) { x.sg_scene(x1, x2); },
    /** поручение человечкам (TASK); true — взялись или возьмутся */
    task(k) { return x.sg_task(k) === 1; },
    age(minutes) { x.sg_age(minutes); },
    jobs() { const a = []; for (let k = 0; k < 10; k++) a.push(x.sg_jobs(k)); return a; },
    built() { return [x.sg_built(0), x.sg_built(1), x.sg_built(2), x.sg_built(3)]; },
    hour(h) { x.sg_hour(h); },
    people() { return x.sg_people(); },
    // Массивы кадра. Смотрят прямо в память wasm, поэтому берутся заново каждый кадр:
    // память может вырасти, и прежние представления станут недействительны.
    grid(k) { return new Uint8Array(memory.buffer, x.sg_ptr(k), eng.W * eng.H); },
    parts() { const n = x.sg_count(0); return n ? new Float32Array(memory.buffer, x.sg_ptr(3), n * 4) : null; },
    balls() {
      const n = x.sg_count(1);
      return { n, under: x.sg_count(2), data: n ? new Float32Array(memory.buffer, x.sg_ptr(4), n * 12) : null };
    },
    px() { const n = x.sg_count(3); return n ? new Float32Array(memory.buffer, x.sg_ptr(5), n * 8) : null; },
    memoryBytes() { return memory.buffer.byteLength; },
  };
  return eng;
}
