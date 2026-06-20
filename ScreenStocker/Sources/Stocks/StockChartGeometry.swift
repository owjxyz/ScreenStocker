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
        guard series.points.count > 1,
              let minValue = range.min,
              let maxValue = range.max else {
            return []
        }

        return series.points.enumerated().map { index, point in
            let x = CGFloat(index) / CGFloat(series.points.count - 1) * size.width
            let value = NSDecimalNumber(decimal: point.close).doubleValue
            let yRatio = (value - minValue) / max(maxValue - minValue, 1)
            let y = size.height - CGFloat(yRatio) * size.height
            return CGPoint(x: x, y: y)
        }
    }

    static func normalizedCandles(for series: StockChartSeries, in size: CGSize) -> [CandlePoint] {
        let range = priceRange(for: series)
        guard series.points.count > 1,
              let minValue = range.min,
              let maxValue = range.max else {
            return []
        }

        return series.points.enumerated().map { index, point in
            CandlePoint(
                x: CGFloat(index) / CGFloat(series.points.count - 1) * size.width,
                openY: yPosition(for: point.open, minValue: minValue, maxValue: maxValue, height: size.height),
                highY: yPosition(for: point.high, minValue: minValue, maxValue: maxValue, height: size.height),
                lowY: yPosition(for: point.low, minValue: minValue, maxValue: maxValue, height: size.height),
                closeY: yPosition(for: point.close, minValue: minValue, maxValue: maxValue, height: size.height)
            )
        }
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

    private static func yPosition(for value: Decimal, minValue: Double, maxValue: Double, height: CGFloat) -> CGFloat {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        let yRatio = (doubleValue - minValue) / max(maxValue - minValue, 1)
        return height - CGFloat(yRatio) * height
    }
}
