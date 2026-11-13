import AppKit
import Foundation

let logicalSize = NSSize(width: 340, height: 260)
let clockNow: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

struct SpriteMetrics {
    var bottomInset: CGFloat = 0
    var topInset: CGFloat = 0
    var headTopInset: CGFloat = 0
    var headX: CGFloat = 0.5
    var headSpan: CGFloat = 1
    static func inspect(_ data: Data) -> SpriteMetrics {
        guard let rep = NSBitmapImageRep(data: data), let bytes = rep.bitmapData,
              !rep.isPlanar, rep.bitsPerSample == 8, rep.hasAlpha else { return SpriteMetrics() }
        let w = rep.pixelsWide, h = rep.pixelsHigh, stride = rep.samplesPerPixel
        let alpha = rep.bitmapFormat.contains(.alphaFirst) ? 0 : stride - 1
        var top = h, bottom = -1
        for y in 0..<h {
            for x in 0..<w where bytes[y * rep.bytesPerRow + x * stride + alpha] > 150 {
                top = min(top, y); bottom = max(bottom, y)
            }
        }
        guard bottom >= top else { return SpriteMetrics() }
        let band = max(3, min(12, h / 45))
        let rgbStart = rep.bitmapFormat.contains(.alphaFirst) ? 1 : 0
        func white(_ x: Int, _ y: Int) -> Bool {
            guard stride >= 4 else { return false }
            let offset = y * rep.bytesPerRow + x * stride
            guard bytes[offset + alpha] > 150 else { return false }
            let r = Int(bytes[offset + rgbStart]), g = Int(bytes[offset + rgbStart + 1]), b = Int(bytes[offset + rgbStart + 2])
            return min(r, g, b) > 215 && max(r, g, b) - min(r, g, b) < 20
        }
        var whiteTop = h
        for y in top...bottom {
            for x in 0..<w where white(x, y) { whiteTop = min(whiteTop, y) }
        }
        let usesWhite = whiteTop < h
        let crown = usesWhite ? whiteTop : top
        var total: CGFloat = 0, weighted: CGFloat = 0
        var headLeft = w, headRight = 0
        let headBottom = min(bottom, crown + Int(Double(bottom - top) * 0.43))
        for y in crown...headBottom {
            for x in 0..<w {
                let belongs = usesWhite ? white(x, y) : bytes[y * rep.bytesPerRow + x * stride + alpha] > 150
                if !belongs { continue }
                headLeft = min(headLeft, x); headRight = max(headRight, x)
                if y <= crown + band { total += 1; weighted += CGFloat(x) }
            }
        }
        return SpriteMetrics(bottomInset: CGFloat(h - bottom - 1) / CGFloat(h), topInset: CGFloat(top) / CGFloat(h), headTopInset: CGFloat(max(0, crown - (usesWhite ? 2 : 0))) / CGFloat(h), headX: total > 0 ? weighted / total / CGFloat(w) : 0.5, headSpan: CGFloat(max(1, headRight - headLeft + 1)))
    }
}

struct SupportAnchor: Decodable {
    let supportYFromBottom: Double
    let headX: Double
    let headYFromBottom: Double
    let bellyX: Double?
    let bellyYFromBottom: Double?
}

final class PetAssets {
    static let names = ["doghouse", "typewriter", "woodstock", "sit-1", "charlie-stand", "charlie-turn-1", "charlie-turn-2"] + (1...16).map { "charlie-\($0)" } + (1...6).map { "hop-\($0)" } + ["dance-first-1", "dance-first-2"] + (1...16).map { String(format: "typing-%02d", $0) } + (1...4).map { "sleep-\($0)" } + (1...6).map { "wake-\($0)" } + (1...8).map { "climb-\($0)" } + (1...4).map { "woodstock-flight-\($0)" } + ["weather-sunny", "weather-pilot", "weather-umbrella", "weather-rain-reach", "weather-rain-hold", "weather-rain-reference", "weather-rain-neutral"] + (1...4).map { "weather-umbrella-flight-\($0)" }
    var images: [String: NSImage] = [:]
    var metrics: [String: SpriteMetrics] = [:]
    var rainUpperContours: [String: [CGFloat?]] = [:]
    var missing: [String] = []
    var climbGrips: [String: NSPoint] = [:]
    var bellyRoosts: [String: NSPoint] = [:]
    init() {
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
        let externalArtwork=Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Assets") : nil
        let candidates = [externalArtwork,Bundle.main.resourceURL?.appendingPathComponent("Assets"), executableDirectory.appendingPathComponent("Assets"), executableDirectory.deletingLastPathComponent().appendingPathComponent("Assets"), URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets")].compactMap { $0 }
        for name in Self.names {
            if let url = candidates.map({ $0.appendingPathComponent(name + ".png") }).first(where: { FileManager.default.fileExists(atPath: $0.path) }), let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
                images[name] = image
                var inspected = SpriteMetrics.inspect(data)
                if name.hasPrefix("classic-"), let index = Int(name.dropFirst(8)), (1...16).contains(index) {
                    let crowns: [CGFloat] = [0.8830,0.8943,0.8868,0.8906,0.8906,0.8943,0.8792,0.8906,0.8755,0.8792,0.8792,0.8830,0.8792,0.8717,0.8868,0.8906]
                    inspected.headX = [8,9,11].contains(index) ? 0.4263 : 0.4303
                    inspected.headTopInset = 1 - crowns[index - 1]
                }
                if name.hasPrefix("hop-"), let index = Int(name.dropFirst(4)), (1...6).contains(index) {
                    let crowns: [CGFloat] = [42, 7, 47, 31, 8, 42]
                    inspected.headX = 0.611
                    inspected.headTopInset = crowns[index - 1] / 423
                }
                metrics[name] = inspected
            } else { missing.append(name) }
        }
        // Flight frames share the canopy registration and planted-pose baseline even with tucked feet.
        if let baseline=metrics["weather-umbrella"]?.bottomInset {
            for index in 1...4 {
                let name="weather-umbrella-flight-\(index)"
                if var inspected=metrics[name] { inspected.bottomInset=baseline;metrics[name]=inspected }
            }
        }
        if let url = candidates.map({ $0.appendingPathComponent("sleep-anchors.json") }).first(where: { FileManager.default.fileExists(atPath: $0.path) }), let data = try? Data(contentsOf: url), let anchors = try? JSONDecoder().decode([String: SupportAnchor].self, from: data) {
            for name in (1...4).map({ "sleep-\($0)" }) + (1...6).map({ "wake-\($0)" }) {
                guard let anchor = anchors[name], (0...1).contains(anchor.supportYFromBottom), (0...1).contains(anchor.headX), (0...1).contains(anchor.headYFromBottom), anchor.headYFromBottom > anchor.supportYFromBottom else {
                    missing.append("sleep-anchors.json: " + name); continue
                }
                if var inspected = metrics[name] {
                    // A sleeping ear hangs below the roof; support is the back, rather than the lowest visible pixel.
                    inspected.bottomInset = CGFloat(anchor.supportYFromBottom)
                    inspected.headX = CGFloat(anchor.headX)
                    inspected.headTopInset = 1 - CGFloat(anchor.headYFromBottom)
                    metrics[name] = inspected
                }
                if let x = anchor.bellyX, let y = anchor.bellyYFromBottom, (0...1).contains(x), (0...1).contains(y) {
                    bellyRoosts[name] = NSPoint(x: x, y: y)
                } else if name.hasPrefix("sleep-") {
                    missing.append("sleep-anchors.json belly: " + name)
                }
            }
        } else { missing.append("sleep-anchors.json") }
        if let url = candidates.map({ $0.appendingPathComponent("climb-anchors.json") }).first(where: { FileManager.default.fileExists(atPath: $0.path) }), let data = try? Data(contentsOf: url), let anchors = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]] {
            for (name, anchor) in anchors {
                guard var metric = metrics[name] else { continue }
                if let x = anchor["headX"] as? Double { metric.headX = CGFloat(x) }
                if let y = anchor["headYFromBottom"] as? Double { metric.headTopInset = 1 - CGFloat(y) }
                if ["climb-5", "climb-6"].contains(name), (anchor["gripContact"] as? Bool ?? true), let x = anchor["gripX"] as? Double, let y = anchor["gripYFromBottom"] as? Double { climbGrips[name] = NSPoint(x: x, y: y) }
                metrics[name] = metric
            }
        }
        do { try installSmoothSleepFrames() }
        catch { missing.append("32-frame breathing: " + error.localizedDescription) }
        do { InteractionMotionSettings.apply(try InteractionMotionSettings.load(),whileInteracting:false) }
        catch { missing.append("互动速度：" + error.localizedDescription) }
        do { try prepareOriginalRainArtwork() }
        catch { missing.append("雨天原画：" + error.localizedDescription) }
    }
    func fittedRect(_ name: String, in box: NSRect) -> NSRect {
        guard let image = images[name], image.size.width > 0, image.size.height > 0 else { return box }
        let scale = min(box.width / image.size.width, box.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSRect(x: box.midX - size.width / 2, y: box.minY - (metrics[name]?.bottomInset ?? 0) * size.height, width: size.width, height: size.height)
    }
    func headPoint(_ name: String, in box: NSRect, mirrored: Bool = false) -> NSPoint {
        if name.hasPrefix("typing-") { return typingHeadPoint(name,in:box,mirrored:mirrored) }
        let canonical = name
        let fit = fittedRect(canonical, in: box), m = metrics[canonical] ?? SpriteMetrics()
        return NSPoint(x: fit.minX + fit.width * (mirrored ? 1 - m.headX : m.headX), y: fit.maxY - fit.height * m.headTopInset)
    }
    func draw(_ name: String, in box: NSRect, alpha: CGFloat = 1, flip: Bool = false, rotation: CGFloat = 0) {
        if name.hasPrefix("typing-") {
            drawStableTyping(name,in:box,alpha:alpha,flip:flip,rotation:rotation)
            return
        }
        guard let image = images[name], alpha > 0 else { return }
        let rect = fittedRect(name, in: box)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.translateBy(x: rect.midX, y: rect.midY)
        if rotation != 0 { NSGraphicsContext.current?.cgContext.rotate(by: rotation * .pi / 180) }
        if flip { NSGraphicsContext.current?.cgContext.scaleBy(x: -1, y: 1) }
        image.draw(in: NSRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height), from: .zero, operation: .sourceOver, fraction: alpha)
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class PetRenderer {
    let assets: PetAssets
    var weatherPresentation: WeatherPresentation?
    init(assets: PetAssets) { self.assets = assets }
    private struct Body { var image: String; var box: NSRect; var alpha: CGFloat = 1 }
    func draw(phase: PetPhase, elapsed: Double, animation: Double, in bounds: NSRect, showLabel: Bool = false) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.clip(to: bounds)
        NSGraphicsContext.current?.cgContext.translateBy(x: bounds.minX, y: bounds.minY)
        NSGraphicsContext.current?.cgContext.scaleBy(x: bounds.width / logicalSize.width, y: bounds.height / logicalSize.height)
        NSGraphicsContext.current?.imageInterpolation = .high
        // fittedRect always applies one uniform scale; the original house proportions are preserved.
        let house = NSRect(x: 140, y: 20, width: 114, height: 104)
        let houseFit = assets.fittedRect("doghouse", in: house)
        let roofY = houseFit.maxY - houseFit.height * (assets.metrics["doghouse"]?.topInset ?? 0)
        let seat = NSRect(x: 140, y: roofY - 1.2, width: 98, height: 90)
        let seatFit = assets.fittedRect("sit-1", in: seat)
        let machine = NSRect(x: seatFit.minX + seatFit.width * 260 / 526, y: seat.minY, width: seatFit.width * 262 / 526, height: 38)
        assets.draw("doghouse", in: house)
        let ground: CGFloat = 20
        let hopWidths = (1...6).compactMap { assets.metrics["hop-\($0)"]?.headSpan }.sorted()
        let targetHeadWidth = (assets.metrics["sit-1"]?.headSpan ?? 310) * seatFit.width / (assets.images["sit-1"]?.size.width ?? 526)
        let hopScale: CGFloat = hopWidths.isEmpty ? 0.18 : targetHeadWidth / hopWidths[hopWidths.count / 2]
        func hopBody(_ time: Double, alpha: CGFloat = 1) -> Body {
            let name = "hop-\(PetMotion.hopFrame(time))", size = assets.images["hop-1"]?.size ?? NSSize(width: 463, height: 423)
            let foot = PetMotion.hopFoot(time, roof: Double(seat.minY), ground: Double(ground))
            return Body(image: name, box: NSRect(x: CGFloat(foot.x) - size.width * hopScale / 2, y: CGFloat(foot.y), width: size.width * hopScale, height: size.height * hopScale), alpha: alpha)
        }
        let danceHeights = ["dance-first-1","dance-first-2"].compactMap { name -> CGFloat? in
            guard let size = assets.images[name]?.size, let m = assets.metrics[name] else { return nil }
            return size.height * (1 - m.topInset - m.bottomInset)
        }
        let danceScale: CGFloat = 100 / max(1,danceHeights.max() ?? 311)
        func danceBody(_ time: Double, alpha: CGFloat = 1) -> Body {
            let name = "dance-first-\(PetMotion.supperFrame(time))"
            let size = assets.images[name]?.size ?? NSSize(width:261,height:321)
            return Body(image:name,box:NSRect(x:260-size.width*danceScale/2+CGFloat(PetMotion.supperSway(time)),y:ground+CGFloat(PetMotion.supperLift(time)),width:size.width*danceScale,height:size.height*danceScale),alpha:alpha)
        }
        let awakeHead = assets.headPoint("typing-01", in: seat)
        func restBody(_ name: String, alpha: CGFloat = 1) -> Body {
            Body(image: name, box: restBodyBox(for: name), alpha: alpha)
        }
        func wakeBodies(_ wakeTime: Double) -> (bodies: [Body], seated: CGFloat, machine: CGFloat) {
            let t = min(PetTiming.wake, max(0, wakeTime))
            let seated = CGFloat(PetMotion.smooth((t - (PetTiming.wake - 0.3)) / 0.3))
            let rising = CGFloat(PetMotion.smooth(t / 0.12))
            let machine = CGFloat(PetMotion.smooth((t - 0.55) / 0.35))
            return ([restBody(PetMotion.sleepSprite(animation), alpha: (1 - rising) * (1 - seated)), restBody("wake-\(PetMotion.wakeFrame(t))", alpha: rising * (1 - seated)), Body(image: "typing-01", box: seat, alpha: seated)], seated, machine)
        }
        let climbEndSize = assets.images["climb-8"]?.size ?? NSSize(width: 600, height: 600)
        let climbEndMetric = assets.metrics["climb-8"] ?? SpriteMetrics(bottomInset: 0.02, headTopInset: 0.25)
        let climbScale = (awakeHead.y - seat.minY) / max(1, climbEndSize.height * (1 - climbEndMetric.headTopInset - climbEndMetric.bottomInset))
        func climbBox(_ index: Int) -> NSRect {
            let name = "climb-\(index)", size = assets.images["climb-\(index)"]?.size ?? climbEndSize
            let metric = assets.metrics[name] ?? climbEndMetric
            let w = size.width * climbScale, h = size.height * climbScale
            if index == 8 {
                return NSRect(x: awakeHead.x - metric.headX * w, y: seat.minY, width: w, height: h)
            }
            if let grip = assets.climbGrips[name], [5,6].contains(index) {
                let targets: [NSPoint] = [NSPoint(x: 253,y: 64), NSPoint(x: 253,y: 64), NSPoint(x: 248,y: 89), NSPoint(x: 243,y: 110), NSPoint(x: 214,y: roofY)]
                let target = targets[index - 2]
                return NSRect(x: target.x - grip.x * w, y: target.y - grip.y * h + metric.bottomInset * h, width: w, height: h)
            }
            let centers: [CGFloat] = [260,253,245,235,225,214,207]
            let heights: [CGFloat] = [ground,ground,38,65,90,seat.minY,seat.minY]
            return NSRect(x: centers[index - 1] - w / 2, y: heights[index - 1], width: w, height: h)
        }
        func climbBodies(_ time: Double, alpha: CGFloat = 1) -> [Body] {
            let slot = PetTiming.returning / 8
            let p = min(7, max(0, time / slot))
            let index = min(8, Int(p) + 1), next = min(8, index + 1)
            let fraction = p - floor(p)
            let poseBlend = CGFloat(PetMotion.smooth((fraction * slot - (slot - 0.15)) / 0.15))
            let a = climbBox(index), b = climbBox(next)
            // Hanging hands and planted roof feet stay attached; blend actual poses instead of floating their contacts.
            let planted = index >= 5
            let travel = planted ? CGFloat(0) : CGFloat(PetMotion.smooth(fraction))
            let box = NSRect(x:a.minX+(b.minX-a.minX)*travel,y:a.minY+(b.minY-a.minY)*travel,width:a.width,height:a.height)
            return [Body(image:"climb-\(index)",box:box,alpha:alpha*(1-poseBlend)),Body(image:"climb-\(next)",box:b,alpha:alpha*poseBlend)]
        }

        var bodies: [Body] = [], seatedAlpha: CGFloat = 0, machineVisibility: CGFloat = 1
        switch phase {
        case .idle:
            machineVisibility = 0; bodies = [restBody(PetMotion.sleepSprite(animation))]
        case .weather:
            machineVisibility = 0
            if let presentation = weatherPresentation { drawWeather(presentation, animation: animation) }
        case .interacting:
            machineVisibility = 0; drawBellyInteraction(elapsed: elapsed, animation: animation)
        case .waking, .settling:
            let time = phase == .waking ? elapsed : PetTiming.wake * (1 - min(1, max(0, elapsed / PetTiming.settle)))
            let result = wakeBodies(time); bodies = result.bodies; seatedAlpha = result.seated; machineVisibility = result.machine
        case .working:
            seatedAlpha = 1; bodies = [Body(image: String(format: "typing-%02d", PetMotion.typingFrame(animation)), box: seat)]
        case .delivery:
            switch PetMotion.arrivalAction(elapsed) {
            case .typing:
                seatedAlpha = 1; bodies = [Body(image: String(format: "typing-%02d", PetMotion.typingFrame(animation)), box: seat)]
            case .hopping:
                let hopTime = elapsed - PetTiming.anticipation, blend = CGFloat(PetMotion.smooth(hopTime / 0.18))
                seatedAlpha = 1 - blend
                bodies = [Body(image: "typing-01", box: seat, alpha: seatedAlpha), hopBody(hopTime, alpha: blend)]
            case .dancing:
                let danceTime = elapsed - PetTiming.anticipation - PetTiming.hop, blend = CGFloat(PetMotion.smooth(danceTime / 0.22))
                bodies = [hopBody(PetTiming.hop, alpha: 1 - blend), danceBody(danceTime, alpha: blend)]
            }
        case .dancing: bodies = [danceBody(PetTiming.danceLead + elapsed)]
        case .departing: bodies = [danceBody(min(PetMotion.supperRestTime, PetTiming.totalDance + elapsed))]
        case .returning:
            let seatBlend = CGFloat(PetMotion.smooth((elapsed - (PetTiming.returning - 0.25)) / 0.25))
            let leaveDance = CGFloat(PetMotion.smooth(elapsed / 0.18))
            seatedAlpha = seatBlend
            bodies = [danceBody(PetMotion.supperRestTime, alpha: 1 - leaveDance)] + climbBodies(elapsed,alpha:leaveDance*(1-seatBlend)) + [Body(image:"typing-01",box:seat,alpha:seatBlend)]
        }
        assets.draw("typewriter", in: machine, alpha: machineVisibility * (1 - seatedAlpha))
        if phase == .delivery || phase == .dancing || phase == .departing {
            let visibleHeights = (1...16).compactMap { index -> CGFloat? in
                let name = "charlie-\(index)"
                guard let image = assets.images[name], let metric = assets.metrics[name] else { return nil }
                return image.size.height * (1 - metric.topInset - metric.bottomInset)
            }
            let scale: CGFloat = 106 / max(1, visibleHeights.max() ?? 388)
            func charlieBox(_ name: String, center: CGFloat) -> NSRect {
                let size = assets.images[name]?.size ?? NSSize(width:440,height:403)
                return NSRect(x:center-size.width*scale/2,y:ground,width:size.width*scale,height:size.height*scale)
            }
            if phase == .delivery {
                let distance = PetMotion.charlieDistance(elapsed)
                let image = elapsed < PetTiming.walk ? "charlie-\(PetMotion.gaitFrame(distance: distance))" : "charlie-stand"
                assets.draw(image,in:charlieBox(image,center:CGFloat(-28+distance)))
            } else if phase == .dancing {
                assets.draw("charlie-stand",in:charlieBox("charlie-stand",center:160))
            } else if elapsed < PetTiming.turn {
                let name = elapsed < PetTiming.turn / 2 ? "charlie-turn-1" : "charlie-turn-2"
                assets.draw(name,in:charlieBox(name,center:160))
            } else {
                let distance = PetMotion.departureDistance(elapsed)
                let image = "charlie-\(PetMotion.gaitFrame(distance:distance))"
                assets.draw(image,in:charlieBox(image,center:CGFloat(160-distance)),flip:true)
            }
        }

        for body in bodies where body.alpha > 0 {
            assets.draw(body.image, in: body.box, alpha: body.alpha)
        }
        let birdVisibility = CGFloat(PetMotion.woodstockVisibility(phase:phase,elapsed:elapsed))
        for body in bodies where body.alpha > 0 && birdVisibility > 0 {
            let head = assets.headPoint(body.image,in:body.box)
            var point = head
            var inset = 1.5 - sin(animation * 2) * 0.15
            if let bellyAnchor = assets.bellyRoosts[body.image] {
                let fit = assets.fittedRect(body.image, in: body.box)
                let belly = NSPoint(x: fit.minX + fit.width * bellyAnchor.x, y: fit.minY + fit.height * bellyAnchor.y)
                let wakeTime = phase == .waking ? elapsed : PetTiming.wake * (1 - min(1, max(0, elapsed / PetTiming.settle)))
                let headBlend = phase == .idle ? 0 : PetMotion.smooth((wakeTime - 0.04) / 0.32)
                point = NSPoint(x: belly.x + (head.x - belly.x) * headBlend,
                               y: belly.y + (head.y - belly.y) * headBlend + sin(headBlend * .pi) * 5)
                inset = 1.2
            }
            // The sleeping perch follows the breathing belly; awake poses keep the head perch.
            assets.draw("woodstock",in:NSRect(x:point.x-10,y:point.y-inset,width:20,height:21),alpha:body.alpha*birdVisibility)
        }

        if showLabel {
            let style = NSMutableParagraphStyle(); style.alignment = .center
            (phase.title as NSString).draw(in: NSRect(x: 4, y: 2, width: logicalSize.width - 8, height: 17), withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor(calibratedWhite: 0.2, alpha: 1), .paragraphStyle: style])
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

enum PetWindowGeometry {
    static func panelFrame(sceneOrigin: NSPoint, crop: NSRect) -> NSRect {
        NSRect(x:sceneOrigin.x+crop.minX,y:sceneOrigin.y+crop.minY,width:crop.width,height:crop.height)
    }
    static func sceneOrigin(panelOrigin: NSPoint, crop: NSRect) -> NSPoint {
        NSPoint(x:panelOrigin.x-crop.minX,y:panelOrigin.y-crop.minY)
    }
    static func clampedOrigin(_ origin: NSPoint, visible: NSRect, screen: NSRect) -> NSPoint {
        let minimumX = screen.minX-visible.minX, maximumX = screen.maxX-visible.maxX
        let minimumY = screen.minY-visible.minY, maximumY = screen.maxY-visible.maxY
        return NSPoint(x:min(max(origin.x,minimumX),max(minimumX,maximumX)),y:min(max(origin.y,minimumY),max(minimumY,maximumY)))
    }
    static func paddedCrop(_ visible: NSRect, canvas: NSRect) -> NSRect {
        let expanded = visible.insetBy(dx:-4,dy:-4)
        let grid: CGFloat = 2
        let x = floor(expanded.minX/grid)*grid, y = floor(expanded.minY/grid)*grid
        return NSRect(x:x,y:y,width:ceil(expanded.maxX/grid)*grid-x,height:ceil(expanded.maxY/grid)*grid-y).intersection(canvas)
    }
}

struct CropEnvelope {
    private(set) var rect: NSRect = .zero
    private var phase: PetPhase?
    mutating func update(_ target: NSRect, phase next: PetPhase) -> NSRect {
        if phase != next || rect.isEmpty { rect = target; phase = next }
        else { rect = rect.union(target) }
        return rect
    }
    mutating func reset() { phase = nil; rect = .zero }
}

final class CachedScene {
    let bitmap: NSBitmapImageRep
    let image: NSImage
    let pixelsPerPoint: CGFloat
    let pixelWidth: Int, pixelHeight: Int
    let visible: NSRect
    let canvas: NSRect
    private let alpha: [UInt8]
    init(bitmap: NSBitmapImageRep, pixelsPerPoint: CGFloat) throws {
        guard let bytes = bitmap.bitmapData, let cg = bitmap.cgImage else { throw NSError(domain:"SceneCache",code:1) }
        self.bitmap = bitmap; self.pixelsPerPoint = pixelsPerPoint
        pixelWidth = bitmap.pixelsWide; pixelHeight = bitmap.pixelsHigh
        let width = pixelWidth, height = pixelHeight
        canvas = NSRect(x:0,y:0,width:CGFloat(width)/pixelsPerPoint,height:CGFloat(height)/pixelsPerPoint)
        image = NSImage(cgImage:cg,size:canvas.size)
        let stride = bitmap.samplesPerPixel, channel = bitmap.bitmapFormat.contains(.alphaFirst) ? 0 : stride-1
        var mask = [UInt8](repeating:0,count:width*height)
        var minX = width, minRow = height, maxX = -1, maxRow = -1
        for row in 0..<height {
            for x in 0..<width {
                let value = bytes[row*bitmap.bytesPerRow+x*stride+channel]
                mask[row*width+x] = value
                if value > 8 { minX=min(minX,x); maxX=max(maxX,x); minRow=min(minRow,row); maxRow=max(maxRow,row) }
            }
        }
        alpha = mask
        if maxX >= minX {
            visible = NSRect(x:CGFloat(minX)/pixelsPerPoint,y:CGFloat(height-maxRow-1)/pixelsPerPoint,width:CGFloat(maxX-minX+1)/pixelsPerPoint,height:CGFloat(maxRow-minRow+1)/pixelsPerPoint)
        } else { visible = NSRect(x:0,y:0,width:1,height:1) }
    }
    static func render(renderer: PetRenderer, phase: PetPhase, elapsed: Double, animation: Double, scale: CGFloat, retina: CGFloat) throws -> CachedScene {
        let ratio = scale*retina
        let (bitmap,context) = try previewBitmap(width:Int(ceil(logicalSize.width*ratio)),height:Int(ceil(logicalSize.height*ratio)))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x:0,y:0,width:bitmap.pixelsWide,height:bitmap.pixelsHigh))
        renderer.draw(phase:phase,elapsed:elapsed,animation:animation,in:NSRect(x:0,y:0,width:logicalSize.width*ratio,height:logicalSize.height*ratio))
        NSGraphicsContext.restoreGraphicsState()
        return try CachedScene(bitmap:bitmap,pixelsPerPoint:retina)
    }
    func opaque(at point: NSPoint) -> Bool {
        let x = Int(floor(point.x*pixelsPerPoint)), fromBottom = Int(floor(point.y*pixelsPerPoint))
        guard x>=0,fromBottom>=0,x<pixelWidth,fromBottom<pixelHeight else { return false }
        return alpha[(pixelHeight-1-fromBottom)*pixelWidth+x] > 32
    }
    func writeCrop(_ crop: NSRect, to path: String) throws {
        let width = Int(ceil(crop.width*pixelsPerPoint)), height = Int(ceil(crop.height*pixelsPerPoint))
        let (output,context) = try previewBitmap(width:width,height:height)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x:0,y:0,width:width,height:height))
        context.cgContext.scaleBy(x:pixelsPerPoint,y:pixelsPerPoint)
        image.draw(in:NSRect(x:-crop.minX,y:-crop.minY,width:canvas.width,height:canvas.height),from:.zero,operation:.sourceOver,fraction:1)
        NSGraphicsContext.restoreGraphicsState()
        try writePreview(output,path:path)
    }
}

func runWindowGeometryTests() throws {
    struct Failure: Error, CustomStringConvertible { let description: String }
    var count = 0
    func check(_ value: @autoclosure () -> Bool,_ message: String) throws {
        guard value() else { throw Failure(description:message) }; count += 1
    }
    let origin=NSPoint(x:50,y:80),crop=NSRect(x:100,y:14,width:90,height:120)
    let frame=PetWindowGeometry.panelFrame(sceneOrigin:origin,crop:crop)
    try check(frame.origin==NSPoint(x:150,y:94) && frame.size==crop.size,"Physical panel wraps the crop, not the full scene")
    try check(PetWindowGeometry.sceneOrigin(panelOrigin:frame.origin,crop:crop)==origin,"Scene origin survives crop/window conversion")
    let screen=NSRect(x:0,y:0,width:1000,height:800),visible=NSRect(x:100,y:14,width:82,height:110)
    let left=PetWindowGeometry.clampedOrigin(NSPoint(x:-999,y:80),visible:visible,screen:screen)
    try check(left.x == -100 && left.x+visible.minX == 0,"Visible artwork reaches screen left with a negative full-scene origin")
    let right=PetWindowGeometry.clampedOrigin(NSPoint(x:9999,y:80),visible:visible,screen:screen)
    try check(right.x+visible.maxX==screen.maxX,"Right clamp also uses artwork bounds")
    let padded=PetWindowGeometry.paddedCrop(visible,canvas:NSRect(x:0,y:0,width:245,height:188))
    try check(PetWindowGeometry.panelFrame(sceneOrigin:left,crop:padded).minX == -4,"Transparent padding does not stop left-edge dragging")
    var envelope=CropEnvelope()
    _=envelope.update(crop,phase:.idle)
    let grown=envelope.update(crop.insetBy(dx:-1,dy:-1),phase:.idle)
    try check(envelope.update(crop,phase:.idle)==grown,"Same-phase envelope avoids per-frame window jitter")
    try check(envelope.update(crop,phase:.working)==crop,"A new phase removes obsolete blank window space")
    let (bitmap,context)=try previewBitmap(width:100,height:100)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=context
    context.cgContext.clear(CGRect(x:0,y:0,width:100,height:100))
    NSColor.white.setFill(); NSRect(x:10,y:20,width:30,height:40).fill()
    NSGraphicsContext.restoreGraphicsState()
    let cache=try CachedScene(bitmap:bitmap,pixelsPerPoint:1)
    try check(cache.visible==NSRect(x:10,y:20,width:30,height:40),"RGBA alpha bounds use the correct macOS bottom-left coordinates")
    try check(cache.opaque(at:NSPoint(x:15,y:25)) && !cache.opaque(at:NSPoint(x:2,y:25)),"Only opaque cached pixels accept mouse events")
    let house=NSPoint(x:140*0.72,y:20*0.72)
    let before=PetWindowGeometry.panelFrame(sceneOrigin:origin,crop:crop).origin
    let changed=NSRect(x:0,y:8,width:230,height:150)
    let after=PetWindowGeometry.panelFrame(sceneOrigin:origin,crop:changed).origin
    try check(before.x+house.x-crop.minX==after.x+house.x-changed.minX,"Changing physical window bounds never slides the house")
    print("PASS: \(count) physical-window and alpha-hit assertions")
}

final class PetView: NSView {
    var cache: CachedScene?
    var crop: NSRect = .zero
    var menuProvider: (() -> NSMenu)?
    var clickAction: ((NSPoint, Int) -> Void)?
    var dragStarted: (() -> Void)?
    var dragMoved: ((NSPoint) -> Void)?
    var dragFinished: (() -> Void)?
    private var startMouse: NSPoint = .zero
    private var pressPoint: NSPoint = .zero
    private var pressCount = 1
    private var gesture = BellyClickGesture()
    private(set) var isDragging = false
    init() {
        super.init(frame:.zero)
        wantsLayer=true; layer?.backgroundColor=NSColor.clear.cgColor
        toolTip="点击睡姿肚子互动 · 拖动移动 · 右键设置"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill(using:.copy)
        guard let cache else { return }
        NSGraphicsContext.current?.imageInterpolation = .high
        cache.image.draw(in:NSRect(x:-crop.minX,y:-crop.minY,width:cache.canvas.width,height:cache.canvas.height),from:.zero,operation:.sourceOver,fraction:1)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        startMouse=NSEvent.mouseLocation; isDragging=true; gesture=BellyClickGesture()
        let local=convert(event.locationInWindow,from:nil)
        pressPoint=NSPoint(x:local.x+crop.minX,y:local.y+crop.minY); pressCount=event.clickCount
        dragStarted?()
    }
    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let point=NSEvent.mouseLocation
        let delta=NSPoint(x:point.x-startMouse.x,y:point.y-startMouse.y)
        gesture.moved(delta)
        if gesture.dragged { dragMoved?(delta) }
    }
    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        let point=NSEvent.mouseLocation
        gesture.moved(NSPoint(x:point.x-startMouse.x,y:point.y-startMouse.y))
        isDragging=false
        if gesture.dragged { dragFinished?() } else { clickAction?(pressPoint,pressCount) }
    }
    override func rightMouseDown(with event: NSEvent) {
        if let menu=menuProvider?() { NSMenu.popUpContextMenu(menu,with:event,for:self) }
    }
}


final class PetPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // Artwork is clamped on release; transparent crop padding may legitimately lie offscreen.
        frameRect
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = PetState()
    let assets = PetAssets()
    let weather = WeatherService()
    var weatherSchedule = WeatherSchedule(startedAt: clockNow())
    lazy var renderer = PetRenderer(assets: assets)
    lazy var monitor = ActivityMonitor { [weak self] source, phase in
        self?.state.receive(source: source, phase: phase, at: clockNow())
    }
    var panel: NSPanel!
    var petView: PetView!
    var statusItem: NSStatusItem!
    var timer: Timer?
    var sceneOrigin: NSPoint = .zero
    var dragSceneOrigin: NSPoint = .zero
    var cachedScene: CachedScene?
    var crop: NSRect = .zero
    var cropEnvelope=CropEnvelope()
    var lastPoseKey: String?
    var sceneScale: CGFloat = CGFloat(UserDefaults.standard.double(forKey: "petScale"))

    func applicationDidFinishLaunching(_ notification: Notification) {
        if assets.missing.count > 0 {
            let alert = NSAlert(); alert.messageText = "桌宠素材不完整"; alert.informativeText = "缺少：" + assets.missing.joined(separator: ", "); alert.runModal(); NSApp.terminate(nil); return
        }
        weatherSchedule = WeatherSchedule(startedAt:clockNow(), interval:weather.settings.interval)
        weatherSchedule.enabled = weather.settings.enabled && weather.settings.location != nil
        let defaults = UserDefaults.standard
        if defaults.integer(forKey: "compactLayoutRevision") < 2 {
            sceneScale = 0.72
            defaults.set(0.72, forKey: "petScale")
            defaults.set(2, forKey: "compactLayoutRevision")
        }
        if sceneScale < 0.45 || sceneScale > 1.1 { sceneScale = 0.72 }
        NSApp.setActivationPolicy(.accessory)
        panel = PetPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: logicalSize.width * sceneScale, height: logicalSize.height * sceneScale)), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Snoopy Desktop"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        petView = PetView()
        petView.autoresizingMask = [.width, .height]
        petView.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }
        petView.clickAction = { [weak self] point, count in
            guard let self else { return }
            let logical=NSPoint(x:point.x/self.sceneScale,y:point.y/self.sceneScale)
            guard self.state.phase != .weather else { return }
            let intent=PetClickIntent.resolve(phase:self.state.phase,hitsBelly:self.renderer.idleBellyHit(logical,animation:clockNow()),count:count)
            switch intent {
            case .touchBelly: _=self.state.startBellyInteraction(at:clockNow()); self.refreshScene(force:true)
            case .demo: self.demo()
            case .none: break
            }
            self.updateMouseRouting()
        }
        petView.dragStarted = { [weak self] in
            guard let self else { return }; self.dragSceneOrigin=self.sceneOrigin; self.panel.ignoresMouseEvents=false
        }
        petView.dragMoved = { [weak self] delta in
            guard let self else { return }
            self.sceneOrigin=NSPoint(x:self.dragSceneOrigin.x+delta.x,y:self.dragSceneOrigin.y+delta.y)
            self.updatePanelFrame()
        }
        petView.dragFinished = { [weak self] in self?.clampAndSavePosition(); self?.updateMouseRouting() }
        panel.contentView = petView
        refreshScene(force:true)
        placeInitially()
        panel.orderFrontRegardless()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐾"
        statusItem.button?.toolTip = "Snoopy Desktop"
        statusItem.menu = makeMenu()
        weather.onChange = { [weak self] in guard let self else { return }; self.statusItem?.menu = self.makeMenu() }
        state.onChange = { [weak self] in
            guard let self else { return }
            self.statusItem?.menu = self.makeMenu()
            self.statusItem?.button?.toolTip = self.state.phase.title
        }
        if !CommandLine.arguments.contains("--diagnostic-idle") {
            monitor.start()
            if CommandLine.arguments.contains("--enable-chatgpt-detection") { monitor.enableAccessibility() }
        }
        if CommandLine.arguments.contains("--diagnostic-live") {
            var samples=0
            Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] debugTimer in
                self?.printLiveWindowDiagnostics(); samples += 1
                if samples>=30 { debugTimer.invalidate() }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / WeatherMotion.renderingFPS, repeats: true) { [weak self] _ in
            guard let self else { return }
            let uptime = clockNow()
            self.state.tick(at: uptime)
            self.weather.refreshIfNeeded()
            self.weatherSchedule.enabled = self.weather.settings.enabled && self.weather.settings.location != nil
            self.weatherSchedule.interval = self.weather.settings.interval
            if self.weatherSchedule.shouldStart(now: uptime, isIdle: self.state.phase == .idle,
                hasActiveSources: !self.state.activeSources.isEmpty,
                isVisible: self.panel.isVisible,
                observationFresh: self.weather.observation?.isFresh(at: Date()) == true),
                let observation = self.weather.observation {
                _ = self.state.startWeather(observation.kind, at: uptime)
            }
            self.refreshScene()
            self.updateMouseRouting()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if weather.settings.location == nil && !CommandLine.arguments.contains("--diagnostic-idle") {
            DispatchQueue.main.async { [weak self] in self?.chooseWeatherLocation() }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { monitor.stop(); timer?.invalidate() }
    func refreshScene(force: Bool = false) {
        InteractionMotionSettings.applyPendingIfSafe(isInteracting:state.phase == .interacting)
        renderer.weatherPresentation = state.weatherPresentation(at: clockNow())
        let now=clockNow(),retina=panel?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pose: String
        switch state.phase {
        case .idle: pose="idle-\(PetMotion.sleepFrame(now))"
        case .working: pose="typing-\(PetMotion.typingFrame(now))"
        case .weather: pose="weather-\(Int(max(0,now-state.phaseStarted)*WeatherMotion.renderingFPS))"
        case .interacting: pose="touch-\(Int(max(0,now-state.phaseStarted)*32))"
        default: pose="dynamic-\(Int(now*32))"
        }
        let key="\(pose)-\(sceneScale)-\(retina)"
        guard force || cachedScene == nil || key != lastPoseKey else { return }
        do {
            let cache=try CachedScene.render(renderer:renderer,phase:state.phase,elapsed:max(0,now-state.phaseStarted),animation:now,scale:sceneScale,retina:retina)
            cachedScene=cache; lastPoseKey=key
            crop=cropEnvelope.update(PetWindowGeometry.paddedCrop(cache.visible,canvas:cache.canvas),phase:state.phase)
            petView.cache=cache; petView.crop=crop
            updatePanelFrame(); petView.needsDisplay=true
        } catch { /* Retain the previous valid frame if an allocation fails. */ }
    }
    func updatePanelFrame() {
        guard panel != nil,!crop.isEmpty else { return }
        let frame=PetWindowGeometry.panelFrame(sceneOrigin:sceneOrigin,crop:crop)
        if panel.frame != frame { panel.setFrame(frame,display:false,animate:false) }
    }
    func updateMouseRouting() {
        guard let panel,let cache=cachedScene else { return }
        if petView.isDragging { panel.ignoresMouseEvents=false; return }
        let mouse=NSEvent.mouseLocation
        panel.ignoresMouseEvents = !cache.opaque(at:NSPoint(x:mouse.x-sceneOrigin.x,y:mouse.y-sceneOrigin.y))
    }
    func printLiveWindowDiagnostics() {
        guard let panel,let cache=cachedScene else { return }
        let mouse=NSEvent.mouseLocation
        let report:[String:Any]=["windowNumber":panel.windowNumber,"phase":state.phase.rawValue,"physicalFrame":[panel.frame.minX,panel.frame.minY,panel.frame.width,panel.frame.height],"sceneOrigin":[sceneOrigin.x,sceneOrigin.y],"cropOffset":[crop.minX,crop.minY],"visibleBounds":[cache.visible.minX,cache.visible.minY,cache.visible.width,cache.visible.height],"ignoresMouseEvents":panel.ignoresMouseEvents,"mouseOverOpaque":cache.opaque(at:NSPoint(x:mouse.x-sceneOrigin.x,y:mouse.y-sceneOrigin.y)),"dragging":petView.isDragging]
        if let data=try? JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),let value=String(data:data,encoding:.utf8) { print("WINDOW_DIAGNOSTICS "+value); fflush(stdout) }
    }
    func placeInitially() {
        let defaults=UserDefaults.standard
        if defaults.object(forKey:"petX") != nil {
            sceneOrigin=NSPoint(x:defaults.double(forKey:"petX"),y:defaults.double(forKey:"petY"))
        } else if let visible=cachedScene?.visible,let screen=NSScreen.main {
            sceneOrigin=NSPoint(x:screen.visibleFrame.maxX-visible.maxX-20,y:screen.visibleFrame.minY-visible.minY+12)
        }
        updatePanelFrame(); updateMouseRouting()
    }
    func clampAndSavePosition() {
        guard let visible=cachedScene?.visible else { return }
        let content=visible.offsetBy(dx:sceneOrigin.x,dy:sceneOrigin.y)
        let screen=NSScreen.screens.max { a,b in
            let first=a.visibleFrame.intersection(content),second=b.visibleFrame.intersection(content)
            return (first.isNull ? 0:first.width*first.height) < (second.isNull ? 0:second.width*second.height)
        } ?? NSScreen.main
        if let screen { sceneOrigin=PetWindowGeometry.clampedOrigin(sceneOrigin,visible:visible,screen:screen.visibleFrame) }
        updatePanelFrame()
        UserDefaults.standard.set(sceneOrigin.x,forKey:"petX"); UserDefaults.standard.set(sceneOrigin.y,forKey:"petY")
    }
    @objc func screenChanged() {
        lastPoseKey=nil; cropEnvelope.reset(); refreshScene(force:true); clampAndSavePosition()
    }
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector?, _ key: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item); return item
        }
        _ = add(state.phase.title, nil)
        if !state.activeSources.isEmpty { _ = add("正在运行：\(state.activeSources.count) 个来源", nil) }
        menu.addItem(.separator())
        _ = add("预览：醒来 → 打字 → 晚饭 → 睡觉", #selector(demo), "d")
        _ = add("预览：摸肚子 → 眨眼 → 躺下", #selector(previewBellyTouch))
        let weatherMenu = NSMenu()
        let weatherItem = add("天气小剧场 · " + (weather.settings.location?.city ?? "未选地区"), nil)
        weatherItem.submenu = weatherMenu
        let enabled = NSMenuItem(title:"每10分钟待机播放", action:#selector(toggleWeather), keyEquivalent:"")
        enabled.target = self; enabled.state = weather.settings.enabled ? .on : .off
        enabled.isEnabled = weather.settings.location != nil
        weatherMenu.addItem(enabled)
        let info = NSMenuItem(title:weather.statusDescription, action:nil, keyEquivalent:""); weatherMenu.addItem(info)
        let choose = NSMenuItem(title:weather.settings.location == nil ? "选择天气地区…" : "更换天气地区…",
                                action:#selector(chooseWeatherLocation), keyEquivalent:"")
        choose.target = self; weatherMenu.addItem(choose)
        let update = NSMenuItem(title:"刷新" + (weather.settings.location?.city ?? "当地") + "天气",
                                action:#selector(refreshWeather), keyEquivalent:"")
        update.target = self; update.isEnabled = weather.settings.location != nil; weatherMenu.addItem(update)
        weatherMenu.addItem(.separator())
        for kind in WeatherKind.allCases {
            let item = NSMenuItem(title:"预览：" + kind.title, action:#selector(previewWeather(_:)), keyEquivalent:"")
            item.target = self; item.representedObject = kind.rawValue
            item.isEnabled = state.phase == .idle && state.activeSources.isEmpty
            weatherMenu.addItem(item)
        }
        _ = add("重新载入动作参数", #selector(reloadSleepMotion))
        _ = add("手动开始打字", #selector(manualStart))
        _ = add("手动完成任务", #selector(manualDone))
        _ = add("重置卡住的状态", #selector(resetActivity))
        menu.addItem(.separator())
        _ = add("启用 ChatGPT 桌面检测…", #selector(enableAccessibility))
        _ = add("打开系统辅助功能权限设置…", #selector(openAccessibilitySettings))
        _ = add("复制网页连接口令", #selector(copyToken))
        _ = add("查看连接状态…", #selector(showConnection))
        menu.addItem(.separator())
        let sizes = NSMenu()
        for (title, value) in [("小 · 55%", 0.55), ("标准 · 72%", 0.72), ("大 · 90%", 0.9)] {
            let item = NSMenuItem(title: title, action: #selector(setSize(_:)), keyEquivalent: ""); item.target = self; item.representedObject = value; item.state = abs(Double(sceneScale) - value) < 0.01 ? .on : .off; sizes.addItem(item)
        }
        let sizeItem = add("桌宠大小", nil); sizeItem.submenu = sizes
        _ = add(panel?.isVisible == true ? "隐藏桌宠" : "显示桌宠", #selector(toggleVisibility))
        _ = add("退出史努比桌宠", #selector(quit), "q")
        return menu
    }
    @objc func demo() { state.demo(at: clockNow()) }
    @objc func previewBellyTouch() { _=state.startBellyInteraction(at:clockNow()) }
    @objc func previewWeather(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = WeatherKind(rawValue:raw) else { return }
        _ = state.startWeather(kind, at:clockNow())
    }
    @objc func chooseWeatherLocation() {
        let alert = NSAlert()
        alert.messageText = "选择天气地区"
        alert.informativeText = "输入城市名，例如上海、杭州或 London。仅使用你选中的地区，不读取电脑定位。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        field.placeholderString = "城市或城市, 国家/省份"
        field.stringValue = weather.settings.location?.city ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "查找地区")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        weather.searchLocations(query: query) { [weak self] result in
            self?.showWeatherLocationResults(result)
        }
    }
    private func showWeatherLocationResults(_ result: Result<[WeatherLocation], Error>) {
        NSApp.activate(ignoringOtherApps: true)
        switch result {
        case .failure(let error):
            let alert = NSAlert()
            alert.messageText = "地区查找失败"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "重新输入")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn { chooseWeatherLocation() }
        case .success(let locations):
            let alert = NSAlert()
            alert.messageText = "确认天气地区"
            alert.informativeText = "同名城市可能位于不同国家或省份，请确认后保存。"
            let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 28))
            for location in locations { picker.addItem(withTitle: location.displayName) }
            alert.accessoryView = picker
            alert.addButton(withTitle: "使用此地区")
            alert.addButton(withTitle: "重新输入")
            alert.addButton(withTitle: "稍后")
            let response = alert.runModal()
            if response == .alertSecondButtonReturn { chooseWeatherLocation(); return }
            guard response == .alertFirstButtonReturn,
                  locations.indices.contains(picker.indexOfSelectedItem) else { return }
            do {
                try weather.setLocation(locations[picker.indexOfSelectedItem])
                if state.phase == .weather { state.resetPresentation(at: clockNow()) }
                weatherSchedule = WeatherSchedule(startedAt: clockNow(), interval: weather.settings.interval)
                weatherSchedule.enabled = weather.settings.enabled && weather.settings.location != nil
                weather.refreshIfNeeded(force: true)
                statusItem.menu = makeMenu()
                refreshScene(force: true)
            } catch {
                let failure = NSAlert()
                failure.messageText = "天气地区未保存"
                failure.informativeText = error.localizedDescription
                failure.runModal()
            }
        }
    }
    @objc func refreshWeather() { weather.refreshIfNeeded(force:true) }
    @objc func toggleWeather() {
        do {
            try weather.setEnabled(!weather.settings.enabled)
            weatherSchedule = WeatherSchedule(startedAt:clockNow(), interval:weather.settings.interval)
            weatherSchedule.enabled = weather.settings.enabled && weather.settings.location != nil
            statusItem.menu = makeMenu()
        } catch {
            let alert=NSAlert(); alert.messageText="天气设置未保存"; alert.informativeText=error.localizedDescription; alert.runModal()
        }
    }
    @objc func reloadSleepMotion() {
        do {
            let previousWeatherSettings = weather.settings
            try weather.reloadSettings()
            if weather.settings != previousWeatherSettings {
                weatherSchedule = WeatherSchedule(startedAt:clockNow(), interval:weather.settings.interval)
                weatherSchedule.enabled = weather.settings.enabled && weather.settings.location != nil
            }
            let nextInteraction=try InteractionMotionSettings.load()
            try assets.installSmoothSleepFrames(force:true)
            InteractionMotionSettings.apply(nextInteraction,whileInteracting:state.phase == .interacting)
            lastPoseKey=nil; cropEnvelope.reset(); refreshScene(force:true)
        } catch {
            let alert=NSAlert(); alert.messageText="动作参数有误"; alert.informativeText=error.localizedDescription; alert.runModal()
        }
    }
    @objc func manualStart() { state.receive(source: "manual", phase: "working", at: clockNow()) }
    @objc func manualDone() { state.receive(source: "manual", phase: "done", at: clockNow()) }
    @objc func resetActivity() {
        monitor.resetActivity()
        state.clearAll(at: clockNow())
    }
    @objc func enableAccessibility() { monitor.enableAccessibility() }
    @objc func openAccessibilitySettings() {
        if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath:"/System/Applications/System Settings.app"))
    }
    @objc func copyToken() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(monitor.connectionToken, forType: .string) }
    @objc func showConnection() {
        let details=monitor.connectionDiagnostics()
        let summary=ActivityMonitor.describeConnections(
            running:details["running"] as? Bool ?? false,
            optedIn:details["accessibilityOptedIn"] as? Bool ?? false,
            trusted:details["accessibilityTrusted"] as? Bool ?? false,
            bridgeReady:details["bridgeReady"] as? Bool ?? false,
            bridgeError:details["bridgeError"] as? String,
            lastWebEvent:details["webLastEventAt"] as? String,
            webConnected:details["webConnected"] as? Bool ?? false,
            axObservedGenerationCount:details["axObservedGenerationCount"] as? Int ?? 0,
            axLastPhase:details["axLastPhase"] as? String)
        func capturedTime(_ key: String) -> String {
            guard let value=details[key] as? String else { return "暂无" }
            guard let date=ISO8601DateFormatter().date(from:value) else { return value }
            let formatter=DateFormatter(); formatter.dateStyle = .short; formatter.timeStyle = .medium
            return formatter.string(from:date)
        }
        let bundle=details["axLastDetectedBundleID"] as? String
        let appNames=["com.openai.codex":"Codex / GPT 统一应用","com.openai.chat":"ChatGPT","com.google.Chrome":"Chrome","com.apple.Safari":"Safari","com.microsoft.edgemac":"Edge"]
        let source=bundle.map { appNames[$0] ?? $0 } ?? "暂无"
        let phaseLabels=["working":"生成中","done":"已结束","failed":"观察中断"]
        let recentPhase=(details["axLastPhase"] as? String).map { phaseLabels[$0] ?? $0 } ?? "暂无"
        let history="最近捕获："+capturedTime("axLastDetectedAt")+"（"+source+"）\n最近阶段："+recentPhase+" · "+capturedTime("axLastPhaseAt")
        var help:[String]=[]
        if details["accessibilityOptedIn"] as? Bool != true { help.append("ChatGPT 桌面检测尚未启用，可在桌宠菜单中启用。") }
        else if details["accessibilityTrusted"] as? Bool != true { help.append("请在系统的“隐私与安全性 → 辅助功能”允许本应用。") }
        if details["webConnected"] as? Bool != true { help.append("首次使用网页扩展：在桌宠菜单复制网页连接口令，再粘贴到 Chrome/Edge 扩展弹窗中保存。") }
        help.append("辅助功能检测覆盖可访问的可见网页；后台网页需要浏览器扩展。")
        let alert=NSAlert()
        alert.messageText="桌宠连接状态"
        alert.informativeText=summary.replacingOccurrences(of:" · ",with:"\n")+"\n"+history+"\n\n"+help.joined(separator:"\n")
        alert.addButton(withTitle:"知道了")
        alert.runModal()
    }
    @objc func setSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        sceneScale = value
        UserDefaults.standard.set(value, forKey: "petScale")
        cropEnvelope.reset(); lastPoseKey=nil; refreshScene(force:true)
        clampAndSavePosition()
        statusItem.menu = makeMenu()
    }
    @objc func toggleVisibility() { if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }; statusItem.menu = makeMenu() }
    @objc func quit() { NSApp.terminate(nil) }
}

func previewState(at time: Double) -> (phase: PetPhase, elapsed: Double) {
    var start = 3.0
    if time < start { return (.idle, time) }
    let stages: [(PetPhase, Double)] = [(.waking,PetTiming.wake),(.working,PetTiming.work),(.delivery,PetTiming.delivery),(.dancing,PetTiming.dance),(.departing,PetTiming.departing),(.returning,PetTiming.returning),(.settling,PetTiming.settle)]
    for (phase, duration) in stages {
        if time < start + duration { return (phase, time - start) }
        start += duration
    }
    return (.idle, time - start)
}

func previewBitmap(width: Int, height: Int) throws -> (NSBitmapImageRep, NSGraphicsContext) {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw NSError(domain: "Preview", code: 1) }
    return (bitmap, context)
}
func writePreview(_ bitmap: NSBitmapImageRep, path: String) throws {
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "Preview", code: 2) }
    try data.write(to: URL(fileURLWithPath: path))
}
func fillPreview(width: CGFloat, height: CGFloat) {
    NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.90, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
}

func renderPreview(path: String, assets: PetAssets, layoutOnly: Bool = false) throws {
    let width = logicalSize.width * 3, height = logicalSize.height * 2
    let (bitmap, context) = try previewBitmap(width: Int(width), height: Int(height))
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    fillPreview(width: width, height: height)
    let renderer = PetRenderer(assets: assets)
    let previews: [(PetPhase, Double)] = layoutOnly ? [(.idle,0),(.waking,0.6),(.working,1),(.delivery,0),(.dancing,1),(.settling,0.7)] : [(.idle,0),(.working,1),(.delivery,1.2),(.dancing,1),(.departing,1.6),(.returning,1.4)]
    for (index, sample) in previews.enumerated() {
        let x = CGFloat(index % 3) * logicalSize.width, y = CGFloat(1 - index / 3) * logicalSize.height
        renderer.draw(phase: sample.0, elapsed: sample.1, animation: sample.1 + 100, in: NSRect(x: x, y: y, width: logicalSize.width, height: logicalSize.height), showLabel: true)
    }
    NSGraphicsContext.restoreGraphicsState()
    try writePreview(bitmap, path: path)
    print("Preview: \(path)")
}

func renderMotionDetail(path: String, assets: PetAssets) throws {
    let times = [10.2,10.6,11.2,12.2,12.9,13.2,16.9,17.2,17.6,18.7,20.4,20.65,21.1,21.7,22.3,22.85,23.3,24.6]
    let width = logicalSize.width * 3, height = logicalSize.height * 6
    let (bitmap, context) = try previewBitmap(width: Int(width), height: Int(height))
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    fillPreview(width: width, height: height)
    let renderer = PetRenderer(assets: assets)
    for (index, time) in times.enumerated() {
        let sample = previewState(at: time)
        let x = CGFloat(index % 3) * logicalSize.width, y = CGFloat(5 - index / 3) * logicalSize.height
        renderer.draw(phase: sample.phase, elapsed: sample.elapsed, animation: time + 100, in: NSRect(x: x, y: y, width: logicalSize.width, height: logicalSize.height), showLabel: true)
        (String(format: "%.2fs", time) as NSString).draw(at: NSPoint(x: x + 8, y: y + logicalSize.height - 18), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor.darkGray])
    }
    NSGraphicsContext.restoreGraphicsState()
    try writePreview(bitmap, path: path)
    print("Motion detail: \(path)")
}

func renderAnimation(directory: String, assets: PetAssets) throws {
    let url = URL(fileURLWithPath: directory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let renderer = PetRenderer(assets: assets)
    var timeline: [[String: Any]] = []
    for index in 0..<448 {
        let time = Double(index) / 16
        let sample = previewState(at: time)
        let (bitmap, context) = try previewBitmap(width: Int(logicalSize.width), height: Int(logicalSize.height))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        fillPreview(width: logicalSize.width, height: logicalSize.height)
        renderer.draw(phase: sample.phase, elapsed: sample.elapsed, animation: time + 100, in: NSRect(origin: .zero, size: logicalSize), showLabel: true)
        NSGraphicsContext.restoreGraphicsState()
        try writePreview(bitmap, path: url.appendingPathComponent(String(format: "frame-%03d.png", index)).path)
        timeline.append(["frame": index, "time": time, "phase": sample.phase.rawValue, "elapsed": sample.elapsed])
    }
    let data = try JSONSerialization.data(withJSONObject: timeline, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url.appendingPathComponent("timeline.json"))
    print("Animation: 448 frames at16fps in \(directory)")
}

func renderCroppedSequence(directory: String, assets: PetAssets, phase: PetPhase, count: Int, fps: Double) throws {
    let url=URL(fileURLWithPath:directory)
    try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
    let renderer=PetRenderer(assets:assets)
    var frames:[CachedScene]=[],union=NSRect.null
    for index in 0..<count {
        let time=Double(index)/fps
        let cache=try CachedScene.render(renderer:renderer,phase:phase,elapsed:time,animation:time,scale:0.72,retina:1)
        frames.append(cache); union=union.union(PetWindowGeometry.paddedCrop(cache.visible,canvas:cache.canvas))
    }
    for (index,frame) in frames.enumerated() { try frame.writeCrop(union,to:url.appendingPathComponent(String(format:"frame-%03d.png",index)).path) }
    let report:[String:Any]=["phase":phase.rawValue,"fps":fps,"frameCount":count,"cropPoints":[union.minX,union.minY,union.width,union.height],"scale":0.72]
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:url.appendingPathComponent("viewport.json"))
    print("Cropped \(phase.rawValue): \(count)frames at\(fps)fps in \(directory)")
}
func renderTyping(directory: String, assets: PetAssets) throws {
    try renderCroppedSequence(directory:directory,assets:assets,phase:.working,count:PetMotion.typingFrameCount,fps:PetMotion.typingFPS)
}
func renderIdle(directory: String, assets: PetAssets) throws {
    try renderCroppedSequence(directory:directory,assets:assets,phase:.idle,count:64,fps:16)
}
func windowDiagnostics(assets: PetAssets) throws {
    let renderer=PetRenderer(assets:assets)
    var report:[[String:Any]]=[]
    let samples:[(PetPhase,Double)]=[(.idle,0),(.working,0),(.delivery,1),(.dancing,0.45),(.returning,2.35)]
    for (phase,time) in samples {
        let cache=try CachedScene.render(renderer:renderer,phase:phase,elapsed:time,animation:time,scale:0.72,retina:2)
        let crop=PetWindowGeometry.paddedCrop(cache.visible,canvas:cache.canvas)
        let left=PetWindowGeometry.clampedOrigin(NSPoint(x:-999,y:80),visible:cache.visible,screen:NSRect(x:0,y:0,width:1440,height:900))
        var opaquePoint=NSPoint(x:cache.visible.midX,y:cache.visible.midY)
        outer: for y in stride(from:cache.visible.minY,through:cache.visible.maxY,by:CGFloat(1)) {
            for x in stride(from:cache.visible.minX,through:cache.visible.maxX,by:CGFloat(1)) {
                if cache.opaque(at:NSPoint(x:x,y:y)) { opaquePoint=NSPoint(x:x,y:y); break outer }
            }
        }
        report.append(["phase":phase.rawValue,"visiblePoints":[cache.visible.minX,cache.visible.minY,cache.visible.width,cache.visible.height],"physicalPanelPoints":[crop.width,crop.height],"cropOffset":[crop.minX,crop.minY],"leftClampSceneOrigin":[left.x,left.y],"visibleLeftAfterClamp":left.x+cache.visible.minX,"opaquePointHit":cache.opaque(at:opaquePoint),"transparentPointHit":cache.opaque(at:NSPoint(x:crop.minX+0.5,y:crop.minY+0.5)),"transparentPointInsideCrop":crop.contains(NSPoint(x:crop.minX+0.5,y:crop.minY+0.5)),"sceneScale":0.72,"oldPanelPoints":[340*0.72,260*0.72]])
    }
    let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
    print(String(decoding:data,as:UTF8.self))
}

func renderSleepTransition(path: String, assets: PetAssets) throws {
    let samples: [(PetPhase, Double)] = [(.idle, 0), (.waking, 0.08), (.waking, 0.25), (.waking, 0.45), (.waking, 0.65), (.waking, 0.85), (.waking, 1.0), (.working, 0), (.settling, 0.15), (.settling, 0.4), (.settling, 0.7), (.settling, 1.0), (.settling, 1.25), (.settling, 1.38), (.idle, 0)]
    let width = logicalSize.width * 3, height = logicalSize.height * 5
    let (bitmap, context) = try previewBitmap(width: Int(width), height: Int(height))
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    fillPreview(width: width, height: height)
    let renderer = PetRenderer(assets: assets)
    for (index, sample) in samples.enumerated() {
        let x = CGFloat(index % 3) * logicalSize.width, y = CGFloat(4 - index / 3) * logicalSize.height
        renderer.draw(phase: sample.0, elapsed: sample.1, animation: sample.1 + 100, in: NSRect(x: x, y: y, width: logicalSize.width, height: logicalSize.height), showLabel: true)
        (String(format: "%@ %.2fs", sample.0.rawValue, sample.1) as NSString).draw(at: NSPoint(x: x + 8, y: y + logicalSize.height - 18), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor.darkGray])
    }
    NSGraphicsContext.restoreGraphicsState()
    try writePreview(bitmap, path: path)
    print("Sleep transition: \(path)")
}

func renderReturn(path: String, assets: PetAssets, climbOnly: Bool = false) throws {
    let samples: [(PetPhase,Double)] = climbOnly ? [(.returning,0),(.returning,0.3),(.returning,0.6),(.returning,0.9),(.returning,1.2),(.returning,1.5),(.returning,1.8),(.returning,2.1),(.returning,2.35),(.settling,0),(.settling,0.7),(.idle,0)] : [(.departing,0),(.departing,0.25),(.departing,0.65),(.departing,2),(.departing,3.35),(.returning,0),(.returning,0.3),(.returning,0.6),(.returning,0.9),(.returning,1.2),(.returning,1.5),(.returning,1.8),(.returning,2.1),(.returning,2.35),(.settling,0.2)]
    let rows = climbOnly ? 4 : 5
    let width = logicalSize.width * 3, height = logicalSize.height * CGFloat(rows)
    let (bitmap,context) = try previewBitmap(width:Int(width),height:Int(height))
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    fillPreview(width:width,height:height)
    let renderer = PetRenderer(assets:assets)
    for (index,sample) in samples.enumerated() {
        let x = CGFloat(index % 3) * logicalSize.width, y = CGFloat(rows - 1 - index / 3) * logicalSize.height
        renderer.draw(phase:sample.0,elapsed:sample.1,animation:100 + sample.1,in:NSRect(x:x,y:y,width:logicalSize.width,height:logicalSize.height),showLabel:true)
        (String(format:"%@ %.2fs",sample.0.rawValue,sample.1) as NSString).draw(at:NSPoint(x:x+8,y:y+logicalSize.height-18),withAttributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:10,weight:.regular),.foregroundColor:NSColor.darkGray])
    }
    NSGraphicsContext.restoreGraphicsState(); try writePreview(bitmap,path:path)
    print("Departure and climb: \(path)")
}

func renderBellyTouch(directory: String, assets: PetAssets) throws {
    let url=URL(fileURLWithPath:directory)
    try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
    let renderer=PetRenderer(assets:assets)
    let lead=0.6, duration=lead+TouchMotion.totalDuration+1.0, fps=32.0
    var frames:[CachedScene]=[],union=NSRect.null,timeline:[[String:Any]]=[]
    for index in 0..<Int(ceil(duration*fps)) {
        let time=Double(index)/fps, elapsed=time-lead
        let phase:PetPhase = elapsed>=0 && elapsed<TouchMotion.totalDuration ? .interacting : .idle
        let cache=try CachedScene.render(renderer:renderer,phase:phase,elapsed:max(0,elapsed),animation:time,scale:0.72,retina:2)
        frames.append(cache); union=union.union(PetWindowGeometry.paddedCrop(cache.visible,canvas:cache.canvas))
        timeline.append(["frame":index,"time":time,"phase":phase.rawValue,"elapsed":max(0,elapsed),"blink":phase == .interacting ? TouchMotion.blinkAmount(elapsed):0,"stage":phase == .interacting ? TouchMotion.stage(elapsed).rawValue:"idle"])
    }
    for (index,frame) in frames.enumerated() { try frame.writeCrop(union,to:url.appendingPathComponent(String(format:"frame-%03d.png",index)).path) }
    try JSONSerialization.data(withJSONObject:timeline,options:[.prettyPrinted,.sortedKeys]).write(to:url.appendingPathComponent("timeline.json"))
    let report:[String:Any]=["fps":fps,"frameCount":frames.count,"cropPoints":[union.minX,union.minY,union.width,union.height],"scale":0.72,"retina":2,"interactionDuration":TouchMotion.totalDuration]
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:url.appendingPathComponent("viewport.json"))
    print("Belly touch: \(frames.count)frames at32fps")
}

func renderWeatherSequence(kind: WeatherKind, directory: String, assets: PetAssets) throws {
    try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
    let renderer=PetRenderer(assets:assets), fps=WeatherMotion.renderingFPS
    let duration=WeatherMotion.duration(for:kind)
    let count=Int(ceil((duration+1.2)*fps))
    func frame(_ index:Int) throws -> CachedScene {
        let t=Double(index)/fps-0.6
        let phase:PetPhase = t < 0 || t >= duration ? .idle : .weather
        renderer.weatherPresentation = phase == .weather ? WeatherPresentation(kind:kind,elapsed:t,exitProgress:nil) : nil
        return try CachedScene.render(renderer:renderer,phase:phase,elapsed:max(0,t),animation:100+Double(index)/fps,scale:0.72,retina:2)
    }
    // Determine one stable viewport, then stream frames instead of retaining1,498 bitmaps in memory.
    var union=NSRect.zero,canvas=NSRect.zero
    for index in 0..<count {
        try autoreleasepool {
            let cache=try frame(index)
            union=union.isEmpty ? cache.visible : union.union(cache.visible);canvas=cache.canvas
        }
    }
    union=PetWindowGeometry.paddedCrop(union,canvas:canvas)
    for index in 0..<count {
        try autoreleasepool { try frame(index).writeCrop(union,to:directory+String(format:"/frame-%04d.png",index)) }
    }
    let report:[String:Any] = ["kind":kind.rawValue,"fps":fps,"frameCount":count,"duration":duration,"holdStart":WeatherMotion.coreHoldStart(for:kind),"holdEnd":WeatherMotion.coreHoldEnd(for:kind),"cropPoints":[union.minX,union.minY,union.width,union.height]]
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:directory+"/timeline.json"))
}

func renderWeatherStills(directory:String, assets:PetAssets) throws {
    try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
    let renderer=PetRenderer(assets:assets)
    for kind in WeatherKind.allCases {
        for time in [0.0,1.0,3.0,6.0,9.0,12.0,18.0,24.0,27.0,30.0] {
            renderer.weatherPresentation=WeatherPresentation(kind:kind,elapsed:time,exitProgress:nil)
            let cache=try CachedScene.render(renderer:renderer,phase:.weather,elapsed:time,animation:100+time,scale:0.72,retina:2)
            try cache.writeCrop(cache.canvas,to:directory+"/"+kind.rawValue+String(format:"-%02d.png",Int(time)))
        }
    }
}

func renderRainDetail(directory:String,assets:PetAssets) throws {
    try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
    let renderer=PetRenderer(assets:assets)
    for time in [2.0,2.25,2.5,2.75,3.0,3.25,3.5,3.75,4.0,
                 4.2,4.5,4.8,5.1,5.4,5.7,6.0,8.0,25.2,25.5,26.0,26.5,
                 27.0,27.25,27.5,27.75,28.0,28.25,28.5,28.75,29.0] {
        renderer.weatherPresentation=WeatherPresentation(kind:.rain,elapsed:time,exitProgress:nil)
        let cache=try CachedScene.render(renderer:renderer,phase:.weather,elapsed:time,animation:100+time,scale:0.72,retina:2)
        try cache.writeCrop(cache.canvas,to:directory+String(format:"/rain-%.1f.png",time))
    }
}

let args = CommandLine.arguments
if let index=args.firstIndex(of:"--benchmark-sunny-cold"),args.count>index+1 {
    do {try benchmarkWeatherPlayback(kind:.sunny,directory:args[index+1]);exit(0)}
    catch {fputs("Cold sunny benchmark failed: \(error)\n",stderr);exit(1)}
}
if let index=args.firstIndex(of:"--benchmark-rain-cold"),args.count>index+1 {
    do {try benchmarkRainPlayback(directory:args[index+1]);exit(0)}
    catch {fputs("Cold rain benchmark failed: \(error)\n",stderr);exit(1)}
}
if let index=args.firstIndex(of:"--render-rain-detail"),args.count>index+1 {
    do { try renderRainDetail(directory:args[index+1],assets:PetAssets());exit(0) } catch { fputs("Rain detail failed: \(error)\n",stderr);exit(1) }
}
if let index=args.firstIndex(of:"--render-weather-stills"),args.count>index+1 {
    do { try renderWeatherStills(directory:args[index+1],assets:PetAssets());exit(0) } catch { fputs("Weather stills failed: \(error)\n",stderr);exit(1) }
}
if let index=args.firstIndex(of:"--render-weather"),args.count>index+2,let kind=WeatherKind(rawValue:args[index+1]) {
    let assets=PetAssets()
    guard assets.missing.isEmpty else { fputs("Missing assets: \(assets.missing)\n",stderr); exit(1) }
    do { try renderWeatherSequence(kind:kind,directory:args[index+2],assets:assets); exit(0) } catch { fputs("Weather preview failed: \(error)\n",stderr); exit(1) }
}
if args.contains("--weather-diagnostics") {
    let service=WeatherService()
    service.refreshIfNeeded(force:true)
    let deadline=Date().addingTimeInterval(22)
    while service.observation == nil && service.lastError == nil && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.05)) }
    let report:[String:Any] = ["city":service.settings.location?.displayName ?? "未选择","status":service.statusDescription,"enabled":service.settings.enabled,"intervalSeconds":service.settings.interval,"fresh":service.observation?.isFresh() ?? false,"kind":service.observation?.kind.rawValue ?? "unavailable","wmo":service.observation?.code ?? -1]
    if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) { print(String(decoding:data,as:UTF8.self)) }
    exit(service.observation?.isFresh() == true ? 0 : 1)
}
if args.contains("--connection-diagnostics") {
    let monitor=ActivityMonitor { _,_ in }
    do {
        let data=try JSONSerialization.data(withJSONObject:monitor.connectionDiagnostics(),options:[.prettyPrinted,.sortedKeys])
        print(String(decoding:data,as:UTF8.self))
        exit(0)
    } catch { fputs("Connection diagnostics failed: \(error)\n",stderr); exit(1) }
}
if args.contains("--geometry-self-test") {
    do { try runWindowGeometryTests(); exit(0) } catch { fputs("Geometry failed: \(error)\n",stderr); exit(1) }
}
if args.contains("--window-diagnostics") {
    do { try windowDiagnostics(assets:PetAssets()); exit(0) } catch { fputs("Diagnostics failed: \(error)\n",stderr); exit(1) }
}
if let index=args.firstIndex(of:"--render-dance"),args.count>index+1 {
    let assets=PetAssets()
    guard assets.missing.isEmpty else { fputs("Missing assets: \(assets.missing)\n",stderr); exit(1) }
    do { try renderCroppedSequence(directory:args[index+1],assets:assets,phase:.dancing,count:64,fps:16); exit(0) } catch { fputs("Dance preview failed: \(error)\n",stderr); exit(1) }
}
if let index=args.firstIndex(of:"--render-touch"),args.count>index+1 {
    let assets=PetAssets()
    guard assets.missing.isEmpty else { fputs("Missing assets: \(assets.missing)\n",stderr); exit(1) }
    do { try renderBellyTouch(directory:args[index+1],assets:assets); exit(0) } catch { fputs("Touch preview failed: \(error)\n",stderr); exit(1) }
}
if args.contains("--self-test") {
    do { try runPetStateTests(); try runWindowGeometryTests(); try runBellyInteractionTests(); try runInteractionMotionSettingsTests(); try runWeatherServiceTests(); try runWeatherStateTests(); try runWeatherRendererTests(); try runWeatherSceneTests(); try runMagazineRendererTests(); try runRainFlightMotionTests(); try runRainAssetTests(); try runSnowSceneTests(); try runOriginalRainArtworkTests(); try runWeatherGestureTests(); try runLocalBridgePairingTests(); exit(0) } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
if args.contains("--smoke-test") {
    let assets = PetAssets()
    do { try runPetStateTests(); try runWindowGeometryTests(); try runBellyInteractionTests(); try runInteractionMotionSettingsTests(); try runWeatherServiceTests(); try runWeatherStateTests(); try runWeatherRendererTests(); try runWeatherSceneTests(); try runMagazineRendererTests(); try runRainFlightMotionTests(); try runRainAssetTests(); try runSnowSceneTests(); try runOriginalRainArtworkTests(); try runWeatherGestureTests(); try runLocalBridgePairingTests() } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    guard assets.missing.isEmpty else { fputs("Missing assets: \(assets.missing.joined(separator: ", "))\n", stderr); exit(1) }
    print("PASS: all \(assets.images.count) transparent sprite assets load")
    exit(0)
}
if let index = args.firstIndex(of: "--render-idle"), args.count > index + 1 {
    let assets = PetAssets()
    let relevantMissing = assets.missing.filter { $0 == "doghouse" || $0 == "woodstock" || $0 == "sit-1" || $0 == "typing-01" || $0.hasPrefix("sleep") || $0.hasPrefix("wake") }
    guard relevantMissing.isEmpty else { fputs("Missing assets: \(assets.missing)\n", stderr); exit(1) }
    do { try renderIdle(directory: args[index + 1], assets: assets); exit(0) } catch { fputs("Idle preview failed: \(error)\n", stderr); exit(1) }
}
if let index = args.firstIndex(of: "--render-sleep-transition"), args.count > index + 1 {
    let assets = PetAssets()
    guard assets.missing.isEmpty else { fputs("Missing assets: \(assets.missing)\n", stderr); exit(1) }
    do { try renderSleepTransition(path: args[index + 1], assets: assets); exit(0) } catch { fputs("Sleep transition failed: \(error)\n", stderr); exit(1) }
}
if let index = args.firstIndex(of: "--render-typing"), args.count > index + 1 {
    let assets = PetAssets()
    guard assets.missing.isEmpty else { fputs("Missing assets: \(assets.missing)\n", stderr); exit(1) }
    do { try renderTyping(directory: args[index + 1], assets: assets); exit(0) } catch { fputs("Typing preview failed: \(error)\n", stderr); exit(1) }
}
if let index = args.firstIndex(of: "--render-layout"), args.count > index + 1 {
    let assets = PetAssets()
    let requiredMissing = assets.missing.filter { !$0.hasPrefix("climb-") && !$0.hasPrefix("charlie-") }
    guard requiredMissing.isEmpty else { fputs("Missing layout assets: \(requiredMissing)\n", stderr); exit(1) }
    do { try renderPreview(path: args[index + 1], assets: assets, layoutOnly: true); exit(0) } catch { fputs("Layout failed: \(error)\n", stderr); exit(1) }
}
if let index = args.firstIndex(of: "--render-climb"), args.count > index + 1 {
    let assets = PetAssets()
    let relevantMissing = assets.missing.filter { !$0.hasPrefix("charlie-") }
    guard relevantMissing.isEmpty else { fputs("Missing climb assets: \(relevantMissing)\n",stderr); exit(1) }
    do { try renderReturn(path:args[index+1],assets:assets,climbOnly:true); exit(0) } catch { fputs("Climb preview failed: \(error)\n",stderr); exit(1) }
}
if let index = args.firstIndex(of: "--render-return"), args.count > index + 1 {
    let assets = PetAssets()
    guard assets.missing.isEmpty else { fputs("Missing assets: \(assets.missing)\n",stderr); exit(1) }
    do { try renderReturn(path:args[index+1],assets:assets); exit(0) } catch { fputs("Return preview failed: \(error)\n",stderr); exit(1) }
}
if let index = args.firstIndex(of: "--render-motion-detail"), args.count > index + 1 {
    let assets = PetAssets()
    guard assets.missing.isEmpty else { fputs("Missing assets: \(assets.missing)\n", stderr); exit(1) }
    do { try renderMotionDetail(path: args[index + 1], assets: assets); exit(0) } catch { fputs("Motion detail failed: \(error)\n", stderr); exit(1) }
}
if let index = args.firstIndex(of: "--render-animation"), args.count > index + 1 {
    let assets = PetAssets()
    guard assets.missing.isEmpty else { fputs("Missing assets: \(assets.missing)\n", stderr); exit(1) }
    do { try renderAnimation(directory: args[index + 1], assets: assets); exit(0) } catch { fputs("Animation failed: \(error)\n", stderr); exit(1) }
}
if let index = args.firstIndex(of: "--render-preview"), args.count > index + 1 {
    let assets = PetAssets()
    guard assets.missing.isEmpty else { fputs("Missing assets: \(assets.missing)\n", stderr); exit(1) }
    do { try renderPreview(path: args[index + 1], assets: assets); exit(0) } catch { fputs("Preview failed: \(error)\n", stderr); exit(1) }
}
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
