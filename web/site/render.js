// Отрисовка кадра Сугроба в WebGL2. Шейдеры — перенос Metal-шейдеров приложения
// (Renderer.swift, PeopleRender.swift): та же раскраска вокселей, шаров и снежинок.

const HEAD = `#version 300 es
precision highp float;
precision highp int;
uniform vec2 uView;
uniform vec2 uGrid;
uniform float uCell;
uniform float uTime;
uniform float uScale;
float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}
`;

// ---------- лежащий снег (воксельная сетка)

const GRID_V = HEAD + `
out vec2 vP;
void main() {
  vec2 uv = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  gl_Position = vec4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 0.0, 1.0);
  vP = uv * uView;
}`;

const GRID_F = HEAD + `
uniform highp sampler2D uG;
uniform highp sampler2D uHd;
uniform highp sampler2D uCv;
in vec2 vP;
out vec4 o;
float cellAt(highp sampler2D g, ivec2 c, ivec2 size) {
  if (c.x < 0 || c.y < 0 || c.x >= size.x || c.y >= size.y) return 0.0;
  return texelFetch(g, c, 0).r;
}
void main() {
  ivec2 size = ivec2(uGrid);
  ivec2 c = ivec2(floor(vP / uCell));
  float v = cellAt(uG, c, size);
  if (v == 0.0) {
    if (cellAt(uCv, c, size) > 0.0) {
      // пустота внутри сугроба (под настом): видна дальняя стенка — голубоватый снег в тени
      vec3 col = vec3(0.63, 0.72, 0.88);
      if (cellAt(uG, c + ivec2(0, -1), size) > 0.0) col *= 0.84;
      else if (cellAt(uG, c + ivec2(0, -2), size) > 0.0) col *= 0.92;
      if (cellAt(uCv, c + ivec2(-1, 0), size) == 0.0 && cellAt(uG, c + ivec2(-1, 0), size) == 0.0) col *= 1.08;
      if (cellAt(uCv, c + ivec2(1, 0), size) == 0.0 && cellAt(uG, c + ivec2(1, 0), size) == 0.0) col *= 1.08;
      col *= 0.96 + 0.05 * hash21(vec2(c) * 0.53 + 1.7);
      float a = 0.92;
      o = vec4(col * a, a);
      return;
    }
    // мягкая тень под снегом, чтобы он читался и на светлых окнах
    float a = 0.0;
    if (cellAt(uG, c + ivec2(0, -1), size) > 0.0) a = 0.20;
    else if (cellAt(uG, c + ivec2(-1, -1), size) > 0.0 || cellAt(uG, c + ivec2(1, -1), size) > 0.0) a = 0.09;
    else if (cellAt(uG, c + ivec2(-1, 0), size) > 0.0 || cellAt(uG, c + ivec2(1, 0), size) > 0.0) a = 0.07;
    if (a == 0.0) discard;
    o = vec4(0.0, 0.0, 0.02 * a, a);
    return;
  }
  int d = 0;
  for (int k = 1; k <= 5; k++) {
    if (cellAt(uG, c + ivec2(0, -k), size) > 0.0) d++; else break;
  }
  vec3 col;
  if (d == 0) col = vec3(1.0);
  else col = mix(vec3(0.94, 0.965, 1.0), vec3(0.77, 0.845, 0.965), float(d - 1) / 4.0);
  bool edge = cellAt(uG, c + ivec2(-1, 0), size) == 0.0 || cellAt(uG, c + ivec2(1, 0), size) == 0.0;
  if (edge && d > 0) col *= vec3(0.93, 0.95, 0.985);
  if (d == 0 && cellAt(uCv, c + ivec2(0, -1), size) > 0.0) col *= vec3(0.80, 0.85, 0.94);
  col *= 0.95 + 0.06 * v;
  // слежалость: плотный снег чуть темнее и синее, наст — голубой лёд с бликами
  float hv = texelFetch(uHd, c, 0).r;
  float dense = smoothstep(0.27, 0.36, hv);
  float frozen = smoothstep(0.74, 0.82, hv);
  col = mix(col, col * vec3(0.895, 0.93, 0.985), dense);
  vec3 ice = d == 0 ? vec3(0.88, 0.96, 1.0)
                    : mix(vec3(0.68, 0.84, 0.99), vec3(0.50, 0.69, 0.95), float(min(d, 5) - 1) / 4.0);
  col = mix(col, ice, frozen * 0.9);
  if (frozen > 0.5 && hash21(vec2(c) * 1.37 + 9.1) > 0.94) col = mix(col, vec3(1.0), 0.65);
  // редкие искорки в толще снега
  float sp = hash21(vec2(c) * 0.731 + 3.1);
  if (sp > 0.99 && d >= 1) {
    float sd = fract(sp * 977.0);
    float a = pow(max(0.0, sin(uTime * (1.3 + sd * 3.0) + sd * 57.0)), 8.0);
    col = mix(col, vec3(1.0), a);
  }
  o = vec4(min(col, vec3(1.0)), 1.0);
}`;

// ---------- шары

const BALL_V = HEAD + `
layout(location = 0) in vec4 aA;   // центр, радиус, поворот
layout(location = 1) in vec4 aB;   // признаки, зерно, осадка, заметённость
layout(location = 2) in vec4 aE;   // срез: направление и глубина; возраст; поворот обозначений
out vec2 vL;
flat out float vR;
flat out float vAngle;
flat out float vFlags;
flat out float vSeed;
flat out float vSquash;
flat out float vCutA;
flat out float vCutD;
flat out float vAge;
flat out float vTurn;
void main() {
  vec2 q = vec2(float(gl_VertexID & 1), float((gl_VertexID >> 1) & 1)) * 2.0 - 1.0;
  float r = aA.z;
  float ext = r * (1.0 + 0.3 * aB.z) + 6.0;
  if ((int(aB.x + 0.5) & 2) != 0) ext = max(ext, r * 1.95 + 4.0);   // у туловища снеговика руки-палки
  vec2 p = aA.xy + q * ext;
  gl_Position = vec4(p.x / uView.x * 2.0 - 1.0, 1.0 - p.y / uView.y * 2.0, 0.0, 1.0);
  vL = q * ext;
  vR = r; vAngle = aA.w; vFlags = aB.x; vSeed = aB.y; vSquash = aB.z;
  vCutA = aE.x; vCutD = aE.y; vAge = aE.z; vTurn = aE.w;
}`;

const BALL_F = HEAD + `
in vec2 vL;
flat in float vR;
flat in float vAngle;
flat in float vFlags;
flat in float vSeed;
flat in float vSquash;
flat in float vCutA;
flat in float vCutD;
flat in float vAge;
flat in float vTurn;
out vec4 o;
float segDist(vec2 p, vec2 a, vec2 b) {
  vec2 ab = b - a;
  float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
  return length(p - (a + ab * t));
}
void main() {
  int flags = int(vFlags + 0.5);
  if ((flags & 8) != 0) {
    // кольцо варежки
    float d = length(vL);
    float a = smoothstep(vR - 2.6, vR - 1.6, d) * (1.0 - smoothstep(vR - 0.6, vR + 0.4, d));
    if (a < 0.01) discard;
    a *= 0.6;
    o = vec4(a, a, a, a);
    return;
  }
  float r = vR;
  // осевший шар: шире и ниже, низ остаётся на месте
  vec2 l = vL;
  l.y -= r * 0.35 * vSquash;
  l = vec2(l.x / (1.0 + 0.3 * vSquash), l.y / (1.0 - 0.35 * vSquash));
  vec2 q = (floor(l / uCell) + 0.5) * uCell;
  float d = length(q);
  float ca = cos(-vAngle), sa = sin(-vAngle);
  vec2 rq = vec2(q.x * ca - q.y * sa, q.x * sa + q.y * ca);      // оси, вращающиеся вместе с шаром

  // обозначения снеговика принадлежат шару и поворачиваются вместе с ним
  float ct = cos(-vTurn), st = sin(-vTurn);
  vec2 fq = vec2(q.x * ct - q.y * st, q.x * st + q.y * ct);

  // скол: у шара, отломанного от примёрзшего основания, нет сегмента
  vec2 cdir = vec2(cos(vCutA), sin(vCutA));
  float toCut = r * (1.0 - vCutD) - dot(rq, cdir);
  bool chipped = vCutD > 0.01 && toCut < 0.0;
  bool body = d <= r && !chipped;
  if (!body) {
    // ветки туловища торчат из-за шара
    if ((flags & 2) != 0 && r > 9.0 && d > r) {
      for (int sg = -1; sg <= 1; sg += 2) {
        vec2 a = vec2(float(sg) * 0.8 * r, -0.05 * r), b = vec2(float(sg) * 1.75 * r, -0.6 * r);
        vec2 m = a + (b - a) * 0.62;
        if (segDist(fq, a, b) < uCell * 0.62 || segDist(fq, m, m + vec2(float(sg) * 0.12 * r, -0.36 * r)) < uCell * 0.55) {
          o = vec4(0.36, 0.25, 0.16, 1.0);
          return;
        }
      }
    }
    discard;
  }

  vec2 n = q / r;
  float nz = sqrt(max(0.0, 1.0 - dot(n, n)));
  float light = dot(normalize(vec3(n, nz)), normalize(vec3(-0.45, -0.65, 0.6)));
  vec3 col = mix(vec3(0.64, 0.74, 0.93), vec3(1.0), clamp(light * 0.62 + 0.5, 0.0, 1.0));
  float h = hash21(floor(rq / uCell) + vSeed);
  col *= 0.94 + 0.07 * h;
  if (h > 0.9) col *= 0.93;
  if (d > r - uCell * 1.05) col *= vec3(0.84, 0.89, 0.97);
  col = mix(col, col * vec3(0.86, 0.91, 0.985), vAge * 0.7);          // слежавшийся шар плотнее и синее
  if (vCutD > 0.01 && toCut < uCell * 1.3) col *= vec3(0.76, 0.84, 0.96) * (0.9 + 0.12 * h);   // шершавый излом

  if ((flags & 1) != 0) {
    // лицо снеговика
    float es = max(uCell * 0.51, r * 0.11);
    vec2 ec = (floor(vec2(0.34 * r, -0.24 * r) / uCell) + 0.5) * uCell;
    vec2 e1 = abs(fq - vec2(-ec.x, ec.y));
    vec2 e2 = abs(fq - ec);
    if (max(e1.x, e1.y) < es || max(e2.x, e2.y) < es) col = vec3(0.09, 0.10, 0.16);
    float nx = fq.x + uCell * 0.5, ny = fq.y - (floor(0.10 * r / uCell) + 0.5) * uCell;
    float len = 0.78 * r;
    if (nx > 0.0 && nx < len && abs(ny) < 0.17 * r * (1.0 - nx / len) + uCell * 0.35) {
      col = mix(vec3(0.98, 0.52, 0.12), vec3(0.85, 0.36, 0.08), nx / len);
    }
    if (r > 11.0) {
      float ms = max(uCell * 0.51, r * 0.045);
      for (int k = -2; k <= 2; k++) {
        vec2 m = abs(fq - (floor(vec2(float(k) * 0.2 * r, (0.5 - 0.03 * float(k * k)) * r) / uCell) + 0.5) * uCell);
        if (max(m.x, m.y) < ms) col = vec3(0.11, 0.12, 0.18);
      }
    }
  }
  if ((flags & 2) != 0) {
    float bs = max(uCell * 0.51, r * 0.09);
    for (int k = -1; k <= 1; k++) {
      if (r < 13.0 && k != 0) continue;       // на маленьком шаре помещается одна пуговица
      vec2 m = abs(fq - (floor(vec2(0.0, float(k) * 0.42 * r) / uCell) + 0.5) * uCell);
      if (max(m.x, m.y) < bs) col = vec3(0.11, 0.12, 0.18);
    }
  }
  o = vec4(col, 1.0);
}`;

// ---------- летящий снег

const PART_V = HEAD + `
layout(location = 0) in vec4 aP;   // x, y, размер, прозрачность (2 — ком)
out float vAlpha;
void main() {
  gl_Position = vec4(aP.x / uView.x * 2.0 - 1.0, 1.0 - aP.y / uView.y * 2.0, 0.0, 1.0);
  gl_PointSize = max(1.0, aP.z * uScale);
  vAlpha = aP.w;
}`;

const PART_F = `#version 300 es
precision highp float;
in float vAlpha;
out vec4 o;
void main() {
  if (vAlpha > 1.5) { o = vec4(0.97, 0.985, 1.0, 1.0); return; }      // ком — целый воксель
  float d = length(gl_PointCoord - 0.5) * 2.0;                        // снежинка — мягкая точка
  float a = vAlpha * (1.0 - smoothstep(0.3, 1.0, d));
  o = vec4(vec3(0.96, 0.98, 1.0) * a, a);
}`;

// ---------- человечки: цветные прямоугольники

const PX_V = HEAD + `
layout(location = 0) in vec4 aRect;
layout(location = 1) in vec4 aColor;
flat out vec4 vColor;
void main() {
  vec2 q = vec2(float(gl_VertexID & 1), float((gl_VertexID >> 1) & 1));
  vec2 p = aRect.xy + q * aRect.zw;
  gl_Position = vec4(p.x / uView.x * 2.0 - 1.0, 1.0 - p.y / uView.y * 2.0, 0.0, 1.0);
  vColor = aColor;
}`;

const PX_F = `#version 300 es
precision highp float;
flat in vec4 vColor;
out vec4 o;
void main() { o = vColor; }`;

function program(gl, vs, fs) {
  const p = gl.createProgram();
  for (const [type, src] of [[gl.VERTEX_SHADER, vs], [gl.FRAGMENT_SHADER, fs]]) {
    const s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error('shader: ' + gl.getShaderInfoLog(s));
    gl.attachShader(p, s);
  }
  gl.linkProgram(p);
  if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error('link: ' + gl.getProgramInfoLog(p));
  const u = {};
  const n = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
  for (let i = 0; i < n; i++) {
    const name = gl.getActiveUniform(p, i).name;
    u[name] = gl.getUniformLocation(p, name);
  }
  return { p, u };
}

export function createRenderer(canvas) {
  const gl = canvas.getContext('webgl2', { alpha: true, premultipliedAlpha: true, antialias: false, depth: false, stencil: false });
  if (!gl) return null;

  const grid = program(gl, GRID_V, GRID_F);
  const ball = program(gl, BALL_V, BALL_F);
  const part = program(gl, PART_V, PART_F);
  const px = program(gl, PX_V, PX_F);

  gl.disable(gl.DEPTH_TEST);
  gl.enable(gl.BLEND);
  gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);

  const tex = [0, 1, 2].map(() => {
    const t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return t;
  });
  let texW = 0, texH = 0;

  const gridVao = gl.createVertexArray();

  function instanced(layout, stride) {
    const vao = gl.createVertexArray();
    const buf = gl.createBuffer();
    gl.bindVertexArray(vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    layout.forEach((off, loc) => {
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, 4, gl.FLOAT, false, stride, off);
      gl.vertexAttribDivisor(loc, 1);
    });
    return { vao, buf, layout, stride };
  }
  const ballGeo = instanced([0, 16, 32], 48);
  const pxGeo = instanced([0, 16], 32);

  const partVao = gl.createVertexArray();
  const partBuf = gl.createBuffer();
  gl.bindVertexArray(partVao);
  gl.bindBuffer(gl.ARRAY_BUFFER, partBuf);
  gl.enableVertexAttribArray(0);
  gl.vertexAttribPointer(0, 4, gl.FLOAT, false, 16, 0);
  gl.bindVertexArray(null);

  function common(pr, eng, view, cell, time, scale) {
    gl.useProgram(pr.p);
    if (pr.u.uView) gl.uniform2f(pr.u.uView, view[0], view[1]);
    if (pr.u.uGrid) gl.uniform2f(pr.u.uGrid, eng.W, eng.H);
    if (pr.u.uCell) gl.uniform1f(pr.u.uCell, cell);
    if (pr.u.uTime) gl.uniform1f(pr.u.uTime, time);
    if (pr.u.uScale) gl.uniform1f(pr.u.uScale, scale);
  }

  function drawBalls(first, count) {
    if (count <= 0) return;
    gl.bindVertexArray(ballGeo.vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, ballGeo.buf);
    // в WebGL2 нет baseInstance — сдвигаем начало атрибутов
    ballGeo.layout.forEach((off, loc) => gl.vertexAttribPointer(loc, 4, gl.FLOAT, false, 48, off + first * 48));
    gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, count);
  }

  return {
    gl,
    /** eng — движок после step(); view — размер в пунктах; cell — размер вокселя; scale — пикселей холста на пункт */
    draw(eng, view, cell, time, scale, forceUpload) {
      gl.viewport(0, 0, canvas.width, canvas.height);
      const hands = (eng.flags & 8) !== 0;
      gl.clearColor(0, 0, 0, hands ? 0.05 : 0);
      gl.clear(gl.COLOR_BUFFER_BIT);

      const fresh = texW !== eng.W || texH !== eng.H;
      for (let k = 0; k < 3; k++) {
        if (!fresh && !forceUpload && !(eng.flags & (1 << k))) continue;
        gl.activeTexture(gl.TEXTURE0 + k);
        gl.bindTexture(gl.TEXTURE_2D, tex[k]);
        const data = eng.grid(k);
        if (fresh) gl.texImage2D(gl.TEXTURE_2D, 0, gl.R8, eng.W, eng.H, 0, gl.RED, gl.UNSIGNED_BYTE, data);
        else gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, eng.W, eng.H, gl.RED, gl.UNSIGNED_BYTE, data);
      }
      texW = eng.W; texH = eng.H;

      const balls = eng.balls();
      if (balls.n > 0) {
        gl.bindBuffer(gl.ARRAY_BUFFER, ballGeo.buf);
        gl.bufferData(gl.ARRAY_BUFFER, balls.data, gl.DYNAMIC_DRAW);
        common(ball, eng, view, cell, time, scale);
        drawBalls(0, balls.under);       // стоящие шары — под снегом: налипшее должно быть поверх
      }

      common(grid, eng, view, cell, time, scale);
      for (let k = 0; k < 3; k++) {
        gl.activeTexture(gl.TEXTURE0 + k);
        gl.bindTexture(gl.TEXTURE_2D, tex[k]);
      }
      gl.uniform1i(grid.u.uG, 0);
      gl.uniform1i(grid.u.uHd, 1);
      gl.uniform1i(grid.u.uCv, 2);
      gl.bindVertexArray(gridVao);
      gl.drawArrays(gl.TRIANGLES, 0, 3);

      const parts = eng.parts();
      if (parts) {
        common(part, eng, view, cell, time, scale);
        gl.bindVertexArray(partVao);
        gl.bindBuffer(gl.ARRAY_BUFFER, partBuf);
        gl.bufferData(gl.ARRAY_BUFFER, parts, gl.DYNAMIC_DRAW);
        gl.drawArrays(gl.POINTS, 0, parts.length / 4);
      }

      if (balls.n > balls.under) {
        common(ball, eng, view, cell, time, scale);
        drawBalls(balls.under, balls.n - balls.under);
      }

      const people = eng.px();
      if (people) {
        common(px, eng, view, cell, time, scale);
        gl.bindVertexArray(pxGeo.vao);
        gl.bindBuffer(gl.ARRAY_BUFFER, pxGeo.buf);
        gl.bufferData(gl.ARRAY_BUFFER, people, gl.DYNAMIC_DRAW);
        gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, people.length / 8);
      }
      gl.bindVertexArray(null);
    },
  };
}
