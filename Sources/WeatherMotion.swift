import Foundation

/// The timeline is in seconds; rendering at more frames never speeds the story up.
struct WeatherPresentation {
    let kind: WeatherKind
    let elapsed: Double
    /// Nil during the normal vignette. Otherwise 0...1 fades the frozen pose into rest.
    let exitProgress: Double?
}

enum WeatherMotion {
    static let exitDuration = 1.2
    static let renderingFPS = 64.0

    static func duration(for _: WeatherKind) -> Double { 30.0 }
    static func coreHoldStart(for kind: WeatherKind) -> Double {
        switch kind {
        case .rain: return 6
        case .sunny, .cloudy: return 4
        case .snow: return 0
        }
    }
    static func coreHoldEnd(for kind: WeatherKind) -> Double {
        kind == .snow ? 24.0 : 25.0
    }
}

func runWeatherStateTests() throws {
    struct Failure: Error, CustomStringConvertible { let description: String }
    var count = 0
    func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
        guard condition() else { throw Failure(description: label) }; count += 1
    }
    try check(WeatherMotion.renderingFPS == 64, "Weather renders at64fps without changing elapsed-time story speed")
    try check(WeatherMotion.exitDuration == 1.2, "Longer weather never extends the bounded real-request exit")
    for kind in WeatherKind.allCases {
        let state = PetState(), duration = WeatherMotion.duration(for: kind)
        try check(duration == 30 && duration * WeatherMotion.renderingFPS == 1920, "Every weather uses thirty seconds and1920 runtime frame opportunities")
        try check(state.startWeather(kind, at: 20), "Each weather can start while idle: \(kind)")
        try check(state.phase == .weather && state.weatherKind == kind && state.activeSources.isEmpty && !state.isDemo, "Weather never fabricates a work source")
        try check(!state.startWeather(kind, at: 21) && state.phaseStarted == 20, "A weather vignette cannot restart itself")
        try check(!state.startBellyInteraction(at: 21), "Belly touches cannot interrupt weather")
        let pose = state.weatherPresentation(at: 22)
        try check(pose?.kind == kind && pose?.elapsed == 2 && pose?.exitProgress == nil, "Normal weather presentation follows the scene clock")
        try check(state.weatherPresentation(at: 19)?.elapsed == 0, "Presentation elapsed cannot be negative")
        try check(state.weatherPresentation(at: 200)?.elapsed == duration, "Presentation elapsed is clamped to its storyboard")
        state.receive(source: "unknown", phase: "done", at: 21)
        state.tick(at: 20 + duration - 0.001)
        try check(state.phase == .weather, "Weather keeps its complete timeline")
        state.tick(at: 20 + duration)
        try check(state.phase == .idle && state.phaseStarted == 20 + duration && state.weatherKind == nil && state.weatherPresentation(at: 99) == nil, "Normal weather finishes asleep with no retained snapshot")
        let expectedStart: Double = kind == .rain ? 6 : (kind == .snow ? 0 : 4)
        let expectedEnd: Double = kind == .snow ? 24 : 25
        try check(WeatherMotion.coreHoldStart(for: kind) == expectedStart && WeatherMotion.coreHoldEnd(for: kind) == expectedEnd, "Each extended core beat has its agreed real-time boundaries")
        try check(expectedEnd - expectedStart >= 19 && expectedEnd < duration, "Longer scenes add sustained action while preserving time for a continuous return")
    }
    let work = PetState(); work.receive(source: "real", phase: "working", at: 0)
    try check(!work.startWeather(.sunny, at: 0.1) && work.activeSources == ["real"] && work.phase == .waking, "Weather cannot start during a real request")
    work.tick(at: 1.3)
    try check(!work.startWeather(.rain, at: 2) && work.phase == .working, "Weather cannot start while typing")
    let touch = PetState(); touch.startBellyInteraction(at: 0)
    try check(!touch.startWeather(.cloudy, at: 0.1) && touch.phase == .interacting, "Weather cannot start during a belly interaction")
    let delivery = PetState(); delivery.receive(source: "q", phase: "working", at: 0); delivery.receive(source: "q", phase: "done", at: 0.1); delivery.tick(at: 1.3)
    try check(!delivery.startWeather(.rain, at: 1.4) && delivery.phase == .delivery, "Weather cannot start during dinner delivery")
    let preempt = PetState(); preempt.startWeather(.rain, at: 0); preempt.receive(source: "a", phase: "working", at: 5)
    try check(preempt.phase == .weather && preempt.weatherExitStarted == 5 && preempt.weatherFrozenElapsed == 5 && preempt.activeSources == ["a"], "A request freezes the weather pose and begins an exit without losing activity")
    let exitPose = preempt.weatherPresentation(at: 5.6)
    try check(exitPose?.elapsed == 5 && abs((exitPose?.exitProgress ?? -1) - 0.5) < 0.0001, "The exit fades a frozen weather pose")
    try check(preempt.weatherPresentation(at: 4)?.exitProgress == 0 && preempt.weatherPresentation(at: 99)?.exitProgress == 1, "Exit progress is bounded")
    preempt.receive(source: "b", phase: "working", at: 5.8)
    try check(preempt.weatherExitStarted == 5 && preempt.weatherFrozenElapsed == 5, "Concurrent starts cannot delay the weather exit")
    preempt.receive(source: "a", phase: "done", at: 5.9)
    preempt.tick(at: 6.199)
    try check(preempt.phase == .weather, "Weather exit completes its smooth1.2second transition")
    preempt.tick(at: 6.201)
    try check(preempt.phase == .waking && abs(preempt.phaseStarted - 6.2) < 0.0001 && preempt.activeSources == ["b"] && preempt.weatherKind == nil, "Only1.2seconds of weather exit precedes waking for remaining work")
    preempt.tick(at: 7.401)
    try check(preempt.phase == .working && preempt.activeSources == ["b"], "Weather exit resumes the actual remaining source")
    let quick = PetState(); quick.startWeather(.sunny, at: 0); quick.receive(source: "q", phase: "working", at: 3); quick.receive(source: "q", phase: "done", at: 3.1)
    quick.tick(at: 4.201)
    try check(quick.phase == .waking && quick.activeSources.isEmpty, "A whole request during weather exit is remembered")
    quick.tick(at: 5.401)
    try check(quick.phase == .delivery && quick.activeSources.isEmpty, "A short successful request still earns dinner after weather")
    let failed = PetState(); failed.startWeather(.snow, at: 0); failed.receive(source: "f", phase: "working", at: 3); failed.receive(source: "f", phase: "failed", at: 3.2); failed.tick(at: 4.201)
    try check(failed.phase == .idle && failed.lastFailure && failed.weatherKind == nil, "A cancellation during weather exits to rest without dinner")
    let restarted = PetState(); restarted.startWeather(.cloudy, at: 0); restarted.receive(source: "a", phase: "working", at: 3); restarted.receive(source: "a", phase: "done", at: 3.1); restarted.receive(source: "b", phase: "working", at: 3.2); restarted.receive(source: "b", phase: "failed", at: 3.3); restarted.tick(at: 4.201)
    try check(restarted.phase == .idle && restarted.lastFailure, "A newer cancellation never resurrects an older successful request")
    let reset = PetState(); reset.startWeather(.rain, at: 0); reset.receive(source: "a", phase: "working", at: 2); reset.clearAll(at: 2.1); reset.receive(source: "a", phase: "done", at: 2.2); reset.tick(at: 100)
    try check(reset.phase == .idle && reset.weatherKind == nil && reset.weatherExitStarted == nil && reset.weatherFrozenElapsed == nil && reset.activeSources.isEmpty, "Reset clears weather, frozen exit and stale request activity")
    let demo = PetState(); demo.startWeather(.sunny, at: 0); demo.demo(at: 2)
    try check(demo.phase == .waking && demo.isDemo && demo.weatherKind == nil, "Manual demo clears a previous weather scene")
    let resetPresentation = PetState(); resetPresentation.startWeather(.cloudy, at: 0); resetPresentation.receive(source: "a", phase: "working", at: 2); resetPresentation.resetPresentation(at: 2.1)
    try check(resetPresentation.phase == .working && resetPresentation.weatherKind == nil && resetPresentation.activeSources == ["a"], "Presentation reset preserves real work while clearing weather")
    let late = PetState(); late.startWeather(.snow, at: 0); late.tick(at: 1000)
    try check(late.phase == .idle && late.weatherKind == nil, "A late timer skips finished weather instead of replaying it")
    try check(PetMotion.woodstockVisibility(phase: .weather, elapsed: 5) == 0, "Weather renderer exclusively owns its bird placement")
    print("PASS: \(count) idle-only weather state, timing and request-priority assertions")
}
