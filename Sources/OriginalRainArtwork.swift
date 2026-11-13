import AppKit

/// Decode the original Peanuts-like poses before the first rain performance.
/// The character art is the exact wake-1…wake-4 PNG sequence introduced in v12.
private enum OriginalRainInk {
    static func upperContour(_ bitmap:NSBitmapImageRep)->[CGFloat?]? {
        guard let bytes=bitmap.bitmapData,!bitmap.isPlanar,bitmap.bitsPerSample==8,
              bitmap.hasAlpha,bitmap.pixelsWide>0,bitmap.pixelsHigh>0 else{return nil}
        let stride=bitmap.samplesPerPixel
        let alpha=bitmap.bitmapFormat.contains(.alphaFirst) ? 0:stride-1
        var contour=[CGFloat?](repeating:nil,count:bitmap.pixelsWide)
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh where bytes[y*bitmap.bytesPerRow+x*stride+alpha]>153 {
                contour[x]=1-CGFloat(y)/CGFloat(bitmap.pixelsHigh);break
            }
        }
        return contour
    }
}

extension PetAssets {
    func prepareOriginalRainArtwork() throws {
        let names=["doghouse","woodstock","weather-umbrella","weather-sunny","weather-rain-reference","weather-rain-neutral"] +
            (1...4).map{"wake-\($0)"} +
            (1...4).map{"weather-umbrella-flight-\($0)"} +
            (1...4).map{"woodstock-flight-\($0)"} +
            (1...32).map{String(format:"breath-%02d",$0)}
        let collision=Set(["doghouse","weather-umbrella"] +
            (1...4).map{"wake-\($0)"} + (1...32).map{String(format:"breath-%02d",$0)})
        for name in names {
            guard let image=images[name],let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil) else {
                throw NSError(domain:"OriginalRainArtwork",code:1,userInfo:[NSLocalizedDescriptionKey:"Missing original sprite "+name])
            }
            // Woodstock's five umbrella drawings have a costly first PNG draw.
            // Copy them into plain bitmaps before any rain animation starts.
            let prepared:CGImage
            if (name.hasPrefix("weather-umbrella") || name == "weather-rain-reference" || name == "weather-rain-neutral"),
               let copy=CGContext(data:nil,width:cg.width,height:cg.height,bitsPerComponent:8,
                   bytesPerRow:cg.width*4,space:CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) {
                copy.draw(cg,in:CGRect(x:0,y:0,width:cg.width,height:cg.height))
                prepared=copy.makeImage() ?? cg
            } else {prepared=cg}
            let bitmap=NSBitmapImageRep(cgImage:prepared)
            _=bitmap.bitmapData
            if collision.contains(name) {
                guard let contour=OriginalRainInk.upperContour(bitmap) else {
                    throw NSError(domain:"OriginalRainArtwork",code:2,userInfo:[NSLocalizedDescriptionKey:"Cannot inspect rain outline "+name])
                }
                rainUpperContours[name]=contour
            }
            if let decoded=bitmap.cgImage {images[name]=NSImage(cgImage:decoded,size:image.size)}
        }
    }
}

func runOriginalRainArtworkTests() throws {
    struct Failure:Error,CustomStringConvertible {let description:String}
    var count=0
    func check(_ value:Bool,_ label:String) throws {guard value else {throw Failure(description:label)};count += 1}
    let assets=PetAssets()
    for name in (1...4).map({"wake-\($0)"}) {
        try check(assets.images[name] != nil,"Original Snoopy wake pose must load: "+name)
        try check(assets.rainUpperContours[name]?.count == 600,"Original rain body contour must be ready: "+name)
    }
    for name in ["weather-umbrella"] {
        try check(assets.images[name] != nil,"The original pose or single-bird umbrella must load: "+name)
        try check(assets.rainUpperContours[name] != nil,"Rain collision must use the visible original art: "+name)
    }
    for index in 1...4 {
        try check(assets.images["weather-umbrella-flight-\(index)"] != nil,"One Woodstock flies with the whole umbrella in every wing pose")
    }
    guard let cg=assets.images["weather-umbrella"]?.cgImage(forProposedRect:nil,context:nil,hints:nil) else {
        throw Failure(description:"Single Woodstock umbrella missing")
    }
    let image=NSBitmapImageRep(cgImage:cg)
    var yellow=0
    for y in stride(from:250,to:min(image.pixelsHigh,540),by:4) {
        for x in stride(from:80,to:min(image.pixelsWide,470),by:4) {
            if let c=image.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),c.alphaComponent>0.7,
               c.redComponent>0.65,c.greenComponent>0.58,c.blueComponent<0.35 {yellow += 1}
        }
    }
    try check(yellow>300,"The umbrella image visibly contains its yellow Woodstock")
    print("PASS: \(count) restored Snoopy poses and visible single-Woodstock umbrella checks")
}
