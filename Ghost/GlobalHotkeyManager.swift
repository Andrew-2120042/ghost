import Cocoa

final class GlobalHotkeyManager {

    static let shared = GlobalHotkeyManager()
    private init() {}

    var onHotkey: (() -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var permissionPollTimer: Timer?

    func start() {
        guard AXIsProcessTrusted() else {
            // Show macOS system dialog (only appears once; silent if already granted)
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(opts as CFDictionary)
            registerLocalMonitor()
            startPermissionPolling()
            return
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let manager = Unmanaged<GlobalHotkeyManager>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let cmdShift: CGEventFlags = [.maskCommand, .maskShift]

                // Cmd+Shift+Space (keycode 49)
                if keyCode == 49 && flags.intersection(cmdShift) == cmdShift {
                    DispatchQueue.main.async { manager.onHotkey?() }
                    return nil // consume the event
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            registerLocalMonitor()
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource!, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Watch for tap becoming invalid so we can restart rather than freeze keyboard
        CFMachPortSetInvalidationCallBack(tap) { _, _ in
            DispatchQueue.main.async {
                GlobalHotkeyManager.shared.restart()
            }
        }

    }

    private func startPermissionPolling() {
        guard permissionPollTimer == nil else { return }
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if AXIsProcessTrusted() {
                timer.invalidate()
                self.permissionPollTimer = nil
                if let m = self.localMonitor { NSEvent.removeMonitor(m); self.localMonitor = nil }
                self.start()
            }
        }
    }

    private func registerLocalMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            if keyCode == 49 && flags.contains(.command) && flags.contains(.shift) {
                DispatchQueue.main.async { self?.onHotkey?() }
                return nil
            }
            return event
        }
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        eventTap = nil
        runLoopSource = nil
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        permissionPollTimer?.invalidate(); permissionPollTimer = nil
    }

    func restart() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        eventTap = nil
        runLoopSource = nil
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        permissionPollTimer?.invalidate(); permissionPollTimer = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.start()
        }
    }
}
