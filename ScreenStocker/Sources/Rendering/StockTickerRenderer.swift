import AppKit
import Charts
import SwiftUI

@MainActor
final class StockTickerRenderer {
    private let viewModel = StockTickerViewModel()
    private var hostingView: NSHostingView<StockTickerScreenView>?

    func attach(to view: NSView) {
        let hostingView = NSHostingView(rootView: StockTickerScreenView(viewModel: viewModel))
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

    func showLoading(symbol: String) {
        viewModel.state = .loading(symbol: symbol)
    }

    func showEmptyWatchlist() {
        viewModel.state = .emptyWatchlist
    }

    func render(quote: StockQuote, series: StockChartSeries?) {
        viewModel.state = .loaded(quote: quote, series: series)
    }

    func showError(message: String, cachedQuote: StockQuote?, cachedSeries: StockChartSeries?) {
        if let cachedQuote {
            viewModel.state = .stale(quote: cachedQuote, series: cachedSeries, message: message)
        } else {
            viewModel.state = .error(message: message)
        }
    }

    func stop() {}
}

@MainActor
private final class StockTickerViewModel: ObservableObject {
    @Published var state: StockTickerState = .emptyWatchlist
}

private enum StockTickerState {
    case emptyWatchlist
    case loading(symbol: String)
    case loaded(quote: StockQuote, series: StockChartSeries?)
    case stale(quote: StockQuote, series: StockChartSeries?, message: String)
    case error(message: String)
}

private struct StockTickerScreenView: View {
    @ObservedObject var viewModel: StockTickerViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.state {
            case .emptyWatchlist:
                MessageView(
                    title: "No Watchlist Symbols",
                    detail: "Open ScreenStocker to add symbols, then choose one in Screen Saver Settings."
                )
            case .loading(let symbol):
                MessageView(title: symbol, detail: "Loading market data...")
            case .loaded(let quote, let series):
                QuoteDashboardView(quote: quote, series: series, status: nil)
            case .stale(let quote, let series, let message):
                QuoteDashboardView(quote: quote, series: series, status: message)
            case .error(let message):
                MessageView(title: "Market Data Unavailable", detail: message)
            }
        }
    }
}

private struct QuoteDashboardView: View {
    let quote: StockQuote
    let series: StockChartSeries?
    let status: String?

    private var isPositive: Bool {
        quote.changePercent >= 0
    }

    private var lineColor: Color {
        isPositive ? .red : .blue
    }

    var body: some View {
        GeometryReader { proxy in
            let sideInset = max(proxy.size.width * 0.07, 42)
            let verticalInset = max(proxy.size.height * 0.08, 36)

            VStack(alignment: .leading, spacing: 12) {
                header

                if let series, series.points.count >= 2 {
                    StockLineChart(series: series, lineColor: lineColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 28)
                } else {
                    MessageView(title: "No Chart Data", detail: "Latest quote is available.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, sideInset)
            .padding(.vertical, verticalInset)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(quote.symbol)
                .font(.system(size: 34, weight: .semibold, design: .default))
                .foregroundStyle(.white)

            Text(quote.priceText)
                .font(.system(size: 72, weight: .bold, design: .default))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.55)
                .lineLimit(1)

            Text("\(isPositive ? "+" : "")\(quote.changePercentText)")
                .font(.system(size: 30, weight: .medium, design: .default))
                .foregroundStyle(lineColor)
        }
    }
}

private struct StockLineChart: View {
    let series: StockChartSeries
    let lineColor: Color

    private var samples: [StockChartSample] {
        let points = normalizedPoints()
        return points.map { point in
            StockChartSample(
                xRatio: point.xRatio,
                close: decimalNumber(point.point.close).doubleValue,
                point: point.point
            )
        }
    }

    private var closeValues: [Double] {
        samples.map(\.close)
    }

    var body: some View {
        let values = closeValues
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let firstValue = values.first ?? minValue
        let valueRange = max(maxValue - minValue, 1)
        let yDomain = minValue...(minValue + valueRange)

        Chart {
            RuleMark(y: .value("Open", firstValue))
                .foregroundStyle(.white.opacity(0.24))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [8, 9]))

            ForEach(samples) { sample in
                LineMark(
                    x: .value("Session", sample.xRatio),
                    y: .value("Close", sample.close)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(lineColor)
                .lineStyle(StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }

            if let latest = samples.last {
                PointMark(
                    x: .value("Session", latest.xRatio),
                    y: .value("Close", latest.close)
                )
                .foregroundStyle(lineColor)
                .symbolSize(180)
            }
        }
        .chartXScale(domain: 0...1)
        .chartYScale(domain: yDomain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { plotArea in
            plotArea.background(.clear)
        }
        .overlay(alignment: .topTrailing) {
            ValueBadge(title: "High", value: StockQuote.currencyText(for: series.highClose ?? 0))
                .foregroundStyle(lineColor)
        }
        .overlay(alignment: .bottomTrailing) {
            ValueBadge(title: "Low", value: StockQuote.currencyText(for: series.lowClose ?? 0))
                .foregroundStyle(lineColor)
        }
    }

    private func normalizedPoints() -> [ChartPoint] {
        guard let intradayPoints = intradayChartPoints(), intradayPoints.count >= 2 else {
            return indexedChartPoints()
        }
        return intradayPoints
    }

    private func intradayChartPoints() -> [ChartPoint]? {
        guard let latestDate = series.points.last?.date else { return nil }
        let calendar = Self.marketCalendar
        let session = marketSession(containing: latestDate, calendar: calendar)
        let sessionDuration = session.end.timeIntervalSince(session.start)
        guard sessionDuration > 0 else { return nil }

        let points = series.points.compactMap { point -> ChartPoint? in
            guard point.date >= session.start, point.date <= session.end else {
                return nil
            }
            let xRatio = point.date.timeIntervalSince(session.start) / sessionDuration
            return ChartPoint(point: point, xRatio: min(max(xRatio, 0), 1))
        }

        return points.count >= 2 ? points : nil
    }

    private func indexedChartPoints() -> [ChartPoint] {
        series.points.enumerated().map { index, point in
            let denominator = Double(max(series.points.count - 1, 1))
            return ChartPoint(point: point, xRatio: Double(index) / denominator)
        }
    }

    private func marketSession(containing date: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let start = calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: components.year,
                month: components.month,
                day: components.day,
                hour: 9,
                minute: 30
            )
        ) ?? date
        let end = calendar.date(byAdding: .minute, value: 390, to: start) ?? start
        return (start, end)
    }

    private func decimalNumber(_ decimal: Decimal) -> NSDecimalNumber {
        decimal as NSDecimalNumber
    }

    private static let marketCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private struct ChartPoint {
        let point: StockTimeSeriesPoint
        let xRatio: Double
    }
}

private struct StockChartSample: Identifiable {
    let id = UUID()
    let xRatio: Double
    let close: Double
    let point: StockTimeSeriesPoint
}

private struct ValueBadge: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(value)
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.48), in: Capsule())
    }
}

private struct MessageView: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(32)
    }
}
