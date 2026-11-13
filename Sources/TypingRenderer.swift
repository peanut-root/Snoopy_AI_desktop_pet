import AppKit

/// Source-pixel masks keep the typing frame's body and machine registered while
/// its canonical head nods rigidly and only the generated forepaws change pose.
enum StableTypingMask {
    static let sourceSize = NSSize(width: 526, height: 403)
    static let neckPivot = NSPoint(x: 192, y: 246)
    static let maximumHeadAngle: CGFloat = 0.75 * .pi / 180
    static let forepawPoints: [NSPoint] = [
        NSPoint(x: 187, y: 269), NSPoint(x: 227, y: 256),
        NSPoint(x: 294, y: 254), NSPoint(x: 321, y: 265),
        NSPoint(x: 331, y: 284), NSPoint(x: 328, y: 307),
        NSPoint(x: 334, y: 319), NSPoint(x: 330, y: 342),
        NSPoint(x: 309, y: 352), NSPoint(x: 238, y: 348),
        NSPoint(x: 214, y: 330), NSPoint(x: 194, y: 316),
        NSPoint(x: 181, y: 298), NSPoint(x: 182, y: 282)
    ]

    static func headAngle(for name: String) -> CGFloat {
        guard name.hasPrefix("typing-"), let frame = Int(name.dropFirst(7)),
              (1...16).contains(frame) else { return 0 }
        let angle = maximumHeadAngle * sin(CGFloat(frame - 1) * 2 * .pi / 16)
        return abs(angle) < 0.000001 ? 0 : angle
    }

    static func point(_ source: NSPoint, in imageRect: NSRect) -> NSPoint {
        NSPoint(x: imageRect.minX + source.x / sourceSize.width * imageRect.width,
                y: imageRect.maxY - source.y / sourceSize.height * imageRect.height)
    }

    static func rotated(_ point: NSPoint, around pivot: NSPoint, by angle: CGFloat) -> NSPoint {
        let dx = point.x - pivot.x, dy = point.y - pivot.y
        return NSPoint(x: pivot.x + dx * cos(angle) - dy * sin(angle),
                       y: pivot.y + dx * sin(angle) + dy * cos(angle))
    }

    static func path(_ points: [NSPoint] = forepawPoints, in imageRect: NSRect) -> CGPath {
        let path = CGMutablePath()
        for (index, source) in points.enumerated() {
            let mapped = point(source, in: imageRect)
            if index == 0 { path.move(to: mapped) } else { path.addLine(to: mapped) }
        }
        path.closeSubpath()
        return path
    }

    static func headPath(in imageRect: NSRect, overlap: Bool) -> CGPath {
        // The muzzle ends at source y245, the collar at y250, and the paper
        // begins at x424. A narrow lower-neck overlap closes the rotating joint.
        let neckBottom: CGFloat = overlap ? 256 : 251
        return path([NSPoint(x: 0, y: 0), NSPoint(x: 410, y: 0),
                     NSPoint(x: 410, y: 246), NSPoint(x: 235, y: 246),
                     NSPoint(x: 235, y: neckBottom), NSPoint(x: 136, y: neckBottom),
                     NSPoint(x: 136, y: 246), NSPoint(x: 0, y: 246)], in: imageRect)
    }
}

extension PetAssets {
    func typingHeadPoint(_ name: String, in box: NSRect, mirrored: Bool = false) -> NSPoint {
        let fit = fittedRect("typing-01", in: box)
        let canonical = metrics["typing-01"]
        let crown = NSPoint(x: fit.minX + fit.width * (canonical?.headX ?? 0.45),
                            y: fit.maxY - fit.height * (canonical?.headTopInset ?? 0.1))
        let pivot = StableTypingMask.point(StableTypingMask.neckPivot, in: fit)
        var result = StableTypingMask.rotated(crown, around: pivot,
                                              by: StableTypingMask.headAngle(for: name))
        if mirrored { result.x = fit.midX * 2 - result.x }
        return result
    }

    /// All head pixels come from typing-01; animation changes only its rigid
    /// angle and the forepaw cutout, never the generated head shape or eye.
    func drawStableTyping(_ name: String, in box: NSRect, alpha: CGFloat = 1,
                          flip: Bool = false, rotation: CGFloat = 0) {
        guard alpha > 0, let canonical = images["typing-01"],
              let graphics = NSGraphicsContext.current else { return }
        let animated = images[name] ?? canonical
        let fit = fittedRect("typing-01", in: box)
        let imageRect = NSRect(x: -fit.width / 2, y: -fit.height / 2,
                               width: fit.width, height: fit.height)
        let forepaws = StableTypingMask.path(in: imageRect)
        let angle = StableTypingMask.headAngle(for: name)
        let movesHead = angle != 0
        let context = graphics.cgContext

        NSGraphicsContext.saveGraphicsState()
        // Complementary hard clips assign every boundary pixel once, avoiding
        // the translucent seam caused by fractional clip coverage in two passes.
        context.setShouldAntialias(false)
        context.translateBy(x: fit.midX, y: fit.midY)
        if rotation != 0 { context.rotate(by: rotation * .pi / 180) }
        if flip { context.scaleBy(x: -1, y: 1) }
        let usesOpacityGroup = alpha < 1
        if usesOpacityGroup {
            context.setAlpha(alpha)
            context.beginTransparencyLayer(in: imageRect, auxiliaryInfo: nil)
        }

        context.saveGState()
        context.addRect(imageRect)
        context.addPath(forepaws)
        if movesHead { context.addPath(StableTypingMask.headPath(in: imageRect, overlap: false)) }
        context.clip(using: .evenOdd)
        canonical.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
        context.restoreGState()

        if movesHead {
            let pivot = StableTypingMask.point(StableTypingMask.neckPivot, in: imageRect)
            context.saveGState()
            context.translateBy(x: pivot.x, y: pivot.y)
            context.rotate(by: angle)
            context.translateBy(x: -pivot.x, y: -pivot.y)
            context.addPath(StableTypingMask.headPath(in: imageRect, overlap: true))
            context.clip()
            canonical.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
            context.restoreGState()
        }

        context.saveGState()
        context.addPath(forepaws)
        context.clip()
        animated.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
        context.restoreGState()
        if usesOpacityGroup { context.endTransparencyLayer() }
        NSGraphicsContext.restoreGraphicsState()
    }
}
