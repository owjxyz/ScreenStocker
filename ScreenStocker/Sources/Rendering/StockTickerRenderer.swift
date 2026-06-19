import AppKit
import SwiftUI

@MainActor
final class StockTickerRenderer {
    private var hostingView: NSHostingView<StockTickerScreenView>?

    func attach(to view: NSView, symbol: String?) {
        let quote = MarketDataCatalog.quote(for: symbol)
        let series = MarketDataCatalog.chartSeries(for: quote.symbol)
        let hostingView = NSHostingView(rootView: StockTickerScreenView(quote: quote, series: series))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.black.cgColor
        view.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        self.hostingView = hostingView
    }

    func update(symbol: String?) {
        let quote = MarketDataCatalog.quote(for: symbol)
        hostingView?.rootView = StockTickerScreenView(
            quote: quote,
            series: MarketDataCatalog.chartSeries(for: quote.symbol)
        )
    }
}

private struct StockTickerScreenView: View {
    let quote: StockQuote
    let series: StockChartSeries

    private var accentColor: Color {
        quote.changePercent >= 0 ? .red : .blue
    }

    var body: some View {
        GeometryReader { proxy in
            let sideInset = max(proxy.size.width * 0.07, 44)
            let verticalInset = max(proxy.size.height * 0.08, 38)

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(quote.symbol)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(.white)

                            Text(quote.priceText)
                                .font(.system(size: 82, weight: .bold))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)

                            Text(quote.changePercentText)
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(accentColor)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 10) {
                            StatusBadge(title: "KRX")
                            Text("Updated 15:30 KST")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.58))
                        }
                    }

                    SaverLineChart(series: series, lineColor: accentColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    HStack(spacing: 22) {
                        MetricBlock(title: "Open", value: StockQuote.currencyText(for: series.points.first?.close ?? quote.price))
                        MetricBlock(title: "High", value: StockQuote.currencyText(for: series.highClose ?? quote.price))
                        MetricBlock(title: "Low", value: StockQuote.currencyText(for: series.lowClose ?? quote.price))
                        Spacer()
                        Text("Market snapshot")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.52))
                    }
                }
                .padding(.horizontal, sideInset)
                .padding(.vertical, verticalInset)
            }
        }
    }
}

private struct SaverLineChart: View {
    let series: StockChartSeries
    let lineColor: Color

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)

            ZStack {
                horizontalGrid(in: proxy.size)

                Path { path in
                    guard let firstPoint = points.first else { return }
                    path.move(to: firstPoint)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))

                if let lastPoint = points.last {
                    Circle()
                        .fill(lineColor)
                        .frame(width: 18, height: 18)
                        .position(lastPoint)
                }
            }
        }
    }

    private func horizontalGrid(in size: CGSize) -> some View {
        Path { path in
            for index in 0..<4 {
                let y = CGFloat(index) / 3 * size.height
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [6, 10]))
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let values = series.points.map { NSDecimalNumber(decimal: $0.close).doubleValue }
        guard values.count > 1,
              let minValue = values.min(),
              let maxValue = values.max() else {
            return []
        }

        let range = max(maxValue - minValue, 1)
        return values.enumerated().map { index, value in
            let x = CGFloat(index) / CGFloat(values.count - 1) * size.width
            let yRatio = (value - minValue) / range
            let y = size.height - CGFloat(yRatio) * size.height
            return CGPoint(x: x, y: y)
        }
    }
}

private struct StatusBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.white.opacity(0.12), in: Capsule())
    }
}

private struct MetricBlock: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.54))
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}
