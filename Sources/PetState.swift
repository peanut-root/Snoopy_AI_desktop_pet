import Foundation

enum PetPhase: String, CaseIterable {
    case idle, interacting, weather, waking, working, delivery, dancing, departing, returning, settling
    var title: String {
        switch self {
        case .idle: return "史努比在屋顶睡觉"
        case .interacting: return "摸摸肚子 · 史努比坐起来看看你"
        case .weather: return "天气小剧场"
        case .waking: return "GPT 开始工作 · 史努比醒来"
        case .working: return "GPT 正在思考 · 史努比打字中"
        case .delivery: return "查理布朗送饭来啦 · 史努比跳下屋顶"
        case .dancing: return "晚饭之舞！"
        case .departing: return "查理布朗端着晚饭回家"
        case .returning: return "史努比慢慢爬回屋顶"
        case .settling: return "忙完啦 · 史努比躺下睡觉"
        }
    }
}

enum PetTiming {
    static let wake = 1.2
    static let settle = 1.4
    static let work = 6.0
    static let walk = 2.85
    static let delivery = 3.0
    static let anticipation = 0.4
    static let hop = 1.6
    static let danceLead = delivery - anticipation - hop
    static let totalDance = 5.0
    static let dance = totalDance - danceLead
    static let turn = 0.4
    static let departing = 3.4
    static let returning = 2.4
}

/// A touch never pretends to be GPT activity. Finish this short visual sequence before
/// waking for actual work, so neither Snoopy nor Woodstock teleports between poses.
enum TouchStage: String, CaseIterable { case takeoff, rising, blinking, lying, returning }
enum TouchMotion {
    static var takeoffDuration: Double { InteractionMotionSettings.current.takeoffDuration }
    static let riseDuration = 1.0
    static let blinkLead = 0.20
    static let blinkClose = 0.12
    static let blinkHold = 0.10
    static let blinkOpen = 0.16
    static let blinkGap = 0.35
    static let blinkTail = 0.20
    static let singleBlinkDuration = blinkClose + blinkHold + blinkOpen
    static let blinkDuration = blinkLead + singleBlinkDuration * 2 + blinkGap + blinkTail
    static let lieDuration = 1.0
    static var returnDuration: Double { InteractionMotionSettings.current.returnDuration }
    static var risingStarts: Double { takeoffDuration }
    static var blinkingStarts: Double { risingStarts + riseDuration }
    static var lyingStarts: Double { blinkingStarts + blinkDuration }
    static var returningStarts: Double { lyingStarts + lieDuration }
    static var totalDuration: Double { returningStarts + returnDuration }

    static func stage(_ elapsed: Double) -> TouchStage {
        let t = max(0, elapsed)
        if t < risingStarts { return .takeoff }
        if t < blinkingStarts { return .rising }
        if t < lyingStarts { return .blinking }
        if t < returningStarts { return .lying }
        return .returning
    }
    static func stageElapsed(_ elapsed: Double) -> Double {
        let starts: [TouchStage: Double] = [.takeoff: 0, .rising: risingStarts,
            .blinking: blinkingStarts, .lying: lyingStarts, .returning: returningStarts]
        return max(0, elapsed - starts[stage(elapsed)]!)
    }
    static func riseProgress(_ elapsed: Double) -> Double {
        PetMotion.smooth((elapsed - risingStarts) / riseDuration)
    }
    static func lieProgress(_ elapsed: Double) -> Double {
        PetMotion.smooth((elapsed - lyingStarts) / lieDuration)
    }
    /// Zero is the sleeping pose; one is seated wake-4 with paws resting on the belly.
    static func seatedProgress(_ elapsed: Double) -> Double {
        switch stage(elapsed) {
        case .takeoff, .returning: return 0
        case .rising: return riseProgress(elapsed)
        case .blinking: return 1
        case .lying: return 1 - lieProgress(elapsed)
        }
    }
    /// Two close-hold-open eyelid motions only; never used by typing or other phases.
    static func blinkAmount(_ elapsed: Double) -> Double {
        let local = elapsed - blinkingStarts - blinkLead
        for start in [0.0, singleBlinkDuration + blinkGap] {
            let t = local - start
            if t >= 0 && t < blinkClose { return PetMotion.smooth(t / blinkClose) }
            if t >= blinkClose && t < blinkClose + blinkHold { return 1 }
            if t >= blinkClose + blinkHold && t < singleBlinkDuration {
                return 1 - PetMotion.smooth((t - blinkClose - blinkHold) / blinkOpen)
            }
        }
        return 0
    }
    /// Zero is the belly perch, one is the away end of the flight path.
    static func birdAwayProgress(_ elapsed: Double) -> Double {
        switch stage(elapsed) {
        case .takeoff: return PetMotion.smooth(elapsed / takeoffDuration)
        case .rising, .blinking, .lying: return 1
        case .returning: return 1 - PetMotion.smooth((elapsed - returningStarts) / returnDuration)
        }
    }
    static func flightWingFrame(_ elapsed: Double) -> Int {
        Int(max(0, elapsed) * InteractionMotionSettings.current.wingFramesPerSecond) % 4 + 1
    }
    static func birdIsFlying(_ elapsed: Double) -> Bool {
        elapsed >= 0 && elapsed < totalDuration && (stage(elapsed) == .takeoff || stage(elapsed) == .returning)
    }
}

struct MotionPoint { var x: Double; var y: Double }
enum ArrivalAction { case typing, hopping, dancing }
enum PetMotion {
    static let sleepFrameCount = 32
    static let sleepCycleDuration = 4.0
    static let sleepFPS = Double(sleepFrameCount) / sleepCycleDuration
    static let typingFrameCount = 16
    static let typingFPS = 8.0
    static let classicFrameCount = 16
    static let classicFPS = 8.0
    static let supperRestTime = ceil(PetTiming.totalDance/1.8)*1.8
    static func supperFrame(_ time: Double) -> Int { Int(max(0,time)/0.9)%2+1 }
    static func supperLift(_ time: Double) -> Double { abs(sin(max(0,time)/0.9 * .pi))*7.2 }
    static func supperSway(_ time: Double) -> Double { sin(max(0,time)/1.8 * 2 * .pi)*2 }
    static func woodstockVisibility(phase: PetPhase, elapsed: Double) -> Double {
        switch phase {
        case .interacting, .weather: return 0 // These scene renderers own their birds.
        case .delivery: return 1-smooth(elapsed/0.35)
        case .dancing,.departing: return 0
        case .returning: return smooth((elapsed-(PetTiming.returning-0.25))/0.25)
        default: return 1
        }
    }
    static func typingFrame(_ time: Double) -> Int { Int(max(0, time) * typingFPS) % typingFrameCount + 1 }
    static func classicFrame(_ time: Double) -> Int { Int(max(0, time) * classicFPS) % classicFrameCount + 1 }
    static func gaitFrame(distance: Double) -> Int { Int(max(0, distance) / 65 * 16) % 16 + 1 }
    static func sleepFrame(_ time: Double) -> Int {
        Int(max(0, time) * sleepFPS) % sleepFrameCount + 1
    }
    static func sleepSprite(_ time: Double) -> String { String(format: "breath-%02d", sleepFrame(time)) }
    static func wakeFrame(_ time: Double) -> Int { min(6, Int(max(0, time) / PetTiming.wake * 6) + 1) }
    static func climbFrame(_ time: Double) -> Int { min(8, Int(max(0, time) / PetTiming.returning * 8) + 1) }
    static func smooth(_ value: Double) -> Double { let t = min(1, max(0, value)); return t * t * (3 - 2 * t) }
    static func arrivalAction(_ time: Double) -> ArrivalAction {
        if time < PetTiming.anticipation { return .typing }
        if time < PetTiming.anticipation + PetTiming.hop { return .hopping }
        return .dancing
    }
    static func charlieDistance(_ time: Double) -> Double {
        let t = min(PetTiming.walk, max(0, time)), deceleration = 0.25
        let cruising = PetTiming.walk - deceleration
        let velocity = 188 / (PetTiming.walk - deceleration / 2)
        if t <= cruising { return velocity * t }
        let u = t - cruising
        return velocity * cruising + velocity * u - velocity * u * u / (2 * deceleration)
    }
    static func departureDistance(_ time: Double) -> Double {
        let t = min(PetTiming.departing - PetTiming.turn, max(0, time - PetTiming.turn))
        let acceleration = 0.2, duration = PetTiming.departing - PetTiming.turn
        let velocity = 218 / (duration - acceleration / 2)
        if t < acceleration { return velocity * t * t / (2 * acceleration) }
        return velocity * (t - acceleration / 2)
    }
    static func hopFrame(_ time: Double) -> Int {
        if time < 0.25 { return 1 }; if time < 0.45 { return 2 }
        if time < 0.70 { return 3 }; if time < 1.0 { return 4 }
        if time < 1.35 { return 5 }; return 6
    }
    static func hopFoot(_ time: Double, roof: Double, ground: Double) -> MotionPoint {
        let p = min(1, max(0, (time - 0.4) / 0.95))
        if p == 0 { return MotionPoint(x: 174, y: roof) }
        if p == 1 { return MotionPoint(x: 260, y: ground) }
        return MotionPoint(x: 174 + 86 * smooth(p), y: roof + (ground - roof) * p + sin(p * .pi) * 44)
    }
}

/// Monitor activity and presentation are separate: new work never teleports Snoopy out of a climb.
final class PetState {
    private(set) var activeSources: Set<String> = []
    private(set) var phase: PetPhase = .idle
    private(set) var phaseStarted: TimeInterval = 0
    private(set) var isDemo = false
    private(set) var lastFailure = false
    private var completedDuringWake = false
    private var completedDuringTouch = false
    private var completedDuringWeather = false
    private(set) var weatherKind: WeatherKind?
    private(set) var weatherExitStarted: TimeInterval?
    private(set) var weatherFrozenElapsed: TimeInterval?
    var onChange: (() -> Void)?

    func receive(source: String, phase event: String, at now: TimeInterval) {
        guard !source.isEmpty, ["working", "done", "failed"].contains(event) else { return }
        if event != "working" && !activeSources.contains(source) { return }
        isDemo = false
        if event == "working" {
            activeSources.insert(source); lastFailure = false; completedDuringWake = false
            completedDuringTouch = false; completedDuringWeather = false
            switch phase {
            case .idle: transition(.waking, at: now)
            case .weather:
                if weatherExitStarted == nil {
                    weatherFrozenElapsed = max(0, now - phaseStarted)
                    weatherExitStarted = now
                }
            case .settling:
                let settled = min(1, max(0, (now - phaseStarted) / PetTiming.settle))
                transition(.waking, at: now - (1 - settled) * PetTiming.wake)
            case .dancing: transition(.departing, at: now)
            case .interacting, .waking, .working, .delivery, .departing, .returning: break
            }
        } else {
            activeSources.remove(source)
            if event == "failed" { lastFailure = true }
            if activeSources.isEmpty {
                switch phase {
                case .interacting: completedDuringTouch = event == "done"
                case .weather: completedDuringWeather = event == "done"
                case .waking: completedDuringWake = event == "done"
                case .working: transition(event == "failed" ? .settling : .delivery, at: now)
                case .delivery, .dancing, .departing, .returning: break
                case .idle, .settling: break
                }
            }
        }
        onChange?()
    }
    /// Idle-only, reentrant-safe interaction. It creates no synthetic work source.
    @discardableResult func startBellyInteraction(at now: TimeInterval) -> Bool {
        guard phase == .idle, activeSources.isEmpty else { return false }
        InteractionMotionSettings.applyPendingIfSafe(isInteracting:false)
        isDemo = false; lastFailure = false
        completedDuringWake = false; completedDuringTouch = false
        transition(.interacting, at: now)
        return true
    }
    /// Weather can only begin while asleep, never during work or another animation.
    @discardableResult func startWeather(_ kind: WeatherKind, at now: TimeInterval) -> Bool {
        guard phase == .idle, activeSources.isEmpty else { return false }
        clearWeather()
        weatherKind = kind
        isDemo = false; lastFailure = false
        completedDuringWake = false; completedDuringTouch = false
        transition(.weather, at: now)
        return true
    }
    func weatherPresentation(at now: TimeInterval) -> WeatherPresentation? {
        guard phase == .weather, let kind = weatherKind else { return nil }
        let elapsed = min(WeatherMotion.duration(for: kind), max(0, weatherFrozenElapsed ?? (now - phaseStarted)))
        let exit = weatherExitStarted.map { min(1, max(0, (now - $0) / WeatherMotion.exitDuration)) }
        return WeatherPresentation(kind: kind, elapsed: elapsed, exitProgress: exit)
    }
    private func clearWeather() {
        weatherKind = nil; weatherExitStarted = nil; weatherFrozenElapsed = nil; completedDuringWeather = false
    }
    func demo(at now: TimeInterval) {
        clearWeather()
        isDemo = true; lastFailure = false; completedDuringWake = false; completedDuringTouch = false
        transition(.waking, at: now)
    }
    func clearAll(at now: TimeInterval) {
        clearWeather()
        activeSources.removeAll(); completedDuringWake = false; completedDuringTouch = false; lastFailure = false; isDemo = false
        transition(.idle, at: now)
    }
    func resetPresentation(at now: TimeInterval) {
        clearWeather()
        isDemo = false; completedDuringTouch = false; transition(activeSources.isEmpty ? .idle : .working, at: now)
    }
    func tick(at now: TimeInterval) {
        for _ in 0..<12 {
            let duration: TimeInterval, next: PetPhase
            switch phase {
            case .weather:
                // A real request cuts a weather vignette short through a bounded visual exit.
                // The source set remains authoritative even when it starts and ends during that exit.
                guard let kind = weatherKind else { transition(.idle, at: now); continue }
                if let exitStarted = weatherExitStarted {
                    guard now - exitStarted >= WeatherMotion.exitDuration else { return }
                    let endedAt = exitStarted + WeatherMotion.exitDuration
                    let wake = !activeSources.isEmpty || completedDuringWeather
                    completedDuringWake = activeSources.isEmpty && completedDuringWeather
                    clearWeather()
                    transition(wake ? .waking : .idle, at: endedAt)
                    continue
                }
                duration = WeatherMotion.duration(for: kind)
                next = .idle
            case .interacting:
                duration = TouchMotion.totalDuration
                next = !activeSources.isEmpty || completedDuringTouch ? .waking : .idle
            case .waking:
                duration = PetTiming.wake
                next = !activeSources.isEmpty || isDemo ? .working : (completedDuringWake ? .delivery : .settling)
            case .working where isDemo: duration = PetTiming.work; next = .delivery
            case .delivery:
                duration = PetTiming.delivery
                next = !activeSources.isEmpty && !isDemo ? .departing : .dancing
            case .dancing: duration = PetTiming.dance; next = .departing
            case .departing: duration = PetTiming.departing; next = .returning
            case .returning: duration = PetTiming.returning; next = activeSources.isEmpty ? .settling : .working
            case .settling: duration = PetTiming.settle; next = activeSources.isEmpty ? .idle : .waking
            default: return
            }
            guard now - phaseStarted >= duration else { return }
            if phase == .returning { isDemo = false }
            if phase == .waking { completedDuringWake = false }
            if phase == .interacting {
                // A whole short request can begin and finish during the touch animation.
                // Preserve its real success through wake-up rather than inventing work.
                completedDuringWake = activeSources.isEmpty && completedDuringTouch
                completedDuringTouch = false
            }
            if phase == .weather { clearWeather() }
            transition(next, at: phaseStarted + duration)
        }
    }
    private func transition(_ next: PetPhase, at now: TimeInterval) { phase = next; phaseStarted = now; onChange?() }
}

func runPetStateTests() throws {
    struct Failure: Error, CustomStringConvertible { let description: String }
    var count = 0
    func require(_ condition: @autoclosure () -> Bool, _ label: String) throws {
        if !condition() { throw Failure(description: label) }; count += 1
    }
    let state = PetState()
    state.receive(source: "a", phase: "working", at: 0)
    state.receive(source: "b", phase: "working", at: 0.5)
    state.tick(at: 1.21)
    try require(state.phase == .working && state.activeSources.count == 2, "Concurrent starts must share one wake sequence")
    state.receive(source: "a", phase: "done", at: 2)
    try require(state.phase == .working, "One completion must not stop another active source")
    state.receive(source: "unknown", phase: "done", at: 2.1)
    try require(state.activeSources == ["b"], "Unknown completions must be ignored")
    state.receive(source: "b", phase: "done", at: 3)
    try require(state.phase == .delivery, "Last completion starts parallel arrival")
    state.tick(at: 5)
    try require(state.phase == .delivery && PetMotion.arrivalAction(2) == .dancing && PetMotion.charlieDistance(2) < 188, "Snoopy must already dance before Charlie arrives")
    state.tick(at: 6.01); try require(state.phase == .dancing, "Arrival must flow into the same dance")
    state.tick(at: 10.01); try require(state.phase == .departing, "Charlie leaves after five total seconds of dancing")
    state.tick(at: 13.41); try require(state.phase == .returning, "Climbing begins after Charlie has walked out")
    state.tick(at: 15.81); try require(state.phase == .settling, "Real climbing ends seated before sleep")
    state.tick(at: 17.3); try require(state.phase == .idle, "The entire dinner scene ends asleep")
    let quick = PetState(); quick.receive(source: "q", phase: "working", at: 0); quick.receive(source: "q", phase: "done", at: 0.1)
    quick.tick(at: 1.1); try require(quick.phase == .waking, "Fast completion must finish waking")
    quick.tick(at: 1.21); try require(quick.phase == .delivery, "Fast completion must not fake an active work phase")
    let failure = PetState(); failure.receive(source: "f", phase: "working", at: 0); failure.receive(source: "f", phase: "failed", at: 0.1)
    failure.tick(at: 1.21); try require(failure.phase == .settling && failure.lastFailure, "A failed task must not trigger dinner")
    failure.tick(at: 3); try require(failure.phase == .idle, "A failed task eventually sleeps")
    let reverse = PetState(); reverse.receive(source: "f", phase: "working", at: 0); reverse.tick(at: 1.21); reverse.receive(source: "f", phase: "failed", at: 2); reverse.receive(source: "n", phase: "working", at: 2.7)
    try require(reverse.phase == .waking && abs(reverse.phaseStarted - 2.1) < 0.001, "New work reverses settling from the same pose")
    reverse.tick(at: 3.31); try require(reverse.phase == .working, "Reversed wake resumes actual work")
    let interrupted = PetState(); interrupted.demo(at: 0); interrupted.tick(at: 14.3)
    try require(interrupted.phase == .departing, "Demo must include a real departure")
    let exitStarted = interrupted.phaseStarted
    interrupted.receive(source: "n", phase: "working", at: 14.4)
    try require(interrupted.phase == .departing && interrupted.phaseStarted == exitStarted, "New work cannot restart or teleport a departure")
    interrupted.tick(at: 17.61)
    try require(interrupted.phase == .returning, "New work waits for the roof climb")
    let climbStarted = interrupted.phaseStarted
    interrupted.receive(source: "m", phase: "working", at: 17.7)
    try require(interrupted.phase == .returning && interrupted.phaseStarted == climbStarted, "A second source cannot restart a climb")
    interrupted.receive(source: "n", phase: "done", at: 17.8); interrupted.tick(at: 20.01)
    try require(interrupted.phase == .working && interrupted.activeSources == ["m"], "Climbing resumes remaining work instead of falling asleep")
    interrupted.clearAll(at: 21)
    try require(interrupted.phase == .idle && interrupted.activeSources.isEmpty, "Reset clears stuck activity")
    let delayed = PetState(); delayed.demo(at: 0); delayed.tick(at: 100)
    try require(delayed.phase == .idle && !delayed.isDemo, "Late timer ticks must preserve the complete storyboard")
    try require(PetMotion.arrivalAction(0.3) == .typing && PetMotion.arrivalAction(0.5) == .hopping && PetMotion.arrivalAction(2.1) == .dancing, "Jumping overlaps Charlie's approach")
    try require(abs(PetTiming.dance + PetTiming.danceLead - 5) < 0.001, "The dance lasts five seconds, not many accelerated cycles")
    try require((0..<16).map { PetMotion.typingFrame(Double($0) / 8) } == Array(1...16) && PetMotion.typingFrame(2) == 1, "Typing uses sixteen poses over two gentle seconds")
    try require(PetMotion.typingFrame(0.1249) == 1 && PetMotion.typingFrame(0.125) == 2 && PetMotion.typingFrame(-1) == 1, "Typing frame boundaries are eight fps")
    try require((0..<16).map { PetMotion.classicFrame(Double($0) / 8) } == Array(1...16) && PetMotion.classicFrame(2) == 1, "Classic dance preserves a two-second cycle")
    try require(PetMotion.gaitFrame(distance: 0) == 1 && PetMotion.gaitFrame(distance: 65) == 1, "Walking cadence follows distance rather than fast timer ticks")
    try require(abs(PetMotion.charlieDistance(2.85) - 188) < 0.001 && PetMotion.charlieDistance(2.85) - PetMotion.charlieDistance(2.84) < 0.02, "Charlie stops smoothly at the bowl-facing position")
    try require(PetMotion.departureDistance(0.3) == 0 && abs(PetMotion.departureDistance(3.4) - 218) < 0.001, "Charlie turns then fully walks offscreen")
    let start = PetMotion.hopFoot(0, roof: 124, ground: 20), land = PetMotion.hopFoot(1.6, roof: 124, ground: 20)
    try require(start.x == 174 && start.y == 124 && land.x == 260 && land.y == 20, "Downward hop has exact roof and ground contacts")
    var maxStep = 0.0, previous = start
    for frame in 1...52 { let p = PetMotion.hopFoot(Double(frame) / 32, roof: 124, ground: 20); maxStep = max(maxStep, hypot(p.x - previous.x, p.y - previous.y)); previous = p }
    try require(maxStep < 10, "Downward hop position remains continuous at runtime cadence")
    try require(Set((0..<160).map { PetMotion.hopFrame(Double($0) / 100) }).count == 6, "Downward hop uses six real poses")
    try require((0..<8).map { PetMotion.climbFrame(Double($0) * 0.3 + 0.01) } == Array(1...8), "Roof ascent uses eight forward climb poses")
    try require((0..<32).map { PetMotion.sleepFrame(Double($0) / 8) } == Array(1...32) && PetMotion.sleepFrame(4) == 1, "Idle uses32 frames without shortening its four-second breath")
    try require(PetMotion.sleepFrame(-1) == 1 && PetMotion.sleepFrame(0.1249) == 1 && PetMotion.sleepFrame(0.125) == 2 && PetMotion.sleepSprite(3.875) == "breath-32", "Sleep frame names and boundaries stay eightfps")
    let touch = PetState()
    try require(touch.startBellyInteraction(at: 10), "Idle belly touch is accepted")
    try require(touch.phase == .interacting && touch.activeSources.isEmpty && !touch.isDemo, "A touch creates neither work nor a demo")
    try require(!touch.startBellyInteraction(at: 10.2) && touch.phaseStarted == 10, "Repeated taps cannot restart or stack interactions")
    touch.receive(source: "unknown", phase: "done", at: 11)
    touch.tick(at: 10 + TouchMotion.totalDuration - 0.001)
    try require(touch.phase == .interacting, "The complete touch scene is allowed to finish")
    touch.tick(at: 10 + TouchMotion.totalDuration + 0.001)
    try require(touch.phase == .idle && touch.activeSources.isEmpty, "Touch-only interaction ends asleep without dinner")
    try require(touch.startBellyInteraction(at: 20), "A later independent belly touch can play again")
    let busyTouch = PetState(); busyTouch.receive(source: "real", phase: "working", at: 0)
    try require(!busyTouch.startBellyInteraction(at: 0.1) && busyTouch.activeSources == ["real"], "Touch cannot interrupt real work or clear its source")
    let queuedWork = PetState(); queuedWork.startBellyInteraction(at: 0)
    queuedWork.receive(source: "a", phase: "working", at: 0.7); queuedWork.receive(source: "b", phase: "working", at: 1.2)
    queuedWork.receive(source: "a", phase: "done", at: 2)
    try require(queuedWork.phase == .interacting && queuedWork.activeSources == ["b"] && queuedWork.phaseStarted == 0, "Concurrent work is tracked without teleporting a touch pose")
    queuedWork.tick(at: TouchMotion.totalDuration + 0.001)
    try require(queuedWork.phase == .waking && queuedWork.activeSources == ["b"], "Remaining work wakes Snoopy after the continuous touch sequence")
    queuedWork.tick(at: TouchMotion.totalDuration + PetTiming.wake + 0.001)
    try require(queuedWork.phase == .working, "Queued activity proceeds to actual typing")
    let touchedQuick = PetState(); touchedQuick.startBellyInteraction(at: 0)
    touchedQuick.receive(source: "quick", phase: "working", at: 0.7); touchedQuick.receive(source: "quick", phase: "done", at: 1.1)
    touchedQuick.tick(at: TouchMotion.totalDuration + 0.001)
    try require(touchedQuick.phase == .waking && touchedQuick.activeSources.isEmpty, "Short success during touch is remembered through waking")
    touchedQuick.tick(at: TouchMotion.totalDuration + PetTiming.wake + 0.001)
    try require(touchedQuick.phase == .delivery, "Short success gets the real dinner sequence without fake work")
    let touchedFailure = PetState(); touchedFailure.startBellyInteraction(at: 0)
    touchedFailure.receive(source: "cancelled", phase: "working", at: 1); touchedFailure.receive(source: "cancelled", phase: "failed", at: 2)
    touchedFailure.tick(at: TouchMotion.totalDuration + 0.001)
    try require(touchedFailure.phase == .idle && touchedFailure.lastFailure, "Cancelled work during touch returns to sleep without success")
    let touchedRestart = PetState(); touchedRestart.startBellyInteraction(at: 0)
    touchedRestart.receive(source: "q", phase: "working", at: 0.2); touchedRestart.receive(source: "q", phase: "done", at: 0.4)
    touchedRestart.receive(source: "new", phase: "working", at: TouchMotion.returningStarts + 0.1)
    touchedRestart.tick(at: TouchMotion.totalDuration + 0.001)
    try require(touchedRestart.phase == .waking && touchedRestart.activeSources == ["new"], "Fresh work supersedes an earlier queued success")
    touchedRestart.receive(source: "new", phase: "failed", at: TouchMotion.totalDuration + 0.2)
    touchedRestart.tick(at: TouchMotion.totalDuration + PetTiming.wake + 0.001)
    try require(touchedRestart.phase == .settling, "A newer cancellation never resurrects an old touch success")
    let touchedReset = PetState(); touchedReset.startBellyInteraction(at: 0); touchedReset.receive(source: "r", phase: "working", at: 1)
    touchedReset.clearAll(at: 2); touchedReset.receive(source: "r", phase: "done", at: 3); touchedReset.tick(at: 100)
    try require(touchedReset.phase == .idle && touchedReset.activeSources.isEmpty, "Reset clears interaction and stale completion")
    try require(TouchMotion.stage(0) == .takeoff && TouchMotion.stage(TouchMotion.risingStarts) == .rising && TouchMotion.stage(TouchMotion.blinkingStarts) == .blinking && TouchMotion.stage(TouchMotion.lyingStarts) == .lying && TouchMotion.stage(TouchMotion.returningStarts) == .returning, "Touch stages preserve bird-rise-blink-lie-return order")
    try require(TouchMotion.seatedProgress(0) == 0 && TouchMotion.seatedProgress(TouchMotion.blinkingStarts) == 1 && TouchMotion.seatedProgress(TouchMotion.returningStarts) == 0, "Only the middle of the interaction is seated")
    try require(TouchMotion.birdAwayProgress(0) == 0 && TouchMotion.birdAwayProgress(TouchMotion.risingStarts) == 1 && TouchMotion.birdAwayProgress(TouchMotion.returningStarts) == 1 && TouchMotion.birdAwayProgress(TouchMotion.totalDuration) == 0, "Woodstock fully leaves and lands exactly back at the belly")
    try require(TouchMotion.birdIsFlying(0.1) && !TouchMotion.birdIsFlying(TouchMotion.blinkingStarts) && TouchMotion.birdIsFlying(TouchMotion.returningStarts + 0.1) && !TouchMotion.birdIsFlying(TouchMotion.totalDuration), "Bird flies only on the outward and returning paths")
    var blinkWindows = 0, previousBlink = false, blinkRangeValid = true
    for frame in 0...Int(TouchMotion.totalDuration * 1000) {
        let amount = TouchMotion.blinkAmount(Double(frame) / 1000)
        let closed = amount > 0
        if closed && !previousBlink { blinkWindows += 1 }
        previousBlink = closed
        blinkRangeValid = blinkRangeValid && amount >= 0 && amount <= 1
    }
    try require(blinkRangeValid && blinkWindows == 2, "Interaction has exactly two separate blinks, both within eyelid range")
    try require(TouchMotion.blinkAmount(TouchMotion.blinkingStarts + TouchMotion.blinkLead + TouchMotion.blinkClose + 0.05) == 1 && TouchMotion.blinkAmount(TouchMotion.blinkingStarts + TouchMotion.blinkLead + TouchMotion.singleBlinkDuration + 0.1) == 0, "Each blink has a closed hold and an open-eye pause")
    try require(TouchMotion.blinkAmount(0) == 0 && TouchMotion.blinkAmount(TouchMotion.totalDuration) == 0 && PetMotion.woodstockVisibility(phase: .interacting, elapsed: 1) == 0, "Touch eyelids and flight are isolated from other scene rendering")
    try require(PetMotion.supperFrame(0)==1 && PetMotion.supperFrame(0.9)==2 && PetMotion.supperFrame(1.8)==1,"First-edition two poses alternate gently over1.8seconds")
    try require(abs(PetMotion.supperLift(0.45)-7.2)<0.001 && PetMotion.supperLift(0)<0.001 && abs(PetMotion.supperSway(0.45)-2)<0.001,"Dinner dance has a small grounded hop and weight shift")
    try require(PetMotion.woodstockVisibility(phase:.delivery,elapsed:0.4)==0 && PetMotion.woodstockVisibility(phase:.dancing,elapsed:1)==0 && PetMotion.woodstockVisibility(phase:.returning,elapsed:2)==0,"Woodstock stays away from downward hop,dance,andclimb")
    try require(PetMotion.woodstockVisibility(phase:.idle,elapsed:0)==1 && PetMotion.woodstockVisibility(phase:.returning,elapsed:2.4)==1,"Woodstock returns only once back on the roof")
    try require(PetMotion.supperLift(PetMotion.supperRestTime)<0.001 && abs(PetMotion.supperSway(PetMotion.supperRestTime))<0.001,"The final supper beat rests on the ground before climbing")
    print("PASS: \(count) state and motion assertions")
}
