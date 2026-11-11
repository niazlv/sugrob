import AppKit
import Metal
import ImageIO
import UniformTypeIdentifiers

/// Общая сцена для самотестов человечков без экрана: симуляция, два «окна», скриптовый курсор,
/// кадры в PNG (общий план и увеличенные вырезки). Сценарии — в PeopleTest*.swift.
final class PeopleStage {
    let sim: Sim
    let outDir: String
    let cell: Float, unit: Float
    let wPt: Float = 1400, hPt: Float = 800, scale: Float = 2
    /// Окна в пунктах экрана; номера окон в симуляции — 100, 101, …
    var wins: [CGRect] = [CGRect(x: 330, y: 190, width: 430, height: 520), CGRect(x: 930, y: 380, width: 330, height: 470)]
    var cur = SIMD2<Float>(-100, -100)      // курсор
    var curOn = false
    let dt: Float = 1.0 / 60

    private let renderer: Renderer
    private let queue: MTLCommandQueue
    private let target: MTLTexture
    private let cs = CGColorSpaceCreateDeviceRGB()
    private let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

    init(outDir: String, device: MTLDevice, renderer: Renderer, queue: MTLCommandQueue, cell: Float, unit: Float) {
        self.outDir = outDir
        self.cell = cell
        self.unit = unit
        self.renderer = renderer
        self.queue = queue
        sim = Sim(widthPt: wPt, heightPt: hPt, cell: cell, seed: 4242)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(wPt * scale), height: Int(hPt * scale), mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        target = device.makeTexture(descriptor: td)!
        sim.topLimit = 30
        setWindows()
        sim.cfg.flakeRate = 14
        sim.cfg.intensity = 1
        sim.cfg.peopleSize = unit
        sim.cfg.peopleEvents = false        // происшествия сценарий включает сам, когда они ему нужны
        sim.cfg.storms = false              // и бураны тоже: иначе в длинном прогоне налетит случайный
        sim.prefill()
        sim.forceFill = true; sim.fillSurfaces(); sim.forceFill = false
        sim.people.reseed(20261111)
        run(4)                              // окна «стоят на месте» уже несколько секунд
    }

    /// Передать симуляции текущие окна (после изменения `wins`).
    func setWindows() {
        let l = wins.enumerated().map {
            Ledge(y: Float($1.minY), x0: Float($1.minX) + 5.4, x1: Float($1.maxX) - 5.4, kind: 1, win: $0 + 100,
                  ox: Float($1.minX), wr: Float($1.maxX), r: 18)
        }
        let b = wins.enumerated().map {
            WinBox(x0: Float($1.minX), x1: Float($1.maxX), y0: Float($1.minY), y1: Float($1.maxY), win: $0 + 100)
        }
        sim.setLedges(l, windows: b)
    }

    /// Прогнать симуляцию; если задана цель, курсор за это время плавно едет к ней.
    func run(_ seconds: Float, to goal: SIMD2<Float>? = nil) {
        let n = max(1, Int(seconds / dt))
        let from = cur
        for i in 1...n {
            if let goal { cur = from + (goal - from) * (Float(i) / Float(n)) }
            sim.setCursor(x: cur.x, y: cur.y, dt: dt, on: curOn)
            sim.step(dt)
        }
    }

    /// Число ячеек снега в сетке.
    func cells() -> Int { sim.snow.reduce(0) { $0 + ($1 != 0 ? 1 : 0) } }

    /// Рамка вокруг всех человечков — для увеличенной вырезки.
    func around(pad: CGFloat = 50) -> CGRect {
        let f = sim.people.folks
        guard !f.isEmpty else { return CGRect(x: 500, y: 600, width: 400, height: 200) }
        let xs = f.map { CGFloat($0.x) }, ys = f.map { CGFloat($0.y) }
        let x0 = max(0, xs.min()! - pad), x1 = min(CGFloat(wPt), xs.max()! + pad)
        let y0 = max(0, ys.min()! - pad - 20), y1 = min(CGFloat(hPt), ys.max()! + 14)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    private func save(_ img: CGImage, _ name: String) {
        let url = URL(fileURLWithPath: outDir).appendingPathComponent(name + ".png")
        if let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dst, img, nil)
            CGImageDestinationFinalize(dst)
        }
    }

    /// Кадр: `<name>.png` целиком (если full) и вырезки `<name>-z0.png`, … (в пунктах экрана), увеличенные в zoom раз.
    /// Печатает строку со временем и `people.summary`.
    func shot(_ name: String, crops: [CGRect] = [], zoom: Int = 3, full: Bool = true) {
        let pw = Int(wPt * scale), ph = Int(hPt * scale)
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = target
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        let cmd = queue.makeCommandBuffer()!
        renderer.encode(sim: sim, cmd: cmd, rpd: rpd, scale: scale)
        cmd.commit()
        cmd.waitUntilCompleted()
        var px = [UInt8](repeating: 0, count: pw * ph * 4)
        target.getBytes(&px, bytesPerRow: pw * 4, from: MTLRegionMake2D(0, 0, pw, ph), mipmapLevel: 0)
        let snowImg = px.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(data: raw.baseAddress, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4,
                      space: cs, bitmapInfo: info)?.makeImage()
        }
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4,
                                  space: cs, bitmapInfo: info), let snowImg else { return }
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        let grad = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.07, green: 0.10, blue: 0.27, alpha: 1),
                                                        CGColor(red: 0.22, green: 0.30, blue: 0.50, alpha: 1)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: CGFloat(hPt)), options: [])
        for (i, w) in wins.enumerated() {
            ctx.setFillColor(i == 0 ? CGColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1)
                                    : CGColor(red: 0.15, green: 0.16, blue: 0.20, alpha: 1))
            ctx.addPath(CGPath(roundedRect: w, cornerWidth: 18, cornerHeight: 18, transform: nil))
            ctx.fillPath()
            for k in 0..<3 {
                ctx.setFillColor([CGColor(red: 1, green: 0.37, blue: 0.34, alpha: 1), CGColor(red: 1, green: 0.74, blue: 0.18, alpha: 1),
                                  CGColor(red: 0.16, green: 0.78, blue: 0.25, alpha: 1)][k])
                ctx.fillEllipse(in: CGRect(x: w.minX + 18 + CGFloat(k) * 20, y: w.minY + 16, width: 12, height: 12))
            }
        }
        ctx.scaleBy(x: 1 / CGFloat(scale), y: -1 / CGFloat(scale))
        ctx.translateBy(x: 0, y: -CGFloat(ph))
        ctx.draw(snowImg, in: CGRect(x: 0, y: 0, width: pw, height: ph))
        guard let out = ctx.makeImage() else { return }
        if full { save(out, name) }
        for (k, r) in crops.enumerated() {
            let pr = CGRect(x: r.minX * CGFloat(scale), y: r.minY * CGFloat(scale), width: r.width * CGFloat(scale), height: r.height * CGFloat(scale))
                .intersection(CGRect(x: 0, y: 0, width: pw, height: ph)).integral
            guard pr.width > 2, pr.height > 2, let part = out.cropping(to: pr) else { continue }
            let zw = Int(pr.width) * zoom, zh = Int(pr.height) * zoom
            guard let zc = CGContext(data: nil, width: zw, height: zh, bitsPerComponent: 8, bytesPerRow: zw * 4, space: cs, bitmapInfo: info) else { continue }
            zc.interpolationQuality = .none
            zc.draw(part, in: CGRect(x: 0, y: 0, width: zw, height: zh))
            if let z = zc.makeImage() { save(z, "\(name)-z\(k)") }
        }
        print(String(format: "%@  t=%.1f  %@", name, sim.time, sim.people.summary))
    }
}
