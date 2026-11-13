import AppKit

/// Check what actually reaches the window, including the unchanged original sprites.
func runWeatherGestureTests() throws {
    struct Failure:Error,CustomStringConvertible {let description:String}
    var count=0
    func check(_ condition:Bool,_ label:String) throws {guard condition else {throw Failure(description:label)};count += 1}
    let assets=PetAssets(),renderer=PetRenderer(assets:assets)
    func point(_ name:String,_ x:CGFloat,_ y:CGFloat)->NSPoint {
        let fit=assets.fittedRect(name,in:renderer.restBodyBox(for:name))
        return NSPoint(x:fit.minX+fit.width*x/600,y:fit.maxY-fit.height*y/600)
    }
    func color(_ kind:WeatherKind,_ elapsed:Double,_ position:NSPoint) throws ->NSColor {
        renderer.weatherPresentation=WeatherPresentation(kind:kind,elapsed:elapsed,exitProgress:nil)
        let frame=try CachedScene.render(renderer:renderer,phase:.weather,elapsed:elapsed,animation:100+elapsed,scale:0.72,retina:2)
        let ratio:CGFloat=0.72*2
        let x=Int(position.x*ratio),y=frame.bitmap.pixelsHigh-1-Int(position.y*ratio)
        guard x>=0,y>=0,x<frame.bitmap.pixelsWide,y<frame.bitmap.pixelsHigh,
              let c=frame.bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) else {
            throw Failure(description:"Cannot sample rendered gesture at \(position)")
        }
        return c
    }
    let rainEye=point("wake-4",295,125)
    let openEye=try color(.rain,7.35,rainEye),blink=try color(.rain,7.6,rainEye)
    try check(openEye.redComponent<0.4 && blink.redComponent>0.78,"The selected rain pose's eye must close and reopen")
    let originalFinger=point("wake-4",335,320)
    let fingerBefore=try color(.rain,3.9,originalFinger)
    let fingerRaised=try color(.rain,7.0,originalFinger)
    try check(fingerBefore.redComponent<0.4 &&
              (fingerRaised.alphaComponent<0.25 || fingerRaised.redComponent>0.70),
              "The original curled paw leaves the chest when that same paw is raised")
    let lens=point("wake-4",270,125)
    let before=try color(.sunny,2.15,lens),placing=try color(.sunny,3.9,lens),reading=try color(.sunny,6.0,lens)
    try check(before.redComponent>0.72 && placing.redComponent<0.30,"Snoopy's sunglasses move onto a formerly bare original face")
    try check(reading.redComponent<0.30,"The final magazine pose keeps Snoopy's sunglasses")
    let sunnyOldFinger=point("wake-4",335,320)
    let sunnyFingerBefore=try color(.sunny,2.5,sunnyOldFinger)
    let sunnyFingerDuring=try color(.sunny,3.7,sunnyOldFinger)
    try check(sunnyFingerBefore.alphaComponent>0.9 && sunnyFingerBefore.redComponent<0.4 &&
              sunnyFingerDuring.alphaComponent>0.9 && sunnyFingerDuring.redComponent<0.4,
              "The original chest paw stays in place while glasses appear on their own")
    let sun=try color(.sunny,8.0,NSPoint(x:237,y:222))
    try check(sun.alphaComponent>0.9 && sun.redComponent>0.85 &&
              sun.greenComponent>0.65 && sun.blueComponent<0.35,
              "The sunny theatre shows a yellow sun in the sky")
    let torso=point("wake-4",260,390)
    let handoff=try color(.sunny,4.5,torso)
    try check(handoff.alphaComponent>0.96 && handoff.redComponent>0.78,
              "Snoopy remains opaque while the original pose hands off to the reading sprite")
    let blackHandoff=try color(.sunny,4.5,lens)
    try check(blackHandoff.redComponent<0.30,
              "The sunglasses stay black during the magazine-pose handoff")
    let birdHead=assets.headPoint("weather-sunny",in:renderer.restBodyBox(for:"weather-sunny"))
    let birdFit=assets.fittedRect("woodstock",in:NSRect(x:birdHead.x-10,y:birdHead.y-1.2,width:20,height:21))
    let birdEye=NSPoint(x:birdFit.minX+birdFit.width*0.57+3.2,
                        y:birdFit.maxY-birdFit.height*0.44)
    let bareBird=try color(.sunny,2.4,birdEye),shadedBird=try color(.sunny,6.0,birdEye)
    try check(bareBird.greenComponent>0.48 && shadedBird.redComponent<0.33,
              "Woodstock must gain his own visible sunglasses after landing")
    print("PASS: \(count) rendered rain-blink and two-character sunny-sunglasses assertions")
}
