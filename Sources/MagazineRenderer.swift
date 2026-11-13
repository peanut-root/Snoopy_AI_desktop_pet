import AppKit

/// Each leaf takes two seconds to cross the slanted book spine, independent of display cadence.
enum MagazineMotion {
    static let turns = [8.0, 15.0, 22.0]
    static let turnDuration = 2.0
    static func progress(at elapsed: Double) -> Double? {
        guard elapsed.isFinite else { return nil }
        for start in turns where elapsed >= start && elapsed < start + turnDuration {
            return (elapsed - start) / turnDuration
        }
        return nil
    }
    struct Leaf {
        let hingeTop: NSPoint
        let hingeBottom: NSPoint
        let freeTop: NSPoint
        let freeBottom: NSPoint
        let curl: CGFloat
        let back: Bool
    }
    static func leaf(progress: Double) -> Leaf {
        let p = min(1, max(0, progress))
        let eased = p * p * (3 - 2 * p)
        let angle = CGFloat(eased * .pi), turn = sin(angle), width = cos(angle)
        let top = NSPoint(x: 362, y: 286), bottom = NSPoint(x: 347, y: 356)
        return Leaf(hingeTop: top, hingeBottom: bottom,
                    freeTop: NSPoint(x: top.x + 45 * width + 12 * turn,
                                     y: top.y - 20 * abs(width) - 22 * turn),
                    freeBottom: NSPoint(x: bottom.x + 37 * width + 8 * turn,
                                        y: bottom.y - 16 * abs(width) - 5 * turn),
                    curl: turn * 10, back: p > 0.5)
    }
}

private enum MagazineInk {
    static func polygon(_ points: [NSPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.line(to: point) }
        path.close()
        return path
    }
    static func paperClip() -> NSBezierPath {
        let path = polygon([NSPoint(x: 302, y: 265), NSPoint(x: 360, y: 284),
                            NSPoint(x: 414, y: 256), NSPoint(x: 389, y: 342),
                            NSPoint(x: 345, y: 361), NSPoint(x: 307, y: 346)])
        // Inset exclusions preserve the original paws and their thick black outlines.
        path.appendOval(in: NSRect(x: 273, y: 286, width: 50, height: 66))
        path.appendOval(in: NSRect(x: 376, y: 282, width: 45, height: 60))
        path.windingRule = .evenOdd
        return path
    }
    static func broadClip() -> NSBezierPath {
        let path = polygon([NSPoint(x: 299, y: 246), NSPoint(x: 424, y: 246),
                            NSPoint(x: 402, y: 343), NSPoint(x: 345, y: 363),
                            NSPoint(x: 300, y: 347)])
        path.appendOval(in: NSRect(x: 273, y: 286, width: 50, height: 66))
        path.appendOval(in: NSRect(x: 376, y: 282, width: 45, height: 60))
        path.windingRule = .evenOdd
        return path
    }
    static func mix(_ a: NSPoint, _ b: NSPoint, _ fraction: CGFloat) -> NSPoint {
        NSPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
    }
    static func leafPath(_ leaf: MagazineMotion.Leaf) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: leaf.hingeTop)
        path.curve(to: leaf.freeTop,
                   controlPoint1: NSPoint(x: leaf.hingeTop.x + (leaf.freeTop.x - leaf.hingeTop.x) * 0.4, y: leaf.hingeTop.y - leaf.curl * 0.7),
                   controlPoint2: NSPoint(x: leaf.freeTop.x - leaf.curl * 0.3, y: leaf.freeTop.y - leaf.curl * 0.3))
        path.curve(to: leaf.freeBottom,
                   controlPoint1: NSPoint(x: leaf.freeTop.x + leaf.curl, y: leaf.freeTop.y + 23),
                   controlPoint2: NSPoint(x: leaf.freeBottom.x + leaf.curl * 0.7, y: leaf.freeBottom.y - 22))
        path.curve(to: leaf.hingeBottom,
                   controlPoint1: NSPoint(x: leaf.freeBottom.x - leaf.curl * 0.3, y: leaf.freeBottom.y + leaf.curl * 0.3),
                   controlPoint2: NSPoint(x: leaf.hingeBottom.x + (leaf.freeBottom.x - leaf.hingeBottom.x) * 0.4, y: leaf.hingeBottom.y - leaf.curl * 0.2))
        path.close()
        return path
    }
    static func lines(topA: NSPoint, bottomA: NSPoint, topB: NSPoint, bottomB: NSPoint,
                      opacity: CGFloat, rows: Int = 5) {
        NSColor(calibratedWhite: 0.27, alpha: opacity).setStroke()
        for index in 0..<rows {
            let row = CGFloat(index + 2) / CGFloat(rows + 4)
            let a = mix(topA, bottomA, row), b = mix(topB, bottomB, row)
            let line = NSBezierPath(); line.lineWidth = 1.25; line.lineCapStyle = .round
            line.move(to: mix(a, b, 0.20)); line.line(to: mix(a, b, index % 2 == 0 ? 0.78 : 0.69)); line.stroke()
        }
    }
}

/// Draw over the seated sprite. The canvas is its complete fitted600px image, not the book bounds.
func drawSunnyMagazine(in fittedCanvas: NSRect, elapsed: Double, alpha: CGFloat) {
    guard alpha > 0, fittedCanvas.width > 0, fittedCanvas.height > 0 else { return }
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext.current?.cgContext else { NSGraphicsContext.restoreGraphicsState(); return }
    context.setAlpha(alpha)
    context.translateBy(x: fittedCanvas.minX, y: fittedCanvas.maxY)
    context.scaleBy(x: fittedCanvas.width / 600, y: -fittedCanvas.height / 600)
    NSGraphicsContext.saveGraphicsState()
    MagazineInk.paperClip().addClip()
    let paper = MagazineInk.polygon([NSPoint(x: 304, y: 269), NSPoint(x: 361, y: 289),
                                     NSPoint(x: 411, y: 261), NSPoint(x: 386, y: 341),
                                     NSPoint(x: 345, y: 357), NSPoint(x: 310, y: 344)])
    NSColor(calibratedRed: 1, green: 0.98, blue: 0.89, alpha: 1).setFill(); paper.fill()
    NSColor(calibratedWhite: 0.15, alpha: 1).setStroke(); paper.lineWidth = 1.6; paper.stroke()
    let crease = NSBezierPath(); crease.move(to: NSPoint(x: 362, y: 288)); crease.line(to: NSPoint(x: 347, y: 354))
    crease.lineWidth = 1.7; crease.stroke()
    MagazineInk.lines(topA:NSPoint(x: 307,y: 272),bottomA:NSPoint(x: 312,y: 342),
                      topB:NSPoint(x: 356,y: 290),bottomB:NSPoint(x: 342,y: 351),opacity:0.52)
    MagazineInk.lines(topA:NSPoint(x: 369,y: 289),bottomA:NSPoint(x: 355,y: 349),
                      topB:NSPoint(x: 406,y: 268),bottomB:NSPoint(x: 386,y: 339),opacity:0.52)
    NSGraphicsContext.restoreGraphicsState()

    if let progress = MagazineMotion.progress(at: elapsed) {
        let leaf = MagazineMotion.leaf(progress: progress)
        let fade = CGFloat(min(1, progress / 0.06, (1 - progress) / 0.06))
        NSGraphicsContext.saveGraphicsState()
        context.setAlpha(alpha * fade)
        MagazineInk.broadClip().addClip()
        let page = MagazineInk.leafPath(leaf)
        NSGraphicsContext.saveGraphicsState()
        context.translateBy(x: 1.6, y: 1.8)
        NSColor.black.withAlphaComponent(0.13 * sin(CGFloat(progress) * .pi)).setFill(); page.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedRed: leaf.back ? 0.97 : 1, green: leaf.back ? 0.95 : 0.99,
                blue: leaf.back ? 0.84 : 0.91, alpha: 1).setFill(); page.fill()
        NSColor(calibratedWhite: 0.12, alpha: 1).setStroke(); page.lineWidth = 1.8; page.lineJoinStyle = .round; page.stroke()
        NSGraphicsContext.saveGraphicsState(); page.addClip()
        MagazineInk.lines(topA:leaf.hingeTop,bottomA:leaf.hingeBottom,
                          topB:leaf.freeTop,bottomB:leaf.freeBottom,opacity:0.45)
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
}

func runMagazineRendererTests() throws {
    struct Failure: Error, CustomStringConvertible { let description: String }
    var count = 0
    func check(_ value: @autoclosure () -> Bool, _ label: String) throws {
        guard value() else { throw Failure(description:label) }; count += 1
    }
    try check(MagazineMotion.progress(at:7.999) == nil && MagazineMotion.progress(at:24) == nil,
              "Reading leaves stay still outside the three deliberate turns")
    for start in MagazineMotion.turns {
        try check(MagazineMotion.progress(at:start) == 0 && MagazineMotion.progress(at:start+1) == 0.5,
                  "Each leaf takes a complete second to reach the spine")
        try check(MagazineMotion.progress(at:start+1.999) != nil && MagazineMotion.progress(at:start+2) == nil,
                  "A page turn lasts two seconds without shortening its tail")
    }
    let first=MagazineMotion.leaf(progress:0), middle=MagazineMotion.leaf(progress:0.5), last=MagazineMotion.leaf(progress:1)
    try check(first.freeTop.x > first.hingeTop.x && last.freeTop.x < last.hingeTop.x,
              "The free page edge really crosses from the right face to the left face")
    try check(middle.curl > 9 && !first.back && last.back,
              "The rising leaf exposes a curved back rather than growing a white triangle")
    try check(first.hingeTop == middle.hingeTop && middle.hingeTop == last.hingeTop && first.hingeBottom == last.hingeBottom,
              "Both ends of the slanted spine stay fixed while the leaf moves")
    let clip=MagazineInk.broadClip()
    try check(!clip.contains(NSPoint(x:300,y:316)) && !clip.contains(NSPoint(x:399,y:310)),
              "Projected paper cannot cover the original white paws")
    try check(!clip.contains(NSPoint(x:350,y:230)) && !clip.contains(NSPoint(x:290,y:256)),
              "Paper stays below the face and clear of the red collar")
    let positions=(0..<96).map { MagazineMotion.leaf(progress:Double($0)/96).freeTop }
    let maximumStep=zip(positions,positions.dropFirst()).map { hypot($1.x-$0.x,$1.y-$0.y) }.max() ?? 0
    try check(maximumStep < 2.5, "Ninety-six poses over two seconds keep the page edge continuous")
    print("PASS: \(count) magazine timing, spine travel, hand clipping and page continuity assertions")
}
