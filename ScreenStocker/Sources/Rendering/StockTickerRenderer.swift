import AppKit
import QuartzCore

final class StockTickerRenderer {
    private let rootLayer = CALayer()
    private let titleLayer = CATextLayer()
    private var quoteLayers: [CATextLayer] = []
    private var bounds: CGRect
    private var phase: CGFloat = 0

    init(bounds: CGRect) {
        self.bounds = bounds
        rootLayer.masksToBounds = true
        rootLayer.backgroundColor = NSColor.black.cgColor

        titleLayer.string = "ScreenStocker"
        titleLayer.alignmentMode = .center
        titleLayer.foregroundColor = NSColor.white.cgColor
        titleLayer.fontSize = 26
        titleLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        rootLayer.addSublayer(titleLayer)
    }

    func attach(to view: NSView) {
        view.layer?.addSublayer(rootLayer)
        resize(to: view.bounds)
    }

    func resize(to newBounds: CGRect) {
        bounds = newBounds
        rootLayer.frame = newBounds
        titleLayer.frame = CGRect(x: 0, y: newBounds.midY + 60, width: newBounds.width, height: 40)
        layoutQuoteLayers()
    }

    func render(quotes: [StockQuote]) {
        quoteLayers.forEach { $0.removeFromSuperlayer() }
        quoteLayers = quotes.map(makeQuoteLayer)
        quoteLayers.forEach(rootLayer.addSublayer)
        layoutQuoteLayers()
    }

    func tick() {
        phase += 0.35
        layoutQuoteLayers()
    }

    func stop() {
        rootLayer.removeAllAnimations()
    }

    private func makeQuoteLayer(for quote: StockQuote) -> CATextLayer {
        let layer = CATextLayer()
        let sign = quote.changePercent >= 0 ? "+" : ""
        layer.string = "\(quote.symbol)  \(quote.priceText)  \(sign)\(quote.changePercentText)"
        layer.alignmentMode = .center
        layer.fontSize = 32
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer.foregroundColor = quote.changePercent >= 0
            ? NSColor.systemGreen.cgColor
            : NSColor.systemRed.cgColor
        return layer
    }

    private func layoutQuoteLayers() {
        guard !quoteLayers.isEmpty else { return }
        let spacing: CGFloat = 58
        let totalHeight = CGFloat(quoteLayers.count - 1) * spacing
        let startY = bounds.midY - totalHeight / 2

        for (index, layer) in quoteLayers.enumerated() {
            let wave = sin((phase + CGFloat(index) * 18) / 40) * 12
            layer.frame = CGRect(
                x: 0,
                y: startY + CGFloat(index) * spacing + wave,
                width: bounds.width,
                height: 42
            )
        }
    }
}

