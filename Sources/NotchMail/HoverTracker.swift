import AppKit

/// Reports the pointer position whenever it moves anywhere on screen.
/// Mouse-move monitors need no Accessibility permission (only key events do).
@MainActor
final class HoverTracker {
    /// Only written in init; read once more in deinit.
    nonisolated(unsafe) private var monitors: [Any] = []

    init(onMove: @escaping @MainActor (CGPoint) -> Void) {
        let report: (NSEvent) -> Void = { _ in
            MainActor.assumeIsolated { onMove(NSEvent.mouseLocation) }
        }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: report) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            report(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    deinit {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
    }
}
