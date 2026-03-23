import Cocoa

enum GhostMode {
    case screenshot
    case chat
}

enum GhostState {
    case idle       // nothing showing
    case selecting  // overlay active
    case answering  // panel visible
    case hidden     // panel exists, content preserved
}

// Top-level C-compatible callback for the ESC event tap.
// Must be a free function — Swift closures that create inner closures
// (e.g. DispatchQueue.main.async) cannot reliably be used as @convention(c)
// callbacks for CGEvent.tapCreate.
private func ghostEscEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let window = Unmanaged<GhostWindow>.fromOpaque(userInfo).takeUnretainedValue()
    if event.getIntegerValueField(.keyboardEventKeycode) == 53 {
        DispatchQueue.main.async {
            switch window.state {
            case .answering: window.fullDismiss()
            case .selecting: window.deactivate()
            default: break
            }
        }
        return nil  // consumed — Safari never sees this ESC
    }
    return Unmanaged.passUnretained(event)
}

class GhostWindow: NSPanel {

    var answerPanel: AnswerPanel?
    var currentScreenshot: NSImage?
    var currentMode: GhostMode = .screenshot
    var state: GhostState = .idle

    private var escEventTap: CFMachPort?
    private var escRunLoopSource: CFRunLoopSource?
    private var safetyTimer: Timer?
    private var deactivateObserver: Any?
    var clickMonitor: Any?

    init() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .screenSaver
        self.backgroundColor = NSColor.clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.sharingType = .none

        // Observe screenshot clear from the panel's "Clear" button
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("GhostClearScreenshot"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.currentScreenshot = nil
            AIManager.shared.clearHistory()
        }

        // Respond to mode toggle asking whether a screenshot exists
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("GhostCheckScreenshot"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if self?.currentScreenshot != nil {
                self?.answerPanel?.showScreenshotPill()
            } else {
                self?.answerPanel?.hideScreenshotPill()
            }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Activate

    func activate() {
        switch state {
        case .hidden:
            restorePanel()
            return
        case .answering:
            hidePanel()
            return
        case .selecting:
            deactivate()
            return
        case .idle:
            break
        }

        print("Ghost: activate() called")
        state = .selecting
        startEscConsumer()

        if answerPanel == nil {
            answerPanel = AnswerPanel()

            answerPanel?.onFollowUp = { [weak self] text, mode in
                print("🟡 onFollowUp fired, mode=\(mode), image=\(((mode == .screenshot) ? self?.currentScreenshot : nil) == nil ? "nil" : "present")")
                guard let self = self else { print("Ghost: self is nil!"); return }
                let image: NSImage? = (mode == .screenshot) ? self.currentScreenshot : nil
                print("🟡 calling query, prompt='\(text)'")

                let followUpBubble = self.answerPanel?.currentStreamingBubble

                AIManager.shared.query(
                    image: image,
                    prompt: text,
                    onChunk: { [weak self] chunk in
                        self?.answerPanel?.appendStreamingText(chunk)
                    },
                    onComplete: { [weak self] fullText in
                        if self?.answerPanel?.currentStreamingBubble === followUpBubble {
                            self?.answerPanel?.finalizeStreamingBubble()
                        }
                        AIManager.shared.conversationHistory.append(
                            ChatMessage(role: "user", content: text)
                        )
                        AIManager.shared.conversationHistory.append(
                            ChatMessage(role: "assistant", content: fullText)
                        )
                    },
                    onError: { [weak self] error in
                        print("Ghost: follow-up error = \(error)")
                        self?.answerPanel?.appendStreamingText("⚠️ \(error)")
                        if self?.answerPanel?.currentStreamingBubble === followUpBubble {
                            self?.answerPanel?.finalizeStreamingBubble()
                        }
                    }
                )
            }

            answerPanel?.onHide = { [weak self] in
                self?.hidePanel()
            }

            answerPanel?.onFullDismiss = { [weak self] in
                self?.fullDismiss()
            }
        }

        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let selectionView = SelectionView(frame: screenFrame)

        selectionView.onRegionSelected = { [weak self] rect in
            guard let self = self else { return }
            print("Ghost: selected region \(rect)")

            ScreenCaptureManager.capture(region: rect) { [weak self] image in
                guard let self = self else { return }
                guard let image = image else {
                    DispatchQueue.main.async { self.deactivate() }
                    return
                }

                self.currentScreenshot = image
                AIManager.shared.clearHistory()

                print("Ghost: image captured, sending to AI...")
                let screen = NSScreen.main ?? NSScreen.screens[0]
                self.answerPanel?.show(near: rect, onScreen: screen)
                self.answerPanel?.showScreenshotPill()
                self.deactivate()
                self.state = .answering
                self.startEscConsumer()
                self.showClickCatcher()

                // Capture this query's bubble so finalizeStreamingBubble()
                // doesn't nil a chat bubble if user switches modes mid-stream.
                let screenshotBubble = self.answerPanel?.currentStreamingBubble

                AIManager.shared.query(
                    image: image,
                    prompt: "Answer this.",
                    onChunk: { [weak self] chunk in
                        self?.answerPanel?.appendStreamingText(chunk)
                    },
                    onComplete: { [weak self] fullText in
                        print("Ghost: answer complete")
                        if self?.answerPanel?.currentStreamingBubble === screenshotBubble {
                            self?.answerPanel?.finalizeStreamingBubble()
                        }
                        AIManager.shared.conversationHistory.append(
                            ChatMessage(role: "user", content: "Answer this.")
                        )
                        AIManager.shared.conversationHistory.append(
                            ChatMessage(role: "assistant", content: fullText)
                        )
                    },
                    onError: { [weak self] error in
                        print("Ghost: error = \(error)")
                        self?.answerPanel?.appendStreamingText("⚠️ \(error)")
                        if self?.answerPanel?.currentStreamingBubble === screenshotBubble {
                            self?.answerPanel?.finalizeStreamingBubble()
                        }
                    }
                )
            }
        }

        self.contentView = selectionView
        self.makeFirstResponder(selectionView)
        self.orderFrontRegardless()
        NSCursor.crosshair.push()

        deactivateObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("GhostDeactivate"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.deactivate()
        }

        safetyTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            print("Ghost: safety timeout — force deactivating")
            self?.deactivate()
        }
    }

    // MARK: - Deactivate (selection overlay only)

    func deactivate() {
        safetyTimer?.invalidate()
        safetyTimer = nil

        if let observer = deactivateObserver {
            NotificationCenter.default.removeObserver(observer)
            deactivateObserver = nil
        }
        stopEscConsumer()
        NSCursor.pop()
        self.contentView = nil
        self.orderOut(nil)

        if state == .selecting { state = .idle }
    }

    // MARK: - Hide (preserve content)

    func hidePanel() {
        guard state == .answering else { return }
        answerPanel?.orderOut(nil)
        removeClickCatcher()
        stopEscConsumer()
        state = .hidden
        NotificationCenter.default.post(name: NSNotification.Name("GhostPanelHidden"), object: nil)
        print("Ghost: panel hidden — content preserved")
    }

    // MARK: - Restore

    func restorePanel() {
        guard state == .hidden else { return }
        guard let panel = answerPanel else {
            state = .idle
            activate()
            return
        }
        panel.orderFrontRegardless()
        showClickCatcher()
        startEscConsumer()
        state = .answering
        NotificationCenter.default.post(name: NSNotification.Name("GhostPanelRestored"), object: nil)
        print("Ghost: panel restored with preserved content")
    }

    // MARK: - Full dismiss (clear content)

    func fullDismiss() {
        answerPanel?.dismiss()
        removeClickCatcher()
        stopEscConsumer()
        currentScreenshot = nil
        AIManager.shared.clearHistory()
        state = .idle
        NotificationCenter.default.post(name: NSNotification.Name("GhostPanelRestored"), object: nil)
        print("Ghost: full dismiss — content cleared")
    }

    // MARK: - ESC consumer (CGEvent tap — consumes ESC before Safari sees it)

    func startEscConsumer() {
        guard escEventTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        escEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: ghostEscEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap = escEventTap else {
            print("Ghost: ESC consumer tap failed")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        escRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("Ghost: ESC consumer active")
    }

    func stopEscConsumer() {
        if let tap = escEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            escEventTap = nil
        }
        if let source = escRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            escRunLoopSource = nil
        }
        print("Ghost: ESC consumer stopped")
    }

    // MARK: - Click catcher (global monitor — observes without consuming)

    func showClickCatcher() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self = self, let panel = self.answerPanel else { return }
            let screenPoint = NSEvent.mouseLocation
            if !panel.frame.contains(screenPoint) {
                DispatchQueue.main.async { self.hidePanel() }
            }
        }
    }

    func removeClickCatcher() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }
}
