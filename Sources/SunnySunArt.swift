import AppKit

/// A small inked sun sits in the sky without widening the pet's footprint.
extension PetRenderer {
    func drawSunnySun(alpha: CGFloat, animation: Double) {
        guard alpha > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        let center = NSPoint(x: 237, y: 222)
        let pulse = CGFloat(sin(animation * .pi / 3)) * 0.35
        let radius: CGFloat = 9.2 + pulse
        let disc = NSBezierPath(ovalIn: NSRect(x: center.x - radius,
                                                y: center.y - radius,
                                                width: radius * 2,
                                                height: radius * 2))
        NSColor(calibratedRed: 1, green: 0.82, blue: 0.08, alpha: 1).setFill()
        disc.fill()
        NSColor.black.setStroke()
        disc.lineWidth = 1.15
        disc.stroke()
        let rays = NSBezierPath()
        rays.lineCapStyle = .round
        for index in 0..<8 {
            let angle = CGFloat(index) * .pi / 4 + .pi / 8
            let inner = radius + 3.2
            let outer = radius + 9.0
            rays.move(to: NSPoint(x: center.x + cos(angle) * inner,
                                  y: center.y + sin(angle) * inner))
            rays.line(to: NSPoint(x: center.x + cos(angle) * outer,
                                  y: center.y + sin(angle) * outer))
        }
        NSColor.black.setStroke()
        rays.lineWidth = 3.2
        rays.stroke()
        NSColor(calibratedRed: 1, green: 0.82, blue: 0.08, alpha: 1).setStroke()
        rays.lineWidth = 1.9
        rays.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
