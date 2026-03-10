import Cocoa

class ReadyViewController: NSViewController {

    var onComplete: (() -> Void)?

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
        // Checkmark SF Symbol
        let imageView = NSImageView()
        if let img = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)
            imageView.image = img.withSymbolConfiguration(config)
        }
        imageView.contentTintColor = .systemGreen
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 72).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 72).isActive = true

        // Title
        let title = NSTextField(labelWithString: "You're ready")
        title.font = NSFont.boldSystemFont(ofSize: 28)
        title.textColor = .white
        title.alignment = .center

        // Description
        let desc = NSTextField(wrappingLabelWithString: "Press Cmd+Shift+Space from anywhere to activate Ghost.\nDraw a box around anything — Ghost answers instantly.")
        desc.font = NSFont.systemFont(ofSize: 14)
        desc.textColor = NSColor.white.withAlphaComponent(0.6)
        desc.alignment = .center
        desc.translatesAutoresizingMaskIntoConstraints = false
        desc.widthAnchor.constraint(equalToConstant: 340).isActive = true

        // Hotkey pill
        let pill = NSTextField(labelWithString: "⌘  ⇧  Space")
        pill.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        pill.textColor = .white
        pill.alignment = .center
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(white: 0.2, alpha: 1).cgColor
        pill.layer?.cornerRadius = 8
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.widthAnchor.constraint(equalToConstant: 160).isActive = true
        pill.heightAnchor.constraint(equalToConstant: 36).isActive = true

        // Start button
        let button = makeButton("Start Using Ghost", action: #selector(startAction))

        // Stack
        let stack = NSStackView(views: [imageView, title, desc, pill, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 380),
            button.widthAnchor.constraint(equalToConstant: 200),
            button.heightAnchor.constraint(equalToConstant: 44)
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

    @objc private func startAction() {
        onComplete?()
    }
}
