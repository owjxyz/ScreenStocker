import AppKit

final class ConfigurationWindowController: NSWindowController {
    private let preferences: StockerPreferences
    private let symbolsField = NSTextField()

    init(preferences: StockerPreferences) {
        self.preferences = preferences

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 150),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "ScreenStocker Settings"
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let label = NSTextField(labelWithString: "Symbols")
        label.frame = NSRect(x: 24, y: 92, width: 120, height: 20)

        symbolsField.stringValue = preferences.symbols.joined(separator: ",")
        symbolsField.frame = NSRect(x: 24, y: 60, width: 372, height: 24)

        let doneButton = NSButton(title: "Done", target: self, action: #selector(done))
        doneButton.frame = NSRect(x: 316, y: 20, width: 80, height: 28)
        doneButton.bezelStyle = .rounded

        contentView.addSubview(label)
        contentView.addSubview(symbolsField)
        contentView.addSubview(doneButton)
    }

    @objc private func done() {
        preferences.symbols = symbolsField.stringValue.split(separator: ",").map(String.init)
        window?.sheetParent?.endSheet(window!)
    }
}

