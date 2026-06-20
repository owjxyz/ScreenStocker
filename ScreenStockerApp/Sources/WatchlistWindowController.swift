import AppKit
import SwiftUI

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
        window.setContentSize(NSSize(width: 880, height: 560))
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

@MainActor
final class WatchlistViewModel: ObservableObject {
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
    @Published var isRefreshingSelectedChart = false
    @Published var isAddingSymbol = false
    @Published var isReorderingSymbols = false
    @Published var isAddSymbolSheetPresented = false
    @Published var symbolToAdd = ""
    @Published var addSymbolErrorMessage: String?
    @Published var marketDataErrorMessage: String?
    @Published var statusMessage = "Ready."

    @Published private(set) var symbols: [String]
    private let preferences: StockerPreferences
    private let credentialsStore = TossInvestCredentialsStore()
    private let marketDataClient = TossInvestMarketDataClient()
    private let installer = ScreenSaverInstaller()
    private var chartStyleWindowController: ChartStyleWindowController?
    private var selectedChartTask: Task<Void, Never>?

    deinit {
        selectedChartTask?.cancel()
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
        scheduleSelectedChartRefresh()
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

            let quotes = try? await marketDataClient.quotes(for: [stockInfo.symbol])
            if let quote = quotes?[stockInfo.symbol] {
                marketSnapshots[stockInfo.symbol] = StockMarketSnapshot(
                    quote: quote,
                    series: StockChartSeries(symbol: stockInfo.symbol, points: [])
                )
            }
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
        statusMessage = isReorderingSymbols ? "Drag symbols to reorder the watchlist." : "Watchlist order saved."
    }

    func moveSymbols(from source: IndexSet, to destination: Int) {
        symbols.move(fromOffsets: source, toOffset: destination)
        preferences.registeredSymbols = symbols
        statusMessage = "Watchlist order saved."
    }

    func refreshMarketData() async {
        guard !isRefreshingMarketData else { return }
        isRefreshingMarketData = true
        statusMessage = "Refreshing market data..."

        do {
            let quotes = try await marketDataClient.quotes(for: symbols)
            marketSnapshots = mergedSnapshots(with: quotes)
            marketDataErrorMessage = nil
            statusMessage = "Market data refreshed."
            scheduleSelectedChartRefresh()
        } catch {
            marketDataErrorMessage = error.localizedDescription
            statusMessage = "Market data refresh failed: \(error.localizedDescription)"
        }

        isRefreshingMarketData = false
    }

    private func scheduleSelectedChartRefresh() {
        selectedChartTask?.cancel()

        let symbol = selectedSymbol
        guard !symbol.isEmpty else { return }

        selectedChartTask = Task { [weak self] in
            await self?.refreshSelectedChart(for: symbol)
        }
    }

    private func refreshSelectedChart(for symbol: String) async {
        isRefreshingSelectedChart = true
        defer {
            if selectedSymbol == symbol {
                isRefreshingSelectedChart = false
            }
        }

        do {
            let snapshot = try await marketDataClient.snapshot(for: symbol)
            guard !Task.isCancelled, selectedSymbol == symbol else { return }
            marketSnapshots[symbol] = snapshot
            marketDataErrorMessage = nil
            statusMessage = "Selected symbol chart refreshed."
        } catch {
            guard !Task.isCancelled, selectedSymbol == symbol else { return }
            marketDataErrorMessage = error.localizedDescription
            statusMessage = "Selected symbol chart refresh failed: \(error.localizedDescription)"
        }
    }

    private func mergedSnapshots(with quotes: [String: StockQuote]) -> [String: StockMarketSnapshot] {
        Dictionary(uniqueKeysWithValues: symbols.compactMap { symbol in
            guard let quote = quotes[symbol] else {
                return marketSnapshots[symbol].map { (symbol, $0) }
            }

            let existingSeries = marketSnapshots[symbol]?.series ?? StockChartSeries(symbol: symbol, points: [])
            let changePercent = changePercent(price: quote.price, series: existingSeries)
                ?? marketSnapshots[symbol]?.quote.changePercent
            let mergedQuote = StockQuote(
                symbol: quote.symbol,
                displayName: quote.displayName,
                price: quote.price,
                changePercent: changePercent,
                currency: quote.currency,
                timestamp: quote.timestamp
            )
            return (symbol, StockMarketSnapshot(quote: mergedQuote, series: existingSeries))
        })
    }

    private func changePercent(price: Decimal?, series: StockChartSeries) -> Decimal? {
        guard let price, let baseline = series.openingPrice, baseline != 0 else { return nil }
        return ((price - baseline) / baseline) * 100
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
            await viewModel.refreshMarketData()
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
                        isSelected: symbol == viewModel.selectedSymbol
                    ) {
                        viewModel.selectSymbol(symbol)
                    }
                }

                Spacer()
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
                        isSelected: symbol == viewModel.selectedSymbol
                    ) {
                        viewModel.selectSymbol(symbol)
                    }
                    .padding(.vertical, 3)
                }
                .onMove { source, destination in
                    viewModel.moveSymbols(from: source, to: destination)
                }
                .moveDisabled(!viewModel.isReorderingSymbols)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Text("\(viewModel.symbols.count) symbols")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                SaveSelectionButton {
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

private struct SaveSelectionButton: View {
    let action: () -> Void

    private static let preferredSize: CGSize = {
        let button = NSButton(title: "Save Selection", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button.intrinsicContentSize
    }()

    var body: some View {
        SaveSelectionNativeButton(action: action)
            .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
    }
}

private struct SaveSelectionNativeButton: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: "Save Selection",
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

private struct SymbolRow: View {
    let quote: StockQuote
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var changeColor: Color {
        guard let changePercent = quote.changePercent else { return .secondary }
        return changePercent >= 0 ? .red : .blue
    }
}

private struct PreviewPalette {
    private let resolvedColorScheme: ColorScheme

    init(appearanceMode: ScreenSaverAppearanceMode, systemColorScheme: ColorScheme) {
        switch appearanceMode {
        case .light:
            self.resolvedColorScheme = .light
        case .dark:
            self.resolvedColorScheme = .dark
        case .automatic:
            self.resolvedColorScheme = systemColorScheme
        }
    }

    private var isLight: Bool {
        resolvedColorScheme == .light
    }

    var background: Color {
        isLight ? .white : .black
    }

    var primaryText: Color {
        (isLight ? Color.black : Color.white).opacity(1)
    }

    var metricText: Color {
        (isLight ? Color.black : Color.white).opacity(0.9)
    }

    var secondaryText: Color {
        (isLight ? Color.black : Color.white).opacity(0.54)
    }

    var tertiaryText: Color {
        (isLight ? Color.black : Color.white).opacity(0.58)
    }

    var badgeText: Color {
        (isLight ? Color.black : Color.white).opacity(0.7)
    }

    var badgeBackground: Color {
        (isLight ? Color.black : Color.white).opacity(0.12)
    }

    var grid: Color {
        (isLight ? Color.black : Color.white).opacity(0.12)
    }
}

private struct PreviewCard: View {
    let quote: StockQuote
    let series: StockChartSeries
    var appearanceMode: ScreenSaverAppearanceMode = .dark
    var chartStyle: ScreenSaverChartStyle = .line

    @Environment(\.colorScheme) private var systemColorScheme

    private var palette: PreviewPalette {
        PreviewPalette(appearanceMode: appearanceMode, systemColorScheme: systemColorScheme)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(palette.background)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    PreviewMetricBlock(
                        title: "Open",
                        value: StockQuote.currencyText(for: series.openingPrice ?? quote.price, currency: quote.currency),
                        palette: palette
                    )
                    PreviewMetricBlock(
                        title: "High",
                        value: StockQuote.currencyText(for: series.highClose ?? quote.price, currency: quote.currency),
                        palette: palette
                    )
                    PreviewMetricBlock(
                        title: "Low",
                        value: StockQuote.currencyText(for: series.lowClose ?? quote.price, currency: quote.currency),
                        palette: palette
                    )
                    Spacer()
                    Text("Market snapshot")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }

                switch chartStyle {
                case .line:
                    MiniLineChart(
                        series: series,
                        lineColor: changeColor,
                        gridColor: palette.grid
                    )
                case .candlestick:
                    MiniCandlestickChart(series: series, gridColor: palette.grid)
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("KRX")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(palette.badgeText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(palette.badgeBackground, in: Capsule())
                        Text(updatedText)
                            .font(.caption)
                            .foregroundStyle(palette.tertiaryText)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(quote.titleText)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(quote.priceText)
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(palette.primaryText)
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Text(quote.changePercentText)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(changeColor)
                    }
                }
            }
            .padding(22)
        }
        .frame(minHeight: 220)
    }

    private var changeColor: Color {
        guard let changePercent = quote.changePercent else { return palette.secondaryText }
        return changePercent >= 0 ? .red : .blue
    }

    private var updatedText: String {
        guard let timestamp = quote.timestamp else {
            return "Waiting for market data"
        }
        return "Updated \(Self.timestampFormatter.string(from: timestamp))"
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "HH:mm 'KST'"
        return formatter
    }()
}

private struct PreviewMetricBlock: View {
    let title: String
    let value: String
    let palette: PreviewPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryText)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(palette.metricText)
        }
    }
}

private struct MiniLineChart: View {
    let series: StockChartSeries
    let lineColor: Color
    let gridColor: Color

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            ZStack {
                Path { path in
                    for index in 0..<3 {
                        let y = CGFloat(index) / 2 * proxy.size.height
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                }
                .stroke(gridColor, style: StrokeStyle(lineWidth: 1, dash: [5, 8]))

                Path { path in
                    guard let firstPoint = points.first else { return }
                    path.move(to: firstPoint)
                    for segment in StockChartGeometry.smoothCurveSegments(through: points) {
                        path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
                    }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(minHeight: 52)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        StockChartGeometry.normalizedPoints(for: series, in: size)
    }
}

private struct MiniCandlestickChart: View {
    let series: StockChartSeries
    let gridColor: Color

    var body: some View {
        GeometryReader { proxy in
            let candles = normalizedCandles(in: proxy.size)

            ZStack {
                Path { path in
                    for index in 0..<3 {
                        let y = CGFloat(index) / 2 * proxy.size.height
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                }
                .stroke(gridColor, style: StrokeStyle(lineWidth: 1, dash: [5, 8]))

                ForEach(Array(candles.enumerated()), id: \.offset) { _, candle in
                    let candleColor: Color = candle.closeY <= candle.openY ? .red : .blue
                    let bodyHeight = max(abs(candle.closeY - candle.openY), 4)

                    Group {
                        Rectangle()
                            .fill(candleColor.opacity(0.8))
                            .frame(width: 2, height: max(candle.lowY - candle.highY, 14))
                            .position(x: candle.x, y: (candle.highY + candle.lowY) / 2)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(candleColor)
                            .frame(width: max(proxy.size.width / CGFloat(max(candles.count, 1)) * 0.42, 4), height: bodyHeight)
                            .position(x: candle.x, y: (candle.openY + candle.closeY) / 2)
                    }
                }
            }
        }
        .frame(minHeight: 52)
    }

    private func normalizedCandles(in size: CGSize) -> [StockChartGeometry.CandlePoint] {
        StockChartGeometry.normalizedCandles(for: series, in: size)
    }
}
