import Cocoa

class LicenseViewController: NSViewController, NSTextFieldDelegate {

    var onComplete: (() -> Void)?

    private var textField: NSTextField!
    private var activateButton: NSButton!
    private var spinner: NSProgressIndicator!
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

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textField)
    }

    private func setupUI() {
        // Title
        let title = NSTextField(labelWithString: "Enter your license key")
        title.font = NSFont.boldSystemFont(ofSize: 22)
        title.textColor = .white
        title.alignment = .center

        // Subtitle
        let subtitle = NSTextField(labelWithString: "You received this after purchase")
        subtitle.font = NSFont.systemFont(ofSize: 13)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.4)
        subtitle.alignment = .center

        // Text field container
        let fieldContainer = NSView()
        fieldContainer.wantsLayer = true
        fieldContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        fieldContainer.layer?.cornerRadius = 10
        fieldContainer.translatesAutoresizingMaskIntoConstraints = false

        textField = NSTextField()
        textField.isEditable = true
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.textColor = .white
        textField.font = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        textField.focusRingType = .none
        textField.delegate = self
        textField.placeholderAttributedString = NSAttributedString(
            string: "GHOST-XXXX-XXXX-XXXX",
            attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.3),
                         .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)]
        )
        textField.translatesAutoresizingMaskIntoConstraints = false
        fieldContainer.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor, constant: 14),
            textField.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor, constant: -14),
            textField.centerYAnchor.constraint(equalTo: fieldContainer.centerYAnchor)
        ])
        view.addSubview(fieldContainer)

        // Activate button
        activateButton = makeButton("Activate", action: #selector(activateKey))
        activateButton.isEnabled = false

        // Spinner
        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        // Status label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 13)
        statusLabel.textColor = .systemGreen
        statusLabel.alignment = .center

        // Stack
        let stack = NSStackView(views: [title, subtitle, fieldContainer, activateButton, spinner, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 380),
            fieldContainer.widthAnchor.constraint(equalToConstant: 380),
            fieldContainer.heightAnchor.constraint(equalToConstant: 44),
            activateButton.widthAnchor.constraint(equalToConstant: 200),
            activateButton.heightAnchor.constraint(equalToConstant: 44)
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

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        activateButton.isEnabled = textField.stringValue.count >= 8
    }

    // MARK: - Actions

    @objc private func activateKey() {
        let key = textField.stringValue.trimmingCharacters(in: .whitespaces).uppercased()

        spinner.startAnimation(nil)
        activateButton.isEnabled = false
        statusLabel.stringValue = ""

        AIManager.shared.validateLicense(key: key) { valid, days, error in
            self.spinner.stopAnimation(nil)
            self.activateButton.isEnabled = true

            if valid {
                KeychainManager.shared.save(key: key, service: "com.ghost.app.license")
                AIManager.shared.licenseKey = key
                self.statusLabel.textColor = .systemGreen
                self.statusLabel.stringValue = "✓ \(days) days remaining"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.onComplete?() }
            } else {
                self.statusLabel.textColor = .systemRed
                self.statusLabel.stringValue = error ?? "Invalid key"
            }
        }
    }
}
