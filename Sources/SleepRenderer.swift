import AppKit
import CoreFoundation

/// This file lives beside the App, so tuning a gentle idle motion does not modify its signature.
struct SleepMotionSettings: Equatable {
    var bellyLift: CGFloat = 8
    var earSway: CGFloat = 8
    var pawLift: CGFloat = 6
    static let defaults = SleepMotionSettings()
    static var preferredFileURL: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("sleep-motion.json")
    }
    static var resolvedFileURL: URL? {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
        var candidates = [preferredFileURL, executable.appendingPathComponent("sleep-motion.json")]
        if let i = CommandLine.arguments.firstIndex(of: "--project"), i + 1 < CommandLine.arguments.count {
            candidates.append(URL(fileURLWithPath: CommandLine.arguments[i + 1], isDirectory: true).appendingPathComponent("sleep-motion.json"))
        }
        candidates += [executable.appendingPathComponent("project/sleep-motion.json"),
                       executable.deletingLastPathComponent().appendingPathComponent("sleep-motion.json"),
                       executable.deletingLastPathComponent().appendingPathComponent("project/sleep-motion.json"),
                       URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).appendingPathComponent("sleep-motion.json")]
        var seen = Set<String>()
        return candidates.map { $0.standardizedFileURL }.first {
            seen.insert($0.path).inserted && FileManager.default.fileExists(atPath: $0.path)
        }
    }
    static func load(from explicitURL: URL? = nil) throws -> SleepMotionSettings {
        guard let url = explicitURL ?? resolvedFileURL else { return defaults }
        func failure(_ message: String) -> NSError {
            NSError(domain: "SleepMotionSettings", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "待机动作配置无效（\(url.lastPathComponent)）：\(message)"])
        }
        let value: Any
        do { value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) }
        catch { throw failure("无法读取 JSON：" + error.localizedDescription) }
        guard let object = value as? [String: Any],
              Set(object.keys).isSubset(of: ["bellyLift", "earSway", "pawLift"]) else {
            throw failure("只支持 bellyLift、earSway、pawLift 三个数值")
        }
        func number(_ name: String, default fallback: CGFloat, limit: Double) throws -> CGFloat {
            guard let value = object[name] else { return fallback }
            guard let numeric = value as? NSNumber, CFGetTypeID(numeric) != CFBooleanGetTypeID(),
                  numeric.doubleValue.isFinite, (0...limit).contains(numeric.doubleValue) else {
                throw failure("\(name) 必须是 0 到 \(Int(limit)) 之间的有限数值")
            }
            return CGFloat(numeric.doubleValue)
        }
        return try SleepMotionSettings(bellyLift: number("bellyLift", default: defaults.bellyLift, limit: 16),
                                       earSway: number("earSway", default: defaults.earSway, limit: 16),
                                       pawLift: number("pawLift", default: defaults.pawLift, limit: 12))
    }
}

/// A four-second breath sampled into 32 poses. Belly, soft ear bend and forepaw follow one clock;
/// the canonical face, planted feet and main roof contact never move.
enum SleepBreathing32 {
    static let frameCount = 32
    static let period = 4.0
    static let maximumLift: CGFloat = 8
    static func spriteName(frame: Int) -> String { String(format: "breath-%02d", (max(1, frame) - 1) % frameCount + 1) }
    static func phase(forFrame frame: Int) -> Double { Double((max(1, frame) - 1) % frameCount) / Double(frameCount) }
    static func amount(forFrame frame: Int) -> Double {
        let phase = self.phase(forFrame: frame), inhale = 0.42
        if phase <= inhale { return (1 - cos(.pi * phase / inhale)) * 0.5 }
        return (1 + cos(.pi * (phase - inhale) / (1 - inhale))) * 0.5
    }
    private static func smooth(_ t: CGFloat) -> CGFloat { let v = max(0, min(1, t)); return v * v * (3 - 2 * v) }
    static func horizontalWeight(_ x: CGFloat, sourceWidth: CGFloat) -> CGFloat {
        let left = sourceWidth * 265 / 600, right = sourceWidth * 438 / 600
        guard x > left, x < right else { return 0 }
        let value = sin(.pi * (x - left) / (right - left)); return value * value
    }
    /// Belly motion tapers out above the arm. The main back and all paw pixels remain fixed
    /// when pawLift is zero, rather than accidentally inheriting the old whole-column stretch.
    static func bellyVerticalWeight(topY: CGFloat) -> CGFloat { smooth((375 - topY) / 32) }
    static func pawHorizontalWeight(_ x: CGFloat) -> CGFloat {
        smooth((x - 311) / 22) * smooth((415 - x) / 17)
    }
    static func pawVerticalWeight(topY: CGFloat) -> CGFloat {
        smooth((topY - 375) / 20) * smooth((480 - topY) / 24)
    }
    static func earBend(topY: CGFloat) -> CGFloat {
        // The root remains attached. The first 12px below the head is a rigid attachment.
        smooth((topY - 450) / 133)
    }
    static func displacement(at point: NSPoint, frame: Int, sourceSize: NSSize, support: CGFloat,
                             bellyY: CGFloat, bellyLift: CGFloat = maximumLift) -> CGFloat {
        guard point.y > support else { return 0 }
        let lift = bellyLift * sourceSize.height / 600 * CGFloat(amount(forFrame: frame))
        let topY = (sourceSize.height - point.y) * 600 / sourceSize.height
        return (point.y - support) * lift * horizontalWeight(point.x, sourceWidth: sourceSize.width)
            / max(1, bellyY - support) * bellyVerticalWeight(topY: topY)
    }
}

extension PetAssets {
    /// Build into temporary dictionaries, then swap. Invalid settings or a render error never
    /// damage the currently displayed cache. Force reload reads the external JSON again.
    func installSmoothSleepFrames(force: Bool = false) throws {
        guard force || images[SleepBreathing32.spriteName(frame: 1)] == nil else { return }
        let settings = try SleepMotionSettings.load()
        guard let source = images["sleep-1"], let sourceMetric = metrics["sleep-1"],
              let belly = bellyRoosts["sleep-1"] else {
            throw NSError(domain: "SleepBreathing32", code: 1, userInfo: [NSLocalizedDescriptionKey: "缺少原始睡姿或肚子定位"])
        }
        let width = Int(source.size.width.rounded()), height = Int(source.size.height.rounded())
        guard width > 0, height > 0,
              let canonical = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: width * 4, bitsPerPixel: 32),
              let canonicalBytes = canonical.bitmapData,
              let context = NSGraphicsContext(bitmapImageRep: canonical) else { throw NSError(domain: "SleepBreathing32", code: 2) }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
        source.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let stride = canonical.bytesPerRow
        let base = Array(UnsafeBufferPointer(start: canonicalBytes, count: stride * height))
        let sourceSize = NSSize(width: width, height: height)
        let support = sourceMetric.bottomInset * CGFloat(height)
        let bellyPoint = NSPoint(x: belly.x * CGFloat(width), y: belly.y * CGFloat(height))
        var bellyVertical = [CGFloat](repeating: 0, count: height), pawVertical = bellyVertical
        for index in 0..<height {
            let y = CGFloat(index) + 0.5, top = (CGFloat(height) - y) * 600 / CGFloat(height)
            bellyVertical[index] = max(0, y - support) / max(1, bellyPoint.y - support) * SleepBreathing32.bellyVerticalWeight(topY: top)
            pawVertical[index] = SleepBreathing32.pawVerticalWeight(topY: top)
        }
        var nextImages: [String: NSImage] = [:], nextRoosts: [String: NSPoint] = [:]
        for frame in 1...SleepBreathing32.frameCount {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: width * 4, bitsPerPixel: 32),
                  let output = bitmap.bitmapData else { throw NSError(domain: "SleepBreathing32", code: 3) }
            base.withUnsafeBufferPointer { output.update(from: $0.baseAddress!, count: base.count) }
            let amount = CGFloat(SleepBreathing32.amount(forFrame: frame))
            let lift = settings.bellyLift * CGFloat(height) / 600 * amount
            let pawLift = settings.pawLift * CGFloat(height) / 600 * amount
            // A continuous monotonic column map combines belly and paw motion before sampling.
            // It avoids stacked layers, phantom paw outlines and cracks at a masked join.
            if lift > 0 || pawLift > 0 {
                var forward = [CGFloat](repeating: 0, count: height)
                let first = max(0, Int(CGFloat(width) * 265 / 600)), last = min(width - 1, Int(ceil(CGFloat(width) * 438 / 600)))
                for x in first...last {
                    let bellyWeight = SleepBreathing32.horizontalWeight(CGFloat(x) + 0.5, sourceWidth: CGFloat(width))
                    let pawWeight = SleepBreathing32.pawHorizontalWeight((CGFloat(x) + 0.5) * 600 / CGFloat(width))
                    guard lift * bellyWeight > 0 || pawLift * pawWeight > 0 else { continue }
                    for index in 0..<height {
                        forward[index] = CGFloat(index) + 0.5 + lift * bellyWeight * bellyVertical[index] + pawLift * pawWeight * pawVertical[index]
                    }
                    var lower = 0
                    for y in 0..<height {
                        let target = CGFloat(y) + 0.5
                        while lower + 1 < height && forward[lower + 1] < target { lower += 1 }
                        let upper = min(height - 1, lower + 1)
                        let fraction = upper == lower ? CGFloat(0) : max(0, min(1, (target - forward[lower]) / max(0.0001, forward[upper] - forward[lower])))
                        let originalIndex = CGFloat(lower) + fraction
                        guard abs(originalIndex - CGFloat(y)) > 0.000001 else { continue }
                        let originalRow = CGFloat(height - 1) - originalIndex
                        let top = max(0, min(height - 1, Int(floor(originalRow)))), bottom = min(height - 1, top + 1)
                        let blend = max(0, min(1, originalRow - CGFloat(top)))
                        let targetRow = height - 1 - y, at = targetRow * stride + x * 4, a = top * stride + x * 4, b = bottom * stride + x * 4
                        for channel in 0..<4 {
                            let value = CGFloat(base[a + channel]) * (1 - blend) + CGFloat(base[b + channel]) * blend
                            output[at + channel] = UInt8(max(0, min(255, value.rounded())))
                        }
                    }
                }
            }
            // The ear is disjoint from the body deformation: bend its cross-sections sideways
            // below the fixed attachment, with no head rotation or change to the ear's width.
            let earSwing = settings.earSway * CGFloat(width) / 600 * CGFloat(sin(SleepBreathing32.phase(forFrame: frame) * 2 * .pi))
            if abs(earSwing) > 0.000001 {
                let first = max(0, Int(CGFloat(width) * 100 / 600)), last = min(width - 1, Int(ceil(CGFloat(width) * 215 / 600)))
                for row in 0..<height {
                    let bend = SleepBreathing32.earBend(topY: (CGFloat(row) + 0.5) * 600 / CGFloat(height))
                    guard bend > 0 else { continue }
                    for x in first...last {
                        let originalX = CGFloat(x) - earSwing * bend
                        let left = max(0, min(width - 1, Int(floor(originalX)))), right = min(width - 1, left + 1)
                        let blend = max(0, min(1, originalX - CGFloat(left)))
                        let at = row * stride + x * 4, a = row * stride + left * 4, b = row * stride + right * 4
                        for channel in 0..<4 {
                            let value = CGFloat(base[a + channel]) * (1 - blend) + CGFloat(base[b + channel]) * blend
                            output[at + channel] = UInt8(max(0, min(255, value.rounded())))
                        }
                    }
                }
            }
            let image = NSImage(size: sourceSize); image.addRepresentation(bitmap)
            let name = SleepBreathing32.spriteName(frame: frame); nextImages[name] = image
            let movement = SleepBreathing32.displacement(at: bellyPoint, frame: frame, sourceSize: sourceSize, support: support, bellyY: bellyPoint.y, bellyLift: settings.bellyLift)
            nextRoosts[name] = NSPoint(x: belly.x, y: belly.y + movement / CGFloat(height))
        }
        for frame in 1...SleepBreathing32.frameCount {
            let name = SleepBreathing32.spriteName(frame: frame)
            images[name] = nextImages[name]; metrics[name] = sourceMetric; bellyRoosts[name] = nextRoosts[name]
        }
    }

    /// Normal drawing is exact for blink==0. The eyelid touches only a small white-face patch;
    /// the rest of the seated sprite, including head outline, ears and planted feet, is unchanged.
    func drawSeatedInteraction(_ name: String, in box: NSRect, blink: CGFloat) {
        draw(name, in: box)
        let amount = max(0, min(1, blink))
        guard name == "wake-4", amount > 0, let image = images[name] else { return }
        let fitted = fittedRect(name, in: box)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext.current!.cgContext
        context.translateBy(x: fitted.minX, y: fitted.minY)
        context.scaleBy(x: fitted.width / 600, y: fitted.height / 600)
        let patch = NSRect(x: 284, y: 444, width: 26, height: 42)
        NSBezierPath(roundedRect: patch, xRadius: 6, yRadius: 6).addClip()
        // Sample eye-free neighbouring face texture, preserving its original off-white and alpha.
        image.draw(in: patch, from: NSRect(x: 314, y: 444, width: 26, height: 42), operation: .copy, fraction: 1)
        let center = NSPoint(x: 296.5, y: 465.5)
        let width: CGFloat = 13 + amount * 4
        let height: CGFloat = max(2.4, 30 * (1 - amount))
        NSColor(calibratedRed: 0.025, green: 0.025, blue: 0.025, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
