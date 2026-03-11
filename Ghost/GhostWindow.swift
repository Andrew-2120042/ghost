import Cocoa

enum GhostMode {
    case screenshot
    case chat
}

class GhostWindow: NSPanel {

    var answerPanel: AnswerPanel?
    var currentScreenshot: NSImage?
    var currentMode: GhostMode = .screenshot

    private var escMonitor: Any?
    private var escMonitorLocal: Any?
    private var safetyTimer: Timer?
    private var deactivateObserver: Any?

    init() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .screenSaver
        self.backgroundColor = NSColor.blue.withAlphaComponent(0.15)
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

    func activate() {
        print("Ghost: activate() called")

        if answerPanel == nil {
            answerPanel = AnswerPanel()

            // Wire up follow-up callback (set once, persists across activations)
            answerPanel?.onFollowUp = { [weak self] text, mode in
                guard let self = self else { return }

                AIManager.shared.conversationHistory.append(
                    ChatMessage(role: "user", content: text)
                )

                let image: NSImage? = (mode == .screenshot) ? self.currentScreenshot : nil

                AIManager.shared.query(
                    image: image,
                    prompt: text,
                    onChunk: { [weak self] chunk in
                        self?.answerPanel?.appendStreamingText(chunk)
                    },
                    onComplete: { [weak self] fullText in
                        self?.answerPanel?.finalizeStreamingBubble()
                        AIManager.shared.conversationHistory.append(
                            ChatMessage(role: "assistant", content: fullText)
                        )
                    },
                    onError: { [weak self] error in
                        print("Ghost: follow-up error = \(error)")
                        self?.answerPanel?.appendStreamingText("⚠️ \(error)")
                        self?.answerPanel?.finalizeStreamingBubble()
                    }
                )
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

                // show() already called startNewAssistantBubble() — stream straight in
                AIManager.shared.query(
                    image: image,
                    prompt: "Answer this.",
                    onChunk: { [weak self] chunk in
                        self?.answerPanel?.appendStreamingText(chunk)
                    },
                    onComplete: { [weak self] fullText in
                        print("Ghost: answer complete")
                        self?.answerPanel?.finalizeStreamingBubble()
                        AIManager.shared.conversationHistory.append(
                            ChatMessage(role: "assistant", content: fullText)
                        )
                    },
                    onError: { [weak self] error in
                        print("Ghost: error = \(error)")
                        self?.answerPanel?.appendStreamingText("⚠️ \(error)")
                        self?.answerPanel?.finalizeStreamingBubble()
                    }
                )
            }
        }

        self.contentView = selectionView
        self.makeFirstResponder(selectionView)
        self.orderFrontRegardless()

        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { DispatchQueue.main.async { self?.deactivate() } }
        }

        escMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                DispatchQueue.main.async { self?.deactivate() }
                return nil
            }
            return event
        }

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

    func deactivate() {
        safetyTimer?.invalidate()
        safetyTimer = nil

        if let observer = deactivateObserver {
            NotificationCenter.default.removeObserver(observer)
            deactivateObserver = nil
        }
        if let monitor = escMonitor     { NSEvent.removeMonitor(monitor); escMonitor     = nil }
        if let monitor = escMonitorLocal { NSEvent.removeMonitor(monitor); escMonitorLocal = nil }
        self.contentView = nil
        self.orderOut(nil)
    }
}
