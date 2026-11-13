import Foundation

/// The complete umbrella prop shares one flight transform; its wing poses never detach from the shaft.
struct RainFlightSample {
    let offsetX: Double
    let offsetY: Double
    let bankDegrees: Double
    let wingFrame: Int
    let nextWingFrame: Int
    let wingBlend: Double
    let flightMix: Double
    let opacity: Double
}

enum RainFlightMotion {
    static let arrivalStart = 4.0
    static let landingTime = 6.0
    static let departureStart = 25.0
    static let departureEnd = 27.0
    static let landingDuration = 0.30
    static let wingPoseRate = 8.0

    private static func smooth(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    /// Offsets are logical points from Woodstock's eventual head perch.
    /// Wing pose interpolation is independent of the two-second travel time.
    static func sample(at elapsed: Double) -> RainFlightSample? {
        guard elapsed.isFinite, elapsed >= arrivalStart, elapsed < departureEnd else { return nil }
        if elapsed >= landingTime && elapsed < departureStart {
            return RainFlightSample(offsetX: 0, offsetY: 0, bankDegrees: 0,
                wingFrame: 1, nextWingFrame: 1, wingBlend: 0, flightMix: 0, opacity: 1)
        }
        let arriving = elapsed < landingTime
        let start = arriving ? arrivalStart : departureStart
        let local = max(0, elapsed - start)
        let progress = smooth(local / 2)
        let envelope = pow(sin(progress * .pi), 2)
        let bob = sin(progress * 4 * .pi) * envelope * 2.2
        let bank = sin(progress * 2 * .pi) * envelope * 2.4
        let wingPosition = local * wingPoseRate
        let wingSlot = Int(floor(wingPosition))
        let frame = wingSlot % 4 + 1
        let fraction = wingPosition - floor(wingPosition)
        let flightMix = arriving
            ? 1 - smooth((elapsed - (landingTime - landingDuration)) / landingDuration)
            : smooth(local / 0.22)
        let opacity = arriving ? smooth(local / 0.20) : 1 - smooth((elapsed - 26.65) / 0.35)
        return RainFlightSample(offsetX: arriving ? 85 * (1 - progress) : 82 * progress,
            offsetY: (arriving ? 5 * (1 - progress) : 5 * progress) + bob,
            bankDegrees: bank, wingFrame: frame, nextWingFrame: frame % 4 + 1,
            wingBlend: smooth(fraction), flightMix: flightMix, opacity: opacity)
    }

    /// Snoopy reaches upward while the bird approaches, then lowers his paw after takeoff.
    static func supportProgress(at elapsed: Double) -> Double {
        guard elapsed.isFinite, elapsed >= 4.0, elapsed < 27.0 else { return 0 }
        if elapsed < landingTime { return min(1,max(0,(elapsed - 4.0) / 2.0)) }
        if elapsed <= departureStart { return 1 }
        return 1 - min(1,max(0,(elapsed - departureStart) / 2.0))
    }
}

func runRainFlightMotionTests() throws {
    struct Failure: Error, CustomStringConvertible { let description: String }
    var count = 0
    func check(_ value: @autoclosure () -> Bool, _ label: String) throws {
        guard value() else { throw Failure(description: label) }; count += 1
    }
    for time in [-1.0, 3.999, 27, 30, Double.nan, Double.infinity] {
        try check(RainFlightMotion.sample(at: time) == nil, "Umbrella is absent outside its own arrival-to-departure interval")
    }
    guard let start = RainFlightMotion.sample(at: 4), let landed = RainFlightMotion.sample(at: 6),
          let depart = RainFlightMotion.sample(at: 25), let almostGone = RainFlightMotion.sample(at: 26.999) else {
        throw Failure(description: "Flight endpoints must exist")
    }
    try check(start.offsetX == 85 && start.offsetY == 5 && start.opacity == 0, "Incoming bird begins above and to the right, still outside the visible fade")
    try check(landed.offsetX == 0 && landed.offsetY == 0 && landed.bankDegrees == 0 && landed.flightMix == 0 && landed.opacity == 1,
              "Landing ends at a fixed perch with folded wings")
    try check(depart.offsetX == 0 && depart.offsetY == 0 && depart.flightMix == 0,
              "Takeoff starts from the same planted feet rather than jumping to a flight pose")
    try check(abs(almostGone.offsetX - 82) < 0.001 && abs(almostGone.offsetY - 5) < 0.001 && almostGone.opacity < 0.001,
              "Departure finishes at its away point through a completed fade")
    let firstStep = RainFlightMotion.sample(at: 4.001)!, lastStep = RainFlightMotion.sample(at: 5.999)!
    try check(abs(firstStep.offsetX - start.offsetX) / 0.001 < 0.1 && abs(lastStep.offsetX - landed.offsetX) / 0.001 < 0.1,
              "Incoming travel accelerates and stops with near-zero endpoint velocities")
    let leaveStep = RainFlightMotion.sample(at: 25.001)!
    try check(abs(leaveStep.offsetX - depart.offsetX) / 0.001 < 0.1,
              "Departure accelerates gently from rest")
    var wingFrames: Set<Int> = [], maximumBank = 0.0, maximumBob = 0.0, maximumStep = 0.0
    var previous = start
    for frame in 0..<96 {
        let elapsed = 4 + Double(frame) / 48
        let sample = RainFlightMotion.sample(at: elapsed)!
        wingFrames.insert(sample.wingFrame)
        maximumBank = max(maximumBank, abs(sample.bankDegrees))
        let t = Double(frame) / 96, progress = t * t * (3 - 2 * t)
        maximumBob = max(maximumBob, abs(sample.offsetY - 5 * (1 - progress)))
        maximumStep = max(maximumStep, hypot(sample.offsetX - previous.offsetX, sample.offsetY - previous.offsetY))
        previous = sample
        try check((1...4).contains(sample.wingFrame) && (1...4).contains(sample.nextWingFrame) && (0...1).contains(sample.wingBlend),
                  "Every rendered wing sample selects valid registered poses and bounded interpolation")
    }
    try check(wingFrames.count == 4, "Powered flight uses four distinct wing poses instead of translating a standing bird")
    try check(maximumBank <= 3 && maximumBob <= 3 && maximumStep < 3,
              "The short flight remains gentle enough to preserve cloud clearance at48fps")
    let flight = RainFlightMotion.sample(at: 5.6)!, landing = RainFlightMotion.sample(at: 5.85)!
    try check(flight.flightMix == 1 && landing.flightMix > 0 && landing.flightMix < 1,
              "Wings fold only in the final0.30seconds of landing")
    for time in [6.0, 9, 16, 24.999] {
        let sample = RainFlightMotion.sample(at: time)!
        try check(sample.offsetX == 0 && sample.offsetY == 0 && sample.bankDegrees == 0 && sample.flightMix == 0,
                  "The entire nineteen-second perch is still and supported")
    }
    try check(RainFlightMotion.supportProgress(at: 4.0) == 0 && RainFlightMotion.supportProgress(at: 5.3) > 0 && RainFlightMotion.supportProgress(at: 5.3) < 1,
              "The supporting paw rises progressively during arrival")
    try check(RainFlightMotion.supportProgress(at: 6) == 1 && RainFlightMotion.supportProgress(at: 25) == 1,
              "The hand stays raised while Woodstock perches")
    try check(RainFlightMotion.supportProgress(at: 25.8) > 0 && RainFlightMotion.supportProgress(at: 25.8) < 1 && RainFlightMotion.supportProgress(at: 27.0) == 0,
              "The hand lowers gradually after Woodstock takes off")
    try check(RainFlightMotion.supportProgress(at: .nan) == 0, "Invalid times cannot raise a detached hand")
    print("PASS: \(count) powered umbrella flight, landing, perch and supporting-paw assertions")
}
