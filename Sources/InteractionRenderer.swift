import AppKit

/// Shared rest geometry keeps hit testing, the sleeping back and all seated poses on the roof.
extension PetRenderer {
    func restBodyBox(for name: String) -> NSRect {
        let house = assets.fittedRect("doghouse", in: NSRect(x: 140, y: 20, width: 114, height: 104))
        let roof = house.maxY - house.height * (assets.metrics["doghouse"]?.topInset ?? 0)
        let seat = NSRect(x: 140, y: roof - 1.2, width: 98, height: 90)
        let head = assets.headPoint("typing-01", in: seat)
        let end = assets.images["wake-6"]?.size ?? NSSize(width: 600, height: 600)
        let metric = assets.metrics["wake-6"] ?? SpriteMetrics(bottomInset: 0.267, headTopInset: 0.092)
        let scale = (head.y - seat.minY) / max(1, end.height * (1 - metric.headTopInset - metric.bottomInset))
        let center = head.x - (metric.headX - 0.5) * end.width * scale
        let size = assets.images[name]?.size ?? end
        return NSRect(x: center - size.width * scale / 2, y: seat.minY, width: size.width * scale, height: size.height * scale)
    }
    func restingBellyPoint(animation: Double) -> NSPoint {
        let name = PetMotion.sleepSprite(animation), fit = assets.fittedRect(name, in: restBodyBox(for: name))
        let anchor = assets.bellyRoosts[name] ?? NSPoint(x: 350.0 / 600, y: 289.0 / 600)
        return NSPoint(x: fit.minX + fit.width * anchor.x, y: fit.minY + fit.height * anchor.y)
    }
    func idleBellyHit(_ point: NSPoint, animation: Double) -> Bool {
        let name = PetMotion.sleepSprite(animation), fit = assets.fittedRect(name, in: restBodyBox(for: name))
        let perch = restingBellyPoint(animation: animation)
        let center = NSPoint(x: perch.x, y: perch.y - fit.height * 48 / 600)
        let x = (point.x - center.x) / (fit.width * 78 / 600)
        let y = (point.y - center.y) / (fit.height * 48 / 600)
        return x * x + y * y <= 1 && point.y < perch.y - 0.3
    }
    private func touchPose(_ name: String, alpha: CGFloat = 1, blink: CGFloat = 0) {
        guard alpha > 0 else { return }
        if blink > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setAlpha(alpha)
            assets.drawSeatedInteraction(name, in: restBodyBox(for: name), blink: blink)
            NSGraphicsContext.restoreGraphicsState()
        } else { assets.draw(name, in: restBodyBox(for: name), alpha: alpha) }
    }
    private func risingTouchPose(_ progress: Double, alpha: CGFloat = 1) {
        let position = min(1, max(0, progress)) * 3
        let index = min(3, Int(position)), fraction = position - Double(index)
        let blend = CGFloat(PetMotion.smooth((fraction - 0.60) / 0.40))
        touchPose("wake-\(index + 1)", alpha: alpha * (1 - blend))
        if index < 3 { touchPose("wake-\(index + 2)", alpha: alpha * blend) }
    }
    func drawBellyInteraction(elapsed: Double, animation: Double) {
        let sleep = PetMotion.sleepSprite(animation)
        switch TouchMotion.stage(elapsed) {
        case .takeoff, .returning: touchPose(sleep)
        case .rising:
            let enter = CGFloat(PetMotion.smooth(TouchMotion.stageElapsed(elapsed) / 0.12))
            touchPose(sleep, alpha: 1 - enter)
            risingTouchPose(TouchMotion.riseProgress(elapsed), alpha: enter)
        case .blinking: touchPose("wake-4", blink: CGFloat(TouchMotion.blinkAmount(elapsed)))
        case .lying:
            let settle = CGFloat(PetMotion.smooth((TouchMotion.stageElapsed(elapsed) - (TouchMotion.lieDuration - 0.16)) / 0.16))
            risingTouchPose(1 - TouchMotion.lieProgress(elapsed), alpha: 1 - settle)
            touchPose(sleep, alpha: settle)
        }
        let away = CGFloat(TouchMotion.birdAwayProgress(elapsed))
        guard away < 0.9999 else { return }
        let perch = restingBellyPoint(animation: animation)
        let point = NSPoint(x: perch.x + 58 * away, y: perch.y + 57 * away + 13 * sin(away * .pi))
        let opacity = CGFloat(1 - PetMotion.smooth(Double((away - 0.72) / 0.28)))
        let flying = TouchMotion.birdIsFlying(elapsed)
        let returning = TouchMotion.stage(elapsed) == .returning
        let flightAmount = flying ? CGFloat(PetMotion.smooth(Double(min(1, away / 0.18)))) : 0
        let standingBox = NSRect(x: point.x - 10, y: point.y - 1.2, width: 20, height: 21)
        if flightAmount < 1 { assets.draw("woodstock", in: standingBox, alpha: opacity * (1 - flightAmount)) }
        if flightAmount > 0 {
            let name = "woodstock-flight-\(TouchMotion.flightWingFrame(elapsed))"
            // Registration uses the eye, not the changing wing/feet bounds. The head stays steady.
            let standingFit = assets.fittedRect("woodstock", in: standingBox)
            let eye = NSPoint(x: standingFit.minX + standingFit.width * 87 / 134, y: standingFit.minY + standingFit.height * 99 / 181)
            let local = assets.fittedRect(name, in: NSRect(x: 0, y: 0, width: 28, height: 28))
            let u: CGFloat = returning ? 1 - 420.0 / 640 : 420.0 / 640
            let localEye = NSPoint(x: local.minX + local.width * u, y: local.minY + local.height * 340 / 640)
            let box = NSRect(x: eye.x - localEye.x, y: eye.y - localEye.y, width: 28, height: 28)
            assets.draw(name, in: box, alpha: opacity * flightAmount, flip: returning)
        }
    }
}

/// Presses remain captured for mouse routing, but only motion beyond three screen points is a drag.
struct BellyClickGesture {
    static let dragThreshold: CGFloat = 3
    private(set) var dragged = false
    mutating func moved(_ delta: NSPoint) { if hypot(delta.x, delta.y) >= Self.dragThreshold { dragged = true } }
}

enum PetClickIntent: Equatable {
    case touchBelly, demo, none
    static func resolve(phase: PetPhase, hitsBelly: Bool, count: Int) -> PetClickIntent {
        if phase == .interacting { return .none }
        if phase == .idle && hitsBelly { return .touchBelly }
        return count == 2 ? .demo : .none
    }
}

func runBellyInteractionTests() throws {
    struct Failure: Error, CustomStringConvertible { let description: String }
    var count = 0
    func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
        guard condition() else { throw Failure(description: label) }; count += 1
    }
    let assets = PetAssets(), renderer = PetRenderer(assets: assets)
    try check(assets.missing.isEmpty, "Original and generated sleeping assets load")
    try check((1...32).allSatisfy { assets.images[SleepBreathing32.spriteName(frame: $0)] != nil }, "All32 breathing poses are installed")
    for index in 0..<32 {
        let t = Double(index) / 8
        let perch = renderer.restingBellyPoint(animation: t)
        let fit = assets.fittedRect(PetMotion.sleepSprite(t), in: renderer.restBodyBox(for: PetMotion.sleepSprite(t)))
        let belly = NSPoint(x: perch.x, y: perch.y - fit.height * 48 / 600)
        try check(renderer.idleBellyHit(belly, animation: t), "Belly center stays clickable in frame\(index)")
        try check(!renderer.idleBellyHit(NSPoint(x: perch.x, y: perch.y + 8), animation: t), "Bird is not a belly target")
        try check(!renderer.idleBellyHit(assets.headPoint(PetMotion.sleepSprite(t), in: renderer.restBodyBox(for: PetMotion.sleepSprite(t))), animation: t), "Head is not a belly target")
    }
    try check(!renderer.idleBellyHit(NSPoint(x: 200, y: 70), animation: 1), "House does not trigger touch")
    var jitter = BellyClickGesture(); jitter.moved(NSPoint(x: 1, y: 1)); try check(!jitter.dragged, "Small pointer jitter is a click")
    jitter.moved(NSPoint(x: 3, y: 0)); try check(jitter.dragged, "Threepoint motion becomes dragging")
    jitter.moved(.zero); try check(jitter.dragged, "Returning pointer after drag cannot create a click")
    try check(PetClickIntent.resolve(phase: .idle, hitsBelly: true, count: 1) == .touchBelly, "Single bellyclick starts touch")
    try check(PetClickIntent.resolve(phase: .idle, hitsBelly: true, count: 2) == .touchBelly, "Doublebellyclick never starts full dinner demo")
    try check(PetClickIntent.resolve(phase: .interacting, hitsBelly: false, count: 2) == .none, "Doubleclick cannot interrupt existing touch")
    try check(PetClickIntent.resolve(phase: .idle, hitsBelly: false, count: 1) == .none, "Single headclick is inert")
    try check(PetClickIntent.resolve(phase: .idle, hitsBelly: false, count: 2) == .demo, "Doubleclick outside belly retains demo")
    print("PASS: \(count) breathing install, belly hit region and click-versus-drag assertions")
}
