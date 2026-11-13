import AppKit

/// Snow starts on each exposed surface together; later the ground banks meet the coated eaves.
enum SnowAccumulationModel {
    static func smooth(_ value:Double) -> Double { let t=min(1,max(0,value));return t*t*(3-2*t) }
    static func amount(at time:Double) -> CGFloat {
        guard time.isFinite else { return 0 }
        let growth=pow(min(1,max(0,(time-0.5)/23.5)),0.85)
        return CGFloat(growth*(1-smooth((time-26)/4)))
    }
    static func snowfall(at time:Double) -> CGFloat {
        guard time>=0,time<26 else { return 0 }
        return CGFloat(smooth(time/0.7)*(1-smooth((time-24)/2)))
    }
    static func interpolate(_ knots:[NSPoint],at x:CGFloat) -> CGFloat? {
        guard let first=knots.first,let last=knots.last,x>=first.x,x<=last.x else { return nil }
        for index in 1..<knots.count where x<=knots[index].x {
            let a=knots[index-1],b=knots[index],u=(x-a.x)/max(0.001,b.x-a.x)
            let p=CGFloat(smooth(Double(u)))
            return a.y+(b.y-a.y)*p
        }
        return last.y
    }
    static func groundKnots(amount g:CGFloat) -> [NSPoint] {
        let spread=12+22*g
        return [NSPoint(x:140-spread,y:16),NSPoint(x:137-spread*0.4,y:19+25*g),
                NSPoint(x:151,y:20+73*pow(g,1.05)),NSPoint(x:184,y:20+61*g),
                NSPoint(x:222,y:20+67*g),NSPoint(x:249,y:20+79*pow(g,0.95)),
                NSPoint(x:258+spread*0.4,y:18+23*g),NSPoint(x:254+spread,y:15)]
    }
    static func groundSurface(at x:CGFloat,amount:CGFloat) -> CGFloat? {
        interpolate(groundKnots(amount:amount),at:x)
    }
    static func roofFront(amount:CGFloat) -> CGFloat { 124-65*pow(amount,0.88) }
    static func roofLeft(at y:CGFloat) -> CGFloat { 140+14*min(1,max(0,(y-64)/60)) }
    static func roofRight(at y:CGFloat) -> CGFloat { 254-14*min(1,max(0,(y-64)/60)) }
    static func roofCoatSurface(at x:CGFloat,amount g:CGFloat) -> CGFloat? {
        guard g>0 else { return nil }
        let front=roofFront(amount:g),left=roofLeft(at:front)-2*g,right=roofRight(at:front)+2*g
        let ridgeLeft=153-3*g,ridgeRight=241+3*g
        guard x>=min(left,ridgeLeft),x<=max(right,ridgeRight) else { return nil }
        func ridge(_ point:CGFloat)->CGFloat {124+2*g+2.2*g*sin((point-151)/92 * .pi)+0.35*g*sin(point*0.31)}
        func lip(_ point:CGFloat)->CGFloat {front-1.3*g+(0.4+2.4*g)*sin(point*0.23)+(0.25+0.8*g)*cos(point*0.53)}
        if x<ridgeLeft {let t=(x-left)/max(0.001,ridgeLeft-left);return lip(left)+(ridge(ridgeLeft)-lip(left))*t}
        if x>ridgeRight {let t=(right-x)/max(0.001,right-ridgeRight);return lip(right)+(ridge(ridgeRight)-lip(right))*t}
        return ridge(x)
    }

}

private enum SnowSceneInk {
    static var upperCache:[String:[CGFloat?]] = [:]
    static func upperContour(_ name:String,assets:PetAssets,whiteOnly:Bool=false) -> [CGFloat?] {
        let key=name+(whiteOnly ? ":white" : ":alpha")
        if let existing=upperCache[key] { return existing }
        guard let image=assets.images[name],let data=image.tiffRepresentation,
              let bitmap=NSBitmapImageRep(data:data),let bytes=bitmap.bitmapData,
              !bitmap.isPlanar,bitmap.hasAlpha,bitmap.bitsPerSample==8 else { return [] }
        let stride=bitmap.samplesPerPixel,alpha=bitmap.bitmapFormat.contains(.alphaFirst) ? 0 : stride-1
        let rgb=bitmap.bitmapFormat.contains(.alphaFirst) ? 1 : 0
        var heights=[CGFloat?](repeating:nil,count:bitmap.pixelsWide)
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh where bytes[y*bitmap.bytesPerRow+x*stride+alpha]>150 {
                let pixel=y*bitmap.bytesPerRow+x*stride
                if whiteOnly && min(bytes[pixel+rgb],bytes[pixel+rgb+1],bytes[pixel+rgb+2])<205 { continue }
                heights[x]=1-CGFloat(y)/CGFloat(bitmap.pixelsHigh);break
            }
        }
        upperCache[key]=heights
        return heights
    }
    static func surface(_ name:String,at x:CGFloat,fit:NSRect,assets:PetAssets,whiteOnly:Bool=false) -> CGFloat? {
        let contour=upperContour(name,assets:assets,whiteOnly:whiteOnly)
        guard !contour.isEmpty,x>=fit.minX,x<=fit.maxX,fit.width>0 else { return nil }
        let index=min(contour.count-1,max(0,Int((x-fit.minX)/fit.width*CGFloat(contour.count))))
        guard let normalized=contour[index] else { return nil }
        return fit.minY+fit.height*normalized
    }
    static func bodyContour(_ name:String,fit:NSRect,roof:CGFloat,assets:PetAssets) -> [NSPoint] {
        var points:[NSPoint]=[]
        var x=fit.minX
        while x<=fit.maxX {
            if let y=surface(name,at:x,fit:fit,assets:assets,whiteOnly:true),y>=roof-1 { points.append(NSPoint(x:x,y:max(roof,y))) }
            x += 0.8
        }
        guard points.count>4 else { return points }
        return points.indices.map { index in
            let a=max(0,index-5),b=min(points.count-1,index+5)
            let mean=points[a...b].reduce(CGFloat(0)){$0+$1.y}/CGFloat(b-a+1)
            return NSPoint(x:points[index].x,y:mean)
        }
    }
    static func ribbon(top:[NSPoint],bottom:[NSPoint]) -> NSBezierPath {
        let path=NSBezierPath();guard let first=top.first else { return path }
        path.move(to:first);for point in top.dropFirst() { path.line(to:point) }
        for point in bottom.reversed() { path.line(to:point) };path.close();return path
    }
    static func samples(from left:CGFloat,to right:CGFloat,step:CGFloat=0.8,value:(CGFloat)->CGFloat) -> [NSPoint] {
        guard right>left else { return [] }
        let count=max(2,Int(ceil((right-left)/step)))
        return (0...count).map { i in let x=left+(right-left)*CGFloat(i)/CGFloat(count);return NSPoint(x:x,y:value(x)) }
    }
}

extension PetRenderer {
    /// The original house and breathing Snoopy are already present underneath this accumulation layer.
    func drawAccumulatingSnow(elapsed time:Double,animation:Double) {
        let g=SnowAccumulationModel.amount(at:time),fall=SnowAccumulationModel.snowfall(at:time)
        let name=PetMotion.sleepSprite(animation),fit=assets.fittedRect(name,in:restBodyBox(for:name))
        let houseFit=assets.fittedRect("doghouse",in:NSRect(x:140,y:20,width:114,height:104))
        let roof=restBodyBox(for:name).minY
        let contour=SnowSceneInk.bodyContour(name,fit:fit,roof:roof,assets:assets)
        var snowShapes:[NSBezierPath]=[]
        var bodyTop:[NSPoint]=[]
        if g>0 {
            // A contour ribbon thickens down over head, belly and toes. Its upper bumps remain distinct.
            if let first=contour.first,let last=contour.last {
                bodyTop=contour.enumerated().map { index,point in
                    let u=CGFloat(index)/CGFloat(max(1,contour.count-1)),edge=pow(max(0,sin(u * .pi)),0.35)
                    return NSPoint(x:point.x+(u-0.5)*g*6,y:point.y+(0.7+8.5*g)*edge)
                }
                let bottom=contour.map { point -> NSPoint in
                    let depth=(point.y-roof+4)*pow(g,0.9)+0.5*g
                    return NSPoint(x:point.x,y:point.y-depth)
                }
                snowShapes.append(SnowSceneInk.ribbon(top:bodyTop,bottom:bottom))
                // Small rounded shoulders join this frosting to the roof rather than drawing an ear capsule.
                if g>0.45 {
                    let blend=(g-0.45)/0.55
                    let shoulder=SnowSceneInk.samples(from:first.x-2*g,to:last.x+2*g) { x in
                        let edge=sin((x-(first.x-2*g))/max(1,last.x-first.x+4*g) * .pi)
                        return roof+3+5*blend*max(0,edge)
                    }
                    snowShapes.append(SnowSceneInk.ribbon(top:shoulder,bottom:shoulder.map{NSPoint(x:$0.x,y:roof-5*blend)}))
                }
            }
            // A rounded coat proceeds down the sloping roof face; it follows the original trapezoid.
            let front=SnowAccumulationModel.roofFront(amount:g)
            let top=SnowSceneInk.samples(from:153-3*g,to:241+3*g) { x in
                124+2*g+2.2*g*sin((x-151)/92 * .pi)+0.35*g*sin(x*0.31)
            }
            let low=SnowSceneInk.samples(from:SnowAccumulationModel.roofLeft(at:front)-2*g,
                                         to:SnowAccumulationModel.roofRight(at:front)+2*g) { x in
                front-1.3*g+(0.4+2.4*g)*sin(x*0.23)+(0.25+0.8*g)*cos(x*0.53)
            }
            snowShapes.append(SnowSceneInk.ribbon(top:top,bottom:low))
            // Snow catches on every exposed shingle ledge from the start, before the main coat reaches it.
            for y in [CGFloat(104),85,65] {
                let left=SnowAccumulationModel.roofLeft(at:y),right=SnowAccumulationModel.roofRight(at:y)
                let ledge=SnowSceneInk.samples(from:left-0.5*g,to:right+0.5*g) { x in
                    y+0.3+3.7*g+0.55*g*sin(x*0.26)
                }
                snowShapes.append(SnowSceneInk.ribbon(top:ledge,bottom:ledge.map{NSPoint(x:$0.x,y:y-0.35*g)}))
            }
            // Both sides and the front accumulate from ground level, gradually burying the lower walls.
            let groundKnots=SnowAccumulationModel.groundKnots(amount:g)
            let ground=SnowSceneInk.samples(from:groundKnots[0].x,to:groundKnots.last!.x) { x in
                SnowAccumulationModel.interpolate(groundKnots,at:x) ?? 15
            }
            snowShapes.append(SnowSceneInk.ribbon(top:ground,bottom:[NSPoint(x:ground[0].x,y:13),NSPoint(x:ground.last!.x,y:13)]))

            NSGraphicsContext.saveGraphicsState()
            let alpha=min(1,g*28)
            NSColor.black.withAlphaComponent(alpha).setStroke()
            // Stroke all edges first; subsequent white union fills erase seams where the deposits meet.
            for shape in snowShapes { shape.lineWidth=1.6;shape.lineJoinStyle = .round;shape.stroke() }
            NSColor.white.withAlphaComponent(alpha).setFill();for shape in snowShapes { shape.fill() }
            // A few short open ink marks describe the snow surface without cutting the merged mass.
            if g>0.18 {
                NSColor.black.withAlphaComponent(min(0.65,g)).setStroke()
                for (x,y,length) in [(CGFloat(147),CGFloat(29),CGFloat(8)),(181,24,11),(235,31,8),(168,109,6),(222,90,7)] {
                    let path=NSBezierPath();path.lineWidth=0.6;path.lineCapStyle = .round
                    let offset=length*g;path.move(to:NSPoint(x:x,y:y+16*g))
                    path.curve(to:NSPoint(x:x+offset,y:y+16*g+0.3),controlPoint1:NSPoint(x:x+offset*0.3,y:y+16*g-0.5),controlPoint2:NSPoint(x:x+offset*0.7,y:y+16*g+0.6));path.stroke()
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        guard fall>0 else { return }
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current?.cgContext.setAlpha(fall)
        for index in 0..<66 {
            let seed=Double(index)
            let x=CGFloat(119+(index*43)%160)+CGFloat(sin(time*0.48+seed*1.7))*2.8
            var surface=SnowAccumulationModel.groundSurface(at:x,amount:g) ?? 14
            if let y=SnowSceneInk.surface("doghouse",at:x,fit:houseFit,assets:assets) { surface=max(surface,y) }
            if let y=SnowSceneInk.surface(name,at:x,fit:fit,assets:assets) { surface=max(surface,y) }
            if g>0,let y=SnowAccumulationModel.interpolate(bodyTop,at:x) { surface=max(surface,y) }
            if let coat=SnowAccumulationModel.roofCoatSurface(at:x,amount:g) {surface=max(surface,coat)}
            if g>0 {
                for ledge in [CGFloat(104),85,65] where x>=SnowAccumulationModel.roofLeft(at:ledge)-0.5*g && x<=SnowAccumulationModel.roofRight(at:ledge)+0.5*g {
                    surface=max(surface,ledge+0.3+3.7*g+0.55*g*sin(x*0.26))
                }
            }
            let distance=max(4,247-surface-1.5)
            let travel=(time*(30+Double(index%5)*2)+seed*29.37).truncatingRemainder(dividingBy:Double(distance))
            let y=247-CGFloat(travel)
            let radius:CGFloat=index%4==0 ? 1.25 : 0.85
            let flake=NSBezierPath(ovalIn:NSRect(x:x-radius,y:y-radius,width:radius*2,height:radius*2))
            NSColor.white.setFill();flake.fill();NSColor.black.setStroke();flake.lineWidth=0.38;flake.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

func runSnowSceneTests() throws {
    struct Failure:Error,CustomStringConvertible { let description:String }
    var count=0
    func check(_ value:Bool,_ label:String) throws { guard value else { throw Failure(description:label) };count += 1 }
    try check(SnowAccumulationModel.amount(at:0)==0 && SnowAccumulationModel.amount(at:0.5)==0,"Entry begins with the original uncoated scene")
    let early=SnowAccumulationModel.amount(at:1)
    try check(early>0.03 && SnowAccumulationModel.groundSurface(at:184,amount:early)!>22,"Ground accumulation is visibly present in the first second")
    var prior:CGFloat=0
    for t in [1.0,3,6,12,18,24] {
        let g=SnowAccumulationModel.amount(at:t)
        try check(g>=prior,"Growth is monotonic until snowfall finishes");prior=g
        let ground=SnowAccumulationModel.groundSurface(at:184,amount:g)!
        try check(ground>20 && SnowAccumulationModel.roofFront(amount:g)<124,"Floor and roof accumulate together, not in separate late phases")
    }
    let heavy=SnowAccumulationModel.amount(at:24)
    try check(heavy==1 && SnowAccumulationModel.roofFront(amount:heavy)<64,"Heavy snow coats the complete roof face down past its eaves")
    for x in [CGFloat(151),184,222,249] {
        try check(SnowAccumulationModel.groundSurface(at:x,amount:heavy)!>SnowAccumulationModel.roofFront(amount:heavy),"Late ground banks overlap the roof coat with no exposed wall gap")
    }
    let knots=SnowAccumulationModel.groundKnots(amount:heavy)
    try check(knots.first!.x>=106 && knots.last!.x<=290,"Ground snow stays a compact local bank around the doghouse")
    try check(SnowAccumulationModel.amount(at:26)==1 && SnowAccumulationModel.amount(at:28)>0 && SnowAccumulationModel.amount(at:28)<1 && SnowAccumulationModel.amount(at:30)==0,"Snow clears continuously within the existing thirty-second story")
    try check(SnowAccumulationModel.snowfall(at:0)==0 && SnowAccumulationModel.snowfall(at:24)==1 && SnowAccumulationModel.snowfall(at:26)==0,"Flakes stop before the snow cover clears")
    try check(SnowAccumulationModel.roofCoatSurface(at:196,amount:1)!>124,"Snowflakes stop on the deep ridge coat")
    try check(SnowAccumulationModel.roofCoatSurface(at:142,amount:1)!>64,"Flakes also hit the rounded side overhang rather than crossing through it")
    try check(SnowAccumulationModel.roofCoatSurface(at:110,amount:1)==nil,"Roof collision does not invent a floating platform outside its coat")
    print("PASS: \(count) simultaneous ground, roof, body snow and connected-drift assertions")
}
