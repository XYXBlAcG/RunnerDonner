import AppKit
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
NSGradient(starting: NSColor(calibratedRed: 0.04, green: 0.25, blue: 0.62, alpha: 1), ending: NSColor(calibratedRed: 0.02, green: 0.68, blue: 0.66, alpha: 1))!.draw(in: background, angle: 50)
let stadium = NSBezierPath(roundedRect: NSRect(x: 226, y: 226, width: 572, height: 572), xRadius: 245, yRadius: 245)
NSColor.white.withAlphaComponent(0.95).setStroke(); stadium.lineWidth=42; stadium.stroke()
let lane = NSBezierPath(roundedRect: NSRect(x: 284, y: 284, width: 456, height: 456), xRadius: 190, yRadius: 190)
NSColor.white.withAlphaComponent(0.45).setStroke(); lane.lineWidth=8
let dash: [CGFloat] = [14,20]; lane.setLineDash(dash, count: 2, phase: 0); lane.stroke()
let arrow = NSBezierPath(); arrow.move(to:NSPoint(x:458,y:390));arrow.line(to:NSPoint(x:458,y:634));arrow.line(to:NSPoint(x:644,y:512));arrow.close()
NSColor.white.setFill();arrow.fill()
let marker = NSBezierPath(ovalIn:NSRect(x:698,y:466,width:112,height:112));NSColor(calibratedRed:1,green:0.74,blue:0.21,alpha:1).setFill();marker.fill()
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
