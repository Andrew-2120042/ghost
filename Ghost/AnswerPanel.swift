import Cocoa

class AnswerPanel: NSPanel {

    private var textView: NSTextView!
    private var dismissTimer: Timer?
    private var escMonitor: Any?
    private var localEscMonitor: Any?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .screenSaver
        self.sharingType = .none
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setupUI()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func setupUI() {
        let initial = NSRect(x: 0, y: 0, width: 380, height: 80)

        let vfx = NSVisualEffectView(frame: initial)
        vfx.material = .hudWindow
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = 14
        vfx.layer?.masksToBounds = true
        vfx.autoresizingMask = [.width, .height]
        self.contentView = vfx

        let scrollView = NSScrollView(frame: initial)
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        vfx.addSubview(scrollView)

        textView = NSTextView(frame: initial)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 348, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView

        // "ghost" label — top-right
        let ghostLabel = NSTextField(labelWithString: "ghost")
        ghostLabel.font = NSFont.systemFont(ofSize: 10)
        ghostLabel.textColor = NSColor.white.withAlphaComponent(0.3)
        ghostLabel.sizeToFit()
        ghostLabel.frame = NSRect(
            x: 380 - 12 - ghostLabel.frame.width,
            y: 80 - 12 - ghostLabel.frame.height,
            width: ghostLabel.frame.width,
            height: ghostLabel.frame.height
        )
        ghostLabel.autoresizingMask = [.minXMargin, .minYMargin]
        vfx.addSubview(ghostLabel)

        // X close button — top-left
        let closeButton = NSButton(title: "✕", target: self, action: #selector(closeAction))
        closeButton.isBordered = false
        closeButton.font = NSFont.systemFont(ofSize: 13)
        closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.5)
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.clear.cgColor
        closeButton.sizeToFit()
        closeButton.frame = NSRect(
            x: 10,
            y: 80 - 10 - closeButton.frame.height,
            width: closeButton.frame.width,
            height: closeButton.frame.height
        )
        closeButton.autoresizingMask = [.maxXMargin, .minYMargin]
        vfx.addSubview(closeButton)

        // "Press Esc to dismiss" hint — bottom center
        let hintLabel = NSTextField(labelWithString: "Press Esc to dismiss")
        hintLabel.font = NSFont.systemFont(ofSize: 10)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.2)
        hintLabel.alignment = .center
        hintLabel.sizeToFit()
        hintLabel.frame = NSRect(
            x: (380 - hintLabel.frame.width) / 2,
            y: 8,
            width: hintLabel.frame.width,
            height: hintLabel.frame.height
        )
        hintLabel.autoresizingMask = [.minXMargin, .maxXMargin]
        vfx.addSubview(hintLabel)
    }

    @objc private func closeAction() {
        dismiss()
    }

    func show(near rect: NSRect, onScreen screen: NSScreen) {
        let panelWidth: CGFloat = 380
        let panelHeight: CGFloat = 200

        var x = rect.maxX + 16
        var y = rect.midY - panelHeight / 2

        if x + panelWidth > screen.frame.maxX - 20 {
            x = rect.minX - panelWidth - 16
        }

        if x < screen.frame.minX + 20 {
            x = rect.midX - panelWidth / 2
            y = rect.minY - panelHeight - 16
        }

        x = max(screen.frame.minX + 20, min(x, screen.frame.maxX - panelWidth - 20))
        y = max(screen.frame.minY + 20, min(y, screen.frame.maxY - panelHeight - 20))

        self.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: false)
        self.orderFrontRegardless()
        textView.string = ""

        if escMonitor == nil {
            escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 {
                    DispatchQueue.main.async { self?.dismiss() }
                }
            }
        }
        if localEscMonitor == nil {
            localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 {
                    DispatchQueue.main.async { self?.dismiss() }
                    return nil
                }
                return event
            }
        }
    }

    func appendText(_ text: String) {
        DispatchQueue.main.async {
            self.textView.string += text

            self.textView.layoutManager?.ensureLayout(for: self.textView.textContainer!)
            let usedHeight = self.textView.layoutManager?
                .usedRect(for: self.textView.textContainer!).height ?? 0
            let inset = self.textView.textContainerInset.height
            let newHeight = min(max(usedHeight + inset * 2 + 8, 80), 400)

            if abs(newHeight - self.frame.size.height) > 1 {
                let topEdge = self.frame.origin.y + self.frame.size.height
                var frame = self.frame
                frame.size.height = newHeight
                frame.origin.y = topEdge - newHeight
                self.setFrame(frame, display: true, animate: false)
            }

            self.textView.scrollToEndOfDocument(nil)
        }
    }

    func startDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
        if let monitor = localEscMonitor {
            NSEvent.removeMonitor(monitor)
            localEscMonitor = nil
        }
        self.orderOut(nil)
        textView.string = ""
    }
}
