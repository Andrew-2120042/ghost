import Cocoa

class SelectionView: NSView {

    var startPoint: NSPoint?
    var currentPoint: NSPoint?
    var onRegionSelected: ((NSRect) -> Void)?

    override var acceptsFirstResponder: Bool { return true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.push()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            if let ghostWindow = self.window as? GhostWindow {
                ghostWindow.deactivate()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = NSEvent.mouseLocation
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = NSEvent.mouseLocation
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = startPoint,
              let current = currentPoint else { return }

        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        if rect.width > 10 && rect.height > 10 {
            onRegionSelected?(rect)
        }

        startPoint = nil
        currentPoint = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Completely clear — nothing drawn on idle
        NSColor.clear.setFill()
        dirtyRect.fill()

        // Only draw if actively selecting
        guard let start = startPoint,
              let current = currentPoint else { return }

        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        // Very subtle white fill inside selection only
        NSColor.white.withAlphaComponent(0.03).setFill()
        NSBezierPath(rect: rect).fill()

        // White dashed border — subtle, not obvious
        let borderPath = NSBezierPath(rect: rect)
        borderPath.lineWidth = 1.5
        NSColor.white.withAlphaComponent(0.6).setStroke()
        borderPath.setLineDash([6, 3], count: 2, phase: 0)
        borderPath.stroke()
    }
}
