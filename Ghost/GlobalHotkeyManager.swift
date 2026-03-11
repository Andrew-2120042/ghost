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
        print("Ghost: start() called, AXTrusted=\(AXIsProcessTrusted())")
        guard AXIsProcessTrusted() else {
            print("Ghost: accessibility not granted — prompting and polling")
            // Trigger macOS "wants to control this computer" dialog
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(opts as CFDictionary)
            // Also show our own alert with a direct link to Settings
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: NSNotification.Name("GhostNeedsAccessibility"), object: nil)
            }
            registerLocalMonitor()
            startPermissionPolling()
            return
        }

        print("Ghost: creating event tap...")
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
                print("Ghost: keyevent keyCode=\(keyCode) flags=\(flags.rawValue)")
                let cmdShift: CGEventFlags = [.maskCommand, .maskShift]

                // Cmd+Shift+Space (keycode 49)
                if keyCode == 49 && flags.intersection(cmdShift) == cmdShift {
                    print("Ghost: hotkey detected keyCode=\(keyCode)")
                    DispatchQueue.main.async { manager.onHotkey?() }
                    return nil // consume the event
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        )

        if eventTap != nil {
            print("Ghost: event tap CREATED successfully")
        } else {
            print("Ghost: event tap FAILED — nil")
        }

        guard let tap = eventTap else {
            print("Ghost: event tap NIL even with AXTrusted — registering fallback local monitor")
            registerLocalMonitor()
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource!, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Watch for tap becoming invalid so we can restart rather than freeze keyboard
        CFMachPortSetInvalidationCallBack(tap) { _, _ in
            DispatchQueue.main.async {
                print("Ghost: event tap invalidated — restarting")
                GlobalHotkeyManager.shared.restart()
            }
        }

        print("Ghost: global hotkey active (Cmd+Shift+Space)")
    }

    private func startPermissionPolling() {
        guard permissionPollTimer == nil else { return }
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if AXIsProcessTrusted() {
                print("Ghost: accessibility granted — creating event tap")
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
            print("Ghost: raw keyevent \(keyCode)")
            if keyCode == 49 && flags.contains(.command) && flags.contains(.shift) {
                DispatchQueue.main.async { self?.onHotkey?() }
                return nil
            }
            return event
        }
        print("Ghost: fallback local monitor registered")
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        eventTap = nil
        runLoopSource = nil
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        permissionPollTimer?.invalidate(); permissionPollTimer = nil
    }

    func restart() {
        print("Ghost: restarting hotkey manager...")
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
