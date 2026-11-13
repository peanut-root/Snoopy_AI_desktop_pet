import AppKit

/// The user-chosen raised-paw image is the exact final rain pose. A matching
/// neutral image lets one fixed-width arm move into it without a second paw.
extension PetRenderer {
    private func rainReferenceRect() -> NSRect? {
        guard let image = assets.images["weather-rain-reference"] else { return nil }
        let seated = assets.fittedRect("wake-4", in: restBodyBox(for: "wake-4"))
        let scale: CGFloat = 0.458
        let width = seated.width * image.size.width * scale / 600
        let height = seated.height * image.size.height * scale / 600
        let left = seated.minX - seated.width * 23 / 600
        let top = seated.maxY + seated.height * 54 / 600
        return NSRect(x: left, y: top - height, width: width, height: height)
    }

    func drawRainTransitionBacking() {
        guard let rect = rainReferenceRect(),
              let neutral = assets.images["weather-rain-neutral"] else { return }
        neutral.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    /// The arm keeps its width as its paw travels from chest to above the head.
    /// At full extension we draw the selected PNG itself, pixel for pixel.
    func drawRainAnimatedPose(progress: CGFloat, alpha: CGFloat) {
        guard alpha > 0, let rect = rainReferenceRect(),
              let reference = assets.images["weather-rain-reference"] else { return }
        let q = min(1, max(0, progress))
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext.current?.cgContext
        context?.setAlpha(alpha)
        context?.beginTransparencyLayer(auxiliaryInfo: nil)
        if q >= 0.999 {
            reference.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        } else if let neutral = assets.images["weather-rain-neutral"] {
            neutral.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            context?.saveGState()
            context?.translateBy(x: rect.minX, y: rect.maxY)
            context?.scaleBy(x: rect.width / 1254, y: -rect.height / 1254)
            let shoulder = NSPoint(x: 560, y: 708)
            let wrist = NSPoint(x: 770 - 250 * q, y: 820 - 570 * q)
            let dx = wrist.x - shoulder.x, dy = wrist.y - shoulder.y
            let length = max(1, hypot(dx, dy))
            let side = NSPoint(x: -dy / length * 42, y: dx / length * 42)
            let arm = NSBezierPath()
            arm.move(to: NSPoint(x: shoulder.x + side.x, y: shoulder.y + side.y))
            arm.curve(to: NSPoint(x: wrist.x + side.x, y: wrist.y + side.y),
                      controlPoint1: NSPoint(x: shoulder.x + dx * 0.35 + side.x,
                                             y: shoulder.y + dy * 0.35 + side.y),
                      controlPoint2: NSPoint(x: wrist.x - dx * 0.35 + side.x,
                                             y: wrist.y - dy * 0.35 + side.y))
            arm.line(to: NSPoint(x: wrist.x - side.x, y: wrist.y - side.y))
            arm.curve(to: NSPoint(x: shoulder.x - side.x, y: shoulder.y - side.y),
                      controlPoint1: NSPoint(x: wrist.x - dx * 0.35 - side.x,
                                             y: wrist.y - dy * 0.35 - side.y),
                      controlPoint2: NSPoint(x: shoulder.x + dx * 0.35 - side.x,
                                             y: shoulder.y + dy * 0.35 - side.y))
            NSColor.white.setFill(); arm.fill()
            arm.lineWidth = 13; arm.lineCapStyle = .round; arm.lineJoinStyle = .round
            NSColor.black.setStroke(); arm.stroke()
            let palm = NSBezierPath()
            palm.move(to: NSPoint(x: wrist.x - 41, y: wrist.y + 6))
            palm.curve(to: NSPoint(x: wrist.x - 81, y: wrist.y - 71),
                       controlPoint1: NSPoint(x: wrist.x - 48, y: wrist.y - 31),
                       controlPoint2: NSPoint(x: wrist.x - 91, y: wrist.y - 42))
            palm.curve(to: NSPoint(x: wrist.x - 22, y: wrist.y - 136),
                       controlPoint1: NSPoint(x: wrist.x - 91, y: wrist.y - 116),
                       controlPoint2: NSPoint(x: wrist.x - 58, y: wrist.y - 143))
            palm.curve(to: NSPoint(x: wrist.x + 62, y: wrist.y - 116),
                       controlPoint1: NSPoint(x: wrist.x + 9, y: wrist.y - 145),
                       controlPoint2: NSPoint(x: wrist.x + 62, y: wrist.y - 149))
            palm.curve(to: NSPoint(x: wrist.x + 49, y: wrist.y - 38),
                       controlPoint1: NSPoint(x: wrist.x + 84, y: wrist.y - 84),
                       controlPoint2: NSPoint(x: wrist.x + 75, y: wrist.y - 47))
            palm.curve(to: NSPoint(x: wrist.x + 20, y: wrist.y + 7),
                       controlPoint1: NSPoint(x: wrist.x + 42, y: wrist.y - 22),
                       controlPoint2: NSPoint(x: wrist.x + 36, y: wrist.y - 5))
            palm.close()
            NSColor.white.setFill(); palm.fill()
            palm.lineWidth = 13; palm.lineCapStyle = .round
            NSColor.black.setStroke(); palm.stroke()
            let fingers = NSBezierPath()
            fingers.move(to: NSPoint(x: wrist.x - 6, y: wrist.y - 112))
            fingers.curve(to: NSPoint(x: wrist.x + 26, y: wrist.y - 120),
                          controlPoint1: NSPoint(x: wrist.x + 6, y: wrist.y - 138),
                          controlPoint2: NSPoint(x: wrist.x + 18, y: wrist.y - 134))
            fingers.move(to: NSPoint(x: wrist.x + 15, y: wrist.y - 79))
            fingers.curve(to: NSPoint(x: wrist.x + 55, y: wrist.y - 88),
                          controlPoint1: NSPoint(x: wrist.x + 34, y: wrist.y - 104),
                          controlPoint2: NSPoint(x: wrist.x + 48, y: wrist.y - 101))
            fingers.lineWidth = 11; fingers.lineCapStyle = .round
            fingers.stroke()
            context?.restoreGState()
        }
        context?.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
    }

    func rainReferencePerch() -> NSPoint {
        guard let rect = rainReferenceRect() else {
            return assets.headPoint("wake-4", in: restBodyBox(for: "wake-4"))
        }
        return NSPoint(x: rect.minX + rect.width * 523 / 1254,
                       y: rect.maxY - rect.height * 115 / 1254)
    }

    func drawRainBlink(elapsed: Double) {
        func closure(around center: Double) -> CGFloat {
            let distance = abs(elapsed - center)
            guard distance < 0.15 else { return 0 }
            let progress = 1 - distance / 0.15
            return CGFloat(pow(sin(progress * .pi / 2), 2))
        }
        let weight = max(closure(around: 7.6), closure(around: 16.2))
        guard weight > 0.001, let rect = rainReferenceRect() else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.translateBy(x: rect.minX, y: rect.maxY)
        NSGraphicsContext.current?.cgContext.scaleBy(x: rect.width / 1254, y: -rect.height / 1254)
        let cover = NSBezierPath(roundedRect: NSRect(x: 673, y: 370, width: 46, height: 84),
                                 xRadius: 22, yRadius: 37)
        NSColor.white.withAlphaComponent(weight).setFill(); cover.fill()
        let eyelid = NSBezierPath()
        eyelid.move(to: NSPoint(x: 679, y: 418))
        eyelid.curve(to: NSPoint(x: 712, y: 414),
                     controlPoint1: NSPoint(x: 690, y: 411),
                     controlPoint2: NSPoint(x: 701, y: 411))
        eyelid.lineWidth = 10; eyelid.lineCapStyle = .round
        NSColor.black.withAlphaComponent(weight).setStroke(); eyelid.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
