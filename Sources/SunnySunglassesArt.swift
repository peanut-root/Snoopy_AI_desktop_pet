import AppKit

/// During the sunny scene, glasses simply materialize on each face.
private enum SunnyGlasses {
    static func pair(alpha: CGFloat) {
        guard alpha > 0 else { return }
        NSColor.black.withAlphaComponent(alpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: 241, y: 96, width: 58, height: 58)).fill()
        NSBezierPath(ovalIn: NSRect(x: 304, y: 93, width: 53, height: 54)).fill()
        let frame = NSBezierPath()
        frame.lineWidth = 8
        frame.lineCapStyle = .round
        frame.move(to: NSPoint(x: 297, y: 120))
        frame.curve(to: NSPoint(x: 307, y: 119),
                    controlPoint1: NSPoint(x: 301, y: 116),
                    controlPoint2: NSPoint(x: 303, y: 116))
        frame.move(to: NSPoint(x: 244, y: 123))
        frame.line(to: NSPoint(x: 203, y: 145))
        NSColor.black.withAlphaComponent(alpha).setStroke()
        frame.stroke()
    }
}

extension PetRenderer {
    private func withWakeFourCanvas(_ work: () -> Void) {
        let fit = assets.fittedRect("wake-4", in: restBodyBox(for: "wake-4"))
        guard fit.width > 0, fit.height > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.translateBy(x: fit.minX, y: fit.maxY)
        NSGraphicsContext.current?.cgContext.scaleBy(x: fit.width / 600, y: -fit.height / 600)
        work()
        NSGraphicsContext.restoreGraphicsState()
    }

    func drawSunnySunglasses(alpha: CGFloat) {
        guard alpha > 0 else { return }
        withWakeFourCanvas { SunnyGlasses.pair(alpha: alpha) }
    }

    func drawWoodstockSunglasses(at perch: NSPoint, alpha: CGFloat) {
        guard alpha > 0, let bird = assets.images["woodstock"] else { return }
        let box = NSRect(x: perch.x - 10, y: perch.y - 1.2, width: 20, height: 21)
        let fit = assets.fittedRect("woodstock", in: box)
        guard fit.width > 0, fit.height > 0,
              bird.size.width > 0, bird.size.height > 0 else { return }
        let eye = NSPoint(x: fit.minX + fit.width * 0.57,
                          y: fit.maxY - fit.height * 0.44)
        let x = eye.x + 0.6, y = eye.y
        NSGraphicsContext.saveGraphicsState()
        NSColor.black.withAlphaComponent(alpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - 2.1, y: y - 1.6, width: 3.2, height: 3.3)).fill()
        NSBezierPath(ovalIn: NSRect(x: x + 1.9, y: y - 1.5, width: 3.2, height: 3.1)).fill()
        let frame = NSBezierPath()
        frame.lineCapStyle = .round
        frame.lineWidth = 0.75
        frame.move(to: NSPoint(x: x + 1.1, y: y + 0.1))
        frame.line(to: NSPoint(x: x + 1.9, y: y + 0.1))
        frame.move(to: NSPoint(x: x - 2, y: y + 0.35))
        frame.line(to: NSPoint(x: x - 5.4, y: y + 0.7))
        NSColor.black.withAlphaComponent(alpha).setStroke()
        frame.stroke()
        NSColor.white.withAlphaComponent(alpha * 0.8).setFill()
        NSBezierPath(ovalIn: NSRect(x: x + 3.5, y: y + 0.25,
                                      width: 0.65, height: 0.45)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
