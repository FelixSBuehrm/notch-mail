// Used by scripts/screenshots/make.sh.
import CoreGraphics
import Foundation
// Prints the window ID of the biggest on-screen window of the given process.
let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
let best = mine.max { a, b in
    let ra = a[kCGWindowBounds as String] as? [String: CGFloat] ?? [:], rb = b[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    return (ra["Width"] ?? 0) * (ra["Height"] ?? 0) < (rb["Width"] ?? 0) * (rb["Height"] ?? 0)
}
if let id = best?[kCGWindowNumber as String] as? Int { print(id) }
