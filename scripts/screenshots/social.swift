// Used by scripts/screenshots/make.sh: the 1280x640 social preview (link cards on GitHub, Slack, X).
// social <icon.png> <list-screenshot.png> <out.png>
import AppKit

let args = CommandLine.arguments
let icon = NSImage(contentsOfFile: args[1])!
let shot = NSImage(contentsOfFile: args[2])!
let size = NSSize(width: 1280, height: 640)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2560, pixelsHigh: 1280, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let canvas = NSRect(origin: .zero, size: size)
NSGradient(colors: [NSColor(red: 0.07, green: 0.08, blue: 0.20, alpha: 1), NSColor(red: 0.25, green: 0.15, blue: 0.40, alpha: 1),
                    NSColor(red: 0.55, green: 0.26, blue: 0.38, alpha: 1)])!.draw(in: canvas, angle: -30)
let glow = NSPoint(x: 980, y: 420)
NSGradient(colors: [NSColor(red: 0.6, green: 0.45, blue: 1, alpha: 0.35), NSColor(red: 0.6, green: 0.45, blue: 1, alpha: 0)])!
    .draw(fromCenter: glow, radius: 0, toCenter: glow, radius: 520, options: [])

icon.draw(in: NSRect(x: 72, y: 420, width: 150, height: 150))
func line(_ text: String, _ font: NSFont, _ color: NSColor, y: CGFloat) {
    NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]).draw(at: NSPoint(x: 80, y: y))
}
line("Notch Mail", .systemFont(ofSize: 80, weight: .heavy), .white, y: 300)
let tagline = NSFont.systemFont(ofSize: 29, weight: .medium)
line("New mail slides out of your MacBook notch.", tagline, NSColor(white: 1, alpha: 0.85), y: 244)
line("Read it, reply with Claude, archive it.", tagline, NSColor(white: 1, alpha: 0.85), y: 206)
line("Free  ·  open source  ·  Gmail + Outlook  ·  no server", .systemFont(ofSize: 21, weight: .semibold),
     NSColor(red: 1, green: 0.74, blue: 0.62, alpha: 1), y: 140)

// The list screenshot, cropped to the notch, on the right.
let crop = NSRect(x: shot.size.width * 0.27, y: shot.size.height * 0.12, width: shot.size.width * 0.46, height: shot.size.height * 0.88)
let targetHeight = 590 * crop.height / crop.width
let target = NSRect(x: 650, y: (640 - targetHeight) / 2, width: 590, height: targetHeight)
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: target, xRadius: 26, yRadius: 26).addClip()
shot.draw(in: target, from: crop, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
NSColor(white: 1, alpha: 0.12).setStroke()
let border = NSBezierPath(roundedRect: target, xRadius: 26, yRadius: 26)
border.lineWidth = 2
border.stroke()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
