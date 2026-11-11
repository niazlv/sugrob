import Metal

/// Рисует «пиксели» человечков (см. People.emit): цветные прямоугольники поверх снега.
/// Свой маленький шейдер и свой конвейер — чтобы не трогать шейдеры снега.
final class PxRenderer {
    private static var pipes: [MTLPixelFormat.RawValue: MTLRenderPipelineState] = [:]
    private static var failed = false
    private var bufs: [MTLBuffer?] = [nil, nil, nil]
    private var frame = 0
    private var insts: [PxInst] = []

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct PxIn { float4 rect; float4 color; };
    struct PxOut { float4 pos [[position]]; float4 color [[flat]]; };
    vertex PxOut px_v(uint vid [[vertex_id]], uint iid [[instance_id]],
                      constant float2& view [[buffer(0)]], const device PxIn* b [[buffer(1)]]) {
        float2 q = float2(vid & 1, (vid >> 1) & 1);
        PxIn r = b[iid];
        float2 p = r.rect.xy + q * r.rect.zw;
        PxOut o;
        o.pos = float4(p.x / view.x * 2 - 1, 1 - p.y / view.y * 2, 0, 1);
        o.color = r.color;
        return o;
    }
    fragment float4 px_f(PxOut in [[stage_in]]) { return in.color; }
    """

    private static func pipe(_ device: MTLDevice, _ format: MTLPixelFormat) -> MTLRenderPipelineState? {
        if let p = pipes[format.rawValue] { return p }
        if failed { return nil }
        do {
            let lib = try device.makeLibrary(source: source, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "px_v")
            d.fragmentFunction = lib.makeFunction(name: "px_f")
            let a = d.colorAttachments[0]!
            a.pixelFormat = format
            a.isBlendingEnabled = true
            a.rgbBlendOperation = .add
            a.alphaBlendOperation = .add
            a.sourceRGBBlendFactor = .one
            a.sourceAlphaBlendFactor = .one
            a.destinationRGBBlendFactor = .oneMinusSourceAlpha
            a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            let p = try device.makeRenderPipelineState(descriptor: d)
            pipes[format.rawValue] = p
            return p
        } catch {
            NSLog("Sugrob: people shader error: \(error)")
            failed = true
            return nil
        }
    }

    func draw(sim: Sim, enc: MTLRenderCommandEncoder, device: MTLDevice, format: MTLPixelFormat) {
        insts.removeAll(keepingCapacity: true)
        sim.people.emit(sim, into: &insts)
        guard !insts.isEmpty, let pipe = PxRenderer.pipe(device, format) else { return }
        frame = (frame + 1) % 3
        let bytes = insts.count * MemoryLayout<PxInst>.stride
        if bufs[frame] == nil || bufs[frame]!.length < bytes {
            var cap = 1 << 14
            while cap < bytes { cap <<= 1 }
            bufs[frame] = device.makeBuffer(length: cap, options: .storageModeShared)
        }
        guard let buf = bufs[frame] else { return }
        insts.withUnsafeBytes { raw in buf.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count) }
        var view = SIMD2<Float>(sim.wPt, sim.hPt)
        enc.setRenderPipelineState(pipe)
        enc.setVertexBytes(&view, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        enc.setVertexBuffer(buf, offset: 0, index: 1)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: insts.count)
    }
}
