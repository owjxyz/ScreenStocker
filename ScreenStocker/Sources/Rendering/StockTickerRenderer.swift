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

enum StockTickerDisplayMode {
    case screenSaver
    case preview

    func horizontalInset(for size: CGSize) -> CGFloat {
        switch self {
        case .screenSaver:
            return max(size.width * 0.07, 44)
        case .preview:
            return 22
        }
    }

    func verticalInset(for size: CGSize) -> CGFloat {
        switch self {
        case .screenSaver:
            return max(size.height * 0.08, 38)
        case .preview:
            return 22
        }
    }

    var stackSpacing: CGFloat { self == .screenSaver ? 24 : 14 }
    var headerSpacing: CGFloat { self == .screenSaver ? 22 : 16 }
    var badgeHorizontalPadding: CGFloat { self == .screenSaver ? 12 : 10 }
    var badgeVerticalPadding: CGFloat { self == .screenSaver ? 7 : 5 }
    var metricSpacing: CGFloat { self == .screenSaver ? 22 : 16 }
    var priceColumnSpacing: CGFloat { self == .screenSaver ? 10 : 6 }
    var titleFontSize: CGFloat { self == .screenSaver ? 36 : 24 }
    var priceFontSize: CGFloat { self == .screenSaver ? 82 : 44 }
    var changeFont: Font { self == .screenSaver ? .system(size: 32, weight: .semibold) : .body.weight(.semibold) }
    var metricValueFont: Font { self == .screenSaver ? .body.monospacedDigit().weight(.semibold) : .caption.monospacedDigit().weight(.semibold) }
    var lineWidth: CGFloat { self == .screenSaver ? 6 : 4 }
    var trackingPointDiameter: CGFloat { self == .screenSaver ? 18 : 10 }
    var gridLineCount: Int { self == .screenSaver ? 4 : 3 }
    var gridDash: [CGFloat] { self == .screenSaver ? [6, 10] : [5, 8] }
    var candleWickWidth: CGFloat { self == .screenSaver ? 3 : 2 }
    var candleMinimumBodyHeight: CGFloat { self == .screenSaver ? 12 : 4 }
    var candleMinimumWickHeight: CGFloat { self == .screenSaver ? 30 : 14 }
    var candleCornerRadius: CGFloat { self == .screenSaver ? 3 : 2 }
    var minimumScaleFactor: CGFloat { self == .screenSaver ? 0.5 : 0.7 }
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
            chartStyle: chartStyle,
            displayMode: .screenSaver
        )
    }
}

struct StockTickerScreenView: View {
    let quote: StockQuote
    let series: StockChartSeries
    let appearanceMode: ScreenSaverAppearanceMode
    let chartStyle: ScreenSaverChartStyle
    var displayMode: StockTickerDisplayMode = .screenSaver

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
            let sideInset = displayMode.horizontalInset(for: proxy.size)
            let verticalInset = displayMode.verticalInset(for: proxy.size)

            ZStack {
                palette.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: displayMode.stackSpacing) {
                    HStack(spacing: displayMode.headerSpacing) {
                        VStack(alignment: .leading, spacing: 10) {
                            StatusBadge(title: exchangeLabelText, palette: palette, displayMode: displayMode)
                        }

                        Spacer()

                        Text(updatedText)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    }

                    switch chartStyle {
                    case .line:
                        SaverLineChart(
                            series: series,
                            lineColor: accentColor,
                            gridColor: palette.grid,
                            displayMode: displayMode
                        )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .candlestick:
                        SaverCandlestickChart(
                            series: series,
                            gridColor: palette.grid,
                            displayMode: displayMode
                        )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    HStack(alignment: .bottom) {
                        HStack(spacing: displayMode.metricSpacing) {
                            MetricBlock(
                                title: "Open",
                                value: StockQuote.currencyText(for: series.openingPrice ?? quote.price, currency: quote.currency),
                                palette: palette,
                                displayMode: displayMode
                            )
                            MetricBlock(
                                title: "High",
                                value: StockQuote.currencyText(for: series.highClose ?? quote.price, currency: quote.currency),
                                palette: palette,
                                displayMode: displayMode
                            )
                            MetricBlock(
                                title: "Low",
                                value: StockQuote.currencyText(for: series.lowClose ?? quote.price, currency: quote.currency),
                                palette: palette,
                                displayMode: displayMode
                            )
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: displayMode.priceColumnSpacing) {
                            Text(quote.titleText)
                                .font(.system(size: displayMode.titleFontSize, weight: .semibold))
                                .foregroundStyle(palette.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(displayMode.minimumScaleFactor)

                            Text(quote.priceText)
                                .font(.system(size: displayMode.priceFontSize, weight: .bold))
                                .foregroundStyle(palette.primaryText)
                                .monospacedDigit()
                                .minimumScaleFactor(displayMode.minimumScaleFactor)
                                .lineLimit(1)

                            Text(quote.changePercentText)
                                .font(displayMode.changeFont)
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
    let displayMode: StockTickerDisplayMode

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
                .stroke(
                    lineColor,
                    style: StrokeStyle(lineWidth: displayMode.lineWidth, lineCap: .round, lineJoin: .round)
                )

                if let trackingPoint = points.last {
                    TrackingPointMarker(color: lineColor, diameter: displayMode.trackingPointDiameter)
                        .position(trackingPoint)
                }
            }
        }
    }

    private func horizontalGrid(in size: CGSize) -> some View {
        Path { path in
            let divisor = max(CGFloat(displayMode.gridLineCount - 1), 1)
            for index in 0..<displayMode.gridLineCount {
                let y = CGFloat(index) / divisor * size.height
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(gridColor, style: StrokeStyle(lineWidth: 1, dash: displayMode.gridDash))
    }

    private func verticalSessionGrid(in size: CGSize) -> some View {
        Path { path in
            for x in sessionDividerPositions(in: size) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
        .stroke(gridColor, style: StrokeStyle(lineWidth: 1, dash: displayMode.gridDash))
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
    let displayMode: StockTickerDisplayMode

    var body: some View {
        GeometryReader { proxy in
            let candles = normalizedCandles(in: proxy.size)

            ZStack {
                horizontalGrid(in: proxy.size)
                verticalSessionGrid(in: proxy.size)

                ForEach(Array(candles.enumerated()), id: \.offset) { _, candle in
                    let candleColor: Color = candle.closeY <= candle.openY ? .red : .blue
                    let bodyHeight = max(abs(candle.closeY - candle.openY), displayMode.candleMinimumBodyHeight)
                    let candleWidth = StockChartGeometry.recommendedCandleWidth(for: series, in: proxy.size)

                    Group {
                        Rectangle()
                            .fill(candleColor.opacity(0.78))
                            .frame(
                                width: displayMode.candleWickWidth,
                                height: max(candle.lowY - candle.highY, displayMode.candleMinimumWickHeight)
                            )
                            .position(x: candle.x, y: (candle.highY + candle.lowY) / 2)
                        RoundedRectangle(cornerRadius: displayMode.candleCornerRadius)
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
            let divisor = max(CGFloat(displayMode.gridLineCount - 1), 1)
            for index in 0..<displayMode.gridLineCount {
                let y = CGFloat(index) / divisor * size.height
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(gridColor, style: StrokeStyle(lineWidth: 1, dash: displayMode.gridDash))
    }

    private func verticalSessionGrid(in size: CGSize) -> some View {
        Path { path in
            for x in sessionDividerPositions(in: size) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
        .stroke(gridColor, style: StrokeStyle(lineWidth: 1, dash: displayMode.gridDash))
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
    let displayMode: StockTickerDisplayMode

    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(palette.badgeText)
            .padding(.horizontal, displayMode.badgeHorizontalPadding)
            .padding(.vertical, displayMode.badgeVerticalPadding)
            .background(palette.badgeBackground, in: Capsule())
    }
}

private struct MetricBlock: View {
    let title: String
    let value: String
    let palette: StockTickerPalette
    let displayMode: StockTickerDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryText)
            Text(value)
                .font(displayMode.metricValueFont)
                .foregroundStyle(palette.metricText)
        }
    }
}
