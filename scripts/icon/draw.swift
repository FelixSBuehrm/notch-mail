// Draws the app icon: the notch opened into a new-mail alert, on the Notch Mail gradient.
// Used by scripts/icon/make.sh. Usage: draw <size-px> <out.png>
import AppKit

let size = CGFloat(Double(CommandLine.arguments[1])!)
let out = CommandLine.arguments[2]
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let s = size / 1024  // design units: 1024 canvas, macOS icon grid

// Squircle body with a soft shadow.
let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24 * s
shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
shadow.set()
NSColor.black.setFill()
squircle.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
squircle.addClip()
NSGradient(colors: [NSColor(red: 0.16, green: 0.17, blue: 0.46, alpha: 1), NSColor(red: 0.42, green: 0.24, blue: 0.60, alpha: 1),
                    NSColor(red: 0.86, green: 0.42, blue: 0.45, alpha: 1)])!.draw(in: body, angle: -70)
// A glow under the notch.
let glowCenter = NSPoint(x: 512 * s, y: 520 * s)
NSGradient(colors: [NSColor(white: 1, alpha: 0.22), NSColor(white: 1, alpha: 0)])!
    .draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: 360 * s, options: [])

// The notch, opened into a small alert: a sender bubble and two lines of text,
// exactly what the app shows when mail arrives.
let top = body.maxY
let panelWidth = 600 * s, panelBottom = top - 360 * s, radius = 92 * s, flare = 34 * s
let left = 512 * s - panelWidth / 2, right = 512 * s + panelWidth / 2
let panel = NSBezierPath()
panel.move(to: NSPoint(x: left - flare, y: top))
panel.curve(to: NSPoint(x: left, y: top - flare), controlPoint1: NSPoint(x: left - flare * 0.25, y: top), controlPoint2: NSPoint(x: left, y: top - flare * 0.25))
panel.line(to: NSPoint(x: left, y: panelBottom + radius))
panel.curve(to: NSPoint(x: left + radius, y: panelBottom), controlPoint1: NSPoint(x: left, y: panelBottom + radius * 0.45), controlPoint2: NSPoint(x: left + radius * 0.45, y: panelBottom))
panel.line(to: NSPoint(x: right - radius, y: panelBottom))
panel.curve(to: NSPoint(x: right, y: panelBottom + radius), controlPoint1: NSPoint(x: right - radius * 0.45, y: panelBottom), controlPoint2: NSPoint(x: right, y: panelBottom + radius * 0.45))
panel.line(to: NSPoint(x: right, y: top - flare))
panel.curve(to: NSPoint(x: right + flare, y: top), controlPoint1: NSPoint(x: right, y: top - flare * 0.25), controlPoint2: NSPoint(x: right + flare * 0.25, y: top))
panel.close()
NSGraphicsContext.saveGraphicsState()
let panelShadow = NSShadow()
panelShadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
panelShadow.shadowBlurRadius = 40 * s
panelShadow.shadowOffset = NSSize(width: 0, height: -16 * s)
panelShadow.set()
NSColor.black.setFill()
panel.fill()
NSGraphicsContext.restoreGraphicsState()

// Sender bubble.
let bubble = NSRect(x: left + 70 * s, y: panelBottom + 80 * s, width: 128 * s, height: 128 * s)
NSGradient(colors: [NSColor(red: 1.0, green: 0.62, blue: 0.42, alpha: 1), NSColor(red: 0.90, green: 0.36, blue: 0.42, alpha: 1)])!
    .draw(in: NSBezierPath(ovalIn: bubble), angle: -60)
// Subject and preview lines.
let textX = bubble.maxX + 44 * s
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: textX, y: bubble.midY + 14 * s, width: right - 70 * s - textX, height: 40 * s), xRadius: 20 * s, yRadius: 20 * s).fill()
NSColor(white: 1, alpha: 0.42).setFill()
NSBezierPath(roundedRect: NSRect(x: textX, y: bubble.midY - 50 * s, width: (right - 70 * s - textX) * 0.72, height: 32 * s), xRadius: 16 * s, yRadius: 16 * s).fill()

NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
