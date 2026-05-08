import Foundation

protocol StockQuoteProvider {
    func fetchQuotes(completion: @escaping ([StockQuote]) -> Void)
}

protocol StockSymbolSearchProviding {
    func searchSymbols(matching query: String, completion: @escaping ([StockSymbolSearchResult]) -> Void)
}

protocol StockTimeSeriesProvider {
    func fetchTimeSeries(completion: @escaping (StockChartSeries?) -> Void)
}

final class DemoStockQuoteProvider: StockQuoteProvider {
    private let symbols: [String]

    init(symbols: [String]) {
        self.symbols = symbols
    }

    func fetchQuotes(completion: @escaping ([StockQuote]) -> Void) {
        let quotes = symbols.enumerated().map { index, symbol in
            StockQuote(
                symbol: symbol,
                price: Decimal(140 + index * 17),
                changePercent: Decimal(index.isMultiple(of: 2) ? 1.24 : -0.82)
            )
        }
        completion(quotes)
    }
}

final class DemoStockTimeSeriesProvider: StockTimeSeriesProvider {
    private let symbol: String

    init(symbol: String) {
        self.symbol = symbol
    }

    func fetchTimeSeries(completion: @escaping (StockChartSeries?) -> Void) {
        let calendar = Self.marketCalendar
        let now = Date()
        let sessionStart = Self.marketSessionStart(near: now, calendar: calendar)
        let sessionEnd = calendar.date(byAdding: .minute, value: 390, to: sessionStart) ?? sessionStart
        let latestPointDate = min(max(now, sessionStart), sessionEnd)
        let elapsedMinutes = max(Int(latestPointDate.timeIntervalSince(sessionStart) / 60), 1)
        let stepMinutes = max(elapsedMinutes / 80, 1)

        let points = stride(from: 0, through: elapsedMinutes, by: stepMinutes).compactMap { minute -> StockTimeSeriesPoint? in
            guard let date = calendar.date(byAdding: .minute, value: minute, to: sessionStart) else {
                return nil
            }
            let progress = Double(minute) / 390.0
            let trend = Decimal(progress * 36)
            let wave = Decimal(sin(Double(minute) / 18.0) * 5)
            let climb = minute > 110 ? Decimal(18) : Decimal(progress * 12)
            return StockTimeSeriesPoint(date: date, close: Decimal(140) + trend + wave + climb)
        }
        completion(StockChartSeries(symbol: symbol, points: points))
    }

    private static let marketCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private static func marketSessionStart(near date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(
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
    }
}

final class TwelveDataQuoteProvider: StockQuoteProvider {
    private let symbols: [String]
    private let apiKey: String
    private let session: URLSession
    private let baseURL: URL

    init(
        symbols: [String],
        apiKey: String,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.twelvedata.com")!
    ) {
        self.symbols = symbols
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
        self.baseURL = baseURL
    }

    func fetchQuotes(completion: @escaping ([StockQuote]) -> Void) {
        guard !symbols.isEmpty, !apiKey.isEmpty, let url = makeQuoteURL() else {
            completion([])
            return
        }

        session.dataTask(with: url) { data, _, error in
            guard error == nil, let data else {
                completion([])
                return
            }
            completion(Self.decodeQuotes(from: data, requestedSymbols: self.symbols))
        }.resume()
    }

    private func makeQuoteURL() -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("quote"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: symbols.joined(separator: ",")),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        return components?.url
    }

    static func decodeQuotes(from data: Data, requestedSymbols: [String]) -> [StockQuote] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        if let stockQuote = TwelveDataQuote(json: json)?.stockQuote {
            return [stockQuote]
        }

        let order = Dictionary(uniqueKeysWithValues: requestedSymbols.enumerated().map { ($0.element, $0.offset) })
        return json.values
            .compactMap { $0 as? [String: Any] }
            .compactMap { TwelveDataQuote(json: $0)?.stockQuote }
            .sorted { lhs, rhs in
                (order[lhs.symbol] ?? Int.max) < (order[rhs.symbol] ?? Int.max)
            }
    }
}

final class TwelveDataTimeSeriesProvider: StockTimeSeriesProvider {
    private let symbol: String
    private let apiKey: String
    private let session: URLSession
    private let baseURL: URL

    init(
        symbol: String,
        apiKey: String,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.twelvedata.com")!
    ) {
        self.symbol = symbol
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
        self.baseURL = baseURL
    }

    func fetchTimeSeries(completion: @escaping (StockChartSeries?) -> Void) {
        guard !symbol.isEmpty, !apiKey.isEmpty, let url = makeTimeSeriesURL() else {
            completion(nil)
            return
        }

        session.dataTask(with: url) { data, _, error in
            guard error == nil, let data else {
                completion(nil)
                return
            }
            completion(Self.decodeTimeSeries(from: data, requestedSymbol: self.symbol))
        }.resume()
    }

    private func makeTimeSeriesURL() -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("time_series"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "interval", value: "1min"),
            URLQueryItem(name: "outputsize", value: "390"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        return components?.url
    }

    static func decodeTimeSeries(from data: Data, requestedSymbol: String) -> StockChartSeries? {
        guard let response = try? JSONDecoder().decode(TwelveDataTimeSeriesResponse.self, from: data) else {
            return nil
        }

        let points = response.values.compactMap { item -> StockTimeSeriesPoint? in
            guard let date = TwelveDataTimeSeriesDateParser.date(from: item.datetime),
                  let close = Decimal(string: item.close, locale: Locale(identifier: "en_US_POSIX")) else {
                return nil
            }
            return StockTimeSeriesPoint(date: date, close: close)
        }
        .sorted { $0.date < $1.date }

        guard !points.isEmpty else { return nil }
        return StockChartSeries(symbol: response.meta.symbol ?? requestedSymbol, points: points)
    }
}

final class TwelveDataSymbolSearchProvider: StockSymbolSearchProviding {
    private let apiKey: String
    private let session: URLSession
    private let baseURL: URL

    init(
        apiKey: String,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.twelvedata.com")!
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
        self.baseURL = baseURL
    }

    func searchSymbols(matching query: String, completion: @escaping ([StockSymbolSearchResult]) -> Void) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, !apiKey.isEmpty, let url = makeSearchURL(query: trimmedQuery) else {
            completion([])
            return
        }

        session.dataTask(with: url) { data, _, error in
            guard error == nil, let data else {
                completion([])
                return
            }
            let response = try? JSONDecoder().decode(TwelveDataSymbolSearchResponse.self, from: data)
            completion(response?.data.map(\.searchResult) ?? [])
        }.resume()
    }

    private func makeSearchURL(query: String) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("symbol_search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: query),
            URLQueryItem(name: "outputsize", value: "12"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        return components?.url
    }
}

private struct TwelveDataQuote {
    let symbol: String?
    let close: Decimal?
    let percentChange: Decimal?

    init?(json: [String: Any]) {
        symbol = json["symbol"] as? String
        close = Self.decimal(from: json["close"])
        percentChange = Self.decimal(from: json["percent_change"])
    }

    var stockQuote: StockQuote? {
        guard let symbol, let close, let percentChange else { return nil }
        return StockQuote(symbol: symbol, price: close, changePercent: percentChange)
    }

    private static func decimal(from value: Any?) -> Decimal? {
        if let value = value as? Decimal {
            return value
        }
        if let value = value as? NSNumber {
            return value.decimalValue
        }
        if let value = value as? String {
            return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
        }
        return nil
    }
}

private struct TwelveDataSymbolSearchResponse: Decodable {
    let data: [TwelveDataSymbolSearchItem]
}

private struct TwelveDataSymbolSearchItem: Decodable {
    let symbol: String
    let instrumentName: String?
    let exchange: String?
    let country: String?
    let currency: String?
    let type: String?

    var searchResult: StockSymbolSearchResult {
        StockSymbolSearchResult(
            symbol: symbol,
            name: instrumentName ?? symbol,
            exchange: exchange,
            country: country,
            currency: currency,
            type: type
        )
    }

    private enum CodingKeys: String, CodingKey {
        case symbol
        case instrumentName = "instrument_name"
        case exchange
        case country
        case currency
        case type
    }
}

private struct TwelveDataTimeSeriesResponse: Decodable {
    let meta: TwelveDataTimeSeriesMeta
    let values: [TwelveDataTimeSeriesItem]
}

private struct TwelveDataTimeSeriesMeta: Decodable {
    let symbol: String?
}

private struct TwelveDataTimeSeriesItem: Decodable {
    let datetime: String
    let close: String
}

private enum TwelveDataTimeSeriesDateParser {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let minuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func date(from value: String) -> Date? {
        minuteFormatter.date(from: value) ?? dayFormatter.date(from: value)
    }
}
