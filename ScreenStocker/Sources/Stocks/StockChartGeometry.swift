import CoreGraphics
import Foundation

enum StockChartGeometry {
    struct CurveSegment: Equatable {
        let end: CGPoint
        let control1: CGPoint
        let control2: CGPoint
    }

    struct CandlePoint: Equatable {
        let x: CGFloat
        let openY: CGFloat
        let highY: CGFloat
        let lowY: CGFloat
        let closeY: CGFloat
    }

    static func normalizedPoints(for series: StockChartSeries, in size: CGSize) -> [CGPoint] {
        let range = priceRange(for: series)
        let xPositions = normalizedXPositions(for: series, in: size)
        guard !series.points.isEmpty,
              let minValue = range.min,
              let maxValue = range.max,
              xPositions.count == series.points.count else {
            return []
        }

        return series.points.enumerated().map { index, point in
            let value = NSDecimalNumber(decimal: point.close).doubleValue
            let yRatio = (value - minValue) / max(maxValue - minValue, 1)
            let y = size.height - CGFloat(yRatio) * size.height
            return CGPoint(x: xPositions[index], y: y)
        }
    }

    static func normalizedCandles(for series: StockChartSeries, in size: CGSize) -> [CandlePoint] {
        let range = priceRange(for: series)
        let xPositions = normalizedXPositions(for: series, in: size)
        guard !series.points.isEmpty,
              let minValue = range.min,
              let maxValue = range.max,
              xPositions.count == series.points.count else {
            return []
        }

        return series.points.enumerated().map { index, point in
            CandlePoint(
                x: xPositions[index],
                openY: yPosition(for: point.open, minValue: minValue, maxValue: maxValue, height: size.height),
                highY: yPosition(for: point.high, minValue: minValue, maxValue: maxValue, height: size.height),
                lowY: yPosition(for: point.low, minValue: minValue, maxValue: maxValue, height: size.height),
                closeY: yPosition(for: point.close, minValue: minValue, maxValue: maxValue, height: size.height)
            )
        }
    }

    static func recommendedCandleWidth(for series: StockChartSeries, in size: CGSize) -> CGFloat {
        guard size.width > 0 else {
            return 0
        }

        if let sessionDuration = series.sessionDuration, sessionDuration > 0 {
            let estimatedInterval = estimatedCandleInterval(for: series)
            let width = size.width * CGFloat(estimatedInterval / sessionDuration) * 0.8
            return max(width, 4)
        }

        let xPositions = normalizedXPositions(for: series, in: size).sorted()
        let spacing = zip(xPositions, xPositions.dropFirst())
            .map { max($1 - $0, 0) }
            .filter { $0 > 0 }
            .min()

        if let spacing {
            return max(spacing * 0.7, 4)
        }

        return max(size.width * 0.04, 4)
    }

    static func normalizedXPosition(for date: Date, in series: StockChartSeries, size: CGSize) -> CGFloat {
        guard size.width > 0 else {
            return 0
        }

        let sessionStart = series.sessionStart ?? series.points.first?.date ?? date
        let sessionEnd = series.sessionEnd ?? series.points.last?.date ?? sessionStart
        let sessionDuration = max(sessionEnd.timeIntervalSince(sessionStart), 1)
        let elapsed = min(max(date.timeIntervalSince(sessionStart), 0), sessionDuration)
        return CGFloat(elapsed / sessionDuration) * size.width
    }

    static func smoothCurveSegments(through points: [CGPoint]) -> [CurveSegment] {
        guard points.count > 1 else {
            return []
        }

        return points.indices.dropFirst().map { index in
            let previous = points[index - 1]
            let current = points[index]
            let pointBeforePrevious = points[max(index - 2, 0)]
            let pointAfterCurrent = points[min(index + 1, points.count - 1)]

            let control1 = CGPoint(
                x: previous.x + (current.x - pointBeforePrevious.x) / 6,
                y: previous.y + (current.y - pointBeforePrevious.y) / 6
            )
            let control2 = CGPoint(
                x: current.x - (pointAfterCurrent.x - previous.x) / 6,
                y: current.y - (pointAfterCurrent.y - previous.y) / 6
            )

            return CurveSegment(end: current, control1: control1, control2: control2)
        }
    }

    private static func priceRange(for series: StockChartSeries) -> (min: Double?, max: Double?) {
        let lows = series.points.map { NSDecimalNumber(decimal: $0.low).doubleValue }
        let highs = series.points.map { NSDecimalNumber(decimal: $0.high).doubleValue }
        return (lows.min(), highs.max())
    }

    private static func normalizedXPositions(for series: StockChartSeries, in size: CGSize) -> [CGFloat] {
        guard size.width > 0, !series.points.isEmpty else {
            return []
        }

        return series.points.map { normalizedXPosition(for: $0.date, in: series, size: size) }
    }

    private static func estimatedCandleInterval(for series: StockChartSeries) -> TimeInterval {
        let intervals = zip(series.points, series.points.dropFirst())
            .map { $1.date.timeIntervalSince($0.date) }
            .filter { $0 > 0 }

        if let interval = intervals.min() {
            return interval
        }

        return 600
    }

    private static func yPosition(for value: Decimal, minValue: Double, maxValue: Double, height: CGFloat) -> CGFloat {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        let yRatio = (doubleValue - minValue) / max(maxValue - minValue, 1)
        return height - CGFloat(yRatio) * height
    }
}
