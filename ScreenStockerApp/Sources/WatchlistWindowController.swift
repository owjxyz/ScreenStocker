import AppKit

final class WatchlistWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private enum Section {
        case watchlist
        case apiKey
    }

    private let preferences: StockerPreferences
    private let installer = ScreenSaverInstaller()
    private var symbols: [String]
    private var searchResults: [StockSymbolSearchResult] = []
    private var selectedSection: Section = .watchlist

    private let tableView = NSTableView()
    private let inputField = NSTextField()
    private let appKeyField = NSSecureTextField()
    private let appSecretField = NSSecureTextField()
    private let sidebarView = NSView()
    private let watchlistButton = NSButton(title: "Watchlist", target: nil, action: nil)
    private let apiKeyButton = NSButton(title: "API Keys", target: nil, action: nil)
    private let watchlistView = NSView()
    private let apiKeyView = NSView()
    private let addButton = NSButton(title: "Add", target: nil, action: nil)
    private let searchButton = NSButton(title: "Search", target: nil, action: nil)
    private let clearAPIKeyButton = NSButton(title: "Clear Key", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove", target: nil, action: nil)
    private let addDemoButton = NSButton(title: "Add Demo Set", target: nil, action: nil)
    private let applyButton = NSButton(title: "Apply", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    init(preferences: StockerPreferences) {
        self.preferences = preferences
        self.symbols = preferences.registeredSymbols

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScreenStocker"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 420)
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

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = symbols.indices.contains(tableView.selectedRow)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        sidebarView.frame = NSRect(x: 0, y: 0, width: 150, height: 460)
        sidebarView.autoresizingMask = [.height]
        sidebarView.wantsLayer = true
        sidebarView.layer?.backgroundColor = NSColor.windowBackgroundColor
            .blended(withFraction: 0.35, of: .controlBackgroundColor)?
            .cgColor

        let appLabel = NSTextField(labelWithString: "ScreenStocker")
        appLabel.font = .boldSystemFont(ofSize: 14)
        appLabel.frame = NSRect(x: 18, y: 414, width: 116, height: 22)
        appLabel.autoresizingMask = [.minYMargin]

        configureSidebarButton(watchlistButton, action: #selector(showWatchlistSection), y: 364)
        configureSidebarButton(apiKeyButton, action: #selector(showAPIKeySection), y: 326)

        watchlistView.frame = NSRect(x: 174, y: 72, width: 482, height: 354)
        watchlistView.autoresizingMask = [.width, .height]

        apiKeyView.frame = watchlistView.frame
        apiKeyView.autoresizingMask = [.width, .height]

        buildWatchlistSection()
        buildAPIKeySection()

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.frame = NSRect(x: 174, y: 28, width: 330, height: 18)
        statusLabel.autoresizingMask = [.width, .maxYMargin]

        applyButton.target = self
        applyButton.action = #selector(applyChanges)
        applyButton.frame = NSRect(x: 560, y: 20, width: 96, height: 32)
        applyButton.autoresizingMask = [.minXMargin, .maxYMargin]
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"

        sidebarView.addSubview(appLabel)
        sidebarView.addSubview(watchlistButton)
        sidebarView.addSubview(apiKeyButton)

        contentView.addSubview(sidebarView)
        contentView.addSubview(watchlistView)
        contentView.addSubview(apiKeyView)
        contentView.addSubview(statusLabel)
        contentView.addSubview(applyButton)

        selectSection(.watchlist)
    }

    private func configureSidebarButton(_ button: NSButton, action: Selector, y: CGFloat) {
        button.target = self
        button.action = action
        button.frame = NSRect(x: 12, y: y, width: 126, height: 32)
        button.autoresizingMask = [.minYMargin]
        button.bezelStyle = .rounded
        button.setButtonType(.pushOnPushOff)
    }

    private func buildWatchlistSection() {
        let titleLabel = NSTextField(labelWithString: "Watchlist")
        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.frame = NSRect(x: 0, y: 326, width: 260, height: 24)
        titleLabel.autoresizingMask = [.minYMargin]

        let hintLabel = NSTextField(labelWithString: "Search and manage symbols shown in the screen saver dropdown.")
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.frame = NSRect(x: 0, y: 304, width: 472, height: 18)
        hintLabel.autoresizingMask = [.width, .minYMargin]

        inputField.placeholderString = "005930"
        inputField.frame = NSRect(x: 0, y: 258, width: 260, height: 26)
        inputField.autoresizingMask = [.width, .minYMargin]
        inputField.target = self
        inputField.action = #selector(addSymbol)

        addButton.target = self
        addButton.action = #selector(addSymbol)
        addButton.frame = NSRect(x: 272, y: 256, width: 88, height: 30)
        addButton.autoresizingMask = [.minXMargin, .minYMargin]

        searchButton.target = self
        searchButton.action = #selector(searchSymbols)
        searchButton.frame = NSRect(x: 372, y: 256, width: 110, height: 30)
        searchButton.autoresizingMask = [.minXMargin, .minYMargin]

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 46, width: 482, height: 194))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autoresizingMask = [.width, .height]

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SymbolColumn"))
        column.title = "Symbol"
        column.width = 470
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 28
        scrollView.documentView = tableView

        addDemoButton.target = self
        addDemoButton.action = #selector(addDemoSet)
        addDemoButton.frame = NSRect(x: 0, y: 2, width: 126, height: 30)
        addDemoButton.autoresizingMask = [.maxYMargin]

        removeButton.target = self
        removeButton.action = #selector(removeSelectedSymbol)
        removeButton.frame = NSRect(x: 364, y: 2, width: 118, height: 30)
        removeButton.autoresizingMask = [.minXMargin, .maxYMargin]
        removeButton.isEnabled = false

        watchlistView.addSubview(titleLabel)
        watchlistView.addSubview(hintLabel)
        watchlistView.addSubview(inputField)
        watchlistView.addSubview(addButton)
        watchlistView.addSubview(searchButton)
        watchlistView.addSubview(scrollView)
        watchlistView.addSubview(addDemoButton)
        watchlistView.addSubview(removeButton)
    }

    private func buildAPIKeySection() {
        let titleLabel = NSTextField(labelWithString: "API Keys")
        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.frame = NSRect(x: 0, y: 326, width: 260, height: 24)
        titleLabel.autoresizingMask = [.minYMargin]

        let hintLabel = NSTextField(labelWithString: "Manage Korea Investment Open API credentials used for live Korean stock quotes.")
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.frame = NSRect(x: 0, y: 304, width: 472, height: 18)
        hintLabel.autoresizingMask = [.width, .minYMargin]

        let appKeyLabel = NSTextField(labelWithString: "KIS App Key")
        appKeyLabel.frame = NSRect(x: 0, y: 260, width: 160, height: 20)
        appKeyLabel.autoresizingMask = [.minYMargin]

        appKeyField.placeholderString = "Paste App Key"
        appKeyField.stringValue = preferences.koreaInvestmentAppKey
        appKeyField.frame = NSRect(x: 0, y: 230, width: 360, height: 26)
        appKeyField.autoresizingMask = [.width, .minYMargin]
        appKeyField.target = self
        appKeyField.action = #selector(applyChanges)

        let appSecretLabel = NSTextField(labelWithString: "KIS App Secret")
        appSecretLabel.frame = NSRect(x: 0, y: 194, width: 160, height: 20)
        appSecretLabel.autoresizingMask = [.minYMargin]

        appSecretField.placeholderString = "Paste App Secret"
        appSecretField.stringValue = preferences.koreaInvestmentAppSecret
        appSecretField.frame = NSRect(x: 0, y: 164, width: 360, height: 26)
        appSecretField.autoresizingMask = [.width, .minYMargin]
        appSecretField.target = self
        appSecretField.action = #selector(applyChanges)

        clearAPIKeyButton.target = self
        clearAPIKeyButton.action = #selector(clearAPIKey)
        clearAPIKeyButton.frame = NSRect(x: 372, y: 162, width: 110, height: 30)
        clearAPIKeyButton.autoresizingMask = [.minXMargin, .minYMargin]

        let noteLabel = NSTextField(wrappingLabelWithString: "Credentials are stored in Keychain. Leave either field empty and apply to use demo data.")
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.font = .systemFont(ofSize: 12)
        noteLabel.frame = NSRect(x: 0, y: 104, width: 482, height: 40)
        noteLabel.autoresizingMask = [.width, .minYMargin]

        apiKeyView.addSubview(titleLabel)
        apiKeyView.addSubview(hintLabel)
        apiKeyView.addSubview(appKeyLabel)
        apiKeyView.addSubview(appKeyField)
        apiKeyView.addSubview(appSecretLabel)
        apiKeyView.addSubview(appSecretField)
        apiKeyView.addSubview(clearAPIKeyButton)
        apiKeyView.addSubview(noteLabel)
    }

    @objc private func addSymbol() {
        let symbol = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !symbol.isEmpty, !symbols.contains(symbol) else { return }

        symbols.append(symbol)
        inputField.stringValue = ""
        saveWatchlist()
        updateStatus(message: "Added \(symbol). Screen saver dropdown updated.")
    }

    @objc private func searchSymbols() {
        let query = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let credentials = currentCredentials()
        guard credentials.isConfigured else {
            updateStatus(message: "Add KIS credentials before searching.")
            return
        }

        searchButton.isEnabled = false
        updateStatus(message: "Looking up KIS symbol...")
        KoreaInvestmentSymbolSearchProvider(credentials: credentials).searchSymbols(matching: query) { [weak self] results in
            DispatchQueue.main.async {
                guard let self else { return }
                self.searchButton.isEnabled = true
                self.searchResults = results
                self.showSearchResults()
            }
        }
    }

    @objc private func removeSelectedSymbol() {
        let selectedRow = tableView.selectedRow
        guard symbols.indices.contains(selectedRow) else { return }

        let removedSymbol = symbols.remove(at: selectedRow)
        saveWatchlist()
        updateStatus(message: "Removed \(removedSymbol). Screen saver dropdown updated.")
    }

    @objc private func addDemoSet() {
        for symbol in StockerPreferences.demoSymbols where !symbols.contains(symbol) {
            symbols.append(symbol)
        }
        saveWatchlist()
        updateStatus(message: "Added demo symbols. Screen saver dropdown updated.")
    }

    @objc private func applyChanges() {
        preferences.koreaInvestmentAppKey = appKeyField.stringValue
        preferences.koreaInvestmentAppSecret = appSecretField.stringValue
        appKeyField.stringValue = preferences.koreaInvestmentAppKey
        appSecretField.stringValue = preferences.koreaInvestmentAppSecret
        saveWatchlist()
        do {
            try installer.reinstall()
            updateStatus(message: "Applied and reinstalled screen saver.")
        } catch {
            updateStatus(message: "Applied, but install failed: \(error.localizedDescription)")
        }
    }

    @objc private func clearAPIKey() {
        appKeyField.stringValue = ""
        appSecretField.stringValue = ""
        updateStatus(message: "KIS credentials cleared. Apply to switch to demo data.")
    }

    @objc private func showWatchlistSection() {
        selectSection(.watchlist)
    }

    @objc private func showAPIKeySection() {
        selectSection(.apiKey)
    }

    private func selectSection(_ section: Section) {
        selectedSection = section
        watchlistView.isHidden = section != .watchlist
        apiKeyView.isHidden = section != .apiKey
        watchlistButton.state = section == .watchlist ? .on : .off
        apiKeyButton.state = section == .apiKey ? .on : .off
        updateStatus()
    }

    private func currentCredentials() -> KoreaInvestmentCredentials {
        let enteredKey = appKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredSecret = appSecretField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return KoreaInvestmentCredentials(
            appKey: enteredKey.isEmpty ? preferences.koreaInvestmentAppKey : enteredKey,
            appSecret: enteredSecret.isEmpty ? preferences.koreaInvestmentAppSecret : enteredSecret
        )
    }

    private func updateStatus(savedSymbol: String? = nil, removedSymbol: String? = nil) {
        if let savedSymbol {
            statusLabel.stringValue = "Added \(savedSymbol). \(symbols.count) symbol(s) ready."
        } else if let removedSymbol {
            statusLabel.stringValue = "Removed \(removedSymbol). \(symbols.count) symbol(s) ready."
        } else {
            switch selectedSection {
            case .watchlist:
                statusLabel.stringValue = "\(symbols.count) symbol(s) ready."
            case .apiKey:
                statusLabel.stringValue = preferences.koreaInvestmentCredentials.isConfigured ? "KIS credentials are saved." : "Demo data is active."
            }
        }
    }

    private func updateStatus(message: String) {
        statusLabel.stringValue = message
    }

    private func saveWatchlist() {
        preferences.registeredSymbols = symbols
        if let selectedSymbol = preferences.selectedSymbol, !preferences.registeredSymbols.contains(selectedSymbol) {
            preferences.selectedSymbol = nil
        }
        symbols = preferences.registeredSymbols
        tableView.reloadData()
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
