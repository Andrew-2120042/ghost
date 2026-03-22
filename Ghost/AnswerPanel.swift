import Cocoa

// MARK: - Return-key-aware text field

class ReturnTextField: NSTextField, NSTextFieldDelegate {
    var onReturn: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        self.delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.delegate = self
    }

    func control(_ control: NSControl,
                 textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onReturn?()
            return true
        }
        return false
    }
}

// MARK: - Flipped container (top-to-bottom scroll layout)

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Drag handle for moving the panel

private class DragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        window?.performDrag(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        if let origin = window?.frame.origin, let panel = window as? AnswerPanel {
            panel.savePositionPublic(origin)
        }
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

// MARK: - AnswerPanel

class AnswerPanel: NSPanel {

    // MARK: - UI references
    private var scrollView: NSScrollView!
    private var contentStack: NSStackView!
    private var inputField: ReturnTextField!
    private(set) var copyButton: NSButton!
    private var modePhotoBtn: NSButton!
    private var modeChatBtn: NSButton!
    private var screenshotPill: NSView!
    private var pillHeightConstraint: NSLayoutConstraint!

    // MARK: - State
    let positionKey = "ghost.panel.position"
    let sizeKey     = "ghost.panel.size"
    private var dismissTimer: Timer?
    private var escMonitor: Any?
    private var cmdCMonitor: Any?
    private var assistantTexts: [String] = []

    var currentStreamingBubble: NSTextField?
    var onFollowUp: ((String, GhostMode) -> Void)?
    var onHide: (() -> Void)?
    var onFullDismiss: (() -> Void)?

    var currentMode: GhostMode = .screenshot {
        didSet { updateModeUI() }
    }

    // MARK: - Init

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        self.level = .screenSaver
        self.sharingType = .none
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.minSize = NSSize(width: 300, height: 300)
        self.maxSize = NSSize(width: 800, height: 900)
        setupUI()
    }

    // canBecomeKey = true so the input field can receive keyboard events
    // nonactivatingPanel style prevents Ghost from stealing app focus
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var isMovable: Bool { get { true } set { } }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        saveSizePublic(frameRect.size)
    }

    private func savePosition(_ origin: NSPoint) {
        UserDefaults.standard.set(
            ["x": Double(origin.x), "y": Double(origin.y)],
            forKey: positionKey
        )
    }

    func savePositionPublic(_ origin: NSPoint) {
        savePosition(origin)
        print("Ghost: panel position saved \(origin)")
    }

    func saveSizePublic(_ size: NSSize) {
        UserDefaults.standard.set(
            ["w": Double(size.width), "h": Double(size.height)],
            forKey: sizeKey
        )
        print("Ghost: panel size saved \(size)")
    }

    // MARK: - UI Setup

    private func setupUI() {
        let vfx = NSVisualEffectView()
        vfx.material = .hudWindow
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = 16
        vfx.layer?.masksToBounds = true
        vfx.autoresizingMask = [.width, .height]
        vfx.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        self.contentView = vfx

        // ── HEADER ───────────────────────────────────────────────────────────
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        vfx.addSubview(header)

        // Drag handle — added first so buttons sit on top of it
        let dragHandle = DragHandleView()
        dragHandle.wantsLayer = true
        dragHandle.layer?.backgroundColor = CGColor.clear
        dragHandle.autoresizingMask = [.width, .height]
        dragHandle.frame = NSRect(x: 0, y: 0, width: 400, height: 44)
        header.addSubview(dragHandle, positioned: .below, relativeTo: nil)

        let ghostLabel = NSTextField(labelWithString: "ghost")
        ghostLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        ghostLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        ghostLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(ghostLabel)

        copyButton = NSButton(title: "⌘C", target: self, action: #selector(copyAnswer))
        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.font = NSFont.systemFont(ofSize: 11)
        copyButton.contentTintColor = NSColor.white.withAlphaComponent(0.4)
        copyButton.toolTip = "Copy answer"
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(copyButton)

        let closeBtn = NSButton(title: "×", target: self, action: #selector(fullDismissPanel))
        closeBtn.bezelStyle = .inline
        closeBtn.isBordered = false
        closeBtn.font = NSFont.systemFont(ofSize: 15)
        closeBtn.contentTintColor = NSColor.white.withAlphaComponent(0.4)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(closeBtn)

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        vfx.addSubview(separator)

        // ── SCREENSHOT PILL ───────────────────────────────────────────────────
        screenshotPill = NSView()
        screenshotPill.wantsLayer = true
        screenshotPill.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15).cgColor
        screenshotPill.layer?.cornerRadius = 6
        screenshotPill.isHidden = true
        screenshotPill.translatesAutoresizingMaskIntoConstraints = false
        vfx.addSubview(screenshotPill)

        let pillLabel = NSTextField(labelWithString: "Screenshot active")
        pillLabel.font = NSFont.systemFont(ofSize: 11)
        pillLabel.textColor = NSColor.systemBlue
        pillLabel.translatesAutoresizingMaskIntoConstraints = false
        screenshotPill.addSubview(pillLabel)

        let clearBtn = NSButton(title: "Clear", target: self, action: #selector(clearScreenshot))
        clearBtn.bezelStyle = .inline
        clearBtn.isBordered = false
        clearBtn.font = NSFont.systemFont(ofSize: 11)
        clearBtn.contentTintColor = .systemBlue
        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        screenshotPill.addSubview(clearBtn)

        // ── SCROLL VIEW ───────────────────────────────────────────────────────
        scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        vfx.addSubview(scrollView)

        let flipView = FlippedView()
        flipView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = flipView

        contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.spacing = 10
        contentStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        contentStack.alignment = .leading
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        flipView.addSubview(contentStack)

        // ── INPUT ROW ─────────────────────────────────────────────────────────
        let inputRow = NSView()
        inputRow.wantsLayer = true
        inputRow.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        inputRow.translatesAutoresizingMaskIntoConstraints = false
        vfx.addSubview(inputRow)

        modePhotoBtn = NSButton(title: "", target: self, action: #selector(switchToScreenshotMode))
        modePhotoBtn.bezelStyle = .inline
        modePhotoBtn.isBordered = false
        modePhotoBtn.image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Screenshot mode")
        modePhotoBtn.contentTintColor = .systemBlue
        modePhotoBtn.toolTip = "Screenshot mode"
        modePhotoBtn.translatesAutoresizingMaskIntoConstraints = false
        inputRow.addSubview(modePhotoBtn)

        modeChatBtn = NSButton(title: "", target: self, action: #selector(switchToChatMode))
        modeChatBtn.bezelStyle = .inline
        modeChatBtn.isBordered = false
        modeChatBtn.image = NSImage(systemSymbolName: "bubble.left.fill", accessibilityDescription: "Chat mode")
        modeChatBtn.contentTintColor = NSColor.white.withAlphaComponent(0.3)
        modeChatBtn.toolTip = "Chat mode"
        modeChatBtn.translatesAutoresizingMaskIntoConstraints = false
        inputRow.addSubview(modeChatBtn)

        let inputContainer = NSView()
        inputContainer.wantsLayer = true
        inputContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        inputContainer.layer?.cornerRadius = 10
        inputContainer.layer?.borderWidth = 0.5
        inputContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        inputRow.addSubview(inputContainer)

        inputField = ReturnTextField(frame: .zero)
        inputField.placeholderString = "Ask a follow-up..."
        inputField.font = NSFont.systemFont(ofSize: 14)
        inputField.textColor = .white
        inputField.backgroundColor = .clear
        inputField.drawsBackground = false
        inputField.isBordered = false
        inputField.focusRingType = .none
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.onReturn = { [weak self] in self?.sendMessage() }
        inputContainer.addSubview(inputField)

        let sendBtn = NSButton(title: "", target: self, action: #selector(sendMessage))
        sendBtn.bezelStyle = .inline
        sendBtn.isBordered = false
        let sendCfg = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        sendBtn.image = NSImage(systemSymbolName: "arrow.up.circle.fill",
                                accessibilityDescription: "Send")?
            .withSymbolConfiguration(sendCfg)
        sendBtn.contentTintColor = .systemBlue
        sendBtn.translatesAutoresizingMaskIntoConstraints = false
        inputRow.addSubview(sendBtn)

        // ── AUTO LAYOUT ───────────────────────────────────────────────────────
        pillHeightConstraint = screenshotPill.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            // Header
            header.topAnchor.constraint(equalTo: vfx.topAnchor),
            header.leadingAnchor.constraint(equalTo: vfx.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: vfx.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),

            ghostLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            ghostLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            closeBtn.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            closeBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            copyButton.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -8),
            copyButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            // Separator
            separator.topAnchor.constraint(equalTo: header.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: vfx.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: vfx.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            // Screenshot pill (height = 0 when hidden, 48 when shown)
            screenshotPill.topAnchor.constraint(equalTo: separator.bottomAnchor),
            screenshotPill.leadingAnchor.constraint(equalTo: vfx.leadingAnchor, constant: 12),
            screenshotPill.trailingAnchor.constraint(equalTo: vfx.trailingAnchor, constant: -12),
            pillHeightConstraint,

            pillLabel.leadingAnchor.constraint(equalTo: screenshotPill.leadingAnchor, constant: 8),
            pillLabel.centerYAnchor.constraint(equalTo: screenshotPill.centerYAnchor),

            clearBtn.trailingAnchor.constraint(equalTo: screenshotPill.trailingAnchor, constant: -8),
            clearBtn.centerYAnchor.constraint(equalTo: screenshotPill.centerYAnchor),

            // Input row (fixed at bottom)
            inputRow.bottomAnchor.constraint(equalTo: vfx.bottomAnchor),
            inputRow.leadingAnchor.constraint(equalTo: vfx.leadingAnchor),
            inputRow.trailingAnchor.constraint(equalTo: vfx.trailingAnchor),
            inputRow.heightAnchor.constraint(equalToConstant: 48),

            modePhotoBtn.leadingAnchor.constraint(equalTo: inputRow.leadingAnchor, constant: 10),
            modePhotoBtn.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
            modePhotoBtn.widthAnchor.constraint(equalToConstant: 28),
            modePhotoBtn.heightAnchor.constraint(equalToConstant: 28),

            modeChatBtn.leadingAnchor.constraint(equalTo: modePhotoBtn.trailingAnchor, constant: 4),
            modeChatBtn.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
            modeChatBtn.widthAnchor.constraint(equalToConstant: 28),
            modeChatBtn.heightAnchor.constraint(equalToConstant: 28),

            sendBtn.trailingAnchor.constraint(equalTo: inputRow.trailingAnchor, constant: -10),
            sendBtn.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
            sendBtn.widthAnchor.constraint(equalToConstant: 28),
            sendBtn.heightAnchor.constraint(equalToConstant: 28),

            inputContainer.leadingAnchor.constraint(equalTo: modeChatBtn.trailingAnchor, constant: 8),
            inputContainer.trailingAnchor.constraint(equalTo: sendBtn.leadingAnchor, constant: -8),
            inputContainer.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
            inputContainer.heightAnchor.constraint(equalToConstant: 32),

            inputField.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 10),
            inputField.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -10),
            inputField.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),

            // Scroll view fills between pill and input row
            scrollView.topAnchor.constraint(equalTo: screenshotPill.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: vfx.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: vfx.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: inputRow.topAnchor),

            // FlippedView = document view, pinned width to scroll view
            flipView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            flipView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            flipView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // ContentStack fills flipView
            contentStack.topAnchor.constraint(equalTo: flipView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: flipView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: flipView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: flipView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: flipView.widthAnchor),
        ])
    }

    // MARK: - Chat bubbles

    @discardableResult
    private func addBubble(text: String, role: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 14)
        label.textColor = .white
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = 320
        label.isSelectable = true
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.backgroundColor = (role == "assistant")
            ? NSColor.white.withAlphaComponent(0.08).cgColor
            : NSColor.systemBlue.withAlphaComponent(0.25).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
        ])

        if role == "user" {
            // Right-aligned: wrap in a full-width view, bubble sits on the right
            let wrapper = NSView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(container)
            NSLayoutConstraint.activate([
                container.topAnchor.constraint(equalTo: wrapper.topAnchor),
                container.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                container.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                container.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            ])
            contentStack.addArrangedSubview(wrapper)
            wrapper.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -24).isActive = true
        } else {
            contentStack.addArrangedSubview(container)
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 360).isActive = true
        }

        scrollToBottom()
        return label
    }

    func startNewAssistantBubble() {
        currentStreamingBubble = addBubble(text: "", role: "assistant")
    }

    func appendStreamingText(_ text: String) {
        DispatchQueue.main.async {
            guard let bubble = self.currentStreamingBubble else { return }
            bubble.stringValue += text
            bubble.invalidateIntrinsicContentSize()
            self.contentStack.needsLayout = true
            self.scrollToBottom()
        }
    }

    func finalizeStreamingBubble() {
        if let text = currentStreamingBubble?.stringValue, !text.isEmpty {
            assistantTexts.append(text)
        }
        currentStreamingBubble = nil
    }

    func addUserBubble(_ text: String) {
        _ = addBubble(text: text, role: "user")
    }

    func scrollToBottom() {
        DispatchQueue.main.async {
            self.scrollView.layoutSubtreeIfNeeded()
            guard let docView = self.scrollView.documentView else { return }
            let docHeight = docView.frame.height
            let clipHeight = self.scrollView.contentView.bounds.height
            let y = max(0, docHeight - clipHeight)
            self.scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
    }

    // Legacy compatibility
    func appendText(_ text: String) { appendStreamingText(text) }
    func startDismissTimer() { /* no auto-dismiss in chat mode */ }

    // MARK: - Show / Dismiss

    func show(near rect: NSRect, onScreen screen: NSScreen) {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        currentStreamingBubble = nil
        assistantTexts = []
        currentMode = .screenshot
        inputField.stringValue = ""
        hideScreenshotPill()

        // Load saved size
        var panelWidth: CGFloat = 400
        var panelHeight: CGFloat = 500
        if let sizeSaved = UserDefaults.standard.dictionary(forKey: sizeKey),
           let w = sizeSaved["w"] as? Double,
           let h = sizeSaved["h"] as? Double {
            panelWidth  = max(300, min(800, CGFloat(w)))
            panelHeight = max(300, min(900, CGFloat(h)))
        }

        // Use saved position if it's still on screen
        if let saved = UserDefaults.standard.dictionary(forKey: positionKey),
           let sx = saved["x"] as? Double,
           let sy = saved["y"] as? Double {
            let savedOrigin = NSPoint(x: sx, y: sy)
            let savedRect = NSRect(origin: savedOrigin, size: NSSize(width: panelWidth, height: panelHeight))
            if screen.frame.intersects(savedRect) {
                super.setFrame(savedRect, display: false)
                orderFrontRegardless()
                updateModeUI()
                startNewAssistantBubble()
                setupKeyMonitors()
                return
            }
        }

        // Smart positioning relative to selection
        var x = rect.maxX + 16
        var y = rect.midY - panelHeight / 2

        if x + panelWidth > screen.frame.maxX - 20 { x = rect.minX - panelWidth - 16 }
        if x < screen.frame.minX + 20 {
            x = rect.midX - panelWidth / 2
            y = rect.minY - panelHeight - 16
        }
        x = max(screen.frame.minX + 20, min(x, screen.frame.maxX - panelWidth - 20))
        y = max(screen.frame.minY + 20, min(y, screen.frame.maxY - panelHeight - 20))

        setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: false)
        orderFrontRegardless()

        // Start a bubble ready for the first streaming response
        updateModeUI()
        startNewAssistantBubble()

        setupKeyMonitors()
    }

    private func setupKeyMonitors() {
        if escMonitor == nil {
            escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { DispatchQueue.main.async { self?.onFullDismiss?() } }
            }
        }
        if cmdCMonitor == nil {
            cmdCMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 8 && event.modifierFlags.contains(.command) {
                    DispatchQueue.main.async { self?.copyAnswer() }
                }
            }
        }
    }

    // Called by GhostWindow.fullDismiss() — removes key monitors and hides
    @objc func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        if let m = escMonitor  { NSEvent.removeMonitor(m); escMonitor  = nil }
        if let m = cmdCMonitor { NSEvent.removeMonitor(m); cmdCMonitor = nil }
        orderOut(nil)
    }

    // X button — fully close and clear content
    @objc func fullDismissPanel() {
        onFullDismiss?()
    }

    // MARK: - Screenshot pill

    func showScreenshotPill() {
        DispatchQueue.main.async {
            self.screenshotPill.isHidden = false
            self.pillHeightConstraint.constant = 48
        }
    }

    func hideScreenshotPill() {
        DispatchQueue.main.async {
            self.screenshotPill.isHidden = true
            self.pillHeightConstraint.constant = 0
        }
    }

    @objc func clearScreenshot() {
        hideScreenshotPill()
        NotificationCenter.default.post(name: NSNotification.Name("GhostClearScreenshot"), object: nil)
    }

    // MARK: - Mode switching

    @objc func switchToScreenshotMode() {
        guard currentMode != .screenshot else { return }
        currentMode = .screenshot
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        AIManager.shared.clearHistory()
        addSeparator("— Screenshot mode —")
        NotificationCenter.default.post(name: NSNotification.Name("GhostCheckScreenshot"), object: nil)
        updateModeUI()
    }

    @objc func switchToChatMode() {
        guard currentMode != .chat else { return }
        currentMode = .chat
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        AIManager.shared.clearHistory()
        addSeparator("— Chat mode —")
        hideScreenshotPill()
        updateModeUI()
    }

    func updateModeUI() {
        switch currentMode {
        case .screenshot:
            modePhotoBtn.contentTintColor = .systemBlue
            modeChatBtn.contentTintColor  = NSColor.white.withAlphaComponent(0.3)
            inputField.placeholderString  = "Ask a follow-up..."
        case .chat:
            modeChatBtn.contentTintColor  = .systemBlue
            modePhotoBtn.contentTintColor = NSColor.white.withAlphaComponent(0.3)
            inputField.placeholderString  = "Ask anything..."
        }
    }

    // MARK: - Separator label

    func addSeparator(_ text: String) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 10)
        label.textColor = NSColor.white.withAlphaComponent(0.25)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            container.heightAnchor.constraint(equalToConstant: 24),
        ])

        contentStack.addArrangedSubview(container)
        scrollToBottom()
    }

    // MARK: - Send message

    @objc func sendMessage() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        addUserBubble(text)
        inputField.stringValue = ""
        startNewAssistantBubble()
        dismissTimer?.invalidate()
        onFollowUp?(text, currentMode)
    }

    // MARK: - Copy answer

    @objc func copyAnswer() {
        let text: String
        if let last = assistantTexts.last, !last.isEmpty {
            text = last
        } else if let streaming = currentStreamingBubble?.stringValue, !streaming.isEmpty {
            text = streaming
        } else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showCopiedFeedback()
    }

    func showCopiedFeedback() {
        copyButton.title = "✓"
        copyButton.contentTintColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.title = "⌘C"
            self?.copyButton.contentTintColor = NSColor.white.withAlphaComponent(0.4)
        }
    }

}
