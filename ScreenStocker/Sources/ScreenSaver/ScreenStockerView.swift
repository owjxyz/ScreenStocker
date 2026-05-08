import AppKit
import ScreenSaver

@objc(ScreenStockerView)
final class ScreenStockerView: ScreenSaverView {
    private let preferences = StockerPreferences()
    private lazy var renderer = StockTickerRenderer(bounds: bounds)
    private var configurationController: ConfigurationWindowController?
    private var lastMarketDataRefreshDate: Date?
    private let marketDataRefreshInterval: TimeInterval = 5 * 60

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        animationTimeInterval = 1.0 / 30.0
        layer?.backgroundColor = NSColor.black.cgColor
        renderer.attach(to: self)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: StockerPreferences.didChangeNotification,
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    override func startAnimation() {
        super.startAnimation()
        refreshMarketData()
    }

    override func stopAnimation() {
        super.stopAnimation()
        renderer.stop()
    }

    override func animateOneFrame() {
        refreshMarketDataIfNeeded()
        renderer.tick()
    }

    override func layout() {
        super.layout()
        renderer.resize(to: bounds)
    }

    override var hasConfigureSheet: Bool {
        true
    }

    override var configureSheet: NSWindow? {
        if configurationController == nil {
            configurationController = ConfigurationWindowController(preferences: preferences)
        }
        configurationController?.reloadSymbols()
        return configurationController?.window
    }

    private func refreshMarketData() {
        lastMarketDataRefreshDate = Date()
        let symbol = preferences.primarySymbol
        let quoteProvider: StockQuoteProvider
        let timeSeriesProvider: StockTimeSeriesProvider

        let credentials = preferences.koreaInvestmentCredentials
        if credentials.isConfigured {
            let tokenProvider = KoreaInvestmentAccessTokenProvider(credentials: credentials)
            quoteProvider = KoreaInvestmentQuoteProvider(
                symbols: [symbol],
                credentials: credentials,
                tokenProvider: tokenProvider
            )
            timeSeriesProvider = KoreaInvestmentTimeSeriesProvider(
                symbol: symbol,
                credentials: credentials,
                tokenProvider: tokenProvider
            )
        } else {
            quoteProvider = DemoStockQuoteProvider(symbols: [symbol])
            timeSeriesProvider = DemoStockTimeSeriesProvider(symbol: symbol)
        }

        let group = DispatchGroup()
        var quote: StockQuote?
        var series: StockChartSeries?

        group.enter()
        quoteProvider.fetchQuotes { quotes in
            quote = quotes.first
            group.leave()
        }

        group.enter()
        timeSeriesProvider.fetchTimeSeries { fetchedSeries in
            series = fetchedSeries
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if let quote, let series {
                self.renderer.render(quote: quote, series: series)
            } else if self.preferences.koreaInvestmentCredentials.isConfigured {
                self.renderDemoMarketData(for: symbol)
            }
        }
    }

    private func renderDemoMarketData(for symbol: String) {
        DemoStockQuoteProvider(symbols: [symbol]).fetchQuotes { [weak self] quotes in
            guard let quote = quotes.first else { return }
            DemoStockTimeSeriesProvider(symbol: symbol).fetchTimeSeries { series in
                DispatchQueue.main.async {
                    self?.renderer.render(quote: quote, series: series)
                }
            }
        }
    }

    private func refreshMarketDataIfNeeded() {
        guard let lastMarketDataRefreshDate else {
            refreshMarketData()
            return
        }
        if Date().timeIntervalSince(lastMarketDataRefreshDate) >= marketDataRefreshInterval {
            refreshMarketData()
        }
    }

    @objc private func preferencesDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.lastMarketDataRefreshDate = nil
            self?.refreshMarketData()
        }
    }
}
