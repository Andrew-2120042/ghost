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
        // FIX 2: clear old keychain items that may cause password popup
        if !UserDefaults.standard.bool(forKey: "ghost.keychain.migrated") {
            KeychainManager.shared.delete(service: "com.ghost.app.license")
            UserDefaults.standard.set(true, forKey: "ghost.keychain.migrated")
        }

        let key = KeychainManager.shared.load(service: "com.ghost.app.license") ?? ""
        AIManager.shared.licenseKey = key

        NSApp.setActivationPolicy(.accessory)

        ghostWindow = GhostWindow()

        GlobalHotkeyManager.shared.onHotkey = { [weak self] in
            self?.ghostWindow?.activate()
        }
        GlobalHotkeyManager.shared.start()

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
                if app.bundleIdentifier == Bundle.main.bundleIdentifier {
                    GlobalHotkeyManager.shared.restart()
                }
            }
        }

        // Panel hidden/restored — update menu bar icon
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("GhostPanelHidden"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let button = self?.statusItem?.button {
                button.image = NSImage(systemSymbolName: "eye.slash.fill", accessibilityDescription: "Ghost — content waiting")
                button.image?.isTemplate = true
                button.toolTip = "Ghost — tap hotkey to restore"
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("GhostPanelRestored"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let button = self?.statusItem?.button {
                button.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Ghost")
                button.image?.isTemplate = true
                button.toolTip = "Ghost — Press Cmd+Shift+Space"
            }
        }

        // FIX 5: check backend health
        checkBackendHealth()
    }

    // MARK: - FIX 5: Backend health check

    func checkBackendHealth() {
        guard let url = URL(string: "http://localhost:3000/health") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            DispatchQueue.main.async {
                if error != nil || data == nil {
                    self?.statusItem?.button?.toolTip = "⚠️ Server offline — answers won't work"
                    if let item = self?.statusItem?.menu?.item(withTag: 100) {
                        item.title = "⚠️ Server offline"
                    }
                } else {
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
            title: "Reset Panel Position",
            action: #selector(resetPanelPosition),
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

    @objc func resetPanelPosition() {
        UserDefaults.standard.removeObject(forKey: "ghost.panel.position")
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
