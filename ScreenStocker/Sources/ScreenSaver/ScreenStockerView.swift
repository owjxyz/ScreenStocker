import AppKit
import ScreenSaver

@objc(ScreenStockerView)
final class ScreenStockerView: ScreenSaverView {
    private let preferences = StockerPreferences()
    private lazy var renderer = StockTickerRenderer(bounds: bounds)
    private var configurationController: ConfigurationWindowController?

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
    }

    override func startAnimation() {
        super.startAnimation()
        refreshQuotes()
    }

    override func stopAnimation() {
        super.stopAnimation()
        renderer.stop()
    }

    override func animateOneFrame() {
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

    private func refreshQuotes() {
        let provider = DemoStockQuoteProvider(symbols: preferences.symbols)
        provider.fetchQuotes { [weak self] quotes in
            DispatchQueue.main.async {
                self?.renderer.render(quotes: quotes)
            }
        }
    }
}
