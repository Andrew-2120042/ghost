import Cocoa
import CoreGraphics

class AppDelegate: NSObject, NSApplicationDelegate {

    var ghostWindow: GhostWindow?
    var onboardingWindowController: OnboardingWindowController?
    var statusItem: NSStatusItem?

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupAppIcon() // FIX 1: set icon before anything else

        // Dev reset: Cmd+Shift+D clears onboarding state
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains([.command, .shift])
               && event.charactersIgnoringModifiers == "d" {
                UserDefaults.standard.removeObject(forKey: "ghost.onboarding.complete")
                KeychainManager.shared.delete(service: "com.ghost.app.license")
                print("Ghost: onboarding reset — relaunch to see onboarding")
            }
            return event
        }

        if OnboardingState.isComplete {
            finishLaunch()
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            showOnboarding()
        }
    }

    // MARK: - FIX 1: App icon

    func setupAppIcon() {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor(white: 0.1, alpha: 1).setFill()
        NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: size),
            xRadius: 100,
            yRadius: 100
        ).fill()

        let emoji = "👻" as NSString
        let font = NSFont.systemFont(ofSize: 300)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let strSize = emoji.size(withAttributes: attrs)
        emoji.draw(
            at: NSPoint(
                x: (size.width - strSize.width) / 2,
                y: (size.height - strSize.height) / 2
            ),
            withAttributes: attrs
        )

        image.unlockFocus()
        NSApp.applicationIconImage = image
    }

    // MARK: - Onboarding

    func showOnboarding() {
        let wc = OnboardingWindowController()
        onboardingWindowController = wc

        let welcome = WelcomeViewController()
        welcome.onContinue = { [weak wc, weak self] in
            let license = LicenseViewController()
            license.onComplete = { [weak wc, weak self] in
                let accessibility = AccessibilityViewController()
                accessibility.onComplete = { [weak wc, weak self] in
                    let ready = ReadyViewController()
                    ready.onComplete = { [weak wc, weak self] in
                        OnboardingState.markComplete()
                        wc?.close()
                        self?.finishLaunch()
                    }
                    wc?.transition(to: ready)
                }
                wc?.transition(to: accessibility)
            }
            wc?.transition(to: license)
        }

        wc.window?.contentViewController = welcome
        wc.window?.center()
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Post-onboarding launch

    func finishLaunch() {
        print("Ghost: finishLaunch() called")

        // FIX 2: clear old keychain items that may cause password popup
        if !UserDefaults.standard.bool(forKey: "ghost.keychain.migrated") {
            KeychainManager.shared.delete(service: "com.ghost.app.license")
            UserDefaults.standard.set(true, forKey: "ghost.keychain.migrated")
        }

        var key = KeychainManager.shared.load(service: "com.ghost.app.license") ?? ""
        if key.isEmpty {
            // No license key saved — use debug key so the app works
            key = "GHOST-DEBUG"
            KeychainManager.shared.save(key: key, service: "com.ghost.app.license")
            print("Ghost: no license key found — saved GHOST-DEBUG")
        }
        print("Ghost: license key loaded = \(key)")
        AIManager.shared.licenseKey = key

        NSApp.setActivationPolicy(.accessory)

        ghostWindow = GhostWindow()

        GlobalHotkeyManager.shared.onHotkey = { [weak self] in
            print("Ghost: hotkey fired — activating")
            self?.ghostWindow?.activate()
        }
        print("Ghost: AXIsProcessTrusted = \(AXIsProcessTrusted())")
        print("Ghost: starting hotkey manager...")
        GlobalHotkeyManager.shared.start()
        print("Ghost: hotkey manager started")

        setupMenuBar()

        // FIX 3: handle screen permission failure notification
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("GhostNeedsScreenPermission"),
            object: nil,
            queue: .main
        ) { _ in
            let alert = NSAlert()
            alert.messageText = "Screen Recording Required"
            alert.informativeText = "Please enable Ghost in:\nSystem Settings → Privacy & Security → Screen Recording\n\nThen relaunch Ghost."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                )
            }
        }

        // FIX 4: restart hotkey tap when Ghost becomes active (tap can be revoked by macOS)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                print("Focus moved to: \(app.localizedName ?? "unknown")")
                if app.bundleIdentifier == Bundle.main.bundleIdentifier {
                    GlobalHotkeyManager.shared.restart()
                }
            }
        }

        // FIX 5: check backend health
        checkBackendHealth()

        print("Ghost: ready — Cmd+Shift+Space to activate")
    }

    // MARK: - FIX 5: Backend health check

    func checkBackendHealth() {
        guard let url = URL(string: "http://localhost:3000/health") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            DispatchQueue.main.async {
                if error != nil || data == nil {
                    print("Ghost: ⚠️ Backend not running!")
                    print("Ghost: Start it with: cd ghost-server && node server.js")
                    self?.statusItem?.button?.toolTip = "⚠️ Server offline — answers won't work"
                    if let item = self?.statusItem?.menu?.item(withTag: 100) {
                        item.title = "⚠️ Server offline"
                    }
                } else {
                    print("Ghost: ✓ Backend connected")
                    self?.statusItem?.button?.toolTip = "Ghost — Press Cmd+Shift+Space"
                    if let item = self?.statusItem?.menu?.item(withTag: 100) {
                        item.title = "✓ Server connected"
                    }
                }
            }
        }.resume()
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Ghost")
            button.image?.isTemplate = true
            button.toolTip = "Ghost — Press Cmd+Shift+Space"
        }

        let menu = NSMenu()

        // FIX 5: server status item at top
        let statusMenuItem = NSMenuItem(title: "Checking server...", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.insertItem(statusMenuItem, at: 0)
        menu.insertItem(NSMenuItem.separator(), at: 1)

        menu.addItem(NSMenuItem(
            title: "Activate Ghost",
            action: #selector(activateFromMenu),
            keyEquivalent: ""
        ))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Reset Onboarding",
            action: #selector(resetOnboarding),
            keyEquivalent: ""
        ))

        menu.addItem(NSMenuItem.separator())

        let queriesItem = NSMenuItem(title: "Queries: loading...", action: nil, keyEquivalent: "")
        queriesItem.tag = 99
        menu.addItem(queriesItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit Ghost",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem?.menu = menu
    }

    // FIX 6: small delay so menu closes before overlay activates
    @objc func activateFromMenu() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.ghostWindow?.activate()
        }
    }

    @objc func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: "ghost.onboarding.complete")
        KeychainManager.shared.delete(service: "com.ghost.app.license")
        let url = Bundle.main.bundleURL
        Process.launchedProcess(launchPath: "/usr/bin/open", arguments: [url.path])
        NSApp.terminate(nil)
    }
}

// MARK: - Onboarding state

enum OnboardingState {
    static var isComplete: Bool {
        UserDefaults.standard.bool(forKey: "ghost.onboarding.complete")
    }
    static func markComplete() {
        UserDefaults.standard.set(true, forKey: "ghost.onboarding.complete")
    }
}
