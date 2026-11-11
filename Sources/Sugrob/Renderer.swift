import Metal
import simd

struct Uniforms {
    var view: SIMD2<Float>
    var grid: SIMD2<Float>
    var cell: Float
    var time: Float
    var dim: Float
    var scale: Float
}

struct BallInst {
    var c: SIMD2<Float>
    var r: Float
    var angle: Float
    var flags: Float
    var seed: Float
    var pad: SIMD2<Float> = .zero
    var ex: SIMD4<Float> = .zero        // срез: направление и глубина; возраст; запас
}

struct PartInst {
    var p: SIMD2<Float>
    var size: Float
    var alpha: Float
}

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct U {
    float2 view;
    float2 grid;
    float cell;
    float time;
    float dim;
    float scale;
};

static inline float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// ---------- лежащий снег (воксельная сетка)

struct GOut { float4 pos [[position]]; float2 p; };

vertex GOut grid_v(uint vid [[vertex_id]], constant U& u [[buffer(0)]]) {
    float2 uv = float2((vid << 1) & 2, vid & 2);
    GOut o;
    o.pos = float4(uv.x * 2 - 1, 1 - uv.y * 2, 0, 1);
    o.p = uv * u.view;
    return o;
}

static inline float cellAt(texture2d<float, access::read> g, int2 c, int2 size) {
    if (c.x < 0 || c.y < 0 || c.x >= size.x || c.y >= size.y) return 0;
    return g.read(uint2(c)).r;
}

fragment float4 grid_f(GOut in [[stage_in]], constant U& u [[buffer(0)]],
                       texture2d<float, access::read> g [[texture(0)]],
                       texture2d<float, access::read> hd [[texture(1)]],
                       texture2d<float, access::read> cv [[texture(2)]]) {
    int2 size = int2(u.grid);
    int2 c = int2(floor(in.p / u.cell));
    float v = cellAt(g, c, size);
    if (v == 0) {
        if (cellAt(cv, c, size) > 0) {
            // пустота внутри сугроба (под настом): видна дальняя стенка — голубоватый снег в тени
            float3 col = float3(0.63, 0.72, 0.88);
            if (cellAt(g, c + int2(0, -1), size) > 0) col *= 0.84;          // сразу под сводом темнее
            else if (cellAt(g, c + int2(0, -2), size) > 0) col *= 0.92;
            if (cellAt(cv, c + int2(-1, 0), size) == 0 && cellAt(g, c + int2(-1, 0), size) == 0) col *= 1.08;   // у выхода светлее
            if (cellAt(cv, c + int2(1, 0), size) == 0 && cellAt(g, c + int2(1, 0), size) == 0) col *= 1.08;
            col *= 0.96 + 0.05 * hash21(float2(c) * 0.53 + 1.7);
            float a = 0.92;
            return float4(col * a, a);
        }
        // мягкая тень под снегом, чтобы он читался и на светлых окнах
        float a = 0;
        if (cellAt(g, c + int2(0, -1), size) > 0) a = 0.20;
        else if (cellAt(g, c + int2(-1, -1), size) > 0 || cellAt(g, c + int2(1, -1), size) > 0) a = 0.09;
        else if (cellAt(g, c + int2(-1, 0), size) > 0 || cellAt(g, c + int2(1, 0), size) > 0) a = 0.07;
        if (a == 0) discard_fragment();
        return float4(0, 0, 0.02 * a, a);
    }
    int d = 0;
    for (int k = 1; k <= 5; k++) {
        if (cellAt(g, c + int2(0, -k), size) > 0) d++; else break;
    }
    float3 col;
    if (d == 0) col = float3(1.0, 1.0, 1.0);
    else col = mix(float3(0.94, 0.965, 1.0), float3(0.77, 0.845, 0.965), float(d - 1) / 4.0);
    bool edge = cellAt(g, c + int2(-1, 0), size) == 0 || cellAt(g, c + int2(1, 0), size) == 0;
    if (edge && d > 0) col *= float3(0.93, 0.95, 0.985);
    if (d == 0 && cellAt(cv, c + int2(0, -1), size) > 0) col *= float3(0.80, 0.85, 0.94);    // дно пустоты в тени свода
    col *= 0.95 + 0.06 * v;
    // слежалость: плотный снег чуть темнее и синее, наст — голубой лёд с бликами
    float hv = hd.read(uint2(c)).r;
    float dense = smoothstep(0.27, 0.36, hv);
    float frozen = smoothstep(0.74, 0.82, hv);
    col = mix(col, col * float3(0.895, 0.93, 0.985), dense);
    float3 ice = d == 0 ? float3(0.88, 0.96, 1.0)
                        : mix(float3(0.68, 0.84, 0.99), float3(0.50, 0.69, 0.95), float(min(d, 5) - 1) / 4.0);
    col = mix(col, ice, frozen * 0.9);
    if (frozen > 0.5 && hash21(float2(c) * 1.37 + 9.1) > 0.94) col = mix(col, float3(1.0), 0.65);
    // редкие искорки в толще снега
    float sp = hash21(float2(c) * 0.731 + 3.1);
    if (sp > 0.99 && d >= 1) {
        float sd = fract(sp * 977.0);
        float a = pow(max(0.0, sin(u.time * (1.3 + sd * 3.0) + sd * 57.0)), 8.0);
        col = mix(col, float3(1.0), a);
    }
    return float4(min(col, float3(1.0)), 1.0);
}

// ---------- шары

struct BallIn { float2 c; float r; float angle; float flags; float seed; float2 pad; float4 ex; };
struct BOut {
    float4 pos [[position]];
    float2 l;
    float r [[flat]];
    float angle [[flat]];
    float flags [[flat]];
    float seed [[flat]];
    float squash [[flat]];
    float cover [[flat]];
    float cutA [[flat]];
    float cutD [[flat]];
    float age [[flat]];
    float turn [[flat]];
};

vertex BOut ball_v(uint vid [[vertex_id]], uint iid [[instance_id]],
                   constant U& u [[buffer(0)]], const device BallIn* b [[buffer(1)]]) {
    float2 q = float2(vid & 1, (vid >> 1) & 1) * 2 - 1;
    BallIn bi = b[iid];
    float ext = bi.r * (1.0 + 0.3 * bi.pad.x) + 6;          // осевший шар шире
    if (int(bi.flags + 0.5) & 2) ext = max(ext, bi.r * 1.95 + 4);   // у среднего шара снеговика руки-палки
    float2 p = bi.c + q * ext;
    BOut o;
    o.pos = float4(p.x / u.view.x * 2 - 1, 1 - p.y / u.view.y * 2, 0, 1);
    o.l = q * ext;
    o.r = bi.r; o.angle = bi.angle; o.flags = bi.flags; o.seed = bi.seed;
    o.squash = bi.pad.x; o.cover = bi.pad.y;
    o.cutA = bi.ex.x; o.cutD = bi.ex.y; o.age = bi.ex.z; o.turn = bi.ex.w;
    return o;
}

static inline float segDist(float2 p, float2 a, float2 b) {
    float2 ab = b - a;
    float t = saturate(dot(p - a, ab) / dot(ab, ab));
    return length(p - (a + ab * t));
}

fragment float4 ball_f(BOut in [[stage_in]], constant U& u [[buffer(0)]]) {
    int flags = int(in.flags + 0.5);
    if (flags & 8) {
        float d = length(in.l);
        float a = smoothstep(in.r - 2.6, in.r - 1.6, d) * (1 - smoothstep(in.r - 0.6, in.r + 0.4, d));
        if (a < 0.01) discard_fragment();
        a *= 0.6;
        return float4(a, a, a, a);
    }
    float r = in.r;
    // осевший шар: шире и ниже, низ остаётся на месте
    float2 l = in.l;
    l.y -= r * 0.35 * in.squash;
    l = float2(l.x / (1.0 + 0.3 * in.squash), l.y / (1.0 - 0.35 * in.squash));
    float2 q = (floor(l / u.cell) + 0.5) * u.cell;
    float d = length(q);
    float ca = cos(-in.angle), sa = sin(-in.angle);
    float2 rq = float2(q.x * ca - q.y * sa, q.x * sa + q.y * ca);      // оси, вращающиеся вместе с шаром
    float ch = hash21(floor(q / u.cell) + in.seed);

    // Обозначения снеговика (лицо, пуговицы, ветки) принадлежат шару и поворачиваются вместе с ним:
    // fq — координаты в осях, где они стоят прямо. Снег их не «стирает»: он настоящий, лежит
    // в сетке и рисуется поверх стоящего шара.
    float ct = cos(-in.turn), st = sin(-in.turn);
    float2 fq = float2(q.x * ct - q.y * st, q.x * st + q.y * ct);

    // скол: у шара, отломанного от примёрзшего основания, нет сегмента
    float2 cdir = float2(cos(in.cutA), sin(in.cutA));
    float toCut = r * (1.0 - in.cutD) - dot(rq, cdir);
    bool chipped = in.cutD > 0.01 && toCut < 0.0;
    bool body = d <= r && !chipped;
    if (!body) {
        // ветки туловища торчат из-за шара
        if ((flags & 2) && r > 9.0 && d > r) {
            for (int sg = -1; sg <= 1; sg += 2) {
                float2 a = float2(float(sg) * 0.8 * r, -0.05 * r), b = float2(float(sg) * 1.75 * r, -0.6 * r);
                float2 m = a + (b - a) * 0.62;
                if (segDist(fq, a, b) < u.cell * 0.62 || segDist(fq, m, m + float2(float(sg) * 0.12 * r, -0.36 * r)) < u.cell * 0.55)
                    return float4(0.36, 0.25, 0.16, 1.0);
            }
        }
        discard_fragment();
    }

    float2 n = q / r;
    float nz = sqrt(max(0.0, 1 - dot(n, n)));
    float light = dot(normalize(float3(n, nz)), normalize(float3(-0.45, -0.65, 0.6)));
    float3 col = mix(float3(0.64, 0.74, 0.93), float3(1.0), saturate(light * 0.62 + 0.5));
    float h = hash21(floor(rq / u.cell) + in.seed);
    col *= 0.94 + 0.07 * h;
    if (h > 0.9) col *= 0.93;
    if (d > r - u.cell * 1.05) col *= float3(0.84, 0.89, 0.97);
    col = mix(col, col * float3(0.86, 0.91, 0.985), in.age * 0.7);          // слежавшийся шар плотнее и синее
    if (in.cutD > 0.01 && toCut < u.cell * 1.3) col *= float3(0.76, 0.84, 0.96) * (0.9 + 0.12 * h);   // шершавый излом

    if (flags & 1) {
        // лицо снеговика
        float es = max(u.cell * 0.51, r * 0.11);
        float2 ec = (floor(float2(0.34 * r, -0.24 * r) / u.cell) + 0.5) * u.cell;
        float2 e1 = abs(fq - float2(-ec.x, ec.y));
        float2 e2 = abs(fq - ec);
        if (max(e1.x, e1.y) < es || max(e2.x, e2.y) < es) col = float3(0.09, 0.10, 0.16);
        float nx = fq.x + u.cell * 0.5, ny = fq.y - (floor(0.10 * r / u.cell) + 0.5) * u.cell;
        float len = 0.78 * r;
        if (nx > 0 && nx < len && abs(ny) < 0.17 * r * (1 - nx / len) + u.cell * 0.35) {
            col = mix(float3(0.98, 0.52, 0.12), float3(0.85, 0.36, 0.08), nx / len);
        }
        if (r > 11) {
            float ms = max(u.cell * 0.51, r * 0.045);
            for (int k = -2; k <= 2; k++) {
                float2 m = abs(fq - (floor(float2(float(k) * 0.2 * r, (0.5 - 0.03 * float(k * k)) * r) / u.cell) + 0.5) * u.cell);
                if (max(m.x, m.y) < ms) col = float3(0.11, 0.12, 0.18);
            }
        }
    }
    if (flags & 2) {
        float bs = max(u.cell * 0.51, r * 0.09);
        for (int k = -1; k <= 1; k++) {
            if (r < 13.0 && k != 0) continue;       // на маленьком шаре помещается одна пуговица
            float2 m = abs(fq - (floor(float2(0, float(k) * 0.42 * r) / u.cell) + 0.5) * u.cell);
            if (max(m.x, m.y) < bs) col = float3(0.11, 0.12, 0.18);
        }
    }
    return float4(col, 1.0);
}

// ---------- летящий снег

struct PIn { float2 p; float size; float alpha; };
struct POut { float4 pos [[position]]; float psize [[point_size]]; float alpha; };

vertex POut part_v(uint vid [[vertex_id]], constant U& u [[buffer(0)]],
                   const device PIn* ps [[buffer(1)]]) {
    PIn p = ps[vid];
    POut o;
    o.pos = float4(p.p.x / u.view.x * 2 - 1, 1 - p.p.y / u.view.y * 2, 0, 1);
    o.psize = max(1.0, p.size * u.scale);
    o.alpha = p.alpha;
    return o;
}

struct PFrag { float4 pos [[position]]; float alpha; };

fragment float4 part_f(PFrag in [[stage_in]], float2 pc [[point_coord]]) {
    if (in.alpha > 1.5) return float4(0.97, 0.985, 1.0, 1.0);      // ком — целый воксель
    float d = length(pc - 0.5) * 2.0;                               // снежинка — мягкая точка
    float a = in.alpha * (1.0 - smoothstep(0.3, 1.0, d));
    return float4(float3(0.96, 0.98, 1.0) * a, a);
}
"""

final class Renderer {
    let device: MTLDevice
    private let gridPipe: MTLRenderPipelineState
    private let ballPipe: MTLRenderPipelineState
    private let partPipe: MTLRenderPipelineState
    private var tex: MTLTexture?
    private var hardTex: MTLTexture?
    private var caveTex: MTLTexture?
    private var partBufs: [MTLBuffer?] = [nil, nil, nil]
    private var ballBufs: [MTLBuffer?] = [nil, nil, nil]
    private var frame = 0
    private var texFor: ObjectIdentifier?
    private let px = PxRenderer()       // человечки (People.swift)

    /// Шейдеры собираются один раз на всё приложение: слоёв снега несколько, и собирать их
    /// заново при появлении каждого — заметная задержка.
    private static var shared: (grid: MTLRenderPipelineState, ball: MTLRenderPipelineState, part: MTLRenderPipelineState)?

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        self.device = device
        if let c = Renderer.shared {
            gridPipe = c.grid; ballPipe = c.ball; partPipe = c.part
            return
        }
        do {
            let lib = try device.makeLibrary(source: shaderSource, options: nil)
            func pipe(_ v: String, _ f: String) throws -> MTLRenderPipelineState {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = lib.makeFunction(name: v)
                d.fragmentFunction = lib.makeFunction(name: f)
                let a = d.colorAttachments[0]!
                a.pixelFormat = pixelFormat
                a.isBlendingEnabled = true
                a.rgbBlendOperation = .add
                a.alphaBlendOperation = .add
                a.sourceRGBBlendFactor = .one
                a.sourceAlphaBlendFactor = .one
                a.destinationRGBBlendFactor = .oneMinusSourceAlpha
                a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                return try device.makeRenderPipelineState(descriptor: d)
            }
            gridPipe = try pipe("grid_v", "grid_f")
            ballPipe = try pipe("ball_v", "ball_f")
            partPipe = try pipe("part_v", "part_f")
            Renderer.shared = (gridPipe, ballPipe, partPipe)
        } catch {
            NSLog("Sugrob: shader error: \(error)")
            return nil
        }
    }

    private func buffer(_ slot: inout MTLBuffer?, bytes: Int) -> MTLBuffer? {
        if let b = slot, b.length >= bytes { return b }
        var cap = 1 << 16
        while cap < bytes { cap <<= 1 }
        slot = device.makeBuffer(length: cap, options: .storageModeShared)
        return slot
    }

    func encode(sim: Sim, cmd: MTLCommandBuffer, rpd: MTLRenderPassDescriptor, scale: Float) {
        // сетка -> текстура
        if tex == nil || tex!.width != sim.W || tex!.height != sim.H || texFor != ObjectIdentifier(sim) {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: sim.W, height: sim.H, mipmapped: false)
            d.usage = .shaderRead
            tex = device.makeTexture(descriptor: d)
            hardTex = device.makeTexture(descriptor: d)
            caveTex = device.makeTexture(descriptor: d)
            sim.hardDirty = true
            sim.caveDirty = true
            texFor = ObjectIdentifier(sim)
            sim.gridDirty = true
        }
        if sim.gridDirty, let tex {
            sim.snow.withUnsafeBytes { raw in
                tex.replace(region: MTLRegionMake2D(0, 0, sim.W, sim.H), mipmapLevel: 0,
                            withBytes: raw.baseAddress!, bytesPerRow: sim.W)
            }
            sim.gridDirty = false
        }
        if sim.hardDirty, let hardTex {
            sim.hard.withUnsafeBytes { raw in
                hardTex.replace(region: MTLRegionMake2D(0, 0, sim.W, sim.H), mipmapLevel: 0,
                                withBytes: raw.baseAddress!, bytesPerRow: sim.W)
            }
            sim.hardDirty = false
        }
        if sim.caveDirty, let caveTex {
            sim.cave.withUnsafeBytes { raw in
                caveTex.replace(region: MTLRegionMake2D(0, 0, sim.W, sim.H), mipmapLevel: 0,
                                withBytes: raw.baseAddress!, bytesPerRow: sim.W)
            }
            sim.caveDirty = false
        }

        frame = (frame + 1) % 3
        var u = Uniforms(view: SIMD2(sim.wPt, sim.hPt), grid: SIMD2(Float(sim.W), Float(sim.H)),
                         cell: sim.cell, time: sim.time, dim: 0, scale: scale)

        // частицы
        let pn = sim.parts.count
        var pbuf: MTLBuffer?
        if pn > 0, let b = buffer(&partBufs[frame], bytes: pn * MemoryLayout<PartInst>.stride) {
            let dst = b.contents().bindMemory(to: PartInst.self, capacity: pn)
            sim.parts.withUnsafeBufferPointer { src in
                for i in 0..<pn {
                    let p = src[i]
                    dst[i] = PartInst(p: SIMD2(p.x, p.y), size: p.size, alpha: p.kind == 1 ? 2 : p.alpha)
                }
            }
            pbuf = b
        }

        // шары (+ кольцо варежки)
        // Стоящие шары рисуются ДО снега: то, что на них лежит и к ним налипло, должно быть поверх.
        // Движущиеся — после, как и раньше.
        var insts: [BallInst] = []
        var over: [BallInst] = []
        for b in sim.balls {
            let inst = BallInst(c: SIMD2(b.x, b.y), r: b.r, angle: b.angle, flags: Float(b.decor), seed: b.seed,
                                pad: SIMD2(0, 0),
                                ex: SIMD4(b.cutA, b.cutD, min(1, b.rest / 240), b.angle - b.decorA))
            if b.slot != 0 { insts.append(inst) } else { over.append(inst) }
        }
        let underCount = insts.count
        if sim.handsMode && sim.heldId == -1 && sim.cursorOn {
            over.append(BallInst(c: SIMD2(sim.cx, sim.cy), r: 15, angle: 0, flags: 8, seed: 0))
        }
        insts += over
        var bbuf: MTLBuffer?
        if !insts.isEmpty, let b = buffer(&ballBufs[frame], bytes: insts.count * MemoryLayout<BallInst>.stride) {
            insts.withUnsafeBytes { raw in
                b.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
            bbuf = b
        }

        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
        let ulen = MemoryLayout<Uniforms>.stride
        enc.setVertexBytes(&u, length: ulen, index: 0)
        enc.setFragmentBytes(&u, length: ulen, index: 0)

        if let bbuf, underCount > 0 {
            enc.setRenderPipelineState(ballPipe)
            enc.setVertexBuffer(bbuf, offset: 0, index: 1)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: underCount)
        }
        if let tex {
            enc.setRenderPipelineState(gridPipe)
            enc.setFragmentTexture(tex, index: 0)
            enc.setFragmentTexture(hardTex, index: 1)
            enc.setFragmentTexture(caveTex, index: 2)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        if let pbuf {
            enc.setRenderPipelineState(partPipe)
            enc.setVertexBuffer(pbuf, offset: 0, index: 1)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: pn)
        }
        if let bbuf, insts.count > underCount {
            enc.setRenderPipelineState(ballPipe)
            enc.setVertexBuffer(bbuf, offset: 0, index: 1)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                               instanceCount: insts.count - underCount, baseInstance: underCount)
        }
        px.draw(sim: sim, enc: enc, device: device, format: rpd.colorAttachments[0].texture?.pixelFormat ?? .bgra8Unorm)
        enc.endEncoding()
    }
}
