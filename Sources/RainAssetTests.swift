import AppKit

func runRainAssetTests() throws {
    struct Failure:Error,CustomStringConvertible { let description:String }
    let assets=PetAssets();var count=0
    func require(_ value:Bool,_ message:String) throws { guard value else { throw Failure(description:message) };count += 1 }
    let standing=assets.metrics["weather-umbrella"]?.bottomInset
    var wingImages=Set<Data>()
    for index in 1...4 {
        let name="weather-umbrella-flight-\(index)"
        try require(assets.images[name] != nil,"Each powered-flight feather pose must be installed")
        try require(assets.metrics[name]?.bottomInset == standing,"Tucked feet must not shift the canopy registration")
        if let data=assets.images[name]?.tiffRepresentation { wingImages.insert(data) }
    }
    try require(wingImages.count == 4,"Four wing strokes must contain genuinely distinct artwork")
    let renderer=PetRenderer(assets:assets)
    let head=renderer.rainReferencePerch()
    for elapsed in [4.4,4.9,5.1,5.4,5.8] {
        renderer.weatherPresentation=WeatherPresentation(kind:.rain,elapsed:elapsed,exitProgress:nil)
        let scene=try CachedScene.render(renderer:renderer,phase:.weather,elapsed:elapsed,animation:100+elapsed,scale:0.72,retina:2)
        func opacity(_ point:NSPoint) -> CGFloat {
            let x=Int(point.x*1.44), y=scene.bitmap.pixelsHigh-1-Int(point.y*1.44)
            return scene.bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0
        }
        let body=assets.fittedRect("wake-4",in:renderer.restBodyBox(for:"wake-4"))
        let foot=NSPoint(x:body.minX+body.width*310/600,y:body.maxY-body.height*410/600)
        try require(opacity(foot)>0.98,"The original Snoopy sitting pose must stay opaque as Woodstock returns")
        let sample=RainFlightMotion.sample(at:elapsed)!
        let perch=NSPoint(x:head.x+sample.offsetX,y:head.y+sample.offsetY)
        let fit=assets.fittedRect("weather-umbrella",in:NSRect(x:perch.x-23.5,y:perch.y-1.2,width:47,height:47))
        let p=NSPoint(x:fit.minX+fit.width/2,y:fit.maxY-fit.height*160/600)
        let angle=sample.bankDegrees * .pi / 180,dx=p.x-perch.x,dy=p.y-perch.y
        let center=NSPoint(x:perch.x+cos(angle)*dx-sin(angle)*dy,y:perch.y+sin(angle)*dx+cos(angle)*dy)
        try require(opacity(center)>0.98,"Interpolated wing poses must keep the shared umbrella canopy opaque")
    }
    print("PASS: \(count) rain artwork and canopy-registration assertions")
}
