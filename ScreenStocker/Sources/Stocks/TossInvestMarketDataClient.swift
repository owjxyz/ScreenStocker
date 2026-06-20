import Foundation

struct StockMarketSnapshot: Equatable {
    let quote: StockQuote
    let series: StockChartSeries
}

enum TossInvestMarketDataError: LocalizedError {
    case missingCredentials
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Toss Invest Open API credentials are missing."
        case .invalidResponse:
            return "The Toss Invest Open API response could not be read."
        case .apiError(let message):
            return message
        }
    }
}

final class TossInvestMarketDataClient {
    private struct TokenResponse: Decodable {
        let accessToken: String

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
        }
    }

    private struct ErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let code: String?
            let message: String?
        }

        let error: APIError?
    }

    private struct OAuthErrorResponse: Decodable {
        let error: String?
        let errorDescription: String?

        private enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    private struct PriceEnvelope: Decodable {
        let result: [PriceResponse]
    }

    private struct StockInfoEnvelope: Decodable {
        let result: [StockInfoResponse]
    }

    private struct PriceResponse: Decodable {
        let symbol: String
        let timestamp: Date?
        let lastPrice: Decimal
        let currency: String

        private enum CodingKeys: String, CodingKey {
            case symbol
            case timestamp
            case lastPrice
            case currency
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            symbol = try container.decode(String.self, forKey: .symbol)
            timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp)
            lastPrice = try container.decodeDecimal(forKey: .lastPrice)
            currency = try container.decode(String.self, forKey: .currency)
        }
    }

    private struct StockInfoResponse: Decodable {
        let symbol: String
        let name: String
        let englishName: String
        let market: String
        let status: String
        let currency: String

        var localizedDisplayName: String {
            if Locale.preferredLanguages.first?.hasPrefix("ko") == true {
                return name
            }
            return englishName.isEmpty ? name : englishName
        }
    }

    private struct CandleEnvelope: Decodable {
        let result: CandlePageResponse
    }

    private struct CandlePageResponse: Decodable {
        let candles: [CandleResponse]
        let nextBefore: Date?
    }

    private struct CandleResponse: Decodable {
        let timestamp: Date
        let openPrice: Decimal
        let highPrice: Decimal?
        let lowPrice: Decimal?
        let closePrice: Decimal

        private enum CodingKeys: String, CodingKey {
            case timestamp
            case openPrice
            case highPrice
            case lowPrice
            case closePrice
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            timestamp = try container.decode(Date.self, forKey: .timestamp)
            openPrice = try container.decodeDecimal(forKey: .openPrice)
            highPrice = try container.decodeDecimalIfPresent(forKey: .highPrice)
            lowPrice = try container.decodeDecimalIfPresent(forKey: .lowPrice)
            closePrice = try container.decodeDecimal(forKey: .closePrice)
        }
    }

    private let credentialsStore: TossInvestCredentialsStore
    private let session: URLSession
    private let baseURL = URL(string: "https://openapi.tossinvest.com")!
    private let decoder: JSONDecoder

    init(credentialsStore: TossInvestCredentialsStore = TossInvestCredentialsStore(), session: URLSession = .shared) {
        self.credentialsStore = credentialsStore
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            try Self.decodeDate(from: decoder)
        }
        self.decoder = decoder
    }

    func quotes(for symbols: [String]) async throws -> [String: StockQuote] {
        let normalizedSymbols = symbols.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        guard !normalizedSymbols.isEmpty else { return [:] }

        let token = try await issueAccessToken()
        let stockInfos = (try? await fetchStockInfos(symbols: normalizedSymbols, token: token)) ?? []
        let stockInfoBySymbol = Dictionary(uniqueKeysWithValues: stockInfos.map { ($0.symbol, $0) })
        let prices = try await fetchPrices(symbols: normalizedSymbols, token: token)

        return Dictionary(uniqueKeysWithValues: prices.map { price in
            (
                price.symbol,
                StockQuote(
                    symbol: price.symbol,
                    displayName: stockInfoBySymbol[price.symbol]?.localizedDisplayName,
                    price: price.lastPrice,
                    changePercent: nil,
                    currency: price.currency,
                    timestamp: price.timestamp
                )
            )
        })
    }

    func snapshot(for symbol: String) async throws -> StockMarketSnapshot {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedSymbol.isEmpty else {
            throw TossInvestMarketDataError.invalidResponse
        }

        let token = try await issueAccessToken()
        let stockInfos = (try? await fetchStockInfos(symbols: [normalizedSymbol], token: token)) ?? []
        let stockInfo = stockInfos.first
        guard let price = try await fetchPrices(symbols: [normalizedSymbol], token: token).first else {
            throw TossInvestMarketDataError.invalidResponse
        }

        let series = try await fetchIntradaySeries(symbol: price.symbol, token: token)
        let changePercent = changePercent(price: price, series: series)
        let quote = StockQuote(
            symbol: price.symbol,
            displayName: stockInfo?.localizedDisplayName,
            price: price.lastPrice,
            changePercent: changePercent,
            currency: price.currency,
            timestamp: price.timestamp
        )
        return StockMarketSnapshot(quote: quote, series: series)
    }

    func snapshots(for symbols: [String]) async throws -> [String: StockMarketSnapshot] {
        let quotes = try await quotes(for: symbols)
        return Dictionary(uniqueKeysWithValues: quotes.map { symbol, quote in
            (symbol, StockMarketSnapshot(quote: quote, series: StockChartSeries(symbol: symbol, points: [])))
        })
    }

    func stockInfo(for rawSymbol: String) async throws -> StockSymbolSearchResult {
        guard let normalizedSymbol = StockSymbolInput.normalizedSymbol(from: rawSymbol) else {
            throw TossInvestMarketDataError.apiError(StockSymbolInput.validationMessage)
        }

        let token = try await issueAccessToken()
        guard let stockInfo = try await fetchStockInfos(symbols: [normalizedSymbol], token: token).first(where: {
            $0.symbol.caseInsensitiveCompare(normalizedSymbol) == .orderedSame
        }) else {
            throw TossInvestMarketDataError.apiError("No stock was found for \(normalizedSymbol).")
        }

        guard stockInfo.status == "ACTIVE" else {
            throw TossInvestMarketDataError.apiError("\(normalizedSymbol) is not an active listed stock.")
        }

        return StockSymbolSearchResult(
            symbol: stockInfo.symbol,
            name: stockInfo.localizedDisplayName,
            exchange: stockInfo.market,
            country: StockSymbolInput.marketKind(for: stockInfo.symbol) == .krx ? "KR" : "US",
            currency: stockInfo.currency,
            type: stockInfo.status
        )
    }

    private func issueAccessToken() async throws -> String {
        guard let credentials = credentialsStore.credentials else {
            throw TossInvestMarketDataError.missingCredentials
        }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: credentials.apiKey),
            URLQueryItem(name: "client_secret", value: credentials.secretKey)
        ]

        var request = URLRequest(url: baseURL.appendingPathComponent("oauth2/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let data = try await validatedData(for: request)
        return try decoder.decode(TokenResponse.self, from: data).accessToken
    }

    private func fetchPrices(symbols: [String], token: String) async throws -> [PriceResponse] {
        var components = URLComponents(url: apiURL(path: "prices"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "symbols", value: symbols.joined(separator: ","))
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data = try await validatedData(for: request)
        return try decoder.decode(PriceEnvelope.self, from: data).result
    }

    private func fetchStockInfos(symbols: [String], token: String) async throws -> [StockInfoResponse] {
        var components = URLComponents(url: apiURL(path: "stocks"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "symbols", value: symbols.joined(separator: ","))
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data = try await validatedData(for: request)
        return try decoder.decode(StockInfoEnvelope.self, from: data).result
    }

    private func fetchIntradaySeries(symbol: String, token: String) async throws -> StockChartSeries {
        let firstPage = try await fetchMinuteCandlePage(symbol: symbol, token: token, before: nil)
        guard !firstPage.candles.isEmpty else {
            return StockChartSeries(symbol: symbol, points: [])
        }

        let (sessionStart, sessionEnd) = sessionBoundsForLatestAvailableCandles(firstPage.candles, symbol: symbol)
        let candles = try await fetchSessionMinuteCandles(
            symbol: symbol,
            token: token,
            firstPage: firstPage,
            sessionStart: sessionStart
        )
        let sessionCandles = candles
            .filter { $0.timestamp >= sessionStart && $0.timestamp <= sessionEnd }
            .sorted { $0.timestamp < $1.timestamp }
        let points = aggregateTenMinuteCandles(sessionCandles, sessionStart: sessionStart)
        return StockChartSeries(symbol: symbol, points: points)
    }

    private func fetchSessionMinuteCandles(
        symbol: String,
        token: String,
        firstPage: CandlePageResponse,
        sessionStart: Date
    ) async throws -> [CandleResponse] {
        var allCandles = firstPage.candles
        var before = firstPage.nextBefore
        var pageCount = 1

        while before != nil && pageCount < 5 {
            let earliestTimestamp = allCandles.map(\.timestamp).min()
            if let earliestTimestamp, earliestTimestamp <= sessionStart {
                break
            }

            let page = try await fetchMinuteCandlePage(symbol: symbol, token: token, before: before)
            allCandles.append(contentsOf: page.candles)
            before = page.nextBefore
            pageCount += 1
        }

        return allCandles
    }

    private func fetchMinuteCandlePage(
        symbol: String,
        token: String,
        before: Date?
    ) async throws -> CandlePageResponse {
        var components = URLComponents(url: apiURL(path: "candles"), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "interval", value: "1m"),
            URLQueryItem(name: "count", value: "200"),
            URLQueryItem(name: "adjusted", value: "true")
        ]
        if let before {
            queryItems.append(URLQueryItem(name: "before", value: Self.queryDateFormatter.string(from: before)))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data = try await validatedData(for: request)
        return try decoder.decode(CandleEnvelope.self, from: data).result
    }

    private func changePercent(price: PriceResponse, series: StockChartSeries) -> Decimal? {
        guard let baseline = series.openingPrice, baseline != 0 else { return nil }
        return ((price.lastPrice - baseline) / baseline) * 100
    }

    private func sessionBoundsForLatestAvailableCandles(
        _ candles: [CandleResponse],
        symbol: String
    ) -> (start: Date, end: Date) {
        let sortedCandles = candles.sorted { $0.timestamp > $1.timestamp }
        if let regularSessionCandle = sortedCandles.first(where: {
            let bounds = regularSessionBounds(for: symbol, on: $0.timestamp)
            return $0.timestamp >= bounds.start && $0.timestamp <= bounds.end
        }) {
            return regularSessionBounds(for: symbol, on: regularSessionCandle.timestamp)
        }

        guard let latestCandle = sortedCandles.first else {
            return regularSessionBounds(for: symbol, on: Date())
        }
        return regularSessionBounds(for: symbol, on: latestCandle.timestamp)
    }

    private func regularSessionBounds(for symbol: String, on date: Date) -> (start: Date, end: Date) {
        let marketKind = StockSymbolInput.marketKind(for: symbol)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.marketTimeZone(for: marketKind)

        let sessionStart = Self.sessionDate(
            matching: date,
            hour: marketKind == .krx ? 9 : 9,
            minute: marketKind == .krx ? 0 : 30,
            calendar: calendar
        )
        let sessionEnd = Self.sessionDate(
            matching: date,
            hour: marketKind == .krx ? 15 : 16,
            minute: marketKind == .krx ? 30 : 0,
            calendar: calendar
        )

        return (sessionStart, sessionEnd)
    }

    private func aggregateTenMinuteCandles(
        _ candles: [CandleResponse],
        sessionStart: Date
    ) -> [StockTimeSeriesPoint] {
        guard !candles.isEmpty else { return [] }

        let groupedCandles = Dictionary(grouping: candles) { candle in
            Int(candle.timestamp.timeIntervalSince(sessionStart) / 600)
        }

        return groupedCandles.keys.sorted().compactMap { bucket in
            guard let bucketCandles = groupedCandles[bucket]?.sorted(by: { $0.timestamp < $1.timestamp }),
                  let first = bucketCandles.first,
                  let last = bucketCandles.last else {
                return nil
            }

            let high = bucketCandles
                .map { $0.highPrice ?? max($0.openPrice, $0.closePrice) }
                .max() ?? max(first.openPrice, last.closePrice)
            let low = bucketCandles
                .map { $0.lowPrice ?? min($0.openPrice, $0.closePrice) }
                .min() ?? min(first.openPrice, last.closePrice)

            return StockTimeSeriesPoint(
                date: first.timestamp,
                open: first.openPrice,
                high: high,
                low: low,
                close: last.closePrice
            )
        }
    }

    private static func marketTimeZone(for marketKind: StockSymbolInput.MarketKind) -> TimeZone {
        switch marketKind {
        case .krx:
            return TimeZone(identifier: "Asia/Seoul") ?? .current
        case .us:
            return TimeZone(identifier: "America/New_York") ?? .current
        }
    }

    private static func sessionDate(matching date: Date, hour: Int, minute: Int, calendar: Calendar) -> Date {
        calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: date
        ) ?? date
    }

    private static let queryDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func validatedData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TossInvestMarketDataError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let oauthError = try? decoder.decode(OAuthErrorResponse.self, from: data),
               oauthError.error != nil || oauthError.errorDescription != nil {
                let code = oauthError.error.map { "\($0): " } ?? ""
                throw TossInvestMarketDataError.apiError("\(code)\(oauthError.errorDescription ?? "Request failed.")")
            }

            if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data),
               let error = envelope.error {
                let code = error.code.map { "\($0): " } ?? ""
                throw TossInvestMarketDataError.apiError("\(code)\(error.message ?? "Request failed.")")
            }
            throw TossInvestMarketDataError.apiError("Request failed with HTTP \(httpResponse.statusCode).")
        }
        return data
    }

    private func apiURL(path: String) -> URL {
        baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent(path)
    }

    private static func decodeDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let withoutFractionalSeconds = ISO8601DateFormatter()
        withoutFractionalSeconds.formatOptions = [.withInternetDateTime]

        for formatter in [withFractionalSeconds, withoutFractionalSeconds] {
            if let date = formatter.date(from: value) {
                return date
            }
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected ISO 8601 date string, got \(value)."
        )
    }
}

private extension KeyedDecodingContainer {
    func decodeDecimal(forKey key: Key) throws -> Decimal {
        if let stringValue = try? decode(String.self, forKey: key),
           let decimal = Decimal(string: stringValue) {
            return decimal
        }

        if let doubleValue = try? decode(Double.self, forKey: key) {
            return Decimal(doubleValue)
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Expected decimal string or number."
        )
    }

    func decodeDecimalIfPresent(forKey key: Key) throws -> Decimal? {
        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return Decimal(string: stringValue)
        }

        if let doubleValue = try? decodeIfPresent(Double.self, forKey: key) {
            return Decimal(doubleValue)
        }

        return nil
    }
}
