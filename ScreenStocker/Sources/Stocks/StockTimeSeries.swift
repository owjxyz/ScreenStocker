import Foundation

struct StockTimeSeriesPoint: Equatable {
    let date: Date
    let open: Decimal
    let high: Decimal
    let low: Decimal
    let close: Decimal

    init(date: Date, open: Decimal, high: Decimal, low: Decimal, close: Decimal) {
        self.date = date
        self.open = open
        self.high = high
        self.low = low
        self.close = close
    }

    init(date: Date, close: Decimal) {
        self.init(date: date, open: close, high: close, low: close, close: close)
    }
}

struct StockChartSeries: Equatable {
    let symbol: String
    let points: [StockTimeSeriesPoint]
    let sessionStart: Date?
    let sessionEnd: Date?

    init(
        symbol: String,
        points: [StockTimeSeriesPoint],
        sessionStart: Date? = nil,
        sessionEnd: Date? = nil
    ) {
        self.symbol = symbol
        self.points = points
        self.sessionStart = sessionStart
        self.sessionEnd = sessionEnd
    }

    var latestClose: Decimal? {
        points.last?.close
    }

    var highClose: Decimal? {
        points.map(\.high).max()
    }

    var lowClose: Decimal? {
        points.map(\.low).min()
    }

    var openingPrice: Decimal? {
        points.first?.open
    }

    var sessionDuration: TimeInterval? {
        guard let sessionStart, let sessionEnd, sessionEnd > sessionStart else {
            return nil
        }
        return sessionEnd.timeIntervalSince(sessionStart)
    }
}
