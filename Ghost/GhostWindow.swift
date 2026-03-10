import Cocoa

class GhostWindow: NSPanel {

    var answerPanel: AnswerPanel?
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
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func activate() {
        print("Ghost: activate() called")
        if answerPanel == nil {
            answerPanel = AnswerPanel()
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

                print("Ghost: image captured, sending to AI...")
                let screen = NSScreen.main ?? NSScreen.screens[0]
                self.answerPanel?.show(near: rect, onScreen: screen)
                self.deactivate()

                AIManager.shared.query(
                    image: image,
                    onChunk: { [weak self] chunk in
                        print("Ghost: chunk received = \(chunk)")
                        self?.answerPanel?.appendText(chunk)
                    },
                    onComplete: { [weak self] in
                        print("Ghost: stream complete")
                        self?.answerPanel?.startDismissTimer()
                    },
                    onError: { [weak self] error in
                        print("Ghost: error = \(error)")
                        self?.answerPanel?.appendText("⚠️ \(error)")
                        self?.answerPanel?.startDismissTimer()
                    }
                )
            }
        }

        self.contentView = selectionView
        self.makeFirstResponder(selectionView)
        self.orderFrontRegardless()

        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                DispatchQueue.main.async { self?.deactivate() }
            }
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

        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
        if let monitor = escMonitorLocal {
            NSEvent.removeMonitor(monitor)
            escMonitorLocal = nil
        }
        self.contentView = nil
        self.orderOut(nil)
    }
}
