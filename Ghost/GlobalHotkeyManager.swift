import Cocoa

final class GlobalHotkeyManager {

    static let shared = GlobalHotkeyManager()
    private init() {}

    var onHotkey: (() -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        print("Ghost: start() called, AXTrusted=\(AXIsProcessTrusted())")
        guard AXIsProcessTrusted() else {
            print("Ghost: event tap is NIL — accessibility not granted or tap failed")
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

        guard let tap = eventTap else { return }

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

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
    }

    func restart() {
        print("Ghost: restarting hotkey manager...")
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.start()
        }
    }
}
