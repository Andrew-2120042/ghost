import Cocoa

class OnboardingWindowController: NSWindowController {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.title = ""
        window.backgroundColor = NSColor(white: 0.09, alpha: 1)
        window.isMovableByWindowBackground = true
        self.init(window: window)
    }

    func transition(to vc: NSViewController) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            self.window?.contentView?.animator().alphaValue = 0
        }) {
            self.window?.contentViewController = vc
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                self.window?.contentView?.animator().alphaValue = 1
            }
        }
    }
}
