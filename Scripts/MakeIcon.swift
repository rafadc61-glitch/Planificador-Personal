import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

func path(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius) }
func fill(_ rect: NSRect, _ radius: CGFloat, _ color: NSColor) { color.setFill(); path(rect, radius).fill() }
func stroke(_ rect: NSRect, _ radius: CGFloat, _ color: NSColor, _ width: CGFloat) {
    let shape = path(rect, radius); shape.lineWidth = width; color.setStroke(); shape.stroke()
}

let outer = path(NSRect(x: 18, y: 18, width: 988, height: 988), 222)
NSGradient(starting: NSColor(red: 0.11, green: 0.17, blue: 0.31, alpha: 1),
           ending: NSColor(red: 0.035, green: 0.065, blue: 0.13, alpha: 1))!
    .draw(in: outer, angle: -45)
stroke(NSRect(x: 19, y: 19, width: 986, height: 986), 221, NSColor.white.withAlphaComponent(0.13), 4)

// Quiet halo behind the planner card.
NSColor(red: 0.48, green: 0.43, blue: 0.82, alpha: 0.18).setFill()
NSBezierPath(ovalIn: NSRect(x: 365, y: 175, width: 560, height: 560)).fill()
NSColor(red: 0.35, green: 0.78, blue: 0.73, alpha: 0.12).setFill()
NSBezierPath(ovalIn: NSRect(x: 115, y: 465, width: 480, height: 480)).fill()

let shadow = NSShadow()
shadow.shadowColor = .black.withAlphaComponent(0.33)
shadow.shadowBlurRadius = 55
shadow.shadowOffset = NSSize(width: 0, height: -28)
shadow.set()
fill(NSRect(x: 205, y: 182, width: 615, height: 650), 104,
     NSColor(red: 0.92, green: 0.94, blue: 0.98, alpha: 1))
NSShadow().set()

// Binding rail and top fold.
fill(NSRect(x: 205, y: 660, width: 615, height: 172), 104,
     NSColor(red: 0.75, green: 0.66, blue: 1, alpha: 1))
fill(NSRect(x: 205, y: 640, width: 615, height: 88), 0,
     NSColor(red: 0.75, green: 0.66, blue: 1, alpha: 1))
for x in [337.0, 687.0] {
    fill(NSRect(x: x - 23, y: 763, width: 46, height: 115), 22,
         NSColor(red: 0.29, green: 0.36, blue: 0.57, alpha: 1))
    fill(NSRect(x: x - 14, y: 772, width: 28, height: 94), 14,
         NSColor(red: 0.95, green: 0.96, blue: 1, alpha: 1))
}

// Three visual priorities: one completed, one active, one upcoming.
let navy = NSColor(red: 0.16, green: 0.22, blue: 0.37, alpha: 1)
let muted = NSColor(red: 0.60, green: 0.65, blue: 0.75, alpha: 1)
for (y, color) in [(560.0, NSColor(red: 0.48, green: 0.79, blue: 0.71, alpha: 1)),
                   (440.0, NSColor(red: 0.75, green: 0.66, blue: 1, alpha: 1)),
                   (320.0, NSColor(red: 0.79, green: 0.83, blue: 0.89, alpha: 1))] {
    fill(NSRect(x: 275, y: y, width: 65, height: 65), 22, color)
}
let check = NSBezierPath()
check.move(to: NSPoint(x: 291, y: 591)); check.line(to: NSPoint(x: 305, y: 576)); check.line(to: NSPoint(x: 326, y: 607))
check.lineWidth = 10; check.lineCapStyle = .round; check.lineJoinStyle = .round
NSColor.white.setStroke(); check.stroke()

for (y, width, color) in [(575.0, 300.0, navy), (455.0, 390.0, navy), (335.0, 245.0, muted)] {
    fill(NSRect(x: 378, y: y, width: width, height: 24), 12, color)
    fill(NSRect(x: 378, y: y - 37, width: width * 0.58, height: 14), 7, muted.withAlphaComponent(0.52))
}

// A small glint adds depth without becoming noisy at 32 px.
let glint = NSBezierPath()
glint.move(to: NSPoint(x: 768, y: 545)); glint.line(to: NSPoint(x: 768, y: 600))
glint.move(to: NSPoint(x: 740, y: 572)); glint.line(to: NSPoint(x: 796, y: 572))
glint.lineWidth = 8; glint.lineCapStyle = .round
NSColor(red: 0.79, green: 0.70, blue: 1, alpha: 0.85).setStroke(); glint.stroke()

NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Assets/AppIcon.png"
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
