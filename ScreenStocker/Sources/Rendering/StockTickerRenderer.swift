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
    private var symbol: String?
    private var quote: StockQuote?
    private var series: StockChartSeries?
    private var appearanceMode: ScreenSaverAppearanceMode = .dark
    private var chartStyle: ScreenSaverChartStyle = .line

    func attach(
        to view: NSView,
        symbol: String?,
        appearanceMode: ScreenSaverAppearanceMode,
        chartStyle: ScreenSaverChartStyle
    ) {
        self.symbol = symbol
        self.quote = StockQuote.placeholder(symbol: symbol)
        self.series = StockChartSeries(symbol: symbol ?? "-", points: [])
        self.appearanceMode = appearanceMode
        self.chartStyle = chartStyle

        let hostingView = NSHostingView(
            rootView: rootView()
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
        let didChangeSymbol = symbol != self.symbol
        self.symbol = symbol
        self.appearanceMode = appearanceMode
        self.chartStyle = chartStyle

        if didChangeSymbol {
            quote = StockQuote.placeholder(symbol: symbol)
            series = StockChartSeries(symbol: symbol ?? "-", points: [])
        }

        hostingView?.layer?.backgroundColor = appearanceMode.nsBackgroundColor.cgColor
        hostingView?.rootView = rootView()
    }

    func update(snapshot: StockMarketSnapshot) {
        quote = snapshot.quote
        series = snapshot.series
        symbol = snapshot.quote.symbol
        hostingView?.rootView = rootView()
    }

    private func rootView() -> StockTickerScreenView {
        StockTickerScreenView(
            quote: quote ?? StockQuote.placeholder(symbol: symbol),
            series: series ?? StockChartSeries(symbol: symbol ?? "-", points: []),
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
        guard let changePercent = quote.changePercent else { return palette.secondaryText }
        return changePercent >= 0 ? .red : .blue
    }

    private var palette: StockTickerPalette {
        StockTickerPalette(appearanceMode: appearanceMode, systemColorScheme: systemColorScheme)
    }

    private var exchangeLabelText: String {
        if let exchangeLabel = quote.exchangeLabel, !exchangeLabel.isEmpty {
            return exchangeLabel
        }
        return StockSymbolInput.marketKind(for: quote.symbol) == .krx ? "KRX" : "US"
    }

    var body: some View {
        GeometryReader { proxy in
            let sideInset = max(proxy.size.width * 0.07, 44)
            let verticalInset = max(proxy.size.height * 0.08, 38)

            ZStack {
                palette.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            StatusBadge(title: exchangeLabelText, palette: palette)
                        }

                        Spacer()

                        Text(updatedText)
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
                        HStack(spacing: 22) {
                            MetricBlock(
                                title: "Open",
                                value: StockQuote.currencyText(for: series.openingPrice ?? quote.price, currency: quote.currency),
                                palette: palette
                            )
                            MetricBlock(
                                title: "High",
                                value: StockQuote.currencyText(for: series.highClose ?? quote.price, currency: quote.currency),
                                palette: palette
                            )
                            MetricBlock(
                                title: "Low",
                                value: StockQuote.currencyText(for: series.lowClose ?? quote.price, currency: quote.currency),
                                palette: palette
                            )
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 10) {
                            Text(quote.titleText)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(palette.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)

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

private struct SaverLineChart: View {
    let series: StockChartSeries
    let lineColor: Color
    let gridColor: Color

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)

            ZStack {
                horizontalGrid(in: proxy.size)
                verticalSessionGrid(in: proxy.size)

                Path { path in
                    guard let firstPoint = points.first else { return }
                    path.move(to: firstPoint)
                    for segment in StockChartGeometry.smoothCurveSegments(through: points) {
                        path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
                    }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))

                if let trackingPoint = points.last {
                    TrackingPointMarker(color: lineColor, diameter: 18)
                        .position(trackingPoint)
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

    private func verticalSessionGrid(in size: CGSize) -> some View {
        Path { path in
            for x in sessionDividerPositions(in: size) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
        .stroke(gridColor, style: StrokeStyle(lineWidth: 1, dash: [6, 10]))
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        StockChartGeometry.normalizedPoints(for: series, in: size)
    }

    private func sessionDividerPositions(in size: CGSize) -> [CGFloat] {
        series.sessionDividers
            .map { StockChartGeometry.normalizedXPosition(for: $0, in: series, size: size) }
    }
}

private struct TrackingPointMarker: View {
    let color: Color
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(reduceMotion ? 0.34 : 0.38))
                .frame(width: diameter * 1.9, height: diameter * 1.9)
                .scaleEffect(reduceMotion ? 1 : (isPulsing ? 1.75 : 0.8))
                .opacity(reduceMotion ? 1 : (isPulsing ? 0 : 0.68))

            Circle()
                .fill(color)
                .frame(width: diameter, height: diameter)
        }
        .onAppear {
            guard !reduceMotion else { return }
            isPulsing = true
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
            value: isPulsing
        )
    }
}

private struct SaverCandlestickChart: View {
    let series: StockChartSeries
    let gridColor: Color

    var body: some View {
        GeometryReader { proxy in
            let candles = normalizedCandles(in: proxy.size)

            ZStack {
                horizontalGrid(in: proxy.size)
                verticalSessionGrid(in: proxy.size)

                ForEach(Array(candles.enumerated()), id: \.offset) { _, candle in
                    let candleColor: Color = candle.closeY <= candle.openY ? .red : .blue
                    let bodyHeight = max(abs(candle.closeY - candle.openY), 12)
                    let candleWidth = StockChartGeometry.recommendedCandleWidth(for: series, in: proxy.size)

                    Group {
                        Rectangle()
                            .fill(candleColor.opacity(0.78))
                            .frame(width: 3, height: max(candle.lowY - candle.highY, 30))
                            .position(x: candle.x, y: (candle.highY + candle.lowY) / 2)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(candleColor)
                            .frame(width: candleWidth, height: bodyHeight)
                            .position(x: candle.x, y: (candle.openY + candle.closeY) / 2)
                    }
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

    private func verticalSessionGrid(in size: CGSize) -> some View {
        Path { path in
            for x in sessionDividerPositions(in: size) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
        .stroke(gridColor, style: StrokeStyle(lineWidth: 1, dash: [6, 10]))
    }

    private func normalizedCandles(in size: CGSize) -> [StockChartGeometry.CandlePoint] {
        StockChartGeometry.normalizedCandles(for: series, in: size)
    }

    private func sessionDividerPositions(in size: CGSize) -> [CGFloat] {
        series.sessionDividers
            .map { StockChartGeometry.normalizedXPosition(for: $0, in: series, size: size) }
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
