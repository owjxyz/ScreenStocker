import AppKit
import ScreenSaver

@objc(ScreenStockerView)
final class ScreenStockerView: ScreenSaverView {
    private let preferences = StockerPreferences()
    private let renderer = StockTickerRenderer()
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
        animationTimeInterval = 0
        layer?.backgroundColor = NSColor.black.cgColor
        renderer.attach(to: self, symbol: preferences.symbolForScreenSaverDisplay)
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
            self.renderer.update(symbol: self.preferences.symbolForScreenSaverDisplay)
        }
    }
}
