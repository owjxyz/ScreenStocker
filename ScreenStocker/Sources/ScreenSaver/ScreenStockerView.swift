import AppKit
import ScreenSaver

@objc(ScreenStockerView)
final class ScreenStockerView: ScreenSaverView {
    private let preferences = StockerPreferences()
    private let renderer = StockTickerRenderer()
    private var configurationController: ConfigurationWindowController?
    private let marketDataRefreshInterval: TimeInterval = 5 * 60
    private var refreshTimer: Timer?
    private var isRefreshingMarketData = false
    private var cachedQuote: StockQuote?
    private var cachedSeries: StockChartSeries?

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
        animationTimeInterval = marketDataRefreshInterval
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
        scheduleRefreshTimer()
        refreshMarketData()
    }

    override func stopAnimation() {
        super.stopAnimation()
        refreshTimer?.invalidate()
        refreshTimer = nil
        isRefreshingMarketData = false
        renderer.stop()
    }

    override func animateOneFrame() {
        refreshMarketData()
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
        guard !isRefreshingMarketData else { return }
        guard let symbol = preferences.symbolForScreenSaverDisplay else {
            renderer.showEmptyWatchlist()
            return
        }

        isRefreshingMarketData = true
        renderer.showLoading(symbol: symbol)

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
            self.isRefreshingMarketData = false
            if let quote, let series {
                self.cachedQuote = quote
                self.cachedSeries = series
                self.renderer.render(quote: quote, series: series)
            } else if self.preferences.koreaInvestmentCredentials.isConfigured {
                self.renderer.showError(
                    message: "Live data failed. Showing the last successful quote when available.",
                    cachedQuote: self.cachedQuote,
                    cachedSeries: self.cachedSeries
                )
            } else if let quote {
                self.cachedQuote = quote
                self.cachedSeries = series
                self.renderer.render(quote: quote, series: series)
            } else {
                self.renderer.showError(
                    message: "Demo market data is unavailable.",
                    cachedQuote: self.cachedQuote,
                    cachedSeries: self.cachedSeries
                )
            }
        }
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: marketDataRefreshInterval, repeats: true) { [weak self] _ in
            self?.refreshMarketData()
        }
    }

    @objc private func preferencesDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshMarketData()
        }
    }
}
