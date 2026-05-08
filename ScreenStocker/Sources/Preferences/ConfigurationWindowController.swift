import AppKit

final class ConfigurationWindowController: NSWindowController {
    private let preferences: StockerPreferences
    private let symbolPopup = NSPopUpButton()
    private let emptyLabel = NSTextField(labelWithString: "No registered symbols. Open ScreenStocker to add symbols.")

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
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: StockerPreferences.didChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let label = NSTextField(labelWithString: "Display")
        label.frame = NSRect(x: 24, y: 92, width: 120, height: 20)

        symbolPopup.frame = NSRect(x: 24, y: 58, width: 372, height: 28)
        reloadSymbols()

        emptyLabel.frame = NSRect(x: 24, y: 36, width: 372, height: 18)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 11)
        emptyLabel.isHidden = !preferences.registeredSymbols.isEmpty

        let doneButton = NSButton(title: "Done", target: self, action: #selector(done))
        doneButton.frame = NSRect(x: 316, y: 20, width: 80, height: 28)
        doneButton.bezelStyle = .rounded

        contentView.addSubview(label)
        contentView.addSubview(symbolPopup)
        contentView.addSubview(emptyLabel)
        contentView.addSubview(doneButton)
    }

    func reloadSymbols() {
        symbolPopup.removeAllItems()
        symbolPopup.addItem(withTitle: "First registered symbol")

        for symbol in preferences.registeredSymbols {
            symbolPopup.addItem(withTitle: symbol)
        }

        if let selectedSymbol = preferences.selectedSymbol {
            symbolPopup.selectItem(withTitle: selectedSymbol)
        } else {
            symbolPopup.selectItem(at: 0)
        }

        emptyLabel.isHidden = !preferences.registeredSymbols.isEmpty
    }

    @objc private func done() {
        if symbolPopup.indexOfSelectedItem <= 0 {
            preferences.selectedSymbol = nil
        } else {
            preferences.selectedSymbol = symbolPopup.titleOfSelectedItem
        }
        window?.sheetParent?.endSheet(window!)
    }

    @objc private func preferencesDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.reloadSymbols()
        }
    }
}
