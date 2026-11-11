// Рабочий стол-демонстрация: нарисованные окна, строка меню и Dock, поверх которых идёт
// настоящий снег Сугроба (ядро приложения в sugrob.wasm, отрисовка в render.js).

import { loadEngine, SET, ACT, TASK } from './engine.js';
import { createRenderer } from './render.js';
import { qrSvg } from './qr.js';
import { NET_ICONS } from './net-icons.js';

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];

// ---------- тексты

const T = {
  ru: {
    title: 'Сугроб — снег с настоящей физикой на рабочем столе Mac',
    name: 'Сугроб',
    tagline: 'Снег с настоящей физикой на рабочем столе Mac.',
    lead: 'Это не видео: в этой вкладке работает движок приложения — тот же код на Swift, собранный в WebAssembly. Окна здесь нарисованные, а снег настоящий.',
    lead_m: 'Проведите по нему курсором.', lead_t: 'Проведите по нему пальцем.',
    download: 'Скачать для macOS',
    source: 'Исходный код',
    meta: 'Бесплатно · открытый код, MIT · macOS 13 и новее',
    mitten: 'Варежка',
    w_hero: 'Сугроб', w_try: 'Что попробовать', w_engine: 'Под капотом', w_people: 'Человечки',
    w_donate: 'Поддержать', support: 'Поддержать проект',
    dn_title: 'Сугроб бесплатный',
    dn_intro: 'Без рекламы и подписок. Если он вас порадовал и не жалко — переведите доллар-другой. Не обязательно, но приятно.',
    dn_low: 'самая низкая комиссия',
    dn_credit: 'Значки Bitcoin, Ethereum, Solana и BNB:',
    dn_warn: 'В кошельке выберите ту же сеть, что и здесь: перевод в другой сети не дойдёт.',
    dn_copy: 'Нажмите, чтобы скопировать адрес', dn_copied: 'Адрес скопирован',
    dn_select: 'Адрес выделен — скопируйте его (⌘C или Ctrl+C)',
    dn_bnb: 'Подойдут BNB, USDT и другие токены этой сети.',
    dn_trx: 'Подойдут TRX и USDT в сети Tron.',
    dn_sol: 'Подойдут SOL и токены сети Solana.',
    dn_eth: 'Тот же адрес работает в Base, Arbitrum, Optimism, Polygon и Linea.',
    dn_btc: 'Обычный адрес Bitcoin (Native SegWit).',
    pp_intro: 'Обычно они сами решают, чем заняться. Здесь им можно подсказать: возьмётся тот, кто свободен.',
    t_summon: 'Позвать ещё', t_ladder: 'Строить лестницу', t_tunnel: 'Рыть тоннель', t_igloo: 'Строить иглу',
    t_angel: 'Снежный ангел', t_tree: 'Принести ёлку', t_sled: 'Санки', t_cornice: 'Снег с карниза',
    a_people: 'Дать им дело',
    time: 'Время', age: 'Снег полежал 5 минут',
    r_none: 'Пока никого нет — позовите.',
    r_now: 'Сейчас', r_built: 'Построено',
    j0: 'лестница', j1: 'тоннель', j2: 'иглу и хозяйство', j3: 'снеговик', j4: 'снежки', j5: 'ангел', j6: 'санки', j7: 'ёлка', j8: 'беда', j9: 'гуляют',
    b0: 'лестниц', b1: 'иглу', b2: 'тоннелей', b3: 'ёлок',
    no_ladder: 'Лестницу ставить некуда: нужен свободный бок окна, под которым нет Dock и других окон, и снег рядом.',
    no_tunnel: 'Рыть сейчас негде: нужен высокий сугроб, а рядом ложбина для входа. Выберите в меню «Снег» сугробы «Огромные» или насыпьте снег.',
    no_sled: 'Для санок нужен склон: окно со снегом и свободный спуск рядом.',
    no_tree: 'Ёлку сейчас поставить некуда.',
    no_cornice: 'На карнизах пока мало снега, чтобы он сорвался.',
    ok_ladder: 'Понесут снег к окну и сложат ступени — это пара минут. Время можно ускорить.',
    ok_tunnel: 'Ближайший свободный пойдёт рыть ход под самым толстым сугробом. Свод может и сесть.',
    ok_igloo: 'Двое взрослых выберут место и начнут резать блоки.',
    ok_angel: 'Сейчас кто-нибудь упадёт в снег.',
    ok_tree: 'Несут ёлку.', ok_sled: 'Поехали.', ok_cornice: 'Берегись!',
    aged: 'Снег слежался: плотный держит форму, наст курсором уже не взять — только расколоть.',
    s_sweep: 'Смахните снег', s_sweep_d: 'Медленно курсор гонит перед собой вал, резким взмахом — снег разлетается.',
    s_drag: 'Перетащите окно', s_drag_d: 'Возьмите за заголовок: сугроб поедет вместе с окном.',
    s_close: 'Закройте окно', s_close_d: 'Красная кнопка — и снег осыплется. Вернуть окно можно из Dock.',
    s_ball: 'Скатайте снежок',
    s_ball_d: 'Зажмите Shift и тяните мышью по снегу. Отпустите на ходу — полетит.',
    s_ball_t: 'Включите «Варежку» в строке меню и тяните пальцем по снегу. Отпустите на ходу — полетит.',
    s_snowman: 'Слепите снеговика', s_snowman_d: 'Мягко опустите один шар на другой. У верхнего появятся глаза и морковка.',
    s_people: 'Дайте дело человечкам', s_people_d: 'Они уже идут. Попросите построить лестницу к окну, вырыть тоннель или сложить иглу.',
    s_storm: 'Устройте буран', s_storm_d: 'Ветер понесёт позёмку и сорвёт снег с карнизов.',
    a_summon: 'Позвать', a_storm: 'Буран',
    e_intro: 'Около 10 тысяч строк симуляции из приложения собраны в один файл wasm. Цифры ниже — живые.',
    e_engine: 'движок', e_size: 'размер wasm', e_grid: 'сетка', e_step: 'шаг симуляции', e_fps: 'кадров в секунду',
    e_voxels: 'вокселей снега', e_flakes: 'снежинок и комьев', e_people: 'человечков',
    e_app: 'В самом приложении на Mac (M1 Max) это около 2 % процессора, 110 МБ памяти и порядка 1 Вт добавки к питанию всего компьютера, почти всё — на GPU и композитор.',
    e_more: 'Подробности и как мерили',
    mb: ' МБ', ms: ' мс', vox: 'воксель', pt: ' pt',
    m_weather: 'Погода', m_snow: 'Снег', m_people: 'Человечки',
    about: 'О программе', pause: 'Поставить снег на паузу', resume: 'Вернуть зиму',
    light: 'Лёгкий снег', snowfall: 'Снегопад', blizzard: 'Метель',
    wind: 'Ветер', w_ll: '⇐ Сильный влево', w_l: '← Влево', w_0: 'Штиль', w_r: '→ Вправо', w_rr: '⇒ Сильный вправо',
    storms: 'Бураны налетают сами', stormNow: 'Устроить буран сейчас',
    depth: 'Сугробы', d_low: 'Низкие', d_mid: 'Средние', d_high: 'Высокие', d_huge: 'Огромные',
    voxel: 'Размер вокселя', v2: 'Мелкий', v3: 'Средний', v4: 'Крупный', v6: 'Очень крупный',
    autoFill: 'Сугробы растут сами', aging: 'Снег слёживается и подмерзает', sweep: 'Курсор смахивает снег',
    floor: 'Снег внизу экрана', fill: 'Насыпать снег сейчас', shovel: 'Убрать весь снег (лопата)',
    p0: 'Не приходят', p1: 'Заходят редко', p2: 'Заходят иногда', p3: 'Заходят часто',
    ladders: 'Строят лестницы к окнам', stay: 'Могут остаться жить', events: 'Зимние происшествия',
    summon: 'Позвать сейчас', clearPeople: 'Прогнать всех и убрать постройки',
    paused: 'Снег на паузе. Вернуть — в меню «Сугроб».',
    reduced: 'В системе включено «Уменьшение движения», поэтому снег стоит на паузе. Запустить — в меню «Сугроб».',
    noEngine: 'Здесь должна идти живая демонстрация, но этот браузер не запустил WebGL2 или WebAssembly. Приложение от этого не зависит.',
    mittenOn: 'Варежка включена: тяните по снегу, чтобы скатать шар.',
  },
  en: {
    title: 'Sugrob — physically simulated snow for the Mac desktop',
    name: 'Sugrob',
    tagline: 'Physically simulated snow for the Mac desktop.',
    lead: 'This is not a video: the app’s engine is running in this tab — the same Swift code, compiled to WebAssembly. The windows are drawn, the snow is real.',
    lead_m: 'Run your cursor through it.', lead_t: 'Run a finger through it.',
    download: 'Download for macOS',
    source: 'Source code',
    meta: 'Free · open source, MIT · macOS 13 or later',
    mitten: 'Mitten',
    w_hero: 'Sugrob', w_try: 'Things to try', w_engine: 'Under the hood', w_people: 'Little people',
    w_donate: 'Support', support: 'Support the project',
    dn_title: 'Sugrob is free',
    dn_intro: 'No ads, no subscriptions. If it made you smile and you can spare it, send a dollar or two. Entirely optional, always appreciated.',
    dn_low: 'lowest fee',
    dn_credit: 'Bitcoin, Ethereum, Solana and BNB icons by',
    dn_warn: 'Pick the same network in your wallet as the one selected here: a transfer on another network will not arrive.',
    dn_copy: 'Click to copy the address', dn_copied: 'Address copied',
    dn_select: 'Address selected — copy it (⌘C or Ctrl+C)',
    dn_bnb: 'BNB, USDT and other tokens on this network all work.',
    dn_trx: 'TRX and USDT on Tron both work.',
    dn_sol: 'SOL and Solana tokens both work.',
    dn_eth: 'The same address works on Base, Arbitrum, Optimism, Polygon and Linea.',
    dn_btc: 'A regular Bitcoin address (Native SegWit).',
    pp_intro: 'Normally they decide for themselves what to do. Here you can nudge them: whoever is free will take the job.',
    t_summon: 'Call more', t_ladder: 'Build a ladder', t_tunnel: 'Dig a tunnel', t_igloo: 'Build an igloo',
    t_angel: 'Snow angel', t_tree: 'Bring a tree', t_sled: 'Sled', t_cornice: 'Snow off a ledge',
    a_people: 'Give them a job',
    time: 'Time', age: 'Let the snow sit 5 min',
    r_none: 'Nobody here yet — call them.',
    r_now: 'Now', r_built: 'Built',
    j0: 'ladder', j1: 'tunnel', j2: 'igloo and chores', j3: 'snowman', j4: 'snowballs', j5: 'angel', j6: 'sled', j7: 'tree', j8: 'trouble', j9: 'strolling',
    b0: 'ladders', b1: 'igloos', b2: 'tunnels', b3: 'trees',
    no_ladder: 'No place for a ladder: it needs a free window side with no Dock or other windows below, and snow nearby.',
    no_tunnel: 'Nowhere to dig right now: it takes a tall drift with a dip next to it for the entrance. Pick “Huge” drifts in the Snow menu or fill with snow.',
    no_sled: 'A sled needs a slope: a snowy window with a clear run next to it.',
    no_tree: 'No room for a tree right now.',
    no_cornice: 'Not enough snow on the ledges to break off yet.',
    ok_ladder: 'They will carry snow to the window and stack the steps — a couple of minutes. You can speed time up.',
    ok_tunnel: 'The nearest free one will go and dig under the thickest drift. The roof may cave in.',
    ok_igloo: 'Two adults will pick a spot and start cutting blocks.',
    ok_angel: 'Someone is about to drop into the snow.',
    ok_tree: 'Bringing a tree.', ok_sled: 'Off they go.', ok_cornice: 'Look out!',
    aged: 'The snow has packed: dense snow holds its shape, and the crust no longer yields to the cursor — only to a blow.',
    s_sweep: 'Brush the snow off', s_sweep_d: 'Move slowly and the cursor ploughs a ridge; swipe fast and the snow scatters.',
    s_drag: 'Drag a window', s_drag_d: 'Grab the title bar: the drift rides along with the window.',
    s_close: 'Close a window', s_close_d: 'Hit the red button and the snow falls. Bring the window back from the Dock.',
    s_ball: 'Roll a snowball',
    s_ball_d: 'Hold Shift and drag across the snow. Let go mid-swing to throw it.',
    s_ball_t: 'Turn on the Mitten in the menu bar and drag a finger across the snow. Let go mid-swing to throw it.',
    s_snowman: 'Build a snowman', s_snowman_d: 'Gently lower one ball onto another. The top one gets eyes and a carrot.',
    s_people: 'Give the little people a job', s_people_d: 'They are on their way. Ask them to build a ladder to a window, dig a tunnel or put up an igloo.',
    s_storm: 'Start a blizzard', s_storm_d: 'The wind drives the snow along and tears it off the ledges.',
    a_summon: 'Call them', a_storm: 'Blizzard',
    e_intro: 'About ten thousand lines of simulation from the app, compiled into one wasm file. The numbers below are live.',
    e_engine: 'engine', e_size: 'wasm size', e_grid: 'grid', e_step: 'simulation step', e_fps: 'frames per second',
    e_voxels: 'snow voxels', e_flakes: 'flakes and clumps', e_people: 'little people',
    e_app: 'In the Mac app itself (M1 Max) it comes to about 2 % of the CPU, 110 MB of memory and roughly 1 W of extra power for the whole computer, mostly GPU and compositor.',
    e_more: 'Details and how it was measured',
    mb: ' MB', ms: ' ms', vox: 'voxel', pt: ' pt',
    m_weather: 'Weather', m_snow: 'Snow', m_people: 'People',
    about: 'About', pause: 'Pause the snow', resume: 'Bring winter back',
    light: 'Light snow', snowfall: 'Snowfall', blizzard: 'Blizzard',
    wind: 'Wind', w_ll: '⇐ Strong, leftward', w_l: '← Leftward', w_0: 'Calm', w_r: '→ Rightward', w_rr: '⇒ Strong, rightward',
    storms: 'Blizzards roll in on their own', stormNow: 'Start a blizzard now',
    depth: 'Drifts', d_low: 'Low', d_mid: 'Medium', d_high: 'High', d_huge: 'Huge',
    voxel: 'Voxel size', v2: 'Fine', v3: 'Medium', v4: 'Coarse', v6: 'Very coarse',
    autoFill: 'Drifts grow on their own', aging: 'Snow settles and freezes', sweep: 'Cursor brushes snow',
    floor: 'Snow along the bottom', fill: 'Fill with snow now', shovel: 'Clear all snow (shovel)',
    p0: 'Never come', p1: 'Visit rarely', p2: 'Visit sometimes', p3: 'Visit often',
    ladders: 'Build ladders to windows', stay: 'May stay and settle', events: 'Winter incidents',
    summon: 'Call them now', clearPeople: 'Send everyone away, remove buildings',
    paused: 'Snow is paused. Resume it from the Sugrob menu.',
    reduced: 'Reduce Motion is on, so the snow starts paused. Start it from the Sugrob menu.',
    noEngine: 'A live demo should be running here, but this browser did not start WebGL2 or WebAssembly. The app itself does not depend on it.',
    mittenOn: 'Mitten is on: drag across the snow to roll a ball.',
  },
};

let lang = (navigator.language || 'en').toLowerCase().startsWith('ru') ? 'ru' : 'en';
try { lang = localStorage.getItem('sugrob-lang') || lang; } catch (e) { /* хранилище недоступно — язык по браузеру */ }
const t = k => T[lang][k] ?? k;

// ---------- состояние

const S = {
  weather: 1, wind: 0, depth: 3, voxel: 3,      // сугробы сразу огромные: есть где рыть и чему обваливаться
  autoFill: true, aging: true, sweep: true, floor: true, storms: true,
  people: 2, ladders: true, stay: true, events: true,
};
let eng = null, renderer = null;
let paused = false;
let engineBytes = 0;
const desk = $('#desk');
const canvas = $('#snow');
const MB = 30;            // высота строки меню, как --mb в стилях
const RADIUS = 12;        // скругление окон, как --radius
const touchDevice = matchMedia('(hover: none)').matches;
document.documentElement.classList.toggle('is-touch', touchDevice);

// ---------- обои: звёзды и ёлки

(function wallpaper() {
  let s = 20261111;
  const rnd = () => (s = (s * 1664525 + 1013904223) >>> 0) / 4294967296;
  const stars = $('#stars');
  let html = '';
  for (let i = 0; i < 90; i++) {
    const r = 0.4 + rnd() * rnd() * 1.3;
    html += `<circle cx="${(rnd() * 100).toFixed(2)}%" cy="${(rnd() * rnd() * 100).toFixed(2)}%" r="${r.toFixed(2)}" fill="#fff" opacity="${(0.25 + rnd() * 0.65).toFixed(2)}"/>`;
  }
  stars.innerHTML = html;
  let pines = '';
  for (let x = -10; x < 1610; x += 16 + rnd() * 30) {
    const h = 26 + rnd() * 46, w = h * 0.34, base = 388 + Math.sin(x / 190) * 5;
    pines += `<path d="M${x.toFixed(1)} ${(base - h).toFixed(1)} L${(x + w).toFixed(1)} ${base.toFixed(1)} L${(x - w).toFixed(1)} ${base.toFixed(1)}Z"/>`;
  }
  $('#pines').innerHTML = pines;
})();

// ---------- окна

const wins = new Map();       // id -> { id, n, el, x, y, w, h, state: 'open' | 'min' | 'closed' }
let order = [];               // от переднего к заднему
let winsDirty = true;
let arranged = false;          // посетитель сам двигал, открывал или закрывал окна — раскладку больше не трогаем

function place(w) { w.el.style.transform = `translate3d(${Math.round(w.x)}px, ${Math.round(w.y)}px, 0)`; }

function measure(w) { w.w = w.el.offsetWidth; w.h = w.el.offsetHeight; }

function clampWin(w) {
  const vw = innerWidth, vh = innerHeight;
  w.x = Math.min(vw - 90, Math.max(90 - w.w, w.x));
  w.y = Math.min(vh - 60, Math.max(MB + 2, w.y));
}

function restack() {
  order.forEach((id, i) => {
    const w = wins.get(id);
    w.el.style.zIndex = 100 - i;
    w.el.classList.toggle('back', i !== 0);
  });
  for (const b of $$('#dock [data-open]')) b.classList.toggle('run', wins.get(b.dataset.open).state !== 'closed');
  winsDirty = true;
}

function focusWin(id) {
  order = [id, ...order.filter(k => k !== id)];
  restack();
}

function showWin(id) {
  const w = wins.get(id);
  if (w.state !== 'open') {
    w.state = 'open';
    w.el.hidden = false;
    measure(w); clampWin(w); place(w);
    void w.el.offsetWidth;          // зафиксировать исходное состояние, чтобы появление было плавным
    w.el.classList.remove('gone');
  }
  focusWin(id);
}

function hideWin(id, state) {
  const w = wins.get(id);
  w.state = state;
  w.el.classList.add('gone');
  setTimeout(() => { if (w.state !== 'open') w.el.hidden = true; }, 190);
  order = [...order.filter(k => k !== id), id];
  restack();
  if (state === 'closed') mark('close');
}

function initWindows() {
  let n = 1;
  for (const el of $$('.win')) {
    const id = el.dataset.win;
    const w = { id, n: n++, el, x: 0, y: 0, w: 0, h: 0, state: 'open' };
    wins.set(id, w);
    order.push(id);

    el.addEventListener('pointerdown', () => { if (!handsActive()) focusWin(id); }, true);
    $('.close', el).addEventListener('click', () => { arranged = true; hideWin(id, 'closed'); });
    $('.min', el).addEventListener('click', () => { arranged = true; hideWin(id, 'min'); });

    const bar = $('.bar', el);
    let drag = null;
    bar.addEventListener('pointerdown', e => {
      if (e.target.closest('.lights') || handsActive() || e.button > 0) return;
      drag = { id: e.pointerId, dx: e.clientX - w.x, dy: e.clientY - w.y, x0: w.x, y0: w.y };
      bar.setPointerCapture(e.pointerId);
    });
    bar.addEventListener('pointermove', e => {
      if (!drag || e.pointerId !== drag.id) return;
      w.x = e.clientX - drag.dx;
      w.y = e.clientY - drag.dy;
      clampWin(w); place(w);
      winsDirty = true;
    });
    const end = e => {
      if (!drag || e.pointerId !== drag.id) return;
      if (Math.hypot(w.x - drag.x0, w.y - drag.y0) > 4) arranged = true;
      if (Math.hypot(w.x - drag.x0, w.y - drag.y0) > 40) mark('drag');
      drag = null;
    };
    bar.addEventListener('pointerup', end);
    bar.addEventListener('pointercancel', end);
    new ResizeObserver(() => { measure(w); winsDirty = true; }).observe(el);
  }
  for (const b of $$('#dock [data-open]')) {
    b.addEventListener('click', () => {
      const id = b.dataset.open, w = wins.get(id);
      arranged = true;
      if (w.state === 'open' && order[0] === id) hideWin(id, 'min'); else showWin(id);
    });
  }
}

/** Начальная раскладка: окна лесенкой, чтобы у каждого был свободный верхний край под сугроб. */
function layout() {
  const vw = innerWidth, vh = innerHeight;
  const hero = wins.get('hero'), tr = wins.get('try'), en = wins.get('engine'), pe = wins.get('people');
  const narrow = vw < 760;
  hero.el.style.width = narrow ? Math.min(460, vw - 20) + 'px' : '470px';
  tr.el.style.width = narrow ? Math.min(400, vw - 36) + 'px' : '390px';
  en.el.style.width = narrow ? Math.min(360, vw - 36) + 'px' : '360px';
  pe.el.style.width = narrow ? Math.min(380, vw - 28) + 'px' : '350px';
  const dn = wins.get('donate');
  dn.el.style.width = narrow ? Math.min(390, vw - 24) + 'px' : '390px';
  for (const w of wins.values()) { w.el.hidden = false; measure(w); }

  const setState = (w, open) => {
    w.state = open ? 'open' : 'min';
    w.el.hidden = !open;
    w.el.classList.toggle('gone', !open);
  };
  const dockTop = vh - 82;
  if (narrow) {
    hero.x = (vw - hero.w) / 2; hero.y = MB + 34;
    tr.x = (vw - tr.w) / 2; tr.y = MB + 70;
    pe.x = (vw - pe.w) / 2; pe.y = MB + 90;
    en.x = (vw - en.w) / 2; en.y = MB + 100;
    setState(hero, true); setState(tr, false); setState(pe, false); setState(en, false);
    order = ['hero', 'try', 'people', 'engine'];
  } else if (vw >= 1290) {
    // три окна в ряд: пульт человечков, главное, список
    const gap = Math.min(40, (vw - pe.w - hero.w - tr.w) / 4);
    pe.x = gap; hero.x = pe.x + pe.w + gap; tr.x = hero.x + hero.w + gap;
    hero.y = Math.max(MB + 46, Math.min(vh * 0.17, dockTop - hero.h - 60));
    tr.y = Math.max(MB + 40, Math.min(hero.y - 44, dockTop - tr.h - 16));
    pe.y = Math.max(MB + 60, Math.min(hero.y + 76, dockTop - pe.h - 90));
    en.x = hero.x + 30; en.y = Math.max(MB + 60, dockTop - en.h - 20);
    setState(hero, true); setState(tr, true); setState(pe, true); setState(en, false);
    order = ['hero', 'people', 'try', 'engine'];
  } else {
    hero.x = Math.max(28, vw * 0.5 - hero.w - 40);
    hero.y = Math.max(MB + 46, Math.min(vh * 0.17, dockTop - hero.h - 60));
    tr.x = Math.min(vw - tr.w - 28, hero.x + hero.w + 50);
    tr.y = Math.max(MB + 40, Math.min(hero.y + 64, dockTop - tr.h - 16));
    pe.x = Math.max(16, hero.x - 10); pe.y = Math.max(MB + 60, dockTop - pe.h - 70);
    en.x = hero.x + 60; en.y = Math.max(MB + 60, dockTop - en.h - 20);
    setState(hero, true); setState(tr, true); setState(pe, false); setState(en, false);
    order = ['hero', 'try', 'people', 'engine'];
  }
  // «Поддержать» само не открывается: только из Dock, меню или по ссылке в главном окне
  dn.x = Math.max(10, (vw - dn.w) / 2);
  dn.y = Math.max(MB + 44, Math.min(vh * 0.22, dockTop - dn.h - 24));
  setState(dn, false);
  order.push('donate');
  for (const w of wins.values()) { clampWin(w); place(w); }
  restack();
}

function dockLedge() {
  const r = $('#dock').getBoundingClientRect();
  return { x0: r.left, x1: r.right, top: r.top + 2, r: 20 };
}

let lastWinSend = 0;
function sendWindows(now) {
  if (!eng) return;
  if (!winsDirty && now - lastWinSend < 400) return;
  const dt = Math.max(0.01, (now - lastWinSend) / 1000);
  lastWinSend = now;
  winsDirty = false;
  const list = order.map(id => wins.get(id)).filter(w => w.state !== 'closed')
    .map(w => ({ id: w.n, x: w.x, y: w.y, w: w.w, h: w.h, shown: w.state === 'open' }));
  eng.windows(list, MB, RADIUS, dockLedge(), dt);
}

// ---------- меню

function menuModel() {
  const radio = (key, vals, labels) => vals.map((v, i) => ({ label: t(labels[i]), on: S[key] === v, run: () => setOpt(key, v) }));
  const check = (key, label) => ({ label: t(label), on: S[key], run: () => setOpt(key, !S[key]) });
  const act = (label, run) => ({ label: t(label), run });
  const link = (label, href) => ({ label: t(label), href });
  return [
    { title: t('name'), items: [
      act('about', () => showWin('hero')),
      act('support', () => { arranged = true; showWin('donate'); }),
      act(paused ? 'resume' : 'pause', () => setPaused(!paused)),
      '-',
      link('download', 'https://github.com/niazlv/sugrob/releases/latest'),
      link('source', 'https://github.com/niazlv/sugrob'),
    ] },
    { title: t('m_weather'), items: [
      ...radio('weather', [0, 1, 2], ['light', 'snowfall', 'blizzard']),
      '-', { cap: t('wind') },
      ...radio('wind', [-2, -1, 0, 1, 2], ['w_ll', 'w_l', 'w_0', 'w_r', 'w_rr']),
      '-',
      check('storms', 'storms'),
      act('stormNow', () => doAct('storm')),
    ] },
    { title: t('m_snow'), items: [
      { cap: t('depth') },
      ...radio('depth', [0, 1, 2, 3], ['d_low', 'd_mid', 'd_high', 'd_huge']),
      '-', { cap: t('voxel') },
      ...radio('voxel', [2, 3, 4, 6], ['v2', 'v3', 'v4', 'v6']),
      '-',
      check('autoFill', 'autoFill'), check('aging', 'aging'), check('sweep', 'sweep'), check('floor', 'floor'),
      '-',
      act('fill', () => doAct('fill')),
      act('shovel', () => doAct('shovel')),
    ] },
    { title: t('m_people'), items: [
      ...radio('people', [0, 1, 2, 3], ['p0', 'p1', 'p2', 'p3']),
      '-',
      check('ladders', 'ladders'), check('stay', 'stay'), check('events', 'events'),
      '-',
      act('summon', () => doAct('summon')),
      act('clearPeople', () => doAct('clearPeople')),
    ] },
  ];
}

let openMenu = -1;
function buildMenus() {
  const root = $('#menus');
  root.textContent = '';
  menuModel().forEach((m, mi) => {
    const box = document.createElement('div');
    box.className = 'menu' + (mi === openMenu ? ' open' : '');
    const b = document.createElement('button');
    b.type = 'button';
    b.textContent = m.title;
    b.addEventListener('pointerdown', e => { e.stopPropagation(); openMenu = openMenu === mi ? -1 : mi; buildMenus(); });
    b.addEventListener('pointerenter', () => { if (openMenu >= 0 && openMenu !== mi) { openMenu = mi; buildMenus(); } });
    const drop = document.createElement('div');
    drop.className = 'drop';
    for (const it of m.items) {
      if (it === '-') { drop.appendChild(document.createElement('hr')); continue; }
      if (it.cap) { const c = document.createElement('div'); c.className = 'cap'; c.textContent = it.cap; drop.appendChild(c); continue; }
      const el = document.createElement(it.href ? 'a' : 'button');
      el.className = 'it';
      if (it.href) { el.href = it.href; el.target = '_blank'; el.rel = 'noopener'; } else el.type = 'button';
      const ck = document.createElement('span');
      ck.className = 'ck';
      ck.textContent = it.on ? '✓' : '';
      el.append(ck, it.label);
      el.addEventListener('click', () => { openMenu = -1; if (it.run) it.run(); buildMenus(); });
      drop.appendChild(el);
    }
    drop.addEventListener('pointerdown', e => e.stopPropagation());
    box.append(b, drop);
    root.appendChild(box);
  });
}
addEventListener('pointerdown', () => { if (openMenu >= 0) { openMenu = -1; buildMenus(); } });

function setOpt(key, v) {
  S[key] = v;
  if (key === 'voxel') { startSim(); return; }
  if (eng) eng.set(SET[key], v);
}

function pushSettings() {
  for (const k of Object.keys(S)) if (k !== 'voxel') eng.set(SET[k], S[k]);
}

function doAct(name) {
  if (!eng) return;
  if (paused) setPaused(false);
  eng.action(ACT[name]);
  if (name === 'storm') mark('storm');
}

function setPaused(p) {
  paused = p;
  canvas.classList.toggle('off', p);
  toast(p ? t('paused') : '');
  lastFrame = 0;
}

// ---------- тексты на странице

function applyLang() {
  document.documentElement.lang = lang;
  document.title = t('title');
  for (const el of $$('[data-i]')) el.textContent = t(el.dataset.i);
  $('#lang').textContent = lang === 'ru' ? 'EN' : 'RU';
  showNet();
  buildMenus();
  for (const w of wins.values()) if (w.state === 'open') measure(w);
  winsDirty = true;
}
$('#lang').addEventListener('click', () => {
  lang = lang === 'ru' ? 'en' : 'ru';
  try { localStorage.setItem('sugrob-lang', lang); } catch (e) { /* не запомнится — не страшно */ }
  applyLang();
});

let toastTimer = 0;
function toast(text, ms = 0) {
  const el = $('#toast');
  clearTimeout(toastTimer);
  el.textContent = text;
  el.hidden = !text;
  if (text && ms) toastTimer = setTimeout(() => { el.hidden = true; }, ms);
}

function tick() {
  const d = new Date();
  $('#clock').textContent = d.toLocaleTimeString(lang === 'ru' ? 'ru-RU' : 'en-GB', { hour: '2-digit', minute: '2-digit' });
  if (eng) eng.hour(d.getHours());
}
setInterval(tick, 20000);

// ---------- список «что попробовать»

function mark(step) {
  const li = $(`#todo [data-step="${step}"]`);
  if (li && !li.classList.contains('done')) li.classList.add('done');
}
for (const b of $$('[data-act]')) b.addEventListener('click', () => doAct(b.dataset.act));
for (const b of $$('[data-openwin]')) b.addEventListener('click', () => { arranged = true; showWin(b.dataset.openwin); });

// ---------- окно «Поддержать»: сеть, QR-код и адрес, который копируется по нажатию

// значки сетей лежат отдельно: net-icons.js
let gradientNo = 0;
const netIcon = id => NET_ICONS[id].replace(/GID/g, 'net-g' + (++gradientNo));

// BNB — первой: там перевод обходится дешевле всего. Адреса те же, что в README проекта.
const NETS = [
  { id: 'bnb', name: 'BNB Chain (BEP-20)', short: 'BNB', color: '#F3BA2F', low: true, addr: '0xBA10A984A88AeE82A2D3b30EA6d91BC554D46A25' },
  { id: 'trx', name: 'Tron (TRC-20)', short: 'Tron', color: '#FF4D62', addr: 'TKyahQhTeLdMraKDbedLz17jorRTfER8xX' },
  { id: 'sol', name: 'Solana', short: 'Solana', color: '#3FE0A5', addr: '9GhoGBorb8xvkUjFgGfrcFun1m6ad9K9chDUhvagXYwX' },
  { id: 'eth', name: 'Ethereum (ERC-20)', short: 'Ethereum', color: '#8497F5', addr: '0xBA10A984A88AeE82A2D3b30EA6d91BC554D46A25' },
  { id: 'btc', name: 'Bitcoin', short: 'Bitcoin', color: '#F7931A', addr: 'bc1qyt9hzvtd69t5jkk7h39fqd4pz7tg9jl9pq4arf' },
];
let net = NETS[0];
let copiedTimer = 0;

function showNet() {
  for (const b of $$('#nets .net')) b.classList.toggle('on', b.dataset.net === net.id);
  wins.get('donate')?.el.style.setProperty('--net', net.color);
  // код рисуется на месте из самого адреса; в середине — значок сети на белой плашке
  const plate = '<rect x="-2.600" y="-2.600" width="29.200" height="29.200" rx="14.600" fill="#fff"/>';
  $('#qr').innerHTML = qrSvg(net.addr, { logo: plate + netIcon(net.id) });
  $('#qr').setAttribute('aria-label', 'QR: ' + net.name);
  $('#net-name').textContent = net.name;
  $('#net-badge').hidden = !net.low;
  $('#net-note').textContent = t('dn_' + net.id);
  // адрес делится пополам: если не влезает в строку, переносится ровно посередине, а не обрывком в три знака
  const half = Math.ceil(net.addr.length / 2);
  $('#addr-text').replaceChildren(net.addr.slice(0, half), document.createElement('wbr'), net.addr.slice(half));
  $('#addr-hint').textContent = t('dn_copy');
  $('#addr').classList.remove('copied');
}
for (const n of NETS) {
  const b = document.createElement('button');
  b.type = 'button';
  b.className = 'net';
  b.dataset.net = n.id;
  b.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true">${netIcon(n.id)}</svg>`;
  b.append(n.short);
  b.addEventListener('click', () => { net = n; showNet(); });
  $('#nets').appendChild(b);
}
$('#addr').addEventListener('click', async () => {
  let ok = false;
  try {
    await navigator.clipboard.writeText(net.addr);
    ok = true;
  } catch (e) {
    // буфер обмена недоступен (старый браузер, запрет) — выделяем адрес, чтобы его можно было скопировать руками
    const r = document.createRange();
    r.selectNodeContents($('#addr-text'));
    const sel = getSelection();
    sel.removeAllRanges();
    sel.addRange(r);
    try { ok = document.execCommand('copy'); } catch (e2) { ok = false; }
  }
  if (!ok) {
    $('#addr-hint').textContent = t('dn_select');
    return;
  }
  $('#addr').classList.add('copied');
  $('#addr-hint').textContent = t('dn_copied');
  clearTimeout(copiedTimer);
  copiedTimer = setTimeout(showNet, 2200);
});

// ---------- пульт человечков: поручения, кто чем занят, ход времени

let speed = 1;
for (const b of $$('#tasks .task')) {
  b.addEventListener('click', () => {
    if (!eng) return;
    if (paused) setPaused(false);
    const name = b.dataset.task;
    if (name === 'summon') { eng.action(ACT.summon); return; }
    const ok = eng.task(TASK[name]);
    if (ok) {
      toast(t('ok_' + name), 5000);
      mark('people');
    } else {
      toast(t('no_' + name), 6000);
      b.classList.remove('no');
      void b.offsetWidth;
      b.classList.add('no');
    }
  });
}
for (const b of $$('#speed button')) {
  b.addEventListener('click', () => {
    speed = +b.dataset.speed;
    for (const o of $$('#speed button')) o.classList.toggle('on', o === b);
  });
}
$('#age').addEventListener('click', () => {
  if (!eng) return;
  eng.age(5);
  toast(t('aged'), 6000);
});

function roster() {
  const jobs = eng.jobs(), built = eng.built();
  const badge = { ladder: 0, tunnel: 1, igloo: 2, angel: 5, sled: 6, tree: 7 };
  for (const id of Object.keys(badge)) $('#j-' + id).textContent = jobs[badge[id]] || '';
  const n = jobs.reduce((a, b) => a + b, 0);
  const now = jobs.map((v, i) => (v ? t('j' + i) + ' — ' + v : '')).filter(Boolean).join(', ');
  const done = built.map((v, i) => (v ? t('b' + i) + ' — ' + v : '')).filter(Boolean).join(', ');
  let text = n ? t('r_now') + ': ' + now + '.' : t('r_none');
  if (done) text += ' ' + t('r_built') + ': ' + done + '.';
  $('#roster').textContent = text;
}

// ---------- курсор и варежка

const ptr = { x: -1000, y: -1000, on: false, px: 0, py: 0, speed: 0 };
let shift = false, ctrlAlt = false, mitten = false, pressed = false;
const handsActive = () => shift || ctrlAlt || mitten;

function setPtr(e) {
  const touch = e.pointerType === 'touch';
  ptr.x = e.clientX + (touch ? 0 : 3);
  ptr.y = e.clientY + (touch ? 0 : 5);
}
addEventListener('pointermove', e => { setPtr(e); if (e.pointerType !== 'touch') ptr.on = true; mods(e); }, { passive: true });
addEventListener('pointerdown', e => {
  setPtr(e); ptr.on = true; mods(e);
  if (handsActive() && !e.target.closest('#menubar, #dock')) {
    pressed = true;
    e.preventDefault();
    e.stopPropagation();
  }
}, true);
const release = e => {
  pressed = false;
  if (e.pointerType === 'touch') ptr.on = false;
};
addEventListener('pointerup', release, true);
addEventListener('pointercancel', release, true);
document.addEventListener('pointerleave', () => { ptr.on = false; });
addEventListener('blur', () => { shift = ctrlAlt = false; pressed = false; ptr.on = false; syncHands(); });
function mods(e) { shift = e.shiftKey; ctrlAlt = e.ctrlKey && e.altKey; syncHands(); }
addEventListener('keydown', mods);
addEventListener('keyup', mods);
addEventListener('contextmenu', e => { if (handsActive()) e.preventDefault(); });
function syncHands() { document.body.classList.toggle('hands', handsActive()); }
$('#mitten').addEventListener('click', () => {
  mitten = !mitten;
  $('#mitten').setAttribute('aria-pressed', mitten);
  syncHands();
  toast(mitten ? t('mittenOn') : '', 3500);
});

// ---------- симуляция и кадр

function startSim() {
  if (!eng) return;
  const w = innerWidth, h = innerHeight;
  canvas.width = w;
  canvas.height = h;
  eng.init(w, h, S.voxel);
  pushSettings();
  winsDirty = true;
  lastWinSend = performance.now() - 100;
  sendWindows(performance.now());
  // стартовая сцена: сугробы внизу лежат давно — сверху плотный снег, в глубине наст; есть где рыть и из чего строить
  eng.scene(-1, -1);
  if (S.people > 0) eng.action(ACT.summon);
  $('#st-grid').textContent = `${eng.W} × ${eng.H}, ${t('vox')} ${S.voxel}${t('pt')}`;
}

let lastFrame = 0, simTime = 0;
let stepAcc = 0, stepN = 0, fpsT = 0, fpsN = 0, sweepN = 0, heldN = 0;
const fmt = n => n.toLocaleString(lang === 'ru' ? 'ru-RU' : 'en-US');

function frame(now) {
  requestAnimationFrame(frame);
  if (!eng || paused) return;
  const dt = lastFrame ? Math.min(Math.max((now - lastFrame) / 1000, 0.001), 0.05) : 1 / 60;
  const moved = Math.hypot(ptr.x - ptr.px, ptr.y - ptr.py);
  ptr.px = ptr.x; ptr.py = ptr.y;
  lastFrame = now;
  simTime += dt;

  sendWindows(now);
  eng.cursor(ptr.x, ptr.y, ptr.on);
  eng.hands(handsActive(), pressed);
  const t0 = performance.now();
  const flags = eng.step(dt, speed);
  stepAcc += performance.now() - t0; stepN++;
  renderer.draw(eng, [innerWidth, innerHeight], S.voxel, simTime, canvas.width / innerWidth, false);

  // отметки в списке «что попробовать»
  if (flags & 16) { if (++heldN > 20) mark('ball'); }
  const balls = eng.balls();
  for (let i = 0; i < balls.n; i++) if (balls.data[i * 12 + 4] === 1) { mark('snowman'); break; }
  if (ptr.on && moved > 1.5 && !(flags & 8)) {
    const g = eng.grid(0), cx = Math.floor(ptr.x / S.voxel), cy = Math.floor(ptr.y / S.voxel);
    let hit = false;
    for (let y = cy - 3; y <= cy + 3 && !hit; y++) for (let x = cx - 3; x <= cx + 3; x++) {
      if (x >= 0 && y >= 0 && x < eng.W && y < eng.H && g[y * eng.W + x]) { hit = true; break; }
    }
    if (hit && ++sweepN > 12) mark('sweep');
  }

  // живые цифры раз в полсекунды
  fpsN++;
  if (now - fpsT > 500) {
    const g = eng.grid(0);
    let vox = 0;
    for (let i = 0; i < g.length; i++) if (g[i]) vox++;
    const parts = eng.parts();
    const people = eng.people();
    if (people > 0) mark('people');
    $('#st-step').textContent = (stepAcc / stepN / speed).toFixed(2) + t('ms');
    roster();
    $('#st-fps').textContent = Math.round(fpsN * 1000 / (now - fpsT));
    $('#st-vox').textContent = fmt(vox);
    $('#st-fl').textContent = fmt(parts ? parts.length / 4 : 0);
    $('#st-pe').textContent = people;
    stepAcc = 0; stepN = 0; fpsN = 0; fpsT = now;
  }
}

let resizeTimer = 0, lastW = innerWidth, lastH = innerHeight;
addEventListener('resize', () => {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => {
    if (innerWidth === lastW && innerHeight === lastH) return;
    lastW = innerWidth; lastH = innerHeight;
    if (arranged) for (const w of wins.values()) { if (w.state === 'open') measure(w); clampWin(w); place(w); }
    else layout();
    startSim();
  }, 200);
});

// ---------- запуск

initWindows();
applyLang();
layout();

// Прямая ссылка на поддержку (её открывает окно «О Сугробе» в приложении): …/#support
function openFromHash() {
  if (location.hash !== '#support') return;
  arranged = true;
  showWin('donate');
}
openFromHash();
addEventListener('hashchange', openFromHash);
tick();
requestAnimationFrame(frame);

(async function boot() {
  try {
    renderer = createRenderer(canvas);
    if (!renderer) throw new Error('no WebGL2');
    const buf = await (await fetch('sugrob.wasm')).arrayBuffer();
    engineBytes = buf.byteLength;
    eng = await loadEngine(buf);
    $('#st-size').textContent = (engineBytes / 1048576).toFixed(1).replace('.', lang === 'ru' ? ',' : '.') + t('mb');
    startSim();
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) { setPaused(true); toast(t('reduced')); }
    window.sugrob = { eng, S, wins };       // для отладки из консоли
  } catch (e) {
    console.error(e);
    eng = null;
    const note = $('#engine-note');
    note.textContent = t('noEngine');
    note.hidden = false;
  }
})();
