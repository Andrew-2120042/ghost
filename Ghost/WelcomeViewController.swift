import Cocoa

class WelcomeViewController: NSViewController {

    var onContinue: (() -> Void)?

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
        // Ghost emoji
        let emoji = NSTextField(labelWithString: "👻")
        emoji.font = NSFont.systemFont(ofSize: 56)
        emoji.alignment = .center

        // Title
        let title = NSTextField(labelWithString: "Ghost")
        title.font = NSFont.boldSystemFont(ofSize: 34)
        title.textColor = .white
        title.alignment = .center

        // Subtitle
        let subtitle = NSTextField(labelWithString: "Invisible AI on any screen")
        subtitle.font = NSFont.systemFont(ofSize: 15)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.5)
        subtitle.alignment = .center

        // Spacer between subtitle and bullets
        let spacer1 = NSView()
        spacer1.translatesAutoresizingMaskIntoConstraints = false
        spacer1.heightAnchor.constraint(equalToConstant: 16).isActive = true

        // Bullet points
        let bulletTexts = [
            "· Invisible to Zoom, Teams & all recorders",
            "· Select anything — get instant AI answers",
            "· Activated with Cmd+Shift+Space anywhere"
        ]
        let bulletStack = NSStackView()
        bulletStack.orientation = .vertical
        bulletStack.alignment = .leading
        bulletStack.spacing = 8
        for text in bulletTexts {
            let label = NSTextField(labelWithString: text)
            label.font = NSFont.systemFont(ofSize: 14)
            label.textColor = NSColor.white.withAlphaComponent(0.7)
            bulletStack.addArrangedSubview(label)
        }

        // Spacer before button
        let spacer2 = NSView()
        spacer2.translatesAutoresizingMaskIntoConstraints = false
        spacer2.heightAnchor.constraint(equalToConstant: 16).isActive = true

        // Get Started button
        let button = makeButton("Get Started", action: #selector(continueAction))

        // License note
        let note = NSTextField(labelWithString: "Requires a Ghost license key")
        note.font = NSFont.systemFont(ofSize: 12)
        note.textColor = NSColor.white.withAlphaComponent(0.3)
        note.alignment = .center

        // Main stack
        let stack = NSStackView(views: [emoji, title, subtitle, spacer1, bulletStack, spacer2, button, note])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(4, after: emoji)
        stack.setCustomSpacing(4, after: title)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 60),
            stack.widthAnchor.constraint(equalToConstant: 360),
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

    @objc private func continueAction() {
        onContinue?()
    }
}
