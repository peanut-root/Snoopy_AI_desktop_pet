import AppKit

/// Small, deterministic effects live in the same roof scene as the character.
/// The house is drawn by PetRenderer before this layer and never moves with the actor.
private enum WeatherInk {
    static var upperContours: [String: [CGFloat?]] = [:]
    static func ramp(_ time: Double, _ start: Double, _ duration: Double) -> CGFloat {
        CGFloat(PetMotion.smooth((time - start) / duration))
    }
    static func mix(_ a: NSPoint, _ b: NSPoint, _ t: CGFloat) -> NSPoint {
        NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
    static func flight(_ a: NSPoint, _ b: NSPoint, _ progress: CGFloat, lift: CGFloat) -> NSPoint {
        let point = mix(a, b, progress)
        return NSPoint(x: point.x, y: point.y + sin(progress * .pi) * lift)
    }
    static func scarfOffset(_ distance: CGFloat, time: Double, tail: Int) -> CGFloat {
        // Zero displacement at the knot avoids a detached ribbon at every wave phase.
        sin(distance * 0.16 - CGFloat(time) * 2.8 + CGFloat(tail) * 0.8) * min(4, distance * 0.14)
    }
}

extension PetRenderer {
    func drawWeather(_ presentation: WeatherPresentation, animation: Double) {
        let exit = CGFloat(presentation.exitProgress ?? 0)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext.current?.cgContext
        context?.setAlpha(1 - exit)
        context?.beginTransparencyLayer(auxiliaryInfo:nil)
        switch presentation.kind {
        case .rain: drawRainTheatre(elapsed: presentation.elapsed, animation: animation)
        case .sunny: drawSunnyTheatre(elapsed: presentation.elapsed, animation: animation)
        case .cloudy: drawPilotTheatre(elapsed: presentation.elapsed, animation: animation)
        case .snow: drawSnowTheatre(elapsed: presentation.elapsed, animation: animation)
        }
        context?.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
        if exit > 0 { weatherIdle(animation: animation, alpha: exit) }
    }

    private func weatherIdle(animation: Double, alpha: CGFloat = 1, bird: Bool = true) {
        let name = PetMotion.sleepSprite(animation)
        assets.draw(name, in: restBodyBox(for: name), alpha: alpha)
        if bird { weatherStandingBird(at: restingBellyPoint(animation: animation), alpha: alpha) }
    }

    private func weatherStandingBird(at point: NSPoint, alpha: CGFloat = 1) {
        assets.draw("woodstock", in: NSRect(x: point.x - 10, y: point.y - 1.2, width: 20, height: 21), alpha: alpha)
    }

    private func weatherFlyingBird(at point: NSPoint, elapsed: Double, alpha: CGFloat = 1, returning: Bool = false) {
        let name = "woodstock-flight-\(Int(max(0, elapsed) * 8) % 4 + 1)"
        let local = assets.fittedRect(name, in: NSRect(x: 0, y: 0, width: 28, height: 28))
        let u: CGFloat = returning ? 1 - 420.0 / 640 : 420.0 / 640
        // All four genuine flight poses share the eye registration used by belly interactions.
        let rect = NSRect(x: point.x - local.minX - local.width * u,
                          y: point.y + 10 - local.minY - local.height * 340 / 640,
                          width: 28, height: 28)
        assets.draw(name, in: rect, alpha: alpha, flip: returning)
    }

    /// The body rises through the established roof-contact poses; only the last portion blends.
    @discardableResult private func weatherRise(_ progress: CGFloat, animation: Double, alpha: CGFloat = 1) -> String {
        if progress <= 0 {
            let name = PetMotion.sleepSprite(animation)
            assets.draw(name, in: restBodyBox(for: name), alpha: alpha)
            return name
        }
        let position = min(1, max(0, progress)) * 3
        let index = min(3, Int(position))
        let blend = WeatherInk.ramp(Double(position - CGFloat(index)), 0.58, 0.42)
        let name = "wake-\(index + 1)"
        assets.draw(name, in: restBodyBox(for: name), alpha: alpha * (1 - blend))
        if index < 3 { assets.draw("wake-\(index + 2)", in: restBodyBox(for: "wake-\(index + 2)"), alpha: alpha * blend) }
        return blend < 0.5 || index == 3 ? name : "wake-\(index + 2)"
    }

    private func weatherSeated(_ name: String, animation: Double, alpha: CGFloat = 1, rotation: CGFloat = 0) {
        guard alpha > 0 else { return }
        var box = restBodyBox(for: name)
        // At this scale an eight-tenths-point breath is visible without bobbing the whole scene.
        let breath = CGFloat(sin(animation * .pi / 2)) * 0.35
        box.size.height += breath
        assets.draw(name, in: box, alpha: alpha, rotation: rotation)
    }

    private func weatherHead(_ name: String = "wake-4") -> NSPoint {
        assets.headPoint(name, in: restBodyBox(for: name))
    }

    private func weatherCloud(center: NSPoint, width: CGFloat, alpha: CGFloat) {
        guard alpha > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        let x=center.x, y=center.y, w=width
        NSGraphicsContext.current?.cgContext.translateBy(x:0,y:y)
        NSGraphicsContext.current?.cgContext.scaleBy(x:1,y:0.72)
        NSGraphicsContext.current?.cgContext.translateBy(x:0,y:-y)
        // Unequal low lobes and small interior ink marks keep the cloud close to comic-panel line art.
        let cloud=NSBezierPath()
        cloud.move(to:NSPoint(x:x-w*0.48,y:y-3))
        cloud.curve(to:NSPoint(x:x-w*0.33,y:y+4),controlPoint1:NSPoint(x:x-w*0.61,y:y+5),controlPoint2:NSPoint(x:x-w*0.43,y:y+12))
        cloud.curve(to:NSPoint(x:x-w*0.14,y:y+10),controlPoint1:NSPoint(x:x-w*0.34,y:y+15),controlPoint2:NSPoint(x:x-w*0.18,y:y+18))
        cloud.curve(to:NSPoint(x:x+w*0.08,y:y+12),controlPoint1:NSPoint(x:x-w*0.08,y:y+21),controlPoint2:NSPoint(x:x+w*0.03,y:y+21))
        cloud.curve(to:NSPoint(x:x+w*0.29,y:y+6),controlPoint1:NSPoint(x:x+w*0.20,y:y+20),controlPoint2:NSPoint(x:x+w*0.30,y:y+16))
        cloud.curve(to:NSPoint(x:x+w*0.46,y:y-2),controlPoint1:NSPoint(x:x+w*0.43,y:y+12),controlPoint2:NSPoint(x:x+w*0.57,y:y+5))
        cloud.curve(to:NSPoint(x:x-w*0.48,y:y-3),controlPoint1:NSPoint(x:x+w*0.20,y:y-4.8),controlPoint2:NSPoint(x:x-w*0.16,y:y-1.4))
        cloud.close()
        NSColor.white.setFill();cloud.fill()
        NSColor(calibratedWhite:0.08,alpha:1).setStroke();cloud.lineWidth=1.05;cloud.lineJoinStyle = .round;cloud.stroke()
        let ink=NSBezierPath();ink.lineWidth=0.65;ink.lineCapStyle = .round
        ink.move(to:NSPoint(x:x-w*0.38,y:y-0.2));ink.curve(to:NSPoint(x:x-w*0.24,y:y+0.5),controlPoint1:NSPoint(x:x-w*0.32,y:y-0.9),controlPoint2:NSPoint(x:x-w*0.27,y:y+1.4))
        ink.move(to:NSPoint(x:x+w*0.22,y:y+0.1));ink.line(to:NSPoint(x:x+w*0.30,y:y+0.5));ink.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func weatherSurface(at x: CGFloat, name: String, box: NSRect) -> CGFloat? {
        let fit = assets.fittedRect(name, in: box)
        guard fit.width > 0, x >= fit.minX, x <= fit.maxX, let image = assets.images[name] else { return nil }
        if assets.rainUpperContours[name] == nil, WeatherInk.upperContours[name] == nil, let data = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: data), let bytes = bitmap.bitmapData,
           !bitmap.isPlanar, bitmap.bitsPerSample == 8, bitmap.hasAlpha {
            var contour = [CGFloat?](repeating: nil, count: bitmap.pixelsWide)
            let stride = bitmap.samplesPerPixel
            let alphaOffset = bitmap.bitmapFormat.contains(.alphaFirst) ? 0 : stride - 1
            for column in 0..<bitmap.pixelsWide {
                for row in 0..<bitmap.pixelsHigh {
                    if bytes[row * bitmap.bytesPerRow + column * stride + alphaOffset] > 153 {
                        contour[column] = 1 - CGFloat(row) / CGFloat(bitmap.pixelsHigh)
                        break
                    }
                }
            }
            WeatherInk.upperContours[name] = contour
        }
        guard let contour = assets.rainUpperContours[name] ?? WeatherInk.upperContours[name], !contour.isEmpty else { return nil }
        let index = min(contour.count - 1, max(0, Int((x - fit.minX) / fit.width * CGFloat(contour.count))))
        guard let height = contour[index] else { return nil }
        return fit.minY + fit.height * height
    }

    private func rainRegisteredSprite(_ name:String,in box:NSRect,weight:CGFloat,flip:Bool=false) {
        guard weight>0,let image=assets.images[name] else { return }
        let rect=assets.fittedRect(name,in:box)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.translateBy(x:rect.midX,y:rect.midY)
        if flip { NSGraphicsContext.current?.cgContext.scaleBy(x:-1,y:1) }
        image.draw(in:NSRect(x:-rect.width/2,y:-rect.height/2,width:rect.width,height:rect.height),
                   from:.zero,operation:.plusLighter,fraction:weight)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func rainUmbrella(_ sample:RainFlightSample,head:NSPoint,elapsed:Double) -> NSRect {
        let perch=NSPoint(x:head.x+sample.offsetX,y:head.y+sample.offsetY)
        let box=NSRect(x:perch.x-23.5,y:perch.y-1.2,width:47,height:47)
        NSGraphicsContext.saveGraphicsState()
        let context=NSGraphicsContext.current?.cgContext
        context?.translateBy(x:perch.x,y:perch.y)
        context?.rotate(by:sample.bankDegrees * .pi / 180)
        context?.translateBy(x:-perch.x,y:-perch.y)
        context?.setAlpha(CGFloat(sample.opacity))
        context?.beginTransparencyLayer(auxiliaryInfo:nil)
        let flying=CGFloat(sample.flightMix)
        rainRegisteredSprite("weather-umbrella",in:box,weight:1-flying)
        rainRegisteredSprite("weather-umbrella-flight-\(sample.wingFrame)",in:box,
                             weight:flying*CGFloat(1-sample.wingBlend),flip:elapsed<6)
        rainRegisteredSprite("weather-umbrella-flight-\(sample.nextWingFrame)",in:box,
                             weight:flying*CGFloat(sample.wingBlend),flip:elapsed<6)
        context?.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
        return box
    }

    private func drawRainTheatre(elapsed t: Double, animation: Double) {
        let rainAlpha = WeatherInk.ramp(t, 0, 1.0) * (1 - WeatherInk.ramp(t, 25, 2.0))
        weatherCloud(center: NSPoint(x: 194, y: 244), width: 108, alpha: rainAlpha)
        let rise = CGFloat(min(1,max(0,(t-2)/2))*(1-min(1,max(0,(t-27)/2))))
        let poseAlpha = WeatherInk.ramp(t, 4.3, 0.4) * (1 - WeatherInk.ramp(t, 26.3, 0.4))
        let supporting = WeatherInk.ramp(t, 4.7, 1.3) * (1 - WeatherInk.ramp(t, 25.0, 1.3))
        if poseAlpha > 0.001 && poseAlpha < 0.999 { drawRainTransitionBacking() }
        let body=weatherRise(rise,animation:animation,alpha:1-poseAlpha)
        drawRainAnimatedPose(progress:supporting,alpha:poseAlpha)
        if supporting > 0.999 { drawRainBlink(elapsed:t) }
        let belly = restingBellyPoint(animation: animation)
        let head = rainReferencePerch()
        let away = NSPoint(x: 266, y: 221)
        if t < 2 {
            let progress = WeatherInk.ramp(t, 0, 2)
            if progress < 0.04 { weatherStandingBird(at: belly, alpha: 1 - progress / 0.04) }
            weatherFlyingBird(at: WeatherInk.flight(belly, away, progress, lift: 17), elapsed: t,
                              alpha: min(1, progress / 0.04) * (1 - WeatherInk.ramp(t, 1.7, 0.3)))
        } else if t >= 28 {
            let progress = WeatherInk.ramp(t, 28, 2)
            let point = WeatherInk.flight(away, belly, progress, lift: 15)
            weatherFlyingBird(at: point, elapsed: t, alpha: 1 - WeatherInk.ramp(t, 29.75, 0.25), returning: true)
            weatherStandingBird(at: belly, alpha: WeatherInk.ramp(t, 29.75, 0.25))
        }
        let flight=RainFlightMotion.sample(at:t)
        let umbrella=flight.map { rainUmbrella($0,head:head,elapsed:t) }
        guard rainAlpha > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(rainAlpha)
        NSColor.black.setStroke()
        let house = NSRect(x: 140, y: 20, width: 114, height: 104)
        for i in 0..<22 {
            let x = CGFloat(133 + i * 6)
            var surface = weatherSurface(at: x, name: "doghouse", box: house) ?? 20
            if let y = weatherSurface(at: x, name: body, box: restBodyBox(for: body)) { surface = max(surface, y) }
            if let flight,flight.opacity>0.6,let umbrella,let y=weatherSurface(at:x,name:"weather-umbrella",box:umbrella) { surface=max(surface,y) }
            let top: CGFloat = 239
            let distance = max(5, top - surface)
            let cycle = (t * 1.25 + Double(i) * 0.381).truncatingRemainder(dividingBy: 1)
            let y = top - CGFloat(cycle) * distance
            let drop = NSBezierPath(); drop.lineWidth = 0.65; drop.lineCapStyle = .round
            drop.move(to: NSPoint(x: x - 0.6, y: max(surface + 0.3, y - 7)))
            drop.line(to: NSPoint(x: x + 0.6, y: min(top, y + 2))); drop.stroke()
            if cycle > 0.79 {
                let splash = CGFloat((cycle - 0.79) / 0.21)
                let path = NSBezierPath(); path.lineWidth = 0.65; path.lineCapStyle = .round
                path.move(to: NSPoint(x: x - 3 - splash * 2, y: surface + 3 * sin(splash * .pi)))
                path.curve(to: NSPoint(x: x, y: surface + 0.4), controlPoint1: NSPoint(x: x - 2, y: surface + 4), controlPoint2: NSPoint(x: x - 1, y: surface + 0.4))
                path.curve(to: NSPoint(x: x + 3 + splash * 2, y: surface + 3 * sin(splash * .pi)), controlPoint1: NSPoint(x: x + 1, y: surface + 0.4), controlPoint2: NSPoint(x: x + 2, y: surface + 4)); path.stroke()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func sunnyPilotPose(elapsed t: Double, animation: Double, name: String, rotation: CGFloat = 0) -> CGFloat {
        let rise = WeatherInk.ramp(t, 0, 2) * (1 - WeatherInk.ramp(t, 27, 2))
        let costume = WeatherInk.ramp(t, 2, 2) * (1 - WeatherInk.ramp(t, 25, 2))
        _ = weatherRise(rise, animation: animation, alpha: 1 - costume)
        weatherSeated(name, animation: animation, alpha: costume, rotation: rotation)
        return costume
    }

    private func sunnyBird(elapsed t: Double, animation: Double, costumeName: String) {
        let belly = restingBellyPoint(animation: animation)
        let head = weatherHead(costumeName)
        let progress = WeatherInk.ramp(t, 0.1, 2.4) * (1 - WeatherInk.ramp(t, 27.5, 2.5))
        let point = WeatherInk.flight(belly, head, progress, lift: 14)
        if progress < 0.04 { weatherStandingBird(at: belly, alpha: 1 - progress / 0.04) }
        if progress > 0.96 { weatherStandingBird(at: head, alpha: (progress - 0.96) / 0.04) }
        if progress > 0 && progress < 1 {
            let flying = min(1, progress / 0.04) * min(1, (1 - progress) / 0.04)
            weatherFlyingBird(at: point, elapsed: t, alpha: flying, returning: t > 25)
        }
    }

    private func drawSunnyTheatre(elapsed t: Double, animation: Double) {
        drawSunnySun(alpha: WeatherInk.ramp(t, 0, 1) * (1 - WeatherInk.ramp(t, 27, 2)),
                     animation: animation)
        let rise = WeatherInk.ramp(t, 0, 2) * (1 - WeatherInk.ramp(t, 27.5, 2))
        let costume = WeatherInk.ramp(t, 4, 0.75) * (1 - WeatherInk.ramp(t, 25, 1))
        let glassesVisible = WeatherInk.ramp(t, 2.2, 1.0) * (1 - WeatherInk.ramp(t, 27.3, 0.5))
        let glassesAlpha = (1 - costume) * glassesVisible
        if costume <= 0 {
            _ = weatherRise(rise, animation: animation)
        } else if costume >= 1 {
            weatherSeated("weather-sunny", animation: animation)
        } else {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo:nil)
            rainRegisteredSprite("wake-4", in:restBodyBox(for:"wake-4"), weight:1-costume)
            rainRegisteredSprite("weather-sunny", in:restBodyBox(for:"weather-sunny"), weight:costume)
            NSGraphicsContext.current?.cgContext.endTransparencyLayer()
            NSGraphicsContext.restoreGraphicsState()
        }
        drawSunnySunglasses(alpha: glassesAlpha)
        sunnyBird(elapsed: t, animation: animation, costumeName: "weather-sunny")
        let birdAlpha = WeatherInk.ramp(t, 2.6, 0.9) * (1 - WeatherInk.ramp(t, 26, 1.2))
        drawWoodstockSunglasses(at:weatherHead("weather-sunny"), alpha:birdAlpha)
        let breath = CGFloat(sin(animation * .pi / 2)) * 0.35
        var breathingBox = restBodyBox(for:"weather-sunny"); breathingBox.size.height += breath
        let bookCanvas = assets.fittedRect("weather-sunny",in:breathingBox)
        drawSunnyMagazine(in:bookCanvas, elapsed:t, alpha:costume)
    }

    private func drawPilotTheatre(elapsed t: Double, animation: Double) {
        let presence = WeatherInk.ramp(t, 0.2, 1.8) * (1 - WeatherInk.ramp(t, 26, 2))
        weatherCloud(center: NSPoint(x: 161 + CGFloat(sin(t * 0.28)) * 20, y: 223), width: 50, alpha: presence * 0.9)
        weatherCloud(center: NSPoint(x: 241 - CGFloat(sin(t * 0.25)) * 17, y: 202), width: 40, alpha: presence * 0.8)
        let rocking = CGFloat(sin((t - 4) * 1.4)) * 0.8 * WeatherInk.ramp(t, 4, 1) * (1 - WeatherInk.ramp(t, 24, 1))
        let costume = sunnyPilotPose(elapsed: t, animation: animation, name: "weather-pilot", rotation: rocking)
        // The knot stays on the neck; each tail has a different travelling wave.
        let fit = assets.fittedRect("weather-pilot", in: restBodyBox(for: "weather-pilot"))
        let knot = NSPoint(x: fit.minX + fit.width * 0.375, y: fit.minY + fit.height * 0.5967)
        if costume > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setAlpha(costume)
            for tail in 0..<2 {
                let path = NSBezierPath()
                let baseY = knot.y - CGFloat(tail) * 3
                path.move(to: NSPoint(x: knot.x, y: baseY))
                for step in 1...12 {
                    let distance = CGFloat(step) * (tail == 0 ? 2.8 : 2.4)
                    path.line(to: NSPoint(x: knot.x - distance, y: baseY + WeatherInk.scarfOffset(distance, time: t, tail: tail)))
                }
                for step in stride(from: 12, through: 0, by: -1) {
                    let distance = CGFloat(step) * (tail == 0 ? 2.8 : 2.4)
                    path.line(to: NSPoint(x: knot.x - distance, y: baseY - 4 + WeatherInk.scarfOffset(distance, time: t, tail: tail)))
                }
                path.close(); NSColor(calibratedRed: 1, green: 0.75, blue: 0.08, alpha: 1).setFill(); path.fill()
                NSColor.black.setStroke(); path.lineWidth = 0.65; path.lineJoinStyle = .round; path.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        let belly = restingBellyPoint(animation: animation)
        let away = NSPoint(x: 270, y: 223)
        if t < 2.4 {
            let p = WeatherInk.ramp(t, 0, 2.4)
            let flap = WeatherInk.ramp(t, 0, 0.16)
            weatherStandingBird(at: belly, alpha: 1 - flap)
            weatherFlyingBird(at: WeatherInk.flight(belly, away, p, lift: 15), elapsed: t, alpha: flap * (1 - WeatherInk.ramp(t, 1.9, 0.5)))
        } else if t > 27.5 {
            let p = WeatherInk.ramp(t, 27.5, 2.5)
            weatherFlyingBird(at: WeatherInk.flight(away, belly, p, lift: 15), elapsed: t, alpha: 1 - WeatherInk.ramp(t, 29.75, 0.25), returning: true)
            weatherStandingBird(at: belly, alpha: WeatherInk.ramp(t, 29.75, 0.25))
        }
    }

    private func drawSnowTheatre(elapsed t:Double,animation:Double) {
        weatherIdle(animation:animation,bird:false)
        let belly=restingBellyPoint(animation:animation),away=NSPoint(x:267,y:219)
        if t<2.4 {
            let progress=WeatherInk.ramp(t,0,2.4),flap=WeatherInk.ramp(t,0,0.16)
            weatherStandingBird(at:belly,alpha:1-flap)
            weatherFlyingBird(at:WeatherInk.flight(belly,away,progress,lift:14),elapsed:t,
                              alpha:flap*(1-WeatherInk.ramp(t,1.9,0.5)))
        } else if t>=28 {
            let progress=WeatherInk.ramp(t,28,2)
            weatherFlyingBird(at:WeatherInk.flight(away,belly,progress,lift:14),elapsed:t,
                              alpha:1-WeatherInk.ramp(t,29.75,0.25),returning:true)
            weatherStandingBird(at:belly,alpha:WeatherInk.ramp(t,29.75,0.25))
        }
        drawAccumulatingSnow(elapsed:t,animation:animation)
    }

}

func runWeatherRendererTests() throws {
    struct Failure: Error, CustomStringConvertible { let description: String }
    var count = 0
    func check(_ value: @autoclosure () -> Bool, _ label: String) throws {
        guard value() else { throw Failure(description: label) }; count += 1
    }
    try check(WeatherInk.ramp(-1, 0, 1) == 0 && WeatherInk.ramp(2, 0, 1) == 1, "Weather ramps clamp both ends")
    let a = NSPoint(x: 170, y: 150), b = NSPoint(x: 267, y: 220)
    try check(WeatherInk.flight(a, b, 0, lift: 15) == a && WeatherInk.flight(a, b, 1, lift: 15) == b, "Slow bird paths keep exact belly and away endpoints")
    try check(WeatherInk.scarfOffset(0, time: 4, tail: 0) == 0 && WeatherInk.scarfOffset(0, time: 7, tail: 1) == 0, "Both scarf roots remain fixed at the neck")
    try check(abs(WeatherInk.scarfOffset(30, time: 4, tail: 0)) <= 4, "Scarf wave remains small at desktop scale")
    try check(abs(WeatherInk.scarfOffset(30, time: 4, tail: 0) - WeatherInk.scarfOffset(30, time: 4.25, tail: 0)) > 0.1, "Scarf moves through a travelling wave")
    print("PASS: \(count) weather renderer geometry assertions")
}
