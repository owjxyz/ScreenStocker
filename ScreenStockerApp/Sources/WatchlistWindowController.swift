import AppKit

final class WatchlistWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let preferences: StockerPreferences
    private var symbols: [String]
    private var searchResults: [StockSymbolSearchResult] = []

    private let tableView = NSTableView()
    private let inputField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let addButton = NSButton(title: "Add", target: nil, action: nil)
    private let searchButton = NSButton(title: "Search", target: nil, action: nil)
    private let saveAPIKeyButton = NSButton(title: "Save Key", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove", target: nil, action: nil)
    private let addDemoButton = NSButton(title: "Add Demo Set", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    init(preferences: StockerPreferences) {
        self.preferences = preferences
        self.symbols = preferences.registeredSymbols

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
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
        textField.frame = NSRect(x: 12, y: 0, width: 440, height: 24)
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
        titleLabel.frame = NSRect(x: 24, y: 394, width: 260, height: 24)

        let hintLabel = NSTextField(labelWithString: "Add a Twelve Data API key, search symbols, then choose them from the screen saver dropdown.")
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.frame = NSRect(x: 24, y: 372, width: 472, height: 18)

        let apiKeyLabel = NSTextField(labelWithString: "Twelve Data API Key")
        apiKeyLabel.frame = NSRect(x: 24, y: 332, width: 160, height: 20)

        apiKeyField.placeholderString = "Paste API key"
        apiKeyField.stringValue = preferences.twelveDataAPIKey
        apiKeyField.frame = NSRect(x: 24, y: 304, width: 354, height: 26)
        apiKeyField.target = self
        apiKeyField.action = #selector(saveAPIKey)

        saveAPIKeyButton.target = self
        saveAPIKeyButton.action = #selector(saveAPIKey)
        saveAPIKeyButton.frame = NSRect(x: 390, y: 302, width: 106, height: 30)

        inputField.placeholderString = "AAPL"
        inputField.frame = NSRect(x: 24, y: 252, width: 250, height: 26)
        inputField.target = self
        inputField.action = #selector(addSymbol)

        addButton.target = self
        addButton.action = #selector(addSymbol)
        addButton.frame = NSRect(x: 286, y: 250, width: 88, height: 30)

        searchButton.target = self
        searchButton.action = #selector(searchSymbols)
        searchButton.frame = NSRect(x: 386, y: 250, width: 110, height: 30)

        let scrollView = NSScrollView(frame: NSRect(x: 24, y: 72, width: 472, height: 164))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SymbolColumn"))
        column.title = "Symbol"
        column.width = 460
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 28
        scrollView.documentView = tableView

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.frame = NSRect(x: 24, y: 48, width: 320, height: 18)

        addDemoButton.target = self
        addDemoButton.action = #selector(addDemoSet)
        addDemoButton.frame = NSRect(x: 24, y: 20, width: 126, height: 30)

        removeButton.target = self
        removeButton.action = #selector(removeSelectedSymbol)
        removeButton.frame = NSRect(x: 378, y: 20, width: 118, height: 30)
        removeButton.isEnabled = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(hintLabel)
        contentView.addSubview(apiKeyLabel)
        contentView.addSubview(apiKeyField)
        contentView.addSubview(saveAPIKeyButton)
        contentView.addSubview(inputField)
        contentView.addSubview(addButton)
        contentView.addSubview(searchButton)
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

    @objc private func searchSymbols() {
        let query = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        guard !preferences.twelveDataAPIKey.isEmpty else {
            updateStatus(message: "Add and save a Twelve Data API key before searching.")
            return
        }

        searchButton.isEnabled = false
        updateStatus(message: "Searching Twelve Data...")
        TwelveDataSymbolSearchProvider(apiKey: preferences.twelveDataAPIKey).searchSymbols(matching: query) { [weak self] results in
            DispatchQueue.main.async {
                guard let self else { return }
                self.searchButton.isEnabled = true
                self.searchResults = results
                self.showSearchResults()
            }
        }
    }

    @objc private func saveAPIKey() {
        preferences.twelveDataAPIKey = apiKeyField.stringValue
        apiKeyField.stringValue = preferences.twelveDataAPIKey
        updateStatus(message: preferences.twelveDataAPIKey.isEmpty ? "Cleared Twelve Data API key." : "Saved Twelve Data API key.")
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

    private func updateStatus(message: String) {
        statusLabel.stringValue = message
    }

    private func showSearchResults() {
        guard !searchResults.isEmpty else {
            updateStatus(message: "No matching symbols found.")
            return
        }

        let menu = NSMenu()
        for result in searchResults {
            let item = NSMenuItem(title: result.displayTitle, action: #selector(addSearchResult(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = result.symbol
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: searchButton.bounds.height + 4), in: searchButton)
        updateStatus(message: "\(searchResults.count) result(s) found.")
    }

    @objc private func addSearchResult(_ sender: NSMenuItem) {
        guard let symbol = sender.representedObject as? String else { return }
        inputField.stringValue = symbol
        addSymbol()
    }
}
