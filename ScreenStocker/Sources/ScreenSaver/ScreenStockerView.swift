import AppKit
import ScreenSaver

@objc(ScreenStockerView)
final class ScreenStockerView: ScreenSaverView {
    private let preferences = StockerPreferences()
    private let renderer = StockTickerRenderer()
    private let marketDataClient = TossInvestMarketDataClient()
    private var configurationController: ConfigurationWindowController?
    private var refreshTask: Task<Void, Never>?

    private static let refreshInterval: UInt64 = 300_000_000_000

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
        animationTimeInterval = 0
        layer?.backgroundColor = backgroundColor(for: preferences.appearanceMode).cgColor
        renderer.attach(
            to: self,
            symbol: preferences.symbolForScreenSaverDisplay,
            appearanceMode: preferences.appearanceMode,
            chartStyle: preferences.chartStyle
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: StockerPreferences.didChangeNotification,
            object: nil
        )
    }

    deinit {
        refreshTask?.cancel()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    override func startAnimation() {
        super.startAnimation()
        startMarketDataRefresh()
    }

    override func stopAnimation() {
        refreshTask?.cancel()
        refreshTask = nil
        super.stopAnimation()
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

    @objc private func preferencesDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layer?.backgroundColor = self.backgroundColor(for: self.preferences.appearanceMode).cgColor
            self.renderer.update(
                symbol: self.preferences.symbolForScreenSaverDisplay,
                appearanceMode: self.preferences.appearanceMode,
                chartStyle: self.preferences.chartStyle
            )
            self.startMarketDataRefresh()
        }
    }

    private func startMarketDataRefresh() {
        refreshTask?.cancel()

        guard let symbol = preferences.symbolForScreenSaverDisplay else {
            return
        }

        refreshTask = Task { [weak self] in
            await self?.runMarketDataRefreshLoop(symbol: symbol)
        }
    }

    @MainActor
    private func runMarketDataRefreshLoop(symbol: String) async {
        while !Task.isCancelled {
            await refreshMarketData(symbol: symbol)

            do {
                try await Task.sleep(nanoseconds: Self.refreshInterval)
            } catch {
                return
            }
        }
    }

    @MainActor
    private func refreshMarketData(symbol: String) async {
        do {
            let snapshot = try await marketDataClient.snapshot(for: symbol)
            guard !Task.isCancelled else {
                return
            }
            renderer.update(snapshot: snapshot)
        } catch {}
    }

    private func backgroundColor(for appearanceMode: ScreenSaverAppearanceMode) -> NSColor {
        switch appearanceMode {
        case .light:
            return .white
        case .dark:
            return .black
        case .automatic:
            return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua ? .white : .black
        }
    }
}
