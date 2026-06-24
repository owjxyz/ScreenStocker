import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class WatchlistWindowController: NSWindowController {
    init(preferences: StockerPreferences) {
        let viewModel = WatchlistViewModel(preferences: preferences)
        let hostingController = NSHostingController(rootView: WatchlistRootView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "ScreenStocker"
        window.isReleasedWhenClosed = false
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 1056, height: 560))
        window.minSize = NSSize(width: 760, height: 500)

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ChartStyleWindowController: NSWindowController {
    init(currentStyle: ScreenSaverChartStyle, onSelect: @escaping (ScreenSaverChartStyle) -> Void) {
        let hostingController = NSHostingController(
            rootView: ChartStyleSelectionView(currentStyle: currentStyle, onSelect: onSelect)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Chart Style"
        window.isReleasedWhenClosed = false
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.backgroundColor = .windowBackgroundColor
        window.setContentSize(NSSize(width: 360, height: 220))
        window.minSize = NSSize(width: 320, height: 200)

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private actor CachedChartSeriesLoader {
    private var marketDataClient: TossInvestMarketDataClient?

    func series(for symbol: String, exchangeLabel: String?) -> StockChartSeries {
        let marketDataClient: TossInvestMarketDataClient
        if let existingClient = self.marketDataClient {
            marketDataClient = existingClient
        } else {
            let newClient = TossInvestMarketDataClient()
            self.marketDataClient = newClient
            marketDataClient = newClient
        }

        return marketDataClient.cachedChartSeries(
            for: symbol,
            exchangeLabel: exchangeLabel
        )
    }
}

@MainActor
final class WatchlistViewModel: ObservableObject {
    private static let marketDataRefreshInterval: UInt64 = 60_000_000_000

    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case watchlist = "Watchlist"
        case saver = "Screen Saver"
        case api = "API"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .overview:
                return "rectangle.grid.2x2"
            case .watchlist:
                return "star"
            case .saver:
                return "display"
            case .api:
                return "key"
            }
        }
    }

    @Published var selectedSection: Section = .overview
    @Published var selectedSymbol: String
    @Published var appearanceMode: ScreenSaverAppearanceMode
    @Published var chartStyle: ScreenSaverChartStyle
    @Published var tossAPIKey: String
    @Published var tossSecretKey: String
    @Published var hasTossCredentials: Bool
    @Published var marketSnapshots: [String: StockMarketSnapshot] = [:]
    @Published var isRefreshingMarketData = false
    @Published var isAddingSymbol = false
    @Published var isReorderingSymbols = false
    @Published var draggedSymbol: String?
    @Published var isAddSymbolSheetPresented = false
    @Published var symbolToAdd = ""
    @Published var addSymbolErrorMessage: String?
    @Published var marketDataErrorMessage: String?
    @Published var statusMessage = "Ready."

    @Published private(set) var symbols: [String]
    private let preferences: StockerPreferences
    private let credentialsStore = TossInvestCredentialsStore()
    private let marketDataClient = TossInvestMarketDataClient()
    private let cachedChartSeriesLoader = CachedChartSeriesLoader()
    private let installer = ScreenSaverInstaller()
    private var chartStyleWindowController: ChartStyleWindowController?
    private var pendingMarketDataRefresh = false
    private var marketDataRefreshTask: Task<Void, Never>?
    private var cachedPreviewTask: Task<Void, Never>?

    deinit {
        marketDataRefreshTask?.cancel()
        cachedPreviewTask?.cancel()
    }

    init(preferences: StockerPreferences) {
        self.preferences = preferences
        self.symbols = preferences.registeredSymbols
        self.selectedSymbol = preferences.selectedSymbol ?? preferences.symbolForScreenSaverDisplay ?? MarketDataCatalog.symbols[0]
        self.appearanceMode = preferences.appearanceMode
        self.chartStyle = preferences.chartStyle
        let credentials = credentialsStore.credentials
        self.tossAPIKey = credentials?.apiKey ?? ""
        self.tossSecretKey = credentials?.secretKey ?? ""
        self.hasTossCredentials = credentials?.isComplete == true
        preferences.registeredSymbols = symbols
    }

    var selectedQuote: StockQuote {
        quote(for: selectedSymbol)
    }

    var selectedSeries: StockChartSeries {
        series(for: selectedSymbol)
    }

    func quote(for symbol: String) -> StockQuote {
        marketSnapshots[symbol]?.quote ?? StockQuote.placeholder(symbol: symbol)
    }

    func series(for symbol: String) -> StockChartSeries {
        marketSnapshots[symbol]?.series ?? StockChartSeries(symbol: symbol, points: [])
    }

    func selectSymbol(_ symbol: String) {
        selectedSymbol = symbol
        preferences.selectedSymbol = symbol
        statusMessage = "\(symbol) selected for the screen saver."
        scheduleCachedPreview(for: symbol)
        scheduleMarketDataRefresh()
    }

    func performAction(_ title: String) {
        statusMessage = "\(title) selected."
    }

    func openAddSymbolSheet() {
        symbolToAdd = ""
        addSymbolErrorMessage = nil
        isAddSymbolSheetPresented = true
        statusMessage = "Add Symbol selected."
    }

    func addSymbol() async {
        guard !isAddingSymbol else { return }
        guard let normalizedSymbol = StockSymbolInput.normalizedSymbol(from: symbolToAdd) else {
            addSymbolErrorMessage = StockSymbolInput.validationMessage
            return
        }

        guard !symbols.contains(normalizedSymbol) else {
            addSymbolErrorMessage = "\(normalizedSymbol) is already in the watchlist."
            return
        }

        isAddingSymbol = true
        addSymbolErrorMessage = nil
        statusMessage = "Checking \(normalizedSymbol)..."

        do {
            let stockInfo = try await marketDataClient.stockInfo(for: normalizedSymbol)
            symbols.append(stockInfo.symbol)
            preferences.registeredSymbols = symbols
            selectSymbol(stockInfo.symbol)
            isAddSymbolSheetPresented = false
            symbolToAdd = ""
            statusMessage = "\(stockInfo.displayTitle) added to the watchlist."
        } catch {
            addSymbolErrorMessage = error.localizedDescription
            statusMessage = "Add Symbol failed: \(error.localizedDescription)"
        }

        isAddingSymbol = false
    }

    func removeSelectedSymbol() {
        guard let index = symbols.firstIndex(of: selectedSymbol) else {
            statusMessage = "Select a symbol to remove."
            return
        }

        let removedSymbol = symbols.remove(at: index)
        marketSnapshots[removedSymbol] = nil
        preferences.registeredSymbols = symbols

        if !symbols.isEmpty {
            let nextIndex = min(index, symbols.count - 1)
            let nextSymbol = symbols[nextIndex]
            selectSymbol(nextSymbol)
            statusMessage = "\(removedSymbol) removed from the watchlist."
        } else {
            preferences.selectedSymbol = nil
            selectedSymbol = ""
            statusMessage = "\(removedSymbol) removed. Add a symbol to use the screen saver."
        }
    }

    func toggleReorderingSymbols() {
        isReorderingSymbols.toggle()
        draggedSymbol = nil
        statusMessage = isReorderingSymbols ? "Drag symbols to reorder the watchlist." : "Watchlist order saved."
    }

    func moveSymbols(from source: IndexSet, to destination: Int) {
        symbols.move(fromOffsets: source, toOffset: destination)
        preferences.registeredSymbols = symbols
        statusMessage = "Watchlist order saved."
    }

    func beginDraggingSymbol(_ symbol: String) {
        guard isReorderingSymbols else { return }
        draggedSymbol = symbol
    }

    func moveDraggedSymbol(before targetSymbol: String) {
        guard
            isReorderingSymbols,
            let draggedSymbol,
            draggedSymbol != targetSymbol,
            let sourceIndex = symbols.firstIndex(of: draggedSymbol),
            let targetIndex = symbols.firstIndex(of: targetSymbol)
        else { return }

        let movedSymbol = symbols.remove(at: sourceIndex)
        let insertionIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        symbols.insert(movedSymbol, at: insertionIndex)
        preferences.registeredSymbols = symbols
        statusMessage = "Watchlist order saved."
    }

    func moveDraggedSymbolToEnd() {
        guard
            isReorderingSymbols,
            let draggedSymbol,
            let sourceIndex = symbols.firstIndex(of: draggedSymbol),
            sourceIndex != symbols.indices.last
        else { return }

        let movedSymbol = symbols.remove(at: sourceIndex)
        symbols.append(movedSymbol)
        preferences.registeredSymbols = symbols
        statusMessage = "Watchlist order saved."
    }

    func finishDraggingSymbol() {
        draggedSymbol = nil
    }

    func refreshMarketData() async {
        guard !isRefreshingMarketData else {
            pendingMarketDataRefresh = true
            return
        }
        isRefreshingMarketData = true
        defer {
            isRefreshingMarketData = false
            if pendingMarketDataRefresh {
                pendingMarketDataRefresh = false
                scheduleMarketDataRefresh()
            }
        }
        statusMessage = "Refreshing market data..."

        do {
            let requestedSymbol = selectedSymbol
            let quotes = try await marketDataClient.quotes(for: symbols)
            guard !Task.isCancelled else { return }
            marketSnapshots = mergedSnapshots(with: quotes)

            if let selectedQuote = marketSnapshots[requestedSymbol]?.quote {
                let series = await marketDataClient.chartSeries(for: selectedQuote)
                guard !Task.isCancelled else { return }
                if !series.points.isEmpty {
                    let currentQuote = marketSnapshots[requestedSymbol]?.quote ?? selectedQuote
                    marketSnapshots[requestedSymbol] = StockMarketSnapshot(
                        quote: StockQuote(
                            symbol: currentQuote.symbol,
                            displayName: currentQuote.displayName,
                            exchangeLabel: series.trackingExchangeLabel ?? currentQuote.exchangeLabel,
                            price: currentQuote.price,
                            changePercent: currentQuote.changePercent,
                            currency: currentQuote.currency,
                            timestamp: currentQuote.timestamp
                        ),
                        series: series
                    )
                }
            }

            marketDataErrorMessage = nil
            statusMessage = "Market data refreshed."
        } catch {
            guard !Task.isCancelled else { return }
            marketDataErrorMessage = error.localizedDescription
            statusMessage = "Market data refresh failed: \(error.localizedDescription)"
        }
    }

    func runMarketDataRefreshLoop() async {
        while !Task.isCancelled {
            await refreshMarketData()

            do {
                try await Task.sleep(nanoseconds: Self.marketDataRefreshInterval)
            } catch {
                return
            }
        }
    }

    private func scheduleMarketDataRefresh() {
        marketDataRefreshTask?.cancel()
        marketDataRefreshTask = Task { [weak self] in
            await self?.refreshMarketData()
        }
    }

    private func scheduleCachedPreview(for symbol: String) {
        cachedPreviewTask?.cancel()

        let originalSnapshot = marketSnapshots[symbol]
        let existingSnapshot = originalSnapshot
            ?? StockMarketSnapshot(
                quote: StockQuote.placeholder(symbol: symbol),
                series: StockChartSeries(symbol: symbol, points: [])
            )
        let loader = cachedChartSeriesLoader

        cachedPreviewTask = Task { [weak self] in
            let cachedSeries = await loader.series(
                for: symbol,
                exchangeLabel: existingSnapshot.quote.exchangeLabel
            )

            guard
                !Task.isCancelled,
                let self,
                self.selectedSymbol == symbol,
                self.marketSnapshots[symbol] == originalSnapshot,
                existingSnapshot.series.points.isEmpty,
                !cachedSeries.points.isEmpty
            else {
                return
            }

            self.marketSnapshots[symbol] = StockMarketSnapshot(
                quote: StockQuote(
                    symbol: existingSnapshot.quote.symbol,
                    displayName: existingSnapshot.quote.displayName,
                    exchangeLabel: cachedSeries.trackingExchangeLabel ?? existingSnapshot.quote.exchangeLabel,
                    price: existingSnapshot.quote.price,
                    changePercent: existingSnapshot.quote.changePercent,
                    currency: existingSnapshot.quote.currency,
                    timestamp: existingSnapshot.quote.timestamp
                ),
                series: cachedSeries
            )
        }
    }

    private func mergedSnapshots(
        with quotes: [String: StockQuote]
    ) -> [String: StockMarketSnapshot] {
        Dictionary(uniqueKeysWithValues: symbols.compactMap { symbol in
            guard let quote = quotes[symbol] else {
                return marketSnapshots[symbol].map { (symbol, $0) }
            }

            let existingSeries = marketSnapshots[symbol]?.series ?? StockChartSeries(symbol: symbol, points: [])
            let changePercent = quote.changePercent ?? marketSnapshots[symbol]?.quote.changePercent
            let mergedQuote = StockQuote(
                symbol: quote.symbol,
                displayName: quote.displayName,
                exchangeLabel: preferredExchangeLabel(
                    marketSnapshots[symbol]?.quote.exchangeLabel,
                    fallback: quote.exchangeLabel
                ),
                price: quote.price,
                changePercent: changePercent,
                currency: quote.currency,
                timestamp: quote.timestamp
            )
            return (symbol, StockMarketSnapshot(quote: mergedQuote, series: existingSeries))
        })
    }

    private func preferredExchangeLabel(_ primary: String?, fallback: String?) -> String? {
        if let primary, !primary.isEmpty {
            return primary
        }

        if let fallback, !fallback.isEmpty {
            return fallback
        }

        return nil
    }

    func toggleAppearanceMode() {
        appearanceMode = appearanceMode.next
        preferences.appearanceMode = appearanceMode
        statusMessage = "Dim Mode set to \(appearanceMode.title)."
    }

    func openChartStyleWindow() {
        if chartStyleWindowController == nil {
            chartStyleWindowController = ChartStyleWindowController(
                currentStyle: chartStyle,
                onSelect: { [weak self] style in
                    self?.selectChartStyle(style)
                }
            )
        }

        chartStyleWindowController?.showWindow(nil)
        chartStyleWindowController?.window?.makeKeyAndOrderFront(nil)
        statusMessage = "Chart Style selected."
    }

    func selectChartStyle(_ style: ScreenSaverChartStyle) {
        chartStyle = style
        preferences.chartStyle = style
        chartStyleWindowController?.close()
        chartStyleWindowController = nil
        statusMessage = "\(style.title) selected."
    }

    func installScreenSaver() {
        preferences.selectedSymbol = selectedSymbol
        preferences.appearanceMode = appearanceMode
        preferences.chartStyle = chartStyle

        do {
            try installer.reinstall()
            statusMessage = "Screen saver installed with \(appearanceMode.title) and \(chartStyle.title)."
        } catch {
            statusMessage = "Install failed: \(error.localizedDescription)"
        }
    }

    func saveSelectionToScreenSaver() {
        preferences.selectedSymbol = selectedSymbol
        preferences.appearanceMode = appearanceMode
        preferences.chartStyle = chartStyle

        do {
            try installer.reinstall()
            statusMessage = "\(selectedSymbol) saved and applied to the screen saver."
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func saveTossCredentials() {
        do {
            try credentialsStore.save(TossInvestCredentials(apiKey: tossAPIKey, secretKey: tossSecretKey))
            let credentials = credentialsStore.credentials
            tossAPIKey = credentials?.apiKey ?? ""
            tossSecretKey = credentials?.secretKey ?? ""
            hasTossCredentials = credentials?.isComplete == true
            statusMessage = "Toss Invest Open API credentials saved."
            Task { await refreshMarketData() }
        } catch {
            statusMessage = "Could not save credentials: \(error.localizedDescription)"
        }
    }

    func clearTossCredentials() {
        do {
            try credentialsStore.clear()
            tossAPIKey = ""
            tossSecretKey = ""
            hasTossCredentials = false
            statusMessage = "Toss Invest Open API credentials removed."
        } catch {
            statusMessage = "Could not remove credentials: \(error.localizedDescription)"
        }
    }
}

private struct WatchlistRootView: View {
    @ObservedObject var viewModel: WatchlistViewModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            content
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.openAddSymbolSheet()
                } label: {
                    Label("Add Symbol", systemImage: "plus")
                }
                .disabled(viewModel.isReorderingSymbols)

                Button {
                    viewModel.removeSelectedSymbol()
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(viewModel.selectedSection != .watchlist || viewModel.symbols.isEmpty || viewModel.isReorderingSymbols)
            }

            ToolbarItemGroup {
                Button {
                    Task { await viewModel.refreshMarketData() }
                } label: {
                    Label("Refresh Prices", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshingMarketData)

                Button {
                    viewModel.performAction("Preview Screen Saver")
                } label: {
                    Label("Preview Screen Saver", systemImage: "play.rectangle")
                }

                Button {
                    viewModel.installScreenSaver()
                } label: {
                    Label("Install Screen Saver", systemImage: "display.and.arrow.down")
                }
            }
        }
        .task {
            await viewModel.runMarketDataRefreshLoop()
        }
        .sheet(isPresented: $viewModel.isAddSymbolSheetPresented) {
            AddSymbolSheet(viewModel: viewModel)
        }
    }

    private var sidebar: some View {
        List(selection: $viewModel.selectedSection) {
            Section("ScreenStocker") {
                ForEach(WatchlistViewModel.Section.allCases) { section in
                    Label(section.rawValue, systemImage: section.symbolName)
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ScreenStocker")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.selectedSection {
        case .overview:
            OverviewView(viewModel: viewModel)
                .navigationTitle("Overview")
        case .watchlist:
            WatchlistView(viewModel: viewModel)
                .navigationTitle("Watchlist")
        case .saver:
            ScreenSaverSettingsView(viewModel: viewModel)
                .navigationTitle("Screen Saver")
        case .api:
            APISettingsView(viewModel: viewModel)
                .navigationTitle("API")
        }
    }
}

private struct OverviewView: View {
    @ObservedObject var viewModel: WatchlistViewModel

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 18) {
                HeaderBlock(
                    title: "Market Dashboard",
                    subtitle: "Monitor the selected symbol and screen saver presentation."
                )

                PreviewCard(
                    quote: viewModel.selectedQuote,
                    series: viewModel.selectedSeries,
                    appearanceMode: viewModel.appearanceMode,
                    chartStyle: viewModel.chartStyle
                )

                HStack(spacing: 10) {
                    CommandButton(title: "Preview Saver", systemImage: "play.rectangle") {
                        viewModel.performAction("Preview Saver")
                    }
                    CommandButton(title: "Arrange Layout", systemImage: "square.grid.2x2") {
                        viewModel.performAction("Arrange Layout")
                    }
                    CommandButton(title: "Export Snapshot", systemImage: "square.and.arrow.down") {
                        viewModel.performAction("Export Snapshot")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                HeaderBlock(title: "Watchlist", subtitle: "Symbols available for the screen saver.")

                ForEach(viewModel.symbols, id: \.self) { symbol in
                    SymbolRow(
                        quote: viewModel.quote(for: symbol),
                        isSelected: symbol == viewModel.selectedSymbol,
                        isReordering: false
                    ) {
                        viewModel.selectSymbol(symbol)
                    }
                }

                HStack {
                    Text("\(viewModel.symbols.count) symbols")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ApplyButton {
                        viewModel.saveSelectionToScreenSaver()
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(width: 250)
        }
        .padding(28)
    }
}

private struct WatchlistView: View {
    @ObservedObject var viewModel: WatchlistViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HeaderBlock(title: "Watchlist", subtitle: "Manage the symbols shown in the screen saver.")

            HStack(spacing: 10) {
                CommandButton(title: "Add Symbol", systemImage: "plus") {
                    viewModel.openAddSymbolSheet()
                }
                .disabled(viewModel.isReorderingSymbols)
                CommandButton(title: "Remove", systemImage: "minus") {
                    viewModel.removeSelectedSymbol()
                }
                .disabled(viewModel.symbols.isEmpty || viewModel.isReorderingSymbols)
                CommandButton(
                    title: viewModel.isReorderingSymbols ? "Done" : "Reorder",
                    systemImage: viewModel.isReorderingSymbols ? "checkmark" : "arrow.up.arrow.down"
                ) {
                    viewModel.toggleReorderingSymbols()
                }
                .disabled(viewModel.symbols.count < 2)
                Spacer()
                if viewModel.isRefreshingMarketData {
                    ProgressView()
                        .controlSize(.small)
                }
                CommandButton(title: "Refresh", systemImage: "arrow.clockwise") {
                    Task { await viewModel.refreshMarketData() }
                }
                .disabled(viewModel.isRefreshingMarketData)
            }

            if let errorMessage = viewModel.marketDataErrorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            List(selection: $viewModel.selectedSymbol) {
                ForEach(viewModel.symbols, id: \.self) { symbol in
                    SymbolRow(
                        quote: viewModel.quote(for: symbol),
                        isSelected: symbol == viewModel.selectedSymbol,
                        isReordering: viewModel.isReorderingSymbols
                    ) {
                        viewModel.selectSymbol(symbol)
                    }
                    .padding(.vertical, 3)
                    .modifier(SymbolRowReorderModifier(
                        symbol: symbol,
                        viewModel: viewModel
                    ))
                }

                if viewModel.isReorderingSymbols {
                    Color.clear
                        .frame(height: 16)
                        .contentShape(Rectangle())
                        .onDrop(
                            of: [UTType.plainText],
                            delegate: SymbolListEndDropDelegate(viewModel: viewModel)
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Text("\(viewModel.symbols.count) symbols")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ApplyButton {
                    viewModel.saveSelectionToScreenSaver()
                }
            }
        }
        .padding(28)
    }
}

private struct ScreenSaverSettingsView: View {
    @ObservedObject var viewModel: WatchlistViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HeaderBlock(title: "Screen Saver", subtitle: "Choose how the selected symbol appears on screen.")

            PreviewCard(
                quote: viewModel.selectedQuote,
                series: viewModel.selectedSeries,
                appearanceMode: viewModel.appearanceMode,
                chartStyle: viewModel.chartStyle
            )
                .frame(height: 280)

            HStack(spacing: 10) {
                Picker("Display", selection: $viewModel.selectedSymbol) {
                    ForEach(viewModel.symbols, id: \.self) { symbol in
                        Text(symbol).tag(symbol)
                    }
                }
                .frame(width: 180)
                .onChange(of: viewModel.selectedSymbol) { symbol in
                    viewModel.selectSymbol(symbol)
                }

                AppearanceModeButton(mode: viewModel.appearanceMode) {
                    viewModel.toggleAppearanceMode()
                }
                CommandButton(title: "Chart Style", systemImage: "chart.xyaxis.line") {
                    viewModel.openChartStyleWindow()
                }
                PrimaryCommandButton(title: "Install Saver", systemImage: "display.and.arrow.down") {
                    viewModel.installScreenSaver()
                }
            }
        }
        .padding(28)
    }
}

private struct APISettingsView: View {
    @ObservedObject var viewModel: WatchlistViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HeaderBlock(
                title: "Toss Invest Open API",
                subtitle: "Store the credentials used to request OAuth access tokens for market data."
            )

            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("API Key") {
                    TextField("Client ID or API key", text: $viewModel.tossAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                }

                LabeledContent("Secret Key") {
                    SecureField("Secret key", text: $viewModel.tossSecretKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)

            HStack(spacing: 10) {
                PrimaryCommandButton(title: "Save Credentials", systemImage: "key.fill") {
                    viewModel.saveTossCredentials()
                }

                CommandButton(title: "Remove", systemImage: "trash") {
                    viewModel.clearTossCredentials()
                }
                .disabled(!viewModel.hasTossCredentials && viewModel.tossAPIKey.isEmpty && viewModel.tossSecretKey.isEmpty)
            }

            Label(
                viewModel.hasTossCredentials ? "Credentials are saved in Keychain." : "Credentials have not been saved.",
                systemImage: viewModel.hasTossCredentials ? "checkmark.seal.fill" : "exclamationmark.circle"
            )
            .font(.caption)
            .foregroundStyle(viewModel.hasTossCredentials ? Color.green : Color.secondary)

            Text("The Open API base server is https://openapi.tossinvest.com.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(28)
    }
}

private struct AddSymbolSheet: View {
    @ObservedObject var viewModel: WatchlistViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HeaderBlock(
                title: "Add Symbol",
                subtitle: "Add a KRX code or US ticker to the watchlist."
            )

            VStack(alignment: .leading, spacing: 8) {
                TextField("005930 or AAPL", text: $viewModel.symbolToAdd)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .disabled(viewModel.isAddingSymbol)
                    .onSubmit {
                        Task { await viewModel.addSymbol() }
                    }

                Text(StockSymbolInput.validationMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let errorMessage = viewModel.addSymbolErrorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                if viewModel.isAddingSymbol {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button("Cancel") {
                    viewModel.isAddSymbolSheetPresented = false
                }
                .disabled(viewModel.isAddingSymbol)

                PrimaryCommandButton(title: "Add", systemImage: "plus") {
                    Task { await viewModel.addSymbol() }
                }
                .disabled(viewModel.isAddingSymbol)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

private struct ChartStyleSelectionView: View {
    let currentStyle: ScreenSaverChartStyle
    let onSelect: (ScreenSaverChartStyle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HeaderBlock(
                title: "Chart Style",
                subtitle: "Select the chart presentation used by the screen saver."
            )

            VStack(spacing: 10) {
                ForEach(ScreenSaverChartStyle.allCases, id: \.rawValue) { style in
                    ChartStyleButton(
                        style: style,
                        isApplied: style == currentStyle,
                        onSelect: onSelect
                    )
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 320, minHeight: 200)
    }
}

private struct ChartStyleButton: View {
    let style: ScreenSaverChartStyle
    let isApplied: Bool
    let onSelect: (ScreenSaverChartStyle) -> Void

    var body: some View {
        Button {
            onSelect(style)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: style.systemImage)
                    .font(.title3)
                    .foregroundStyle(isApplied ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(style.title)
                        .font(.body.weight(.semibold))
                    Text(isApplied ? "Currently applied" : "Apply to screen saver")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isApplied ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isApplied ? Color.accentColor : Color.secondary)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isApplied ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.2),
                        lineWidth: 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct HeaderBlock: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CommandButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct PrimaryCommandButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    private var preferredSize: CGSize {
        Self.preferredSize(title: title, systemImage: systemImage)
    }

    var body: some View {
        PrimaryCommandNativeButton(title: title, systemImage: systemImage, action: action)
            .frame(width: preferredSize.width, height: preferredSize.height)
    }

    private static func preferredSize(title: String, systemImage: String) -> CGSize {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.keyEquivalent = "\r"
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        return button.intrinsicContentSize
    }
}

private struct PrimaryCommandNativeButton: NSViewRepresentable {
    let title: String
    let systemImage: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: title,
            target: context.coordinator,
            action: #selector(Coordinator.performAction)
        )
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.keyEquivalent = "\r"
        button.imagePosition = .imageLeading
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        update(button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        update(button)
    }

    private func update(_ button: NSButton) {
        button.title = title
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}

private struct ApplyButton: View {
    let action: () -> Void

    private static let preferredSize: CGSize = {
        let button = NSButton(title: "Apply", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button.intrinsicContentSize
    }()

    var body: some View {
        ApplyNativeButton(action: action)
            .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
    }
}

private struct ApplyNativeButton: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: "Apply",
            target: context.coordinator,
            action: #selector(Coordinator.performAction)
        )
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.keyEquivalent = "\r"
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}

private struct AppearanceModeButton: View {
    let mode: ScreenSaverAppearanceMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Dim: \(mode.title)", systemImage: mode.systemImage)
        }
        .help("Cycle screen saver appearance")
    }
}

private struct SymbolRowReorderModifier: ViewModifier {
    let symbol: String
    @ObservedObject var viewModel: WatchlistViewModel

    func body(content: Content) -> some View {
        if viewModel.isReorderingSymbols {
            content
                .contentShape(Rectangle())
                .opacity(viewModel.draggedSymbol == symbol ? 0.55 : 1)
                .onDrag {
                    viewModel.beginDraggingSymbol(symbol)
                    return NSItemProvider(object: symbol as NSString)
                }
                .onDrop(
                    of: [UTType.plainText],
                    delegate: SymbolRowDropDelegate(
                        targetSymbol: symbol,
                        viewModel: viewModel
                    )
                )
        } else {
            content
        }
    }
}

private struct SymbolRowDropDelegate: DropDelegate {
    let targetSymbol: String
    @ObservedObject var viewModel: WatchlistViewModel

    func dropEntered(info: DropInfo) {
        viewModel.moveDraggedSymbol(before: targetSymbol)
    }

    func performDrop(info: DropInfo) -> Bool {
        viewModel.finishDraggingSymbol()
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct SymbolListEndDropDelegate: DropDelegate {
    @ObservedObject var viewModel: WatchlistViewModel

    func dropEntered(info: DropInfo) {
        viewModel.moveDraggedSymbolToEnd()
    }

    func performDrop(info: DropInfo) -> Bool {
        viewModel.finishDraggingSymbol()
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct SymbolRow: View {
    let quote: StockQuote
    let isSelected: Bool
    let isReordering: Bool
    let action: () -> Void

    var body: some View {
        if isReordering {
            rowContent
                .contentShape(Rectangle())
        } else {
            Button(action: action) {
                rowContent
            }
            .buttonStyle(.plain)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(quote.titleText)
                    .font(.body.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                Text("Market status")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(quote.priceText)
                    .font(.body.monospacedDigit())
                Text(quote.changePercentText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(changeColor)
            }

            Image(systemName: isReordering ? "line.3.horizontal" : isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isReordering ? Color.secondary : isSelected ? Color.accentColor : Color.secondary)
        }
        .contentShape(Rectangle())
    }

    private var changeColor: Color {
        guard let changePercent = quote.changePercent else { return .secondary }
        return changePercent >= 0 ? .red : .blue
    }
}

private struct PreviewCard: View {
    let quote: StockQuote
    let series: StockChartSeries
    var appearanceMode: ScreenSaverAppearanceMode = .dark
    var chartStyle: ScreenSaverChartStyle = .line

    var body: some View {
        StockTickerScreenView(
            quote: quote,
            series: series,
            appearanceMode: appearanceMode,
            chartStyle: chartStyle,
            displayMode: .preview
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(minHeight: 220)
    }
}
