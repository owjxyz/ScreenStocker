import AppKit
import Charts
import QuartzCore
import SwiftUI

final class StockTickerRenderer {
    private let rootLayer = CALayer()
    private let symbolLayer = CATextLayer()
    private let priceLayer = CATextLayer()
    private let changeLayer = CATextLayer()
    private let highLayer = CATextLayer()
    private let lowLayer = CATextLayer()
    private let endpointLayer = CAShapeLayer()
    private var chartHostingView: NSHostingView<StockTickerChartView>?
    private var quote: StockQuote?
    private var series: StockChartSeries?
    private var bounds: CGRect
    private var phase: CGFloat = 0

    init(bounds: CGRect) {
        self.bounds = bounds
        rootLayer.masksToBounds = true
        rootLayer.backgroundColor = NSColor.black.cgColor

        configureTextLayer(symbolLayer, fontSize: 34, weight: .semibold, color: .white)
        configureTextLayer(priceLayer, fontSize: 72, weight: .bold, color: .white)
        configureTextLayer(changeLayer, fontSize: 30, weight: .medium, color: .secondaryLabelColor)
        configureTextLayer(highLayer, fontSize: 22, weight: .semibold, color: .systemRed)
        configureTextLayer(lowLayer, fontSize: 22, weight: .semibold, color: .systemRed)

        endpointLayer.fillColor = NSColor.systemRed.cgColor
        endpointLayer.strokeColor = NSColor.clear.cgColor
        endpointLayer.shadowColor = NSColor.white.cgColor
        endpointLayer.shadowOffset = .zero
        endpointLayer.shadowRadius = 18
        endpointLayer.shadowOpacity = 0.85

        [endpointLayer, symbolLayer, priceLayer, changeLayer, highLayer, lowLayer]
            .forEach(rootLayer.addSublayer)
    }

    func attach(to view: NSView) {
        view.layer?.addSublayer(rootLayer)
        let hostingView = NSHostingView(rootView: StockTickerChartView(configuration: nil))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = []
        hostingView.isHidden = true
        view.addSubview(hostingView)
        chartHostingView = hostingView
        resize(to: view.bounds)
    }

    func resize(to newBounds: CGRect) {
        bounds = newBounds
        rootLayer.frame = newBounds
        layoutLayers()
    }

    func render(quote: StockQuote, series: StockChartSeries?) {
        self.quote = quote
        self.series = series
        layoutLayers()
    }

    func tick() {
        phase += 0.05
        let pulse = (sin(phase * 2.8) + 1) / 2
        let scale = 0.92 + pulse * 0.32
        endpointLayer.transform = CATransform3DMakeScale(scale, scale, 1)
        endpointLayer.opacity = Float(0.38 + pulse * 0.62)
        endpointLayer.shadowOpacity = Float(0.22 + pulse * 0.78)
        endpointLayer.shadowRadius = 12 + pulse * 18
    }

    func stop() {
        rootLayer.removeAllAnimations()
    }

    private func layoutLayers() {
        guard let quote else {
            clearChart()
            return
        }

        let lineColor = quote.changePercent >= 0 ? NSColor.systemRed : NSColor.systemBlue
        let sideInset = max(bounds.width * 0.07, 42)
        let topInset = max(bounds.height * 0.08, 36)
        let priceHeight = max(bounds.height * 0.12, 82)
        let chartTop = topInset + 150
        let chartBottomInset = max(bounds.height * 0.11, 72)
        let chartFrame = CGRect(
            x: sideInset,
            y: chartBottomInset,
            width: max(bounds.width - sideInset * 2, 10),
            height: max(bounds.height - chartTop - chartBottomInset, 10)
        )

        symbolLayer.string = quote.symbol
        symbolLayer.frame = CGRect(x: sideInset, y: bounds.height - topInset - 44, width: bounds.width - sideInset * 2, height: 44)

        priceLayer.string = quote.priceText
        priceLayer.frame = CGRect(x: sideInset, y: bounds.height - topInset - 44 - priceHeight, width: bounds.width - sideInset * 2, height: priceHeight)

        let sign = quote.changePercent >= 0 ? "+" : ""
        changeLayer.string = "\(sign)\(quote.changePercentText)"
        changeLayer.foregroundColor = lineColor.cgColor
        changeLayer.frame = CGRect(x: sideInset, y: bounds.height - topInset - 44 - priceHeight - 42, width: bounds.width - sideInset * 2, height: 38)

        let chartLineWidth = max(min(bounds.width, bounds.height) * 0.006, 4)
        endpointLayer.fillColor = lineColor.withAlphaComponent(0.92).cgColor
        highLayer.foregroundColor = lineColor.cgColor
        lowLayer.foregroundColor = lineColor.cgColor

        guard let series, series.points.count >= 2 else {
            clearChart()
            return
        }

        drawChart(series: series, in: chartFrame, color: lineColor, lineWidth: chartLineWidth)
    }

    private func drawChart(series: StockChartSeries, in chartFrame: CGRect, color: NSColor, lineWidth: CGFloat) {
        let chartPoints = intradayChartPoints(from: series) ?? indexedChartPoints(from: series)
        let closes = chartPoints.map(\.point.close)
        guard let minClose = closes.min(),
              let maxClose = closes.max(),
              let firstClose = closes.first else {
            clearChart()
            return
        }

        let minValue = decimalNumber(minClose).doubleValue
        let maxValue = decimalNumber(maxClose).doubleValue
        let valueRange = max(maxValue - minValue, 1)

        var latestPoint = CGPoint.zero
        var highPoint = CGPoint.zero
        var lowPoint = CGPoint.zero
        let chartSamples = chartPoints.map { chartPoint in
            StockTickerChartSample(
                xRatio: Double(chartPoint.xRatio),
                close: decimalNumber(chartPoint.point.close).doubleValue
            )
        }

        for chartPoint in chartPoints {
            let point = chartPoint.point
            let value = decimalNumber(point.close).doubleValue
            let x = chartFrame.minX + chartPoint.xRatio * chartFrame.width
            let yRatio = CGFloat((value - minValue) / valueRange)
            let y = chartFrame.minY + yRatio * chartFrame.height
            let cgPoint = CGPoint(x: x, y: y)

            if point.close == maxClose {
                highPoint = cgPoint
            }
            if point.close == minClose {
                lowPoint = cgPoint
            }
            latestPoint = cgPoint
        }

        chartHostingView?.frame = chartFrame
        chartHostingView?.isHidden = false
        chartHostingView?.rootView = StockTickerChartView(
            configuration: StockTickerChartConfiguration(
                samples: chartSamples,
                baseline: decimalNumber(firstClose).doubleValue,
                minValue: minValue,
                maxValue: minValue + valueRange,
                lineColor: Color(nsColor: color),
                lineWidth: lineWidth
            )
        )

        let dotRadius = max(min(bounds.width, bounds.height) * 0.011, 9)
        endpointLayer.bounds = CGRect(x: 0, y: 0, width: dotRadius * 2, height: dotRadius * 2)
        endpointLayer.position = latestPoint
        endpointLayer.path = CGPath(ellipseIn: endpointLayer.bounds, transform: nil)
        endpointLayer.shadowPath = endpointLayer.path

        highLayer.string = "High \(StockQuote.currencyText(for: maxClose))"
        lowLayer.string = "Low \(StockQuote.currencyText(for: minClose))"
        highLayer.frame = labelFrame(anchoredAt: highPoint, in: chartFrame, preferAbove: true)
        lowLayer.frame = labelFrame(anchoredAt: lowPoint, in: chartFrame, preferAbove: false)
    }

    private func intradayChartPoints(from series: StockChartSeries) -> [ChartPoint]? {
        guard let latestDate = series.points.last?.date else { return nil }
        let calendar = Self.marketCalendar
        let session = marketSession(containing: latestDate, calendar: calendar)
        let sessionDuration = session.end.timeIntervalSince(session.start)
        guard sessionDuration > 0 else { return nil }

        let points = series.points.compactMap { point -> ChartPoint? in
            guard point.date >= session.start, point.date <= session.end else {
                return nil
            }
            let xRatio = CGFloat(point.date.timeIntervalSince(session.start) / sessionDuration)
            return ChartPoint(point: point, xRatio: min(max(xRatio, 0), 1))
        }

        guard points.count >= 2 else { return nil }
        return points
    }

    private func indexedChartPoints(from series: StockChartSeries) -> [ChartPoint] {
        series.points.enumerated().map { index, point in
            let denominator = CGFloat(max(series.points.count - 1, 1))
            return ChartPoint(point: point, xRatio: CGFloat(index) / denominator)
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

    private func labelFrame(anchoredAt point: CGPoint, in chartFrame: CGRect, preferAbove: Bool) -> CGRect {
        let size = CGSize(width: min(max(bounds.width * 0.24, 150), 260), height: 30)
        let x = min(max(point.x - size.width / 2, chartFrame.minX), chartFrame.maxX - size.width)
        let candidateY = preferAbove ? point.y + 18 : point.y - size.height - 18
        let y = min(max(candidateY, chartFrame.minY), chartFrame.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func clearChart() {
        chartHostingView?.isHidden = true
        chartHostingView?.rootView = StockTickerChartView(configuration: nil)
        endpointLayer.path = nil
        highLayer.string = nil
        lowLayer.string = nil
    }

    private func configureTextLayer(
        _ layer: CATextLayer,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        color: NSColor
    ) {
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer.foregroundColor = color.cgColor
        layer.font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        layer.fontSize = fontSize
        layer.alignmentMode = .left
        layer.truncationMode = .end
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
        let xRatio: CGFloat
    }
}

private struct StockTickerChartSample: Identifiable, Equatable {
    let id = UUID()
    let xRatio: Double
    let close: Double
}

private struct StockTickerChartConfiguration: Equatable {
    let samples: [StockTickerChartSample]
    let baseline: Double
    let minValue: Double
    let maxValue: Double
    let lineColor: Color
    let lineWidth: CGFloat
}

private struct StockTickerChartView: View {
    let configuration: StockTickerChartConfiguration?

    var body: some View {
        if let configuration {
            Chart {
                RuleMark(y: .value("Open", configuration.baseline))
                    .foregroundStyle(.white.opacity(0.24))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [8, 9]))

                ForEach(configuration.samples) { sample in
                    LineMark(
                        x: .value("Session", sample.xRatio),
                        y: .value("Close", sample.close)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(configuration.lineColor)
                    .lineStyle(StrokeStyle(lineWidth: configuration.lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
            .chartXScale(domain: 0...1)
            .chartYScale(domain: configuration.minValue...configuration.maxValue)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { plotArea in
                plotArea.background(.clear)
            }
            .background(.clear)
        } else {
            Color.clear
        }
    }
}
