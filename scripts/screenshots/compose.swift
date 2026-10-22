// Used by scripts/screenshots/make.sh and record.sh.
import AppKit
// compose <notch.png> <out.png> [extra-bottom-pt] [width-pt] [height-pt]   notch capture on a made-up desktop
// compose --background <width-pt> <height-pt> <out.png>   the desktop alone (for recordings)
let args = CommandLine.arguments
let backgroundOnly = args[1] == "--background"
var notch: NSImage?
var px = (w: 0, h: 0)
var bottom = 0
let scale: CGFloat = 2
let width: CGFloat
let height: CGFloat
let outPath: String
if backgroundOnly {
    width = CGFloat(Double(args[2])!)
    height = CGFloat(Double(args[3])!)
    outPath = args[4]
} else {
    let image = NSImage(contentsOfFile: args[1])!
    let rep = image.representations.first as! NSBitmapImageRep
    px = (rep.pixelsWide, rep.pixelsHigh)
    // Lowest non-transparent row in the middle column = bottom of the shape.
    for y in stride(from: px.h - 1, through: 0, by: -1) {
        if let c = rep.colorAt(x: px.w / 2, y: y), c.alphaComponent > 0.5 { bottom = y; break }
    }
    notch = image
    let extra = CGFloat(Double(args.count > 3 ? args[3] : "70")!)
    width = CGFloat(Double(args.count > 4 ? args[4] : "1200")!)
    // A fixed height keeps a gallery of shots the same shape.
    height = args.count > 5 ? CGFloat(Double(args[5])!) : max(CGFloat(bottom) / scale + extra, 200)
    outPath = args[2]
}
let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
out.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
let canvas = NSRect(x: 0, y: 0, width: width, height: height)

// Wallpaper: deep blue to violet with two soft glows.
NSGradient(colors: [NSColor(red: 0.07, green: 0.09, blue: 0.22, alpha: 1), NSColor(red: 0.27, green: 0.16, blue: 0.42, alpha: 1),
                    NSColor(red: 0.62, green: 0.30, blue: 0.40, alpha: 1)])!.draw(in: canvas, angle: -35)
for (center, color, radius) in [(NSPoint(x: width * 0.18, y: height * 0.15), NSColor(red: 0.95, green: 0.55, blue: 0.35, alpha: 0.35), 520.0),
                                (NSPoint(x: width * 0.85, y: height * 0.9), NSColor(red: 0.35, green: 0.55, blue: 1, alpha: 0.30), 600.0)] {
    NSGradient(colors: [color, color.withAlphaComponent(0)])!.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

// Menu bar.
let bar: CGFloat = 37
NSColor(white: 0, alpha: 0.28).setFill()
NSRect(x: 0, y: height - bar, width: width, height: bar).fill()
let font = NSFont.systemFont(ofSize: 13.5, weight: .regular)
let bold = NSFont.systemFont(ofSize: 13.5, weight: .bold)
func text(_ s: String, _ x: CGFloat, _ f: NSFont = font) -> CGFloat {
    let a = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: NSColor.white])
    a.draw(at: NSPoint(x: x, y: height - bar + (bar - a.size().height) / 2))
    return x + a.size().width
}
func symbol(_ name: String, _ x: CGFloat, size: CGFloat = 15) -> CGFloat {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium).applying(.init(paletteColors: [.white]))
    let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    img.draw(in: NSRect(x: x, y: height - bar + (bar - img.size.height) / 2, width: img.size.width, height: img.size.height))
    return x + img.size.width
}
// Narrow crops have no room beside the notch: an empty bar then.
if width >= 1000 {
var x = symbol("applelogo", 20, size: 15) + 22
x = text("Mail", x, bold) + 20
for item in ["File", "Edit", "View"] { x = text(item, x) + 20 }
var r = width - 20
let clock = NSAttributedString(string: "Thu 23 Oct  9:41", attributes: [.font: font])
r -= clock.size().width; _ = text("Thu 23 Oct  9:41", r)
r -= 46; _ = symbol("battery.75percent", r, size: 13)
r -= 32; _ = symbol("wifi", r, size: 14)
r -= 34; _ = symbol("envelope", r, size: 14)
}

// The notch capture, centered at the top.
if let notch {
    let drawWidth = CGFloat(px.w) / scale, drawHeight = CGFloat(px.h) / scale
    notch.draw(in: NSRect(x: (width - drawWidth) / 2, y: height - drawHeight, width: drawWidth, height: drawHeight))
}
NSGraphicsContext.restoreGraphicsState()
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
