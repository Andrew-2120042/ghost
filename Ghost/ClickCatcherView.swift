import Cocoa

class ClickCatcherView: NSView {
    var onTap: (() -> Void)?
    var panelToIgnore: NSPanel?

    override func mouseDown(with event: NSEvent) {
        let screenPoint = NSEvent.mouseLocation
        if let panel = panelToIgnore, panel.frame.contains(screenPoint) {
            return
        }
        onTap?()
    }

    override func rightMouseDown(with event: NSEvent) {
        let screenPoint = NSEvent.mouseLocation
        if let panel = panelToIgnore, panel.frame.contains(screenPoint) {
            return
        }
        onTap?()
    }
}
