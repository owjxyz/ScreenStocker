import Foundation

struct StockTimeSeriesPoint: Equatable {
    let date: Date
    let close: Decimal
}

struct StockChartSeries: Equatable {
    let symbol: String
    let points: [StockTimeSeriesPoint]

    var latestClose: Decimal? {
        points.last?.close
    }

    var highClose: Decimal? {
        points.map(\.close).max()
    }

    var lowClose: Decimal? {
        points.map(\.close).min()
    }
}
