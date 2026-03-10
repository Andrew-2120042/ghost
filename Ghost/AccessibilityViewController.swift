import Cocoa

class AccessibilityViewController: NSViewController {

    var onComplete: (() -> Void)?
    private var statusLabel: NSTextField!

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 520))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(white: 0.09, alpha: 1).cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        // Lock emoji
        let lock = NSTextField(labelWithString: "🔐")
        lock.font = NSFont.systemFont(ofSize: 44)
        lock.alignment = .center

        // Title
        let title = NSTextField(labelWithString: "Enable Global Hotkey")
        title.font = NSFont.boldSystemFont(ofSize: 22)
        title.textColor = .white
        title.alignment = .center

        // Description
        let desc = NSTextField(wrappingLabelWithString: "Ghost needs Accessibility access to detect Cmd+Shift+Space from any app.")
        desc.font = NSFont.systemFont(ofSize: 14)
        desc.textColor = NSColor.white.withAlphaComponent(0.6)
        desc.alignment = .center
        desc.translatesAutoresizingMaskIntoConstraints = false
        desc.widthAnchor.constraint(equalToConstant: 340).isActive = true

        // Open Settings button
        let openButton = makeButton("Open Accessibility Settings", action: #selector(openSettings))

        // I've enabled it button (outline style)
        let checkButton = NSButton(title: "I've enabled it", target: self, action: #selector(checkPermission))
        checkButton.isBordered = true
        checkButton.bezelStyle = .rounded
        checkButton.contentTintColor = .white
        checkButton.font = NSFont.systemFont(ofSize: 14)

        // Status label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 13)
        statusLabel.textColor = .systemGreen
        statusLabel.alignment = .center

        // Skip link
        let skipButton = NSButton(title: "Skip", target: self, action: #selector(skip))
        skipButton.isBordered = false
        skipButton.contentTintColor = NSColor.white.withAlphaComponent(0.3)
        skipButton.font = NSFont.systemFont(ofSize: 12)

        // Stack
        let stack = NSStackView(views: [lock, title, desc, openButton, checkButton, statusLabel, skipButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 380),
            openButton.widthAnchor.constraint(equalToConstant: 260),
            openButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 22
        button.layer?.backgroundColor = NSColor.white.cgColor
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.black,
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold)
            ]
        )
        return button
    }

    @objc private func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func checkPermission() {
        if AXIsProcessTrusted() {
            statusLabel.textColor = .systemGreen
            statusLabel.stringValue = "✓ Permission granted"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.onComplete?() }
        } else {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "Not enabled yet — check the list in System Settings"
        }
    }

    @objc private func skip() {
        onComplete?()
    }
}
