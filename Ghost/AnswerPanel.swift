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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        guard cmd else { return super.performKeyEquivalent(with: event) }
        switch event.keyCode {
        case 9: return NSApp.sendAction(#selector(NSText.paste(_:)),      to: currentEditor(), from: self)
        case 8: return NSApp.sendAction(#selector(NSText.copy(_:)),       to: currentEditor(), from: self)
        case 7: return NSApp.sendAction(#selector(NSText.cut(_:)),        to: currentEditor(), from: self)
        case 0: return NSApp.sendAction(#selector(NSText.selectAll(_:)),  to: currentEditor(), from: self)
        default: return super.performKeyEquivalent(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }
}

// MARK: - Selectable answer bubble label (makes panel key on click)

private class SelectableLabel: NSTextField {
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
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
    private var screenshotStack: NSStackView!
    private var chatStack: NSStackView!
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
    private var cmdCMonitor: Any?
    private var screenshotAssistantTexts: [String] = []
    private var chatAssistantTexts: [String] = []

    var currentStreamingBubble: NSTextField?
    var onFollowUp: ((String, GhostMode) -> Void)?
    var onHide: (() -> Void)?
    var onFullDismiss: (() -> Void)?

    var currentMode: GhostMode = .screenshot {
        didSet { updateModeUI() }
    }

    private var activeStack: NSStackView {
        currentMode == .screenshot ? screenshotStack : chatStack
    }

    private var activeAssistantTexts: [String] {
        get { currentMode == .screenshot ? screenshotAssistantTexts : chatAssistantTexts }
        set {
            if currentMode == .screenshot { screenshotAssistantTexts = newValue }
            else { chatAssistantTexts = newValue }
        }
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

        // Parent stack holds both mode stacks
        screenshotStack = NSStackView()
        screenshotStack.orientation = .vertical
        screenshotStack.spacing = 10
        screenshotStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        screenshotStack.alignment = .leading
        screenshotStack.translatesAutoresizingMaskIntoConstraints = false

        chatStack = NSStackView()
        chatStack.orientation = .vertical
        chatStack.spacing = 10
        chatStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        chatStack.alignment = .leading
        chatStack.isHidden = true
        chatStack.translatesAutoresizingMaskIntoConstraints = false

        let parentStack = NSStackView(views: [screenshotStack, chatStack])
        parentStack.orientation = .vertical
        parentStack.spacing = 0
        parentStack.alignment = .leading
        parentStack.translatesAutoresizingMaskIntoConstraints = false
        flipView.addSubview(parentStack)

        // ── INPUT ROW ─────────────────────────────────────────────────────────
        let inputRow = NSView()
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

            // Screenshot pill
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

            // FlippedView pinned width to scroll view
            flipView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            flipView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            flipView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Parent stack fills flipView
            parentStack.topAnchor.constraint(equalTo: flipView.topAnchor),
            parentStack.leadingAnchor.constraint(equalTo: flipView.leadingAnchor),
            parentStack.trailingAnchor.constraint(equalTo: flipView.trailingAnchor),
            parentStack.bottomAnchor.constraint(equalTo: flipView.bottomAnchor),
            parentStack.widthAnchor.constraint(equalTo: flipView.widthAnchor),

            // Each stack fills full width
            screenshotStack.widthAnchor.constraint(equalTo: parentStack.widthAnchor),
            chatStack.widthAnchor.constraint(equalTo: parentStack.widthAnchor),
        ])
    }

    // MARK: - Chat bubbles

    @discardableResult
    private func addBubble(text: String, role: String) -> NSTextField {
        let label: NSTextField = role == "assistant"
            ? SelectableLabel(labelWithString: text)
            : NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 14)
        label.textColor = .white
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = 320
        if role == "assistant" {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.alignment = .justified
        }
        label.isSelectable = true
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        if role == "user" {
            container.layer?.cornerRadius = 10
            container.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.25).cgColor
        }
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        let hPad: CGFloat = role == "assistant" ? 16 : 10
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hPad),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -hPad),
        ])

        if role == "user" {
            let wrapper = NSView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(container)
            NSLayoutConstraint.activate([
                container.topAnchor.constraint(equalTo: wrapper.topAnchor),
                container.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                container.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                container.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            ])
            activeStack.addArrangedSubview(wrapper)
            wrapper.widthAnchor.constraint(equalTo: activeStack.widthAnchor, constant: -24).isActive = true
        } else {
            activeStack.addArrangedSubview(container)
            container.widthAnchor.constraint(equalTo: activeStack.widthAnchor).isActive = true
        }

        scrollToBottom()
        return label
    }

    func startNewAssistantBubble() {
        currentStreamingBubble = addBubble(text: "", role: "assistant")
        print("🔵 bubble created in \(currentMode == .screenshot ? "screenshotStack" : "chatStack")")
        print("🔵 currentStreamingBubble set: \(currentStreamingBubble != nil)")
    }

    func appendStreamingText(_ text: String) {
        print("🔵 appendStreamingText called, chunk='\(text.prefix(30))', bubble=\(currentStreamingBubble != nil ? "EXISTS" : "NIL")")
        DispatchQueue.main.async {
            guard let bubble = self.currentStreamingBubble else {
                print("🔵 appendStreamingText: bubble is NIL, dropping chunk")
                return
            }
            bubble.stringValue += text
            bubble.invalidateIntrinsicContentSize()
            self.activeStack.needsLayout = true
            self.scrollToBottom()
        }
    }

    func finalizeStreamingBubble() {
        if let text = currentStreamingBubble?.stringValue, !text.isEmpty {
            activeAssistantTexts.append(text)
        }
        currentStreamingBubble = nil
    }

    func addUserBubble(_ text: String) {
        _ = addBubble(text: text, role: "user")
    }

    func scrollToBottom() {
        DispatchQueue.main.async {
            let point = NSPoint(
                x: 0,
                y: max(0, (self.scrollView.documentView?.frame.height ?? 0) - self.scrollView.frame.height)
            )
            self.scrollView.documentView?.scroll(point)
        }
    }

    func appendText(_ text: String) { appendStreamingText(text) }
    func startDismissTimer() {}

    // MARK: - Show / Dismiss

    func show(near rect: NSRect, onScreen screen: NSScreen) {
        print("🔵 show() called, resetting stacks")
        // Clear both stacks for fresh session
        screenshotStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        chatStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        currentStreamingBubble = nil
        screenshotAssistantTexts = []
        chatAssistantTexts = []
        inputField.stringValue = ""
        hideScreenshotPill()

        // Start in screenshot mode
        screenshotStack.isHidden = false
        chatStack.isHidden = true
        currentMode = .screenshot
        updateModeUI()

        // Load saved size
        var panelWidth: CGFloat = 400
        var panelHeight: CGFloat = 500
        if let sizeSaved = UserDefaults.standard.dictionary(forKey: sizeKey),
           let w = sizeSaved["w"] as? Double,
           let h = sizeSaved["h"] as? Double {
            panelWidth  = max(300, min(800, CGFloat(w)))
            panelHeight = max(300, min(900, CGFloat(h)))
        }

        // Use saved position if still on screen
        if let saved = UserDefaults.standard.dictionary(forKey: positionKey),
           let sx = saved["x"] as? Double,
           let sy = saved["y"] as? Double {
            let savedOrigin = NSPoint(x: sx, y: sy)
            let savedRect = NSRect(origin: savedOrigin, size: NSSize(width: panelWidth, height: panelHeight))
            if screen.frame.intersects(savedRect) {
                super.setFrame(savedRect, display: false)
                orderFrontRegardless()
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
        startNewAssistantBubble()
        setupKeyMonitors()
    }

    private func setupKeyMonitors() {
        if cmdCMonitor == nil {
            cmdCMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, self.isVisible else { return }
                if event.keyCode == 8 && event.modifierFlags.contains(.command) {
                    DispatchQueue.main.async { self.copyAnswer() }
                }
            }
        }
    }

    @objc func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        if let m = cmdCMonitor { NSEvent.removeMonitor(m); cmdCMonitor = nil }
        orderOut(nil)
    }

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

        chatStack.isHidden = true
        screenshotStack.isHidden = false

        AIManager.shared.clearHistory()
        NotificationCenter.default.post(name: NSNotification.Name("GhostCheckScreenshot"), object: nil)
        inputField.placeholderString = "Ask a follow-up..."
        updateModeUI()

        if !screenshotStack.arrangedSubviews.isEmpty {
            addSeparatorToStack(screenshotStack, text: "— Screenshot mode —")
        }

        scrollToBottom()
    }

    @objc func switchToChatMode() {
        guard currentMode != .chat else { return }
        currentMode = .chat

        screenshotStack.isHidden = true
        chatStack.isHidden = false

        print("🔵 switched to chat, chatStack.isHidden=\(chatStack.isHidden), screenshotStack.isHidden=\(screenshotStack.isHidden)")

        AIManager.shared.clearHistory()
        hideScreenshotPill()
        inputField.placeholderString = "Ask anything..."
        updateModeUI()

        if chatStack.arrangedSubviews.isEmpty {
            addSeparatorToStack(chatStack, text: "— Chat mode —")
        }

        scrollToBottom()
    }

    func updateModeUI() {
        switch currentMode {
        case .screenshot:
            modePhotoBtn.contentTintColor = .systemBlue
            modeChatBtn.contentTintColor  = NSColor.white.withAlphaComponent(0.3)
        case .chat:
            modeChatBtn.contentTintColor  = .systemBlue
            modePhotoBtn.contentTintColor = NSColor.white.withAlphaComponent(0.3)
        }
    }

    // MARK: - Separator

    func addSeparator(_ text: String) {
        addSeparatorToStack(activeStack, text: text)
    }

    func addSeparatorToStack(_ stack: NSStackView, text: String) {
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

        stack.addArrangedSubview(container)
        scrollToBottom()
    }

    // MARK: - Send message

    @objc func sendMessage() {
        print("🔵 sendMessage called, text='\(inputField.stringValue)', mode=\(currentMode)")
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        addUserBubble(text)
        inputField.stringValue = ""
        print("🔵 startNewAssistantBubble called, activeStack=\(currentMode == .screenshot ? "screenshot" : "chat"), chatHidden=\(chatStack.isHidden)")
        startNewAssistantBubble()
        dismissTimer?.invalidate()
        print("Ghost: firing onFollowUp, onFollowUp isNil=\(onFollowUp == nil)")
        onFollowUp?(text, currentMode)
    }

    // MARK: - Copy answer

    @objc func copyAnswer() {
        let texts = activeAssistantTexts
        let text: String
        if let last = texts.last, !last.isEmpty {
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
