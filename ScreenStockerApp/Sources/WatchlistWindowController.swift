import AppKit

final class WatchlistWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let preferences: StockerPreferences
    private var symbols: [String]

    private let tableView = NSTableView()
    private let inputField = NSTextField()
    private let addButton = NSButton(title: "Add", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove", target: nil, action: nil)
    private let addDemoButton = NSButton(title: "Add Demo Set", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    init(preferences: StockerPreferences) {
        self.preferences = preferences
        self.symbols = preferences.registeredSymbols

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScreenStocker Registration Demo"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
        updateStatus()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        symbols.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("SymbolCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? NSTableCellView()

        let textField = cell.textField ?? NSTextField(labelWithString: "")
        textField.frame = NSRect(x: 12, y: 0, width: 340, height: 24)
        textField.autoresizingMask = [.width]
        textField.stringValue = symbols[row]

        if cell.textField == nil {
            cell.identifier = identifier
            cell.addSubview(textField)
            cell.textField = textField
        }

        return cell
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "Register Watchlist Symbols")
        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.frame = NSRect(x: 24, y: 314, width: 260, height: 24)

        let hintLabel = NSTextField(labelWithString: "Add symbols here, then choose them from the screen saver dropdown.")
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.frame = NSRect(x: 24, y: 292, width: 372, height: 18)

        inputField.placeholderString = "AAPL"
        inputField.frame = NSRect(x: 24, y: 252, width: 274, height: 26)
        inputField.target = self
        inputField.action = #selector(addSymbol)

        addButton.target = self
        addButton.action = #selector(addSymbol)
        addButton.frame = NSRect(x: 310, y: 250, width: 86, height: 30)

        let scrollView = NSScrollView(frame: NSRect(x: 24, y: 72, width: 372, height: 164))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SymbolColumn"))
        column.title = "Symbol"
        column.width = 360
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 28
        scrollView.documentView = tableView

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.frame = NSRect(x: 24, y: 48, width: 220, height: 18)

        addDemoButton.target = self
        addDemoButton.action = #selector(addDemoSet)
        addDemoButton.frame = NSRect(x: 24, y: 20, width: 126, height: 30)

        removeButton.target = self
        removeButton.action = #selector(removeSelectedSymbol)
        removeButton.frame = NSRect(x: 278, y: 20, width: 118, height: 30)
        removeButton.isEnabled = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(hintLabel)
        contentView.addSubview(inputField)
        contentView.addSubview(addButton)
        contentView.addSubview(scrollView)
        contentView.addSubview(statusLabel)
        contentView.addSubview(addDemoButton)
        contentView.addSubview(removeButton)
    }

    @objc private func addSymbol() {
        let symbol = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !symbol.isEmpty, !symbols.contains(symbol) else { return }

        symbols.append(symbol)
        saveSymbols()
        inputField.stringValue = ""
        tableView.reloadData()
        updateStatus(savedSymbol: symbol)
    }

    @objc private func removeSelectedSymbol() {
        let selectedRow = tableView.selectedRow
        guard symbols.indices.contains(selectedRow) else { return }

        let removedSymbol = symbols.remove(at: selectedRow)
        if preferences.selectedSymbol == removedSymbol {
            preferences.selectedSymbol = nil
        }
        saveSymbols()
        tableView.reloadData()
        updateStatus(removedSymbol: removedSymbol)
    }

    @objc private func addDemoSet() {
        for symbol in ["AAPL", "MSFT", "NVDA", "TSLA"] where !symbols.contains(symbol) {
            symbols.append(symbol)
        }
        saveSymbols()
        tableView.reloadData()
        updateStatus()
    }

    private func saveSymbols() {
        preferences.registeredSymbols = symbols
        symbols = preferences.registeredSymbols
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = symbols.indices.contains(tableView.selectedRow)
    }

    private func updateStatus(savedSymbol: String? = nil, removedSymbol: String? = nil) {
        if let savedSymbol {
            statusLabel.stringValue = "Saved \(savedSymbol). \(symbols.count) symbol(s) registered."
        } else if let removedSymbol {
            statusLabel.stringValue = "Removed \(removedSymbol). \(symbols.count) symbol(s) registered."
        } else {
            statusLabel.stringValue = "\(symbols.count) symbol(s) registered."
        }
    }
}
