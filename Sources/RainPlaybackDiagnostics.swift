import AppKit

/// One cold pass, before the exporter's crop-union pass can warm any render caches.
func benchmarkWeatherPlayback(kind:WeatherKind,directory:String) throws {
    let assets=PetAssets()
    guard assets.missing.isEmpty else {throw NSError(domain:"RainBenchmark",code:1,userInfo:[NSLocalizedDescriptionKey:assets.missing.joined(separator:", ")])}
    let renderer=PetRenderer(assets:assets)
    var samples:[Double]=[]
    for frame in 0..<1920 {
        try autoreleasepool {
            let time=Double(frame)/64
            renderer.weatherPresentation=WeatherPresentation(kind:kind,elapsed:time,exitProgress:nil)
            let start=ProcessInfo.processInfo.systemUptime
            _=try CachedScene.render(renderer:renderer,phase:.weather,elapsed:time,animation:100+time,scale:0.72,retina:2)
            samples.append((ProcessInfo.processInfo.systemUptime-start)*1000)
        }
    }
    let sorted=samples.sorted()
    func percentile(_ fraction:Double)->Double {sorted[min(sorted.count-1,Int(Double(sorted.count-1)*fraction))]}
    let report:[String:Any]=["kind":kind.rawValue,"frameCount":samples.count,"passes":1,"cold":true,
        "fpsBudgetMilliseconds":1000.0/64,"p50Milliseconds":percentile(0.5),
        "p95Milliseconds":percentile(0.95),"p99Milliseconds":percentile(0.99),
        "maximumMilliseconds":sorted.last ?? 0,"overBudgetFrames":samples.filter{$0>1000/64}.count,
        "firstFrameMilliseconds":samples[0],"precomputedRainContours":assets.rainUpperContours.count,
        "frameMilliseconds":samples]
    try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:directory+"/cold-frame-timing.json"))
    print("\(kind.rawValue) cold pass:1920frames, p95=\(percentile(0.95))ms, p99=\(percentile(0.99))ms, max=\(sorted.last ?? 0)ms")
}

func benchmarkRainPlayback(directory:String) throws {try benchmarkWeatherPlayback(kind:.rain,directory:directory)}
