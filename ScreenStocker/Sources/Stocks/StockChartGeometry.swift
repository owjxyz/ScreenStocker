import CoreGraphics
import Foundation

enum StockChartGeometry {
    struct CurveSegment: Equatable {
        let end: CGPoint
        let control1: CGPoint
        let control2: CGPoint
    }

    static func normalizedPoints(for series: StockChartSeries, in size: CGSize) -> [CGPoint] {
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
}
