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

struct KoreaInvestmentCredentials: Equatable {
    let appKey: String
    let appSecret: String

    init(appKey: String, appSecret: String) {
        self.appKey = appKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appSecret = appSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isConfigured: Bool {
        !appKey.isEmpty && !appSecret.isEmpty
    }
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

final class KoreaInvestmentQuoteProvider: StockQuoteProvider {
    private let symbols: [String]
    private let credentials: KoreaInvestmentCredentials
    private let session: URLSession
    private let baseURL: URL
    private let tokenProvider: KoreaInvestmentAccessTokenProviding

    init(
        symbols: [String],
        credentials: KoreaInvestmentCredentials,
        session: URLSession = .shared,
        baseURL: URL = KoreaInvestmentAPI.productionBaseURL,
        tokenProvider: KoreaInvestmentAccessTokenProviding? = nil
    ) {
        self.symbols = symbols
        self.credentials = credentials
        self.session = session
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider ?? KoreaInvestmentAccessTokenProvider(
            credentials: credentials,
            session: session,
            baseURL: baseURL
        )
    }

    func fetchQuotes(completion: @escaping ([StockQuote]) -> Void) {
        guard !symbols.isEmpty, credentials.isConfigured else {
            completion([])
            return
        }

        tokenProvider.fetchAccessToken { [weak self] token in
            guard let self, let token else {
                completion([])
                return
            }

            let group = DispatchGroup()
            let lock = NSLock()
            var quotes: [StockQuote] = []

            for symbol in self.symbols {
                guard let request = self.makeQuoteRequest(symbol: symbol, accessToken: token) else {
                    continue
                }
                group.enter()
                self.session.dataTask(with: request) { data, _, error in
                    defer { group.leave() }
                    guard error == nil, let data,
                          let quote = Self.decodeQuote(from: data, requestedSymbol: symbol) else {
                        return
                    }
                    lock.lock()
                    quotes.append(quote)
                    lock.unlock()
                }.resume()
            }

            group.notify(queue: .global()) {
                let order = Dictionary(uniqueKeysWithValues: self.symbols.enumerated().map { ($0.element, $0.offset) })
                completion(quotes.sorted {
                    (order[$0.symbol] ?? Int.max) < (order[$1.symbol] ?? Int.max)
                })
            }
        }
    }

    private func makeQuoteRequest(symbol: String, accessToken: String) -> URLRequest? {
        let url = baseURL.appendingPathComponent("uapi/domestic-stock/v1/quotations/inquire-price")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "FID_COND_MRKT_DIV_CODE", value: "J"),
            URLQueryItem(name: "FID_INPUT_ISCD", value: symbol)
        ]
        guard let requestURL = components?.url else { return nil }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = KoreaInvestmentAPI.headers(
            credentials: credentials,
            accessToken: accessToken,
            transactionID: "FHKST01010100"
        )
        return request
    }

    static func decodeQuote(from data: Data, requestedSymbol: String) -> StockQuote? {
        guard let response = try? JSONDecoder().decode(KoreaInvestmentQuoteResponse.self, from: data),
              response.rtCode == "0",
              let output = response.output,
              let price = Decimal(string: output.currentPrice, locale: Locale(identifier: "en_US_POSIX")),
              let changePercent = Decimal(string: output.previousDayRate, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        return StockQuote(symbol: requestedSymbol, price: price, changePercent: changePercent)
    }
}

final class KoreaInvestmentTimeSeriesProvider: StockTimeSeriesProvider {
    private let symbol: String
    private let credentials: KoreaInvestmentCredentials
    private let session: URLSession
    private let baseURL: URL
    private let tokenProvider: KoreaInvestmentAccessTokenProviding
    private let calendar: Calendar

    init(
        symbol: String,
        credentials: KoreaInvestmentCredentials,
        session: URLSession = .shared,
        baseURL: URL = KoreaInvestmentAPI.productionBaseURL,
        tokenProvider: KoreaInvestmentAccessTokenProviding? = nil,
        calendar: Calendar = .current
    ) {
        self.symbol = symbol
        self.credentials = credentials
        self.session = session
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider ?? KoreaInvestmentAccessTokenProvider(
            credentials: credentials,
            session: session,
            baseURL: baseURL
        )
        self.calendar = calendar
    }

    func fetchTimeSeries(completion: @escaping (StockChartSeries?) -> Void) {
        guard !symbol.isEmpty, credentials.isConfigured else {
            completion(nil)
            return
        }

        tokenProvider.fetchAccessToken { [weak self] token in
            guard let self, let token, let request = self.makeTimeSeriesRequest(accessToken: token) else {
                completion(nil)
                return
            }

            self.session.dataTask(with: request) { data, _, error in
                guard error == nil, let data else {
                    completion(nil)
                    return
                }
                completion(Self.decodeTimeSeries(from: data, requestedSymbol: self.symbol))
            }.resume()
        }
    }

    private func makeTimeSeriesRequest(accessToken: String) -> URLRequest? {
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -160, to: endDate) ?? endDate
        let url = baseURL.appendingPathComponent("uapi/domestic-stock/v1/quotations/inquire-daily-itemchartprice")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "FID_COND_MRKT_DIV_CODE", value: "J"),
            URLQueryItem(name: "FID_INPUT_ISCD", value: symbol),
            URLQueryItem(name: "FID_INPUT_DATE_1", value: KoreaInvestmentDateFormatter.string(from: startDate)),
            URLQueryItem(name: "FID_INPUT_DATE_2", value: KoreaInvestmentDateFormatter.string(from: endDate)),
            URLQueryItem(name: "FID_PERIOD_DIV_CODE", value: "D"),
            URLQueryItem(name: "FID_ORG_ADJ_PRC", value: "1")
        ]
        guard let requestURL = components?.url else { return nil }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = KoreaInvestmentAPI.headers(
            credentials: credentials,
            accessToken: accessToken,
            transactionID: "FHKST03010100"
        )
        return request
    }

    static func decodeTimeSeries(from data: Data, requestedSymbol: String) -> StockChartSeries? {
        guard let response = try? JSONDecoder().decode(KoreaInvestmentTimeSeriesResponse.self, from: data),
              response.rtCode == "0" else {
            return nil
        }

        let points = response.output.compactMap { item -> StockTimeSeriesPoint? in
            guard let date = KoreaInvestmentDateFormatter.date(from: item.businessDate),
                  let close = Decimal(string: item.closePrice, locale: Locale(identifier: "en_US_POSIX")) else {
                return nil
            }
            return StockTimeSeriesPoint(date: date, close: close)
        }
        .sorted { $0.date < $1.date }

        guard !points.isEmpty else { return nil }
        return StockChartSeries(symbol: requestedSymbol, points: points)
    }
}

final class KoreaInvestmentSymbolSearchProvider: StockSymbolSearchProviding {
    private let credentials: KoreaInvestmentCredentials
    private let session: URLSession
    private let baseURL: URL
    private let tokenProvider: KoreaInvestmentAccessTokenProviding

    init(
        credentials: KoreaInvestmentCredentials,
        session: URLSession = .shared,
        baseURL: URL = KoreaInvestmentAPI.productionBaseURL,
        tokenProvider: KoreaInvestmentAccessTokenProviding? = nil
    ) {
        self.credentials = credentials
        self.session = session
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider ?? KoreaInvestmentAccessTokenProvider(
            credentials: credentials,
            session: session,
            baseURL: baseURL
        )
    }

    func searchSymbols(matching query: String, completion: @escaping ([StockSymbolSearchResult]) -> Void) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmedQuery.range(of: #"^[0-9A-Z]{6,7}$"#, options: .regularExpression) != nil,
              credentials.isConfigured else {
            completion([])
            return
        }

        tokenProvider.fetchAccessToken { [weak self] token in
            guard let self, let token,
                  let request = KoreaInvestmentQuoteProvider(
                    symbols: [trimmedQuery],
                    credentials: self.credentials,
                    session: self.session,
                    baseURL: self.baseURL,
                    tokenProvider: self.tokenProvider
                  ).makeLookupRequest(symbol: trimmedQuery, accessToken: token) else {
                completion([])
                return
            }

            self.session.dataTask(with: request) { data, _, error in
                guard error == nil, let data,
                      let result = Self.decodeSearchResult(from: data, requestedSymbol: trimmedQuery) else {
                    completion([])
                    return
                }
                completion([result])
            }.resume()
        }
    }

    static func decodeSearchResult(from data: Data, requestedSymbol: String) -> StockSymbolSearchResult? {
        guard let response = try? JSONDecoder().decode(KoreaInvestmentQuoteResponse.self, from: data),
              response.rtCode == "0",
              let output = response.output else {
            return nil
        }
        return StockSymbolSearchResult(
            symbol: requestedSymbol,
            name: output.name ?? requestedSymbol,
            exchange: "KRX",
            country: "KR",
            currency: "KRW",
            type: nil
        )
    }
}

private extension KoreaInvestmentQuoteProvider {
    func makeLookupRequest(symbol: String, accessToken: String) -> URLRequest? {
        makeQuoteRequest(symbol: symbol, accessToken: accessToken)
    }
}

protocol KoreaInvestmentAccessTokenProviding {
    func fetchAccessToken(completion: @escaping (String?) -> Void)
}

final class KoreaInvestmentAccessTokenProvider: KoreaInvestmentAccessTokenProviding {
    private let credentials: KoreaInvestmentCredentials
    private let session: URLSession
    private let baseURL: URL
    private let lock = NSLock()
    private var cachedToken: CachedAccessToken?

    init(
        credentials: KoreaInvestmentCredentials,
        session: URLSession = .shared,
        baseURL: URL = KoreaInvestmentAPI.productionBaseURL
    ) {
        self.credentials = credentials
        self.session = session
        self.baseURL = baseURL
    }

    func fetchAccessToken(completion: @escaping (String?) -> Void) {
        lock.lock()
        let token = cachedToken
        lock.unlock()

        if let token, token.expirationDate > Date().addingTimeInterval(60) {
            completion(token.value)
            return
        }

        guard credentials.isConfigured else {
            completion(nil)
            return
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("oauth2/tokenP"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONEncoder().encode(KoreaInvestmentTokenRequest(
            grantType: "client_credentials",
            appKey: credentials.appKey,
            appSecret: credentials.appSecret
        ))

        session.dataTask(with: request) { [weak self] data, _, error in
            guard let self, error == nil, let data,
                  let response = try? JSONDecoder().decode(KoreaInvestmentTokenResponse.self, from: data),
                  !response.accessToken.isEmpty else {
                completion(nil)
                return
            }

            let expirationDate = response.expiredAt.flatMap(KoreaInvestmentTokenExpirationParser.date)
                ?? Date().addingTimeInterval(60 * 60 * 23)
            self.lock.lock()
            self.cachedToken = CachedAccessToken(value: response.accessToken, expirationDate: expirationDate)
            self.lock.unlock()
            completion(response.accessToken)
        }.resume()
    }
}

private enum KoreaInvestmentAPI {
    static let productionBaseURL = URL(string: "https://openapi.koreainvestment.com:9443")!

    static func headers(
        credentials: KoreaInvestmentCredentials,
        accessToken: String,
        transactionID: String
    ) -> [String: String] {
        [
            "Content-Type": "application/json",
            "Accept": "text/plain",
            "authorization": "Bearer \(accessToken)",
            "appkey": credentials.appKey,
            "appsecret": credentials.appSecret,
            "tr_id": transactionID,
            "custtype": "P"
        ]
    }
}

private struct CachedAccessToken {
    let value: String
    let expirationDate: Date
}

private struct KoreaInvestmentTokenRequest: Encodable {
    let grantType: String
    let appKey: String
    let appSecret: String

    private enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case appKey = "appkey"
        case appSecret = "appsecret"
    }
}

private struct KoreaInvestmentTokenResponse: Decodable {
    let accessToken: String
    let expiredAt: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiredAt = "access_token_token_expired"
    }
}

private struct KoreaInvestmentQuoteResponse: Decodable {
    let rtCode: String
    let output: KoreaInvestmentQuoteOutput?

    private enum CodingKeys: String, CodingKey {
        case rtCode = "rt_cd"
        case output
    }
}

private struct KoreaInvestmentQuoteOutput: Decodable {
    let currentPrice: String
    let previousDayRate: String
    let name: String?

    private enum CodingKeys: String, CodingKey {
        case currentPrice = "stck_prpr"
        case previousDayRate = "prdy_ctrt"
        case name = "hts_kor_isnm"
    }
}

private struct KoreaInvestmentTimeSeriesResponse: Decodable {
    let rtCode: String
    let output: [KoreaInvestmentTimeSeriesItem]

    private enum CodingKeys: String, CodingKey {
        case rtCode = "rt_cd"
        case output = "output2"
    }
}

private struct KoreaInvestmentTimeSeriesItem: Decodable {
    let businessDate: String
    let closePrice: String

    private enum CodingKeys: String, CodingKey {
        case businessDate = "stck_bsop_date"
        case closePrice = "stck_clpr"
    }
}

private enum KoreaInvestmentDateFormatter {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from value: String) -> Date? {
        formatter.date(from: value)
    }
}

private enum KoreaInvestmentTokenExpirationParser {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func date(from value: String) -> Date? {
        formatter.date(from: value)
    }
}
