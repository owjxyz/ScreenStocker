import AppKit
import SwiftUI

private extension ScreenSaverAppearanceMode {
    var nsBackgroundColor: NSColor {
        switch self {
        case .light:
            return .white
        case .dark:
            return .black
        case .automatic:
            return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua ? .white : .black
        }
    }
}

private struct StockTickerPalette {
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
        (isLight ? Color.black : Color.white).opacity(0.78)
    }

    var badgeBackground: Color {
        (isLight ? Color.black : Color.white).opacity(0.12)
    }

    var grid: Color {
        (isLight ? Color.black : Color.white).opacity(0.12)
    }
}

@MainActor
final class StockTickerRenderer {
    private var hostingView: NSHostingView<StockTickerScreenView>?

    func attach(
        to view: NSView,
        symbol: String?,
        appearanceMode: ScreenSaverAppearanceMode,
        chartStyle: ScreenSaverChartStyle
    ) {
        let quote = MarketDataCatalog.quote(for: symbol)
        let series = MarketDataCatalog.chartSeries(for: quote.symbol)
        let hostingView = NSHostingView(
            rootView: StockTickerScreenView(
                quote: quote,
                series: series,
                appearanceMode: appearanceMode,
                chartStyle: chartStyle
            )
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = appearanceMode.nsBackgroundColor.cgColor
        view.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        self.hostingView = hostingView
    }

    func update(symbol: String?, appearanceMode: ScreenSaverAppearanceMode, chartStyle: ScreenSaverChartStyle) {
        let quote = MarketDataCatalog.quote(for: symbol)
        hostingView?.layer?.backgroundColor = appearanceMode.nsBackgroundColor.cgColor
        hostingView?.rootView = StockTickerScreenView(
            quote: quote,
            series: MarketDataCatalog.chartSeries(for: quote.symbol),
            appearanceMode: appearanceMode,
            chartStyle: chartStyle
        )
    }
}

private struct StockTickerScreenView: View {
    let quote: StockQuote
    let series: StockChartSeries
    let appearanceMode: ScreenSaverAppearanceMode
    let chartStyle: ScreenSaverChartStyle

    @Environment(\.colorScheme) private var systemColorScheme

    private var accentColor: Color {
        quote.changePercent >= 0 ? .red : .blue
    }

    private var palette: StockTickerPalette {
        StockTickerPalette(appearanceMode: appearanceMode, systemColorScheme: systemColorScheme)
    }

    var body: some View {
        GeometryReader { proxy in
            let sideInset = max(proxy.size.width * 0.07, 44)
            let verticalInset = max(proxy.size.height * 0.08, 38)

            ZStack {
                palette.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 22) {
                        MetricBlock(
                            title: "Open",
                            value: StockQuote.currencyText(for: series.points.first?.close ?? quote.price),
                            palette: palette
                        )
                        MetricBlock(
                            title: "High",
                            value: StockQuote.currencyText(for: series.highClose ?? quote.price),
                            palette: palette
                        )
                        MetricBlock(
                            title: "Low",
                            value: StockQuote.currencyText(for: series.lowClose ?? quote.price),
                            palette: palette
                        )
                        Spacer()
                        Text("Market snapshot")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    }

                    switch chartStyle {
                    case .line:
                        SaverLineChart(series: series, lineColor: accentColor, gridColor: palette.grid)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .candlestick:
                        SaverCandlestickChart(series: series, gridColor: palette.grid)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 10) {
                            StatusBadge(title: "KRX", palette: palette)
                            Text("Updated 15:30 KST")
                                .font(.caption)
                                .foregroundStyle(palette.tertiaryText)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 10) {
                            Text(quote.symbol)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(palette.primaryText)

                            Text(quote.priceText)
                                .font(.system(size: 82, weight: .bold))
                                .foregroundStyle(palette.primaryText)
                                .monospacedDigit()
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)

                            Text(quote.changePercentText)
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(accentColor)
                        }
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
    let gridColor: Color

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)

            ZStack {
                horizontalGrid(in: proxy.size)

                Path { path in
                    guard let firstPoint = points.first else { return }
                    path.move(to: firstPoint)
                    for segment in StockChartGeometry.smoothCurveSegments(through: points) {
                        path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
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
        .stroke(gridColor, style: StrokeStyle(lineWidth: 1, dash: [6, 10]))
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        StockChartGeometry.normalizedPoints(for: series, in: size)
    }
}

private struct SaverCandlestickChart: View {
    let series: StockChartSeries
    let gridColor: Color

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)

            ZStack {
                horizontalGrid(in: proxy.size)

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    let previous = index == 0 ? point : points[index - 1]
                    let candleColor: Color = point.y <= previous.y ? .red : .blue
                    let bodyHeight = max(abs(point.y - previous.y), 12)
                    let candleWidth = max(proxy.size.width / CGFloat(max(points.count, 1)) * 0.42, 10)

                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(candleColor.opacity(0.78))
                            .frame(width: 3, height: max(bodyHeight + 24, 30))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(candleColor)
                            .frame(width: candleWidth, height: bodyHeight)
                    }
                    .position(x: point.x, y: (point.y + previous.y) / 2)
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
        .stroke(gridColor, style: StrokeStyle(lineWidth: 1, dash: [6, 10]))
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        StockChartGeometry.normalizedPoints(for: series, in: size)
    }
}

private struct StatusBadge: View {
    let title: String
    let palette: StockTickerPalette

    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(palette.badgeText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(palette.badgeBackground, in: Capsule())
    }
}

private struct MetricBlock: View {
    let title: String
    let value: String
    let palette: StockTickerPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryText)
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(palette.metricText)
        }
    }
}
