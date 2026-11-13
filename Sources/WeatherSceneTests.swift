import AppKit

/// Pixel contracts protect the established sleeping artwork at both ends of every vignette.
func runWeatherSceneTests() throws {
    struct Failure: Error, CustomStringConvertible { let description: String }
    let assets=PetAssets(), renderer=PetRenderer(assets:assets)
    func png(phase:PetPhase, presentation:WeatherPresentation?) throws -> Data {
        renderer.weatherPresentation=presentation
        let cache=try CachedScene.render(renderer:renderer,phase:phase,elapsed:presentation?.elapsed ?? 0,animation:101.375,scale:0.72,retina:2)
        guard let data=cache.bitmap.representation(using:.png,properties:[:]) else { throw Failure(description:"Cannot encode scene") }
        return data
    }
    let idle=try png(phase:.idle,presentation:nil)
    var count=0
    for kind in WeatherKind.allCases {
        for elapsed in [0.0,WeatherMotion.duration(for:kind)] {
            let frame=try png(phase:.weather,presentation:WeatherPresentation(kind:kind,elapsed:elapsed,exitProgress:nil))
            guard frame == idle else { throw Failure(description:"\(kind.rawValue) at\(elapsed)s must join the exact established idle artwork") };count += 1
        }
        let middle=WeatherMotion.coreHoldStart(for:kind)+5
        let active=try png(phase:.weather,presentation:WeatherPresentation(kind:kind,elapsed:middle,exitProgress:nil))
        guard active != idle else { throw Failure(description:"\(kind.rawValue) must visibly affect the character scene") };count += 1
        let exit=try png(phase:.weather,presentation:WeatherPresentation(kind:kind,elapsed:middle,exitProgress:1))
        guard exit == idle else { throw Failure(description:"\(kind.rawValue) interruption must clear all costume and effect pixels") };count += 1
    }
    // Measure the rendered shapes: the hand-drawn cloud is not a rectangular collision box.
    for elapsed in [5.0,5.5,6.0,20.0,26.0] {
        renderer.weatherPresentation=WeatherPresentation(kind:.rain,elapsed:elapsed,exitProgress:nil)
        let scene=try CachedScene.render(renderer:renderer,phase:.weather,elapsed:elapsed,animation:100+elapsed,scale:0.72,retina:2)
        let bitmap=scene.bitmap
        var cloudBottom = -1,canopyTop=bitmap.pixelsHigh
        for y in 0..<min(100,bitmap.pixelsHigh) {
            for x in 0..<bitmap.pixelsWide {
                guard let color=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),color.alphaComponent>0.1 else { continue }
                let r=color.redComponent*255,g=color.greenComponent*255,b=color.blueComponent*255
                if y<40 && min(r,g,b)>220 { cloudBottom=max(cloudBottom,y) }
                if r>160 && g>60 && g<210 && b<80 { canopyTop=min(canopyTop,y) }
            }
        }
        guard cloudBottom>=0,canopyTop<bitmap.pixelsHigh,Double(canopyTop-cloudBottom-2)/1.44>=6 else {
            throw Failure(description:"Rendered cloud and canopy must stay visibly separated at\(elapsed)s (rows\(cloudBottom),\(canopyTop))")
        };count += 1
    }
    for kind in WeatherKind.allCases {
        guard WeatherMotion.duration(for:kind) == 30 else { throw Failure(description:"Each complete weather story must last thirty seconds") };count += 1
    }
    guard WeatherMotion.renderingFPS == 64 else { throw Failure(description:"Weather interpolation must run at64fps without changing seconds") };count += 1
    print("PASS: \(count) weather entry, ending, visible-effect and interruption pixel contracts")
}
