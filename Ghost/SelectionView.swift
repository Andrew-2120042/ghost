import Cocoa

class SelectionView: NSView {

    var startPoint: NSPoint?
    var currentPoint: NSPoint?
    var onRegionSelected: ((NSRect) -> Void)?

    override var acceptsFirstResponder: Bool { return true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
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
        guard let start = startPoint, let current = currentPoint else {
            NSColor.clear.setFill()
            bounds.fill()
            return
        }

        let screenRect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        // Screen coords match view coords directly (both bottom-left origin,
        // and this view sits at screen origin)
        let viewRect = screenRect

        // Dark overlay outside selection
        NSColor.black.withAlphaComponent(0.3).setFill()
        let outside = NSBezierPath(rect: bounds)
        outside.append(NSBezierPath(rect: viewRect).reversed)
        outside.fill()

        // Clear inside selection
        NSColor.clear.setFill()
        viewRect.fill()

        // Dashed white border
        let border = NSBezierPath(rect: viewRect)
        border.lineWidth = 2
        NSColor.white.setStroke()
        let dashPattern: [CGFloat] = [8, 4]
        border.setLineDash(dashPattern, count: 2, phase: 0)
        border.stroke()
    }
}
