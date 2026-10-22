// Used by scripts/screenshots/record.sh.
// Shows a made-up desktop over the top of the notched screen, just below the
// notch panel, so a recording of that area contains nothing from the real screen.
// backdrop <image.png> <seconds>
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main!
let image = NSImage(contentsOfFile: CommandLine.arguments[1])!
let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - image.size.height, width: screen.frame.width, height: image.size.height)
let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)  // above the menu bar, below the notch panel
window.ignoresMouseEvents = true
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
let view = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
view.image = image
view.imageScaling = .scaleAxesIndependently
window.contentView = view
window.orderFrontRegardless()
// Print the screen geometry for the recorder: points and pixel scale.
print("\(Int(screen.frame.width)) \(Int(screen.frame.height)) \(Int(screen.backingScaleFactor))")
fflush(stdout)
DispatchQueue.main.asyncAfter(deadline: .now() + Double(CommandLine.arguments[2])!) { exit(0) }
app.run()
